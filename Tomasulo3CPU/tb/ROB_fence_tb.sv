`timescale 1ns/1ps

module ROB_fence_tb;
    import riscv_types_pkg::*;

    localparam int unsigned ROB_DEPTH = 4;
    localparam int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH);
    localparam int unsigned DMEM_WIDTH = 64;
    localparam int unsigned DMEM_DEPTH = 32;
    localparam int unsigned IMEM_DEPTH = 64;
    localparam int unsigned ARCH_REG_COUNT = 32;
    localparam int unsigned ARCH_REG_WIDTH = $clog2(ARCH_REG_COUNT);
    localparam int unsigned PHY_REGISTER_FILE_WIDTH = 7;
    localparam int unsigned W_BYTE_NUM = DMEM_WIDTH / 8;

    logic clk;
    logic rst_n;

    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_sw_rt_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_pre_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_new_phy_addr;
    logic dis_inst_valid;
    logic [ARCH_REG_WIDTH-1:0] dis_rob_rd_arch_addr;
    logic dis_reg_write;
    logic [IMEM_DEPTH-1:0] dis_pc;
    rob_opclass_t dis_rob_opclass;
    csr_cmd_e dis_csr_cmd;
    csr_addr_t dis_csr_addr;
    trap_cause_t dis_trap_cause;
    logic [ARCH_REG_WIDTH-1:0] dis_csr_rs1_arch_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] rrat_csr_rs1_phy;

    logic [ROB_INDEX_WIDTH-1:0] rob_bottom_ptr;
    logic rob_full;
    logic rob_two_or_more_vacant;

    logic cdb_valid;
    logic [ROB_INDEX_WIDTH-1:0] cdb_rob_tag;
    logic [DMEM_DEPTH-1:0] cdb_sw_addr;
    logic [W_BYTE_NUM-1:0] cdb_sw_strb;
    logic cdb_flush;

    logic [PHY_REGISTER_FILE_WIDTH-1:0] rt_sb_phy_addr;
    logic sb_full;
    logic sb_drained;
    logic [DMEM_DEPTH-1:0] rob_sw_addr;
    logic [W_BYTE_NUM-1:0] rob_sw_strb;
    logic rob_commit_mem_write;

    logic [ROB_INDEX_WIDTH-1:0] rob_top_ptr;
    logic rob_commit;
    logic [ARCH_REG_WIDTH-1:0] rob_commit_rd_arch_addr;
    logic rob_reg_write;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] rob_commit_curr_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] rob_commit_pre_phy_addr;
    logic rob_serializing_committed;
    logic rob_fence_pending;
    logic [ROB_INDEX_WIDTH-1:0] rob_fence_tag;

    logic csr_commit_valid;
    csr_addr_t csr_commit_addr;
    csr_cmd_e csr_commit_cmd;
    logic csr_commit_rs1_is_x0;
    logic [4:0] csr_commit_zimm;
    logic ecall_commit;
    logic ebreak_commit;
    logic mret_commit;
    logic [IMEM_DEPTH-1:0] trap_commit_pc;
    logic [63:0] csr_rdata;
    logic csr_redirect_valid;
    logic [63:0] csr_redirect_pc;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] csr_wr_phy_addr;
    logic [63:0] csr_wr_data;
    logic csr_wr_en;
    logic trap_commit_flush;
    logic [IMEM_DEPTH-1:0] trap_redirect_pc;
    logic fence_i_commit_flush;
    logic [IMEM_DEPTH-1:0] fence_i_redirect_pc;

    ROB #(
        .ROB_DEPTH(ROB_DEPTH),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .DMEM_WIDTH(DMEM_WIDTH),
        .DMEM_DEPTH(DMEM_DEPTH),
        .IMEM_DEPTH(IMEM_DEPTH),
        .ARCH_REG_COUNT(ARCH_REG_COUNT),
        .ARCH_REG_WIDTH(ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .W_BYTE_NUM(W_BYTE_NUM)
    ) dut (
        .*
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    int failures;

    task automatic check_bit(input string name, input logic actual, expected);
        if (actual !== expected) begin
            $error("[FAIL] %s: got %0b, expected %0b", name, actual, expected);
            failures++;
        end
    endtask

    task automatic check_tag(
        input string name,
        input logic [ROB_INDEX_WIDTH-1:0] actual,
        input logic [ROB_INDEX_WIDTH-1:0] expected
    );
        if (actual !== expected) begin
            $error("[FAIL] %s: got %0d, expected %0d", name, actual, expected);
            failures++;
        end
    endtask

    task automatic clear_inputs();
        dis_sw_rt_phy_addr = '0;
        dis_pre_phy_addr = '0;
        dis_new_phy_addr = '0;
        dis_inst_valid = 1'b0;
        dis_rob_rd_arch_addr = '0;
        dis_reg_write = 1'b0;
        dis_pc = '0;
        dis_rob_opclass = ROB_ALU;
        dis_csr_cmd = CSR_CMD_NONE;
        dis_csr_addr = '0;
        dis_trap_cause = TRAP_CAUSE_NONE;
        dis_csr_rs1_arch_addr = '0;
        rrat_csr_rs1_phy = '0;
        cdb_valid = 1'b0;
        cdb_rob_tag = '0;
        cdb_sw_addr = '0;
        cdb_sw_strb = '0;
        cdb_flush = 1'b0;
        sb_full = 1'b0;
        sb_drained = 1'b1;
        csr_rdata = '0;
        csr_redirect_valid = 1'b0;
        csr_redirect_pc = '0;
    endtask

    task automatic reset_dut();
        rst_n = 1'b0;
        clear_inputs();
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1;
    endtask

    task automatic dispatch(input rob_opclass_t opclass, input logic [63:0] pc);
        dis_rob_opclass = opclass;
        dis_pc = pc;
        dis_inst_valid = 1'b1;
        @(posedge clk);
        #1;
        dis_inst_valid = 1'b0;
    endtask

    initial begin
        failures = 0;

        $display("[TEST] FENCE waits for a fully drained store buffer");
        reset_dut();
        sb_drained = 1'b0;
        dispatch(ROB_FENCE, 64'h100);
        check_bit("fence is pending", rob_fence_pending, 1'b1);
        check_bit("fence cannot commit before store responses", rob_commit, 1'b0);
        sb_drained = 1'b1;
        #1;
        check_bit("fence commits after store responses", rob_commit, 1'b1);
        @(posedge clk);
        #1;
        check_bit("fence retires", rob_fence_pending, 1'b0);

        $display("[TEST] Oldest of multiple fences is exported");
        reset_dut();
        sb_drained = 1'b0;
        dispatch(ROB_FENCE, 64'h200);
        dispatch(ROB_FENCE_I, 64'h204);
        check_tag("oldest fence tag", rob_fence_tag, 2'd0);
        sb_drained = 1'b1;
        #1;
        @(posedge clk);
        #1;
        check_bit("second fence remains pending", rob_fence_pending, 1'b1);
        check_tag("second fence becomes oldest", rob_fence_tag, 2'd1);

        $display("[TEST] FENCE.I redirects to its sequential PC at commit");
        reset_dut();
        dispatch(ROB_FENCE_I, 64'h300);
        check_bit("fence.i commit flush", fence_i_commit_flush, 1'b1);
        if (fence_i_redirect_pc !== 64'h304) begin
            $error("[FAIL] fence.i redirect: got 0x%0h, expected 0x304",
                   fence_i_redirect_pc);
            failures++;
        end

        $display("[TEST] Flushing younger fences removes the LSQ boundary");
        reset_dut();
        dispatch(ROB_ALU, 64'h400);
        dispatch(ROB_FENCE, 64'h404);
        check_bit("younger fence initially pending", rob_fence_pending, 1'b1);
        cdb_rob_tag = 2'd0;
        cdb_flush = 1'b1;
        @(posedge clk);
        #1;
        cdb_flush = 1'b0;
        check_bit("flushed fence no longer pending", rob_fence_pending, 1'b0);

        if (failures == 0)
            $display("[PASS] ROB_fence_tb");
        else
            $fatal(1, "[FAIL] ROB_fence_tb: %0d failure(s)", failures);
        $finish;
    end

    initial begin
        #100_000;
        $fatal(1, "[FAIL] ROB_fence_tb timeout");
    end
endmodule
