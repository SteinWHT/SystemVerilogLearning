`timescale 1ns/1ps

module LSQ_fence_tb;
    import riscv_types_pkg::*;

    localparam int unsigned LSQ_DEPTH = 4;
    localparam int unsigned LSQ_INDEX_WIDTH = $clog2(LSQ_DEPTH);
    localparam int unsigned SAB_DEPTH = 4;
    localparam int unsigned SAB_INDEX_WIDTH = $clog2(SAB_DEPTH);
    localparam int unsigned DMEM_DEPTH = 32;
    localparam int unsigned ROB_DEPTH = 16;
    localparam int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH);
    localparam int unsigned PHY_REGISTER_FILE_WIDTH = 7;
    localparam int unsigned REG_FILE_DATA_WIDTH = 64;
    localparam int unsigned SB_DEPTH = 4;
    localparam int unsigned SB_INDEX_WIDTH = $clog2(SB_DEPTH);
    localparam int unsigned OPCODE_WIDTH = 7;

    logic clk;
    logic rst_n;
    logic [SB_INDEX_WIDTH-1:0] sb_flush_sw_tag;
    logic sb_flush_sw;
    logic sb_entry_sw;
    logic [SB_INDEX_WIDTH-1:0] sb_entry_sw_tag;
    logic [ROB_INDEX_WIDTH-1:0] sb_entry_sw_rob_tag;
    logic [ROB_INDEX_WIDTH-1:0] rob_tag;
    logic [ROB_INDEX_WIDTH-1:0] rob_top_ptr;
    logic rob_fence_pending;
    logic [ROB_INDEX_WIDTH-1:0] rob_fence_tag;
    logic rob_commit_mem_write;
    logic dis_ld_st_issue_en;
    logic dis_rs_data_ready;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rs_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_new_rd_phy_addr;
    logic [ROB_INDEX_WIDTH-1:0] dis_rob_tag;
    logic [OPCODE_WIDTH-1:0] dis_opcode;
    logic [7:0] dis_imm;
    logic lsq_ld_st_full;
    logic lsq_ld_st_two_or_more_vacant;
    logic dcache_ready;
    logic dcache_valid;
    logic [DMEM_DEPTH-1:0] dcache_addr;
    logic cdb_valid;
    logic cdb_flush;
    logic [ROB_INDEX_WIDTH-1:0] cdb_rob_depth;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] cdb_rd_phy_addr;
    logic cdb_phy_reg_write;
    logic [REG_FILE_DATA_WIDTH-1:0] iss_rs_data_lsq;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rs_phy_addr_ls;
    logic lsb_en;
    logic [OPCODE_WIDTH-1:0] iss_lsq_opcode;
    logic [ROB_INDEX_WIDTH-1:0] iss_lsq_rob_tag;
    logic [DMEM_DEPTH-1:0] iss_lsq_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_lsq_phy_addr;
    logic iss_lsq_rdy;

    LSQ #(
        .XLEN(8),
        .LSQ_DEPTH(LSQ_DEPTH),
        .LSQ_INDEX_WIDTH(LSQ_INDEX_WIDTH),
        .SAB_DEPTH(SAB_DEPTH),
        .SAB_INDEX_WIDTH(SAB_INDEX_WIDTH),
        .DMEM_DEPTH(DMEM_DEPTH),
        .ROB_DEPTH(ROB_DEPTH),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .REG_FILE_DATA_WIDTH(REG_FILE_DATA_WIDTH),
        .SB_DEPTH(SB_DEPTH),
        .SB_INDEX_WIDTH(SB_INDEX_WIDTH),
        .OPCODE_WIDTH(OPCODE_WIDTH)
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

    task automatic clear_inputs();
        sb_flush_sw_tag = '0;
        sb_flush_sw = 1'b0;
        sb_entry_sw = 1'b0;
        sb_entry_sw_tag = '0;
        sb_entry_sw_rob_tag = '0;
        rob_tag = '0;
        rob_top_ptr = '0;
        rob_fence_pending = 1'b0;
        rob_fence_tag = '0;
        rob_commit_mem_write = 1'b0;
        dis_ld_st_issue_en = 1'b0;
        dis_rs_data_ready = 1'b1;
        dis_rs_phy_addr = 7'd1;
        dis_new_rd_phy_addr = 7'd32;
        dis_rob_tag = '0;
        dis_opcode = INSTR_LD;
        dis_imm = '0;
        dcache_ready = 1'b1;
        cdb_valid = 1'b0;
        cdb_flush = 1'b0;
        cdb_rob_depth = '0;
        cdb_rd_phy_addr = '0;
        cdb_phy_reg_write = 1'b0;
        iss_rs_data_lsq = 64'h100;
        lsb_en = 1'b0;
    endtask

    task automatic reset_dut();
        rst_n = 1'b0;
        clear_inputs();
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1;
    endtask

    task automatic enqueue_ready_load(input logic [ROB_INDEX_WIDTH-1:0] tag);
        dis_rob_tag = tag;
        dis_ld_st_issue_en = 1'b1;
        @(posedge clk);
        #1;
        dis_ld_st_issue_en = 1'b0;
        @(posedge clk);
        #1;
    endtask

    task automatic consume_load();
        lsb_en = 1'b1;
        @(posedge clk);
        #1;
        lsb_en = 1'b0;
    endtask

    initial begin
        failures = 0;

        $display("[TEST] A load older than the fence may issue");
        reset_dut();
        rob_top_ptr = 4'd0;
        rob_fence_pending = 1'b1;
        rob_fence_tag = 4'd4;
        enqueue_ready_load(4'd3);
        check_bit("older load ready", iss_lsq_rdy, 1'b1);
        check_bit("older load reaches dcache only when accepted", dcache_valid, 1'b0);
        lsb_en = 1'b1;
        #1;
        check_bit("older load can access dcache", dcache_valid, 1'b1);
        consume_load();

        $display("[TEST] A load younger than the fence waits for retirement");
        enqueue_ready_load(4'd5);
        check_bit("younger load blocked", iss_lsq_rdy, 1'b0);
        check_bit("younger load cannot access dcache", dcache_valid, 1'b0);
        rob_fence_pending = 1'b0;
        #1;
        check_bit("younger load released after fence", iss_lsq_rdy, 1'b1);
        lsb_en = 1'b1;
        #1;
        check_bit("released load accesses dcache", dcache_valid, 1'b1);
        consume_load();

        $display("[TEST] ROB wraparound preserves the age comparison");
        reset_dut();
        rob_top_ptr = 4'd14;
        rob_fence_pending = 1'b1;
        rob_fence_tag = 4'd15;
        enqueue_ready_load(4'd0);
        check_bit("wrapped younger load blocked", iss_lsq_rdy, 1'b0);
        rob_fence_pending = 1'b0;
        #1;
        check_bit("wrapped load released after fence", iss_lsq_rdy, 1'b1);

        if (failures == 0)
            $display("[PASS] LSQ_fence_tb");
        else
            $fatal(1, "[FAIL] LSQ_fence_tb: %0d failure(s)", failures);
        $finish;
    end

    initial begin
        #100_000;
        $fatal(1, "[FAIL] LSQ_fence_tb timeout");
    end
endmodule
