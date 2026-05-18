// CPU back-end integration testbench: ISSUEQ, ISSUEUNIT, PRF, EXE, LSB, CDB.
/* verilator lint_off WIDTH */
// verilog_lint: waive-start explicit-parameter-storage-type
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module CPU_BACK_END_tb;
import riscv_types_pkg::*;

    parameter int unsigned XLEN                    = 64;
    parameter int unsigned INSTR_WIDTH             = 32;
    parameter int unsigned ARCH_REG_COUNT          = 32;
    localparam  int unsigned ARCH_REG_WIDTH        = $clog2(ARCH_REG_COUNT);
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7;
    parameter int unsigned REG_FILE_DATA_WIDTH     = 64;
    parameter int unsigned DMEM_WIDTH              = 32;
    parameter int unsigned DMEM_DEPTH              = 32;
    parameter int unsigned ROB_DEPTH               = 16;
    localparam  int unsigned ROB_INDEX_WIDTH       = $clog2(ROB_DEPTH);
    parameter int unsigned ISSUE_QUEUE_DEPTH       = 4;
    parameter int unsigned SB_DEPTH                = 4;
    localparam  int unsigned SB_INDEX_WIDTH        = $clog2(SB_DEPTH);
    parameter int unsigned LSB_DEPTH               = 4;
    parameter int unsigned BPB_PC_BITS             = 3;
    parameter int unsigned DIV_CYCLES              = 7;
    parameter int unsigned MUL_CYCLES              = 4;
    parameter int unsigned INT_CYCLES              = 1;
    parameter int unsigned LD_ST_CYCLES            = 1;
    parameter int unsigned OPCODE_WIDTH            = 6;

    logic clk;
    logic rst_n;

    logic [ROB_INDEX_WIDTH-1:0]          rob_top_ptr;

    logic                                dis_int_issq_en;
    logic                                dis_div_issq_en;
    logic                                dis_mul_issq_en;
    logic                                dis_ld_st_issq_en;
    logic                                dis_reg_write;
    logic                                dis_rs_data_ready;
    logic                                dis_rt_data_ready;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]  dis_rs_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]  dis_rt_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]  dis_new_rd_phy_addr;
    logic [ROB_INDEX_WIDTH-1:0]          dis_rob_tag;
    logic [OPCODE_WIDTH-1:0]             dis_opcode;
    logic [15:0]                         dis_imm16;
    logic [DMEM_WIDTH-1:0]               dis_branch_other_addr;
    logic [BPB_PC_BITS:0]                dis_branch_pc_bits;
    logic                                dis_branch_prediction;
    logic                                dis_branch;
    logic                                dis_jr_inst;
    logic                                dis_jal_inst;
    logic                                dis_jr31_inst;

    logic [ROB_INDEX_WIDTH-1:0]          rob_tag;
    logic                                rob_commit_mem_write;

    logic [REG_FILE_DATA_WIDTH-1:0]      rt_sb_data;

    logic [SB_INDEX_WIDTH-1:0]           sb_flush_sw_tag;
    logic                                sb_flush_sw;
    logic [SB_INDEX_WIDTH-1:0]           sb_entry_sw_tag;
    logic [DMEM_DEPTH-1:0]               sb_entry_sw_addr;

    logic [PHY_REGISTER_FILE_WIDTH-1:0]  rt_sb_phy_addr;

    logic                                dcache_read_busy;
    logic                                dcache_read_done;
    logic [REG_FILE_DATA_WIDTH-1:0]      dcache_rdata;
    logic                                dcache_req;
    logic [DMEM_DEPTH-1:0]               dcache_addr;

    logic                                issq_intq_full;
    logic                                issq_divq_full;
    logic                                issq_mulq_full;
    logic                                issq_ld_stq_full;
    logic                                issq_intq_two_or_more_vacant;
    logic                                issq_divq_two_or_more_vacant;
    logic                                issq_mulq_two_or_more_vacant;
    logic                                issq_ld_stq_two_or_more_vacant;

    logic                                cdb_valid;
    logic [ROB_INDEX_WIDTH-1:0]          cdb_rob_tag;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]  cdb_rd_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0]      cdb_rd_data;
    logic                                cdb_reg_write;
    logic                                cdb_flush;
    logic [ROB_INDEX_WIDTH-1:0]          cdb_rob_depth;
    logic [DMEM_DEPTH-1:0]               cdb_sw_addr;
    logic                                cdb_upd_branch;
    logic [BPB_PC_BITS-1:0]              cdb_upd_branch_addr;
    logic                                cdb_branch_outcome;
    logic [31:0]                         cdb_branch_addr;
    logic                                cdb_jalr_resolved;

    logic [ROB_INDEX_WIDTH-1:0]          lsb_rob_tag;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]  lsb_rd_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0]      lsb_data;
    logic                                lsb_rw;
    logic [DMEM_DEPTH-1:0]               lsb_sw_addr;
    logic                                lsb_result_valid;

    CPU_BACK_END #(
        .XLEN                    (XLEN),
        .INSTR_WIDTH             (INSTR_WIDTH),
        .ARCH_REG_COUNT          (ARCH_REG_COUNT),
        .ARCH_REG_WIDTH          (ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH (PHY_REGISTER_FILE_WIDTH),
        .REG_FILE_DATA_WIDTH     (REG_FILE_DATA_WIDTH),
        .DMEM_WIDTH              (DMEM_WIDTH),
        .DMEM_DEPTH              (DMEM_DEPTH),
        .ROB_DEPTH               (ROB_DEPTH),
        .ROB_INDEX_WIDTH         (ROB_INDEX_WIDTH),
        .ISSUE_QUEUE_DEPTH       (ISSUE_QUEUE_DEPTH),
        .SB_DEPTH                (SB_DEPTH),
        .LSB_DEPTH               (LSB_DEPTH),
        .BPB_PC_BITS             (BPB_PC_BITS),
        .DIV_CYCLES              (DIV_CYCLES),
        .MUL_CYCLES              (MUL_CYCLES),
        .INT_CYCLES              (INT_CYCLES),
        .LD_ST_CYCLES            (LD_ST_CYCLES),
        .OPCODE_WIDTH            (OPCODE_WIDTH)
    ) dut (
        .clk                                (clk),
        .rst_n                              (rst_n),
        .rob_top_ptr                        (rob_top_ptr),
        .dis_int_issq_en                    (dis_int_issq_en),
        .dis_div_issq_en                    (dis_div_issq_en),
        .dis_mul_issq_en                    (dis_mul_issq_en),
        .dis_ld_st_issq_en                  (dis_ld_st_issq_en),
        .dis_reg_write                      (dis_reg_write),
        .dis_rs_data_ready                  (dis_rs_data_ready),
        .dis_rt_data_ready                  (dis_rt_data_ready),
        .dis_rs_phy_addr                    (dis_rs_phy_addr),
        .dis_rt_phy_addr                    (dis_rt_phy_addr),
        .dis_new_rd_phy_addr                (dis_new_rd_phy_addr),
        .dis_rob_tag                        (dis_rob_tag),
        .dis_opcode                         (dis_opcode),
        .dis_imm16                          (dis_imm16),
        .dis_branch_other_addr              (dis_branch_other_addr),
        .dis_branch_pc_bits                 (dis_branch_pc_bits),
        .dis_branch_prediction              (dis_branch_prediction),
        .dis_branch                         (dis_branch),
        .dis_jr_inst                        (dis_jr_inst),
        .dis_jal_inst                       (dis_jal_inst),
        .dis_jr31_inst                      (dis_jr31_inst),
        .rob_tag                            (rob_tag),
        .rob_commit_mem_write               (rob_commit_mem_write),
        .rt_sb_data                         (rt_sb_data),
        .sb_flush_sw_tag                    (sb_flush_sw_tag),
        .sb_flush_sw                        (sb_flush_sw),
        .sb_entry_sw_tag                    (sb_entry_sw_tag),
        .sb_entry_sw_addr                   (sb_entry_sw_addr),
        .rt_sb_phy_addr                     (rt_sb_phy_addr),
        .dcache_read_busy                   (dcache_read_busy),
        .dcache_read_done                   (dcache_read_done),
        .dcache_rdata                       (dcache_rdata),
        .dcache_req                         (dcache_req),
        .dcache_addr                        (dcache_addr),
        .issq_intq_full                     (issq_intq_full),
        .issq_divq_full                     (issq_divq_full),
        .issq_mulq_full                     (issq_mulq_full),
        .issq_ld_stq_full                   (issq_ld_stq_full),
        .issq_intq_two_or_more_vacant       (issq_intq_two_or_more_vacant),
        .issq_divq_two_or_more_vacant       (issq_divq_two_or_more_vacant),
        .issq_mulq_two_or_more_vacant       (issq_mulq_two_or_more_vacant),
        .issq_ld_stq_two_or_more_vacant     (issq_ld_stq_two_or_more_vacant),
        .cdb_valid                          (cdb_valid),
        .cdb_rob_tag                        (cdb_rob_tag),
        .cdb_rd_phy_addr                    (cdb_rd_phy_addr),
        .cdb_rd_data                        (cdb_rd_data),
        .cdb_reg_write                      (cdb_reg_write),
        .cdb_flush                          (cdb_flush),
        .cdb_rob_depth                      (cdb_rob_depth),
        .cdb_sw_addr                        (cdb_sw_addr),
        .cdb_upd_branch                     (cdb_upd_branch),
        .cdb_upd_branch_addr                (cdb_upd_branch_addr),
        .cdb_branch_outcome                 (cdb_branch_outcome),
        .cdb_branch_addr                    (cdb_branch_addr),
        .cdb_jalr_resolved                  (cdb_jalr_resolved),
        .lsb_rob_tag                        (lsb_rob_tag),
        .lsb_rd_phy_addr                    (lsb_rd_phy_addr),
        .lsb_data                           (lsb_data),
        .lsb_rw                             (lsb_rw),
        .lsb_sw_addr                        (lsb_sw_addr),
        .lsb_result_valid                   (lsb_result_valid)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    int pass_cnt = 0;
    int fail_cnt = 0;

    task automatic check_bit(input string tag, input logic actual, input logic expected);
        if (actual !== expected) begin
            $error("[FAIL] %s: got %0b, want %0b @ %0t", tag, actual, expected, $time);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
    endtask

    task automatic check_val(input string tag, input logic [63:0] actual, input logic [63:0] expected);
        if (actual !== expected) begin
            $error("[FAIL] %s: got 0x%0h, want 0x%0h @ %0t", tag, actual, expected, $time);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
    endtask

    task automatic clear_dispatch();
        dis_int_issq_en       = 1'b0;
        dis_div_issq_en       = 1'b0;
        dis_mul_issq_en       = 1'b0;
        dis_ld_st_issq_en     = 1'b0;
        dis_reg_write         = 1'b0;
        dis_rs_data_ready     = 1'b0;
        dis_rt_data_ready     = 1'b0;
        dis_rs_phy_addr       = '0;
        dis_rt_phy_addr       = '0;
        dis_new_rd_phy_addr   = '0;
        dis_rob_tag           = '0;
        dis_opcode            = INSTR_NONE;
        dis_imm16             = '0;
        dis_branch_other_addr = '0;
        dis_branch_pc_bits    = '0;
        dis_branch_prediction = 1'b0;
        dis_branch            = 1'b0;
        dis_jr_inst           = 1'b0;
        dis_jal_inst          = 1'b0;
        dis_jr31_inst         = 1'b0;
    endtask

    task automatic clear_inputs();
        clear_dispatch();
        rob_top_ptr           = '0;
        rob_tag               = '0;
        rob_commit_mem_write  = 1'b0;
        sb_flush_sw_tag       = '0;
        sb_flush_sw           = 1'b0;
        sb_entry_sw_tag       = '0;
        sb_entry_sw_addr      = '0;
        rt_sb_phy_addr        = '0;
        dcache_read_busy      = 1'b0;
        dcache_read_done      = 1'b0;
        dcache_rdata          = '0;
    endtask

    task automatic reset_dut();
        rst_n = 1'b0;
        clear_inputs();
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;
    endtask

    task automatic dispatch_int_raw(
        input logic [ROB_INDEX_WIDTH-1:0]         rob_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rt_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd_i,
        input logic [OPCODE_WIDTH-1:0]            opcode_i,
        input logic [15:0]                        imm_i,
        input logic                               reg_write_i,
        input logic                               rs_ready_i,
        input logic                               rt_ready_i,
        input logic                               branch_i,
        input logic                               branch_prediction_i,
        input logic [DMEM_WIDTH-1:0]              branch_other_addr_i
    );
        clear_dispatch();
        dis_int_issq_en       = 1'b1;
        dis_reg_write         = reg_write_i;
        dis_rs_data_ready     = rs_ready_i;
        dis_rt_data_ready     = rt_ready_i;
        dis_rs_phy_addr       = rs_i;
        dis_rt_phy_addr       = rt_i;
        dis_new_rd_phy_addr   = rd_i;
        dis_rob_tag           = rob_i;
        dis_opcode            = opcode_i;
        dis_imm16             = imm_i;
        dis_branch_other_addr = branch_other_addr_i;
        dis_branch_pc_bits    = {1'b0, 3'd5};
        dis_branch_prediction = branch_prediction_i;
        dis_branch            = branch_i;
        @(posedge clk); #1;
        clear_dispatch();
    endtask

    task automatic dispatch_int(
        input logic [ROB_INDEX_WIDTH-1:0]         rob_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rt_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd_i,
        input logic [OPCODE_WIDTH-1:0]            opcode_i,
        input logic [15:0]                        imm_i,
        input logic                               reg_write_i,
        input logic                               branch_i,
        input logic                               branch_prediction_i,
        input logic [DMEM_WIDTH-1:0]              branch_other_addr_i
    );
        dispatch_int_raw(rob_i, rs_i, rt_i, rd_i, opcode_i, imm_i, reg_write_i,
                         1'b1, 1'b1, branch_i, branch_prediction_i,
                         branch_other_addr_i);
    endtask

    task automatic dispatch_load(
        input logic [ROB_INDEX_WIDTH-1:0]         rob_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] base_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd_i,
        input logic [15:0]                        imm_i
    );
        clear_dispatch();
        dis_ld_st_issq_en    = 1'b1;
        dis_reg_write        = 1'b1;
        dis_rs_data_ready    = 1'b1;
        dis_rs_phy_addr      = base_i;
        dis_new_rd_phy_addr  = rd_i;
        dis_rob_tag          = rob_i;
        dis_opcode           = INSTR_LW;
        dis_imm16            = imm_i;
        @(posedge clk); #1;
        clear_dispatch();
    endtask

    task automatic dispatch_store(
        input logic [ROB_INDEX_WIDTH-1:0]         rob_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] base_i,
        input logic [15:0]                        imm_i
    );
        clear_dispatch();
        dis_ld_st_issq_en    = 1'b1;
        dis_reg_write        = 1'b0;
        dis_rs_data_ready    = 1'b1;
        dis_rs_phy_addr      = base_i;
        dis_new_rd_phy_addr  = '0;
        dis_rob_tag          = rob_i;
        dis_opcode           = INSTR_SW;
        dis_imm16            = imm_i;
        @(posedge clk); #1;
        clear_dispatch();
    endtask

    task automatic dispatch_mul(
        input logic [ROB_INDEX_WIDTH-1:0]         rob_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rt_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd_i
    );
        clear_dispatch();
        dis_mul_issq_en      = 1'b1;
        dis_reg_write        = 1'b1;
        dis_rs_data_ready    = 1'b1;
        dis_rt_data_ready    = 1'b1;
        dis_rs_phy_addr      = rs_i;
        dis_rt_phy_addr      = rt_i;
        dis_new_rd_phy_addr  = rd_i;
        dis_rob_tag          = rob_i;
        dis_opcode           = INSTR_MUL;
        @(posedge clk); #1;
        clear_dispatch();
    endtask

    task automatic dispatch_divrem(
        input logic [ROB_INDEX_WIDTH-1:0]         rob_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rt_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd_i,
        input logic [OPCODE_WIDTH-1:0]            opcode_i
    );
        clear_dispatch();
        dis_div_issq_en      = 1'b1;
        dis_reg_write        = 1'b1;
        dis_rs_data_ready    = 1'b1;
        dis_rt_data_ready    = 1'b1;
        dis_rs_phy_addr      = rs_i;
        dis_rt_phy_addr      = rt_i;
        dis_new_rd_phy_addr  = rd_i;
        dis_rob_tag          = rob_i;
        dis_opcode           = opcode_i;
        @(posedge clk); #1;
        clear_dispatch();
    endtask

    task automatic wait_for_cdb_valid(input string tag);
        int cycles;
        begin
            for (cycles = 0; cycles < 80 && cdb_valid !== 1'b1; cycles++) begin
                @(posedge clk); #1;
            end
            check_bit({tag, " cdb_valid"}, cdb_valid, 1'b1);
        end
    endtask

    task automatic wait_for_dcache_req(input string tag);
        int cycles;
        begin
            for (cycles = 0; cycles < 20 && dcache_req !== 1'b1; cycles++) begin
                @(posedge clk); #1;
            end
            check_bit({tag, " dcache_req"}, dcache_req, 1'b1);
        end
    endtask

    task automatic check_no_cdb_for_cycles(input string tag, input int cycles_i);
        for (int i = 0; i < cycles_i; i++) begin
            @(posedge clk); #1;
            check_bit({tag, " no cdb_valid"}, cdb_valid, 1'b0);
        end
    endtask

    task automatic check_no_dcache_req_for_cycles(input string tag, input int cycles_i);
        for (int i = 0; i < cycles_i; i++) begin
            @(posedge clk); #1;
            check_bit({tag, " no dcache_req"}, dcache_req, 1'b0);
        end
    endtask

    task automatic dcache_respond(input logic [REG_FILE_DATA_WIDTH-1:0] data_i);
        dcache_rdata     = data_i;
        dcache_read_done = 1'b1;
        @(posedge clk); #1;
        dcache_read_done = 1'b0;
        dcache_rdata     = '0;
    endtask

    task automatic preload_reg(
        input logic [ROB_INDEX_WIDTH-1:0]         rob_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd_i,
        input logic [15:0]                        data_i
    );
        dispatch_int(rob_i, 7'd0, 7'd0, rd_i, INSTR_ADDI, data_i,
                     1'b1, 1'b0, 1'b0, 32'h0);
        wait_for_cdb_valid("preload");
        check_val("preload rd", cdb_rd_phy_addr, rd_i);
        check_val("preload data", cdb_rd_data, data_i);
        @(posedge clk); #1;
    endtask

    initial begin
        `ifdef FSDB_DUMP
            $fsdbDumpfile("CPU_BACK_END.fsdb");
            $fsdbDumpvars(0, CPU_BACK_END_tb);
            $fsdbDumpMDA();
        `else
            $dumpfile("CPU_BACK_END.vcd");
            $dumpvars(0, CPU_BACK_END_tb);
        `endif

        $display("=======================================");
        $display("  CPU_BACK_END Testbench Start");
        $display("=======================================");

        $display("\n[Test 1] Reset state");
        reset_dut();
        check_bit("cdb_valid after reset", cdb_valid, 1'b0);
        check_bit("dcache_req after reset", dcache_req, 1'b0);
        check_bit("int queue not full", issq_intq_full, 1'b0);
        check_bit("div queue not full", issq_divq_full, 1'b0);
        check_bit("mul queue not full", issq_mulq_full, 1'b0);
        check_bit("ld/st queue not full", issq_ld_stq_full, 1'b0);
        check_bit("int queue has vacancies", issq_intq_two_or_more_vacant, 1'b1);
        check_val("rt_sb_data reset", rt_sb_data, '0);

        $display("\n[Test 2] Integer ADDI dispatch reaches CDB and writes PRF");
        reset_dut();
        dispatch_int(4'd1, 7'd0, 7'd0, 7'd10, INSTR_ADDI, 16'd37,
                     1'b1, 1'b0, 1'b0, 32'h0);
        wait_for_cdb_valid("addi");
        check_val("addi rob tag", cdb_rob_tag, 4'd1);
        check_val("addi rd phy", cdb_rd_phy_addr, 7'd10);
        check_val("addi data", cdb_rd_data, 64'd37);
        check_bit("addi reg write", cdb_reg_write, 1'b1);
        check_bit("addi no flush", cdb_flush, 1'b0);
        rt_sb_phy_addr = 7'd10;
        @(posedge clk); #1;
        check_val("PRF writeback visible to store data port", rt_sb_data, 64'd37);

        $display("\n[Test 3] Load dispatch requests D-cache and broadcasts loaded data");
        reset_dut();
        dispatch_load(4'd2, 7'd0, 7'd12, 16'h0040);
        wait_for_dcache_req("load");
        check_val("load dcache addr", dcache_addr, 32'h40);
        dcache_respond(64'hCAFE_BABE_1234_5678);
        wait_for_cdb_valid("load");
        check_val("load cdb rob tag", cdb_rob_tag, 4'd2);
        check_val("load cdb rd phy", cdb_rd_phy_addr, 7'd12);
        check_val("load cdb data", cdb_rd_data, 64'hCAFE_BABE_1234_5678);
        check_bit("load cdb reg write", cdb_reg_write, 1'b1);

        $display("\n[Test 4] Mispredicted branch sets flush and branch update fields");
        reset_dut();
        dispatch_int(4'd3, 7'd0, 7'd0, 7'd0, INSTR_BEQ, 16'd0,
                     1'b0, 1'b1, 1'b1, 32'h0000_0200);
        wait_for_cdb_valid("branch");
        check_bit("branch update valid", cdb_upd_branch, 1'b1);
        check_bit("branch flush", cdb_flush, 1'b1);
        check_bit("branch outcome", cdb_branch_outcome, 1'b0);
        check_val("branch target", cdb_branch_addr, 32'h0000_0200);

        $display("\n[Test 5] Waiting integer operand wakes up from CDB");
        reset_dut();
        dispatch_int_raw(4'd5, 7'd20, 7'd0, 7'd21, INSTR_ADDI, 16'd5,
                         1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 32'h0);
        check_no_cdb_for_cycles("dependent int waits", 2);
        preload_reg(4'd4, 7'd20, 16'd11);
        wait_for_cdb_valid("dependent int");
        check_val("dependent rob tag", cdb_rob_tag, 4'd5);
        check_val("dependent rd phy", cdb_rd_phy_addr, 7'd21);
        check_val("dependent addi data", cdb_rd_data, 64'd16);
        check_bit("dependent reg write", cdb_reg_write, 1'b1);

        $display("\n[Test 6] Store dispatch produces CDB store sideband without PRF write");
        reset_dut();
        dispatch_store(4'd6, 7'd0, 16'h0080);
        wait_for_cdb_valid("store");
        check_val("store rob tag", cdb_rob_tag, 4'd6);
        check_val("store sw addr", cdb_sw_addr, 32'h80);
        check_bit("store no reg write", cdb_reg_write, 1'b0);
        check_bit("store lsb rw flag", lsb_rw, 1'b0);

        $display("\n[Test 7] D-cache busy holds a ready load in LSQ");
        reset_dut();
        dcache_read_busy = 1'b1;
        dispatch_load(4'd7, 7'd0, 7'd22, 16'h0030);
        check_no_dcache_req_for_cycles("busy dcache load", 3);
        dcache_read_busy = 1'b0;
        wait_for_dcache_req("busy load released");
        check_val("busy load dcache addr", dcache_addr, 32'h30);
        dcache_respond(64'h0000_0000_0000_0BAD);
        wait_for_cdb_valid("busy load result");
        check_val("busy load cdb data", cdb_rd_data, 64'hBAD);
        check_val("busy load rd phy", cdb_rd_phy_addr, 7'd22);

        $display("\n[Test 8] INT issue queue full and vacancy flags");
        reset_dut();
        dispatch_int_raw(4'd0, 7'd40, 7'd50, 7'd60, INSTR_ADD, 16'd0,
                         1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 32'h0);
        dispatch_int_raw(4'd1, 7'd41, 7'd51, 7'd61, INSTR_ADD, 16'd0,
                         1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 32'h0);
        check_bit("int queue still has two vacancies", issq_intq_two_or_more_vacant, 1'b1);
        dispatch_int_raw(4'd2, 7'd42, 7'd52, 7'd62, INSTR_ADD, 16'd0,
                         1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 32'h0);
        check_bit("int queue no longer has two vacancies", issq_intq_two_or_more_vacant, 1'b0);
        dispatch_int_raw(4'd3, 7'd43, 7'd53, 7'd63, INSTR_ADD, 16'd0,
                         1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 32'h0);
        check_bit("int queue full", issq_intq_full, 1'b1);
        check_bit("int queue has fewer than two vacancies", issq_intq_two_or_more_vacant, 1'b0);
        dispatch_int_raw(4'd4, 7'd44, 7'd54, 7'd64, INSTR_ADD, 16'd0,
                         1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 32'h0);
        check_bit("int queue stays full after overflow attempt", issq_intq_full, 1'b1);

        $display("\n[Test 9] MUL dispatch broadcasts product");
        reset_dut();
        preload_reg(4'd0, 7'd30, 16'd6);
        preload_reg(4'd1, 7'd31, 16'd7);
        dispatch_mul(4'd8, 7'd30, 7'd31, 7'd32);
        wait_for_cdb_valid("mul");
        check_val("mul rob tag", cdb_rob_tag, 4'd8);
        check_val("mul rd phy", cdb_rd_phy_addr, 7'd32);
        check_val("mul product", cdb_rd_data, 64'd42);
        check_bit("mul reg write", cdb_reg_write, 1'b1);

        $display("\n[Test 10] DIV dispatch broadcasts quotient");
        reset_dut();
        preload_reg(4'd0, 7'd33, 16'd100);
        preload_reg(4'd1, 7'd34, 16'd5);
        dispatch_divrem(4'd9, 7'd33, 7'd34, 7'd35, INSTR_DIV);
        wait_for_cdb_valid("div");
        check_val("div rob tag", cdb_rob_tag, 4'd9);
        check_val("div rd phy", cdb_rd_phy_addr, 7'd35);
        check_val("div quotient", cdb_rd_data, 64'd20);
        check_bit("div reg write", cdb_reg_write, 1'b1);

        $display("\n[Test 11] REM dispatch broadcasts remainder");
        reset_dut();
        preload_reg(4'd0, 7'd36, 16'd100);
        preload_reg(4'd1, 7'd37, 16'd6);
        dispatch_divrem(4'd10, 7'd36, 7'd37, 7'd38, INSTR_REM);
        wait_for_cdb_valid("rem");
        check_val("rem rob tag", cdb_rob_tag, 4'd10);
        check_val("rem rd phy", cdb_rd_phy_addr, 7'd38);
        check_val("rem remainder", cdb_rd_data, 64'd4);
        check_bit("rem reg write", cdb_reg_write, 1'b1);

        $display("\n[Test 12] Correctly predicted branch updates BPB without flush");
        reset_dut();
        dispatch_int(4'd11, 7'd0, 7'd0, 7'd0, INSTR_BNE, 16'd0,
                     1'b0, 1'b1, 1'b1, 32'h0000_0300);
        wait_for_cdb_valid("correct branch");
        check_bit("correct branch update valid", cdb_upd_branch, 1'b1);
        check_bit("correct branch no flush", cdb_flush, 1'b0);
        check_bit("correct branch outcome", cdb_branch_outcome, 1'b1);

        $display("\n============================================");
        if (fail_cnt == 0)
            $display("CPU_BACK_END_tb PASSED (%0d checks)", pass_cnt);
        else
            $display("CPU_BACK_END_tb FAILED: %0d failures, %0d passes", fail_cnt, pass_cnt);
        $display("============================================");
        $finish;
    end
endmodule
