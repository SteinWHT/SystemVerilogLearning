// Common data bus: registered broadcast from EXE or LSB.
/* verilator lint_off WIDTH */
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module CDB_tb;

    parameter int unsigned REG_FILE_DATA_WIDTH     = 64;
    parameter int unsigned DMEM_WIDTH              = 32;
    parameter int unsigned DMEM_DEPTH              = 32;
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7;
    parameter int unsigned ROB_INDEX_WIDTH         = 4;
    parameter int unsigned ROB_DEPTH               = 16;
    parameter int unsigned BPB_PC_BITS             = 3;

    logic clk;
    logic rst_n;

    logic [ROB_INDEX_WIDTH-1:0]         rob_top_ptr;

    logic                               cdb_valid;
    logic [ROB_INDEX_WIDTH-1:0]         cdb_rob_tag;
    logic [DMEM_DEPTH-1:0]              cdb_sw_addr;
    logic                               cdb_flush;

    logic [PHY_REGISTER_FILE_WIDTH-1:0] cdb_rd_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0]     cdb_rd_data;
    logic                               cdb_reg_write;
    logic [ROB_INDEX_WIDTH-1:0]         cdb_rob_depth;

    logic                               exe_valid;
    logic [ROB_INDEX_WIDTH-1:0]         exe_rob_tag;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] exe_rd_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0]     exe_rd_data;
    logic                               exe_reg_write;
    logic                               exe_branch_mispredicted;
    logic                               exe_branch;
    logic                               exe_jr_inst;
    logic                               exe_jr31_inst;
    logic                               exe_jal_inst;
    logic [BPB_PC_BITS-1:0]             exe_branch_pc_bits;
    logic [DMEM_WIDTH-1:0]              exe_branch_other_addr;

    logic [ROB_INDEX_WIDTH-1:0]         lsb_rob_tag;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] lsb_rd_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0]     lsb_data;
    logic                               lsb_rw;
    logic [DMEM_DEPTH-1:0]              lsb_sw_addr;
    logic                               lsb_ready;

    logic                               cdb_upd_branch;
    logic [BPB_PC_BITS-1:0]             cdb_upd_branch_addr;
    logic                               cdb_branch_outcome;
    logic [31:0]                        cdb_branch_addr;
    logic                               cdb_jalr_resolved;

    CDB #(
        .REG_FILE_DATA_WIDTH(REG_FILE_DATA_WIDTH),
        .DMEM_WIDTH(DMEM_WIDTH),
        .DMEM_DEPTH(DMEM_DEPTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .ROB_DEPTH(ROB_DEPTH),
        .BPB_PC_BITS(BPB_PC_BITS)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .rob_top_ptr(rob_top_ptr),
        .cdb_valid(cdb_valid),
        .cdb_rob_tag(cdb_rob_tag),
        .cdb_sw_addr(cdb_sw_addr),
        .cdb_flush(cdb_flush),
        .cdb_rd_phy_addr(cdb_rd_phy_addr),
        .cdb_rd_data(cdb_rd_data),
        .cdb_reg_write(cdb_reg_write),
        .cdb_rob_depth(cdb_rob_depth),
        .exe_valid(exe_valid),
        .exe_rob_tag(exe_rob_tag),
        .exe_rd_phy_addr(exe_rd_phy_addr),
        .exe_rd_data(exe_rd_data),
        .exe_reg_write(exe_reg_write),
        .exe_branch_mispredicted(exe_branch_mispredicted),
        .exe_branch(exe_branch),
        .exe_jr_inst(exe_jr_inst),
        .exe_jr31_inst(exe_jr31_inst),
        .exe_jal_inst(exe_jal_inst),
        .exe_branch_pc_bits(exe_branch_pc_bits),
        .exe_branch_other_addr(exe_branch_other_addr),
        .lsb_rob_tag(lsb_rob_tag),
        .lsb_rd_phy_addr(lsb_rd_phy_addr),
        .lsb_data(lsb_data),
        .lsb_rw(lsb_rw),
        .lsb_sw_addr(lsb_sw_addr),
        .lsb_ready(lsb_ready),
        .cdb_upd_branch(cdb_upd_branch),
        .cdb_upd_branch_addr(cdb_upd_branch_addr),
        .cdb_branch_outcome(cdb_branch_outcome),
        .cdb_branch_addr(cdb_branch_addr),
        .cdb_jalr_resolved(cdb_jalr_resolved)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    int pass_cnt = 0;
    int fail_cnt = 0;

    task automatic check_bit(input string tag, input logic actual, input logic expected);
        if (actual !== expected) begin
            $error("[FAIL] %s: got %0b, want %0b @ %0t", tag, actual, expected, $time);
            fail_cnt++;
        end else pass_cnt++;
    endtask

    task automatic check_val(input string tag, input logic [63:0] actual, input logic [63:0] expected);
        if (actual !== expected) begin
            $error("[FAIL] %s: got 0x%0h, want 0x%0h @ %0t", tag, actual, expected, $time);
            fail_cnt++;
        end else pass_cnt++;
    endtask

    task automatic clear_sources();
        exe_valid = 1'b0;
        lsb_ready = 1'b0;
        exe_rob_tag = '0;
        exe_rd_phy_addr = '0;
        exe_rd_data = '0;
        exe_reg_write = 1'b0;
        exe_branch_mispredicted = 1'b0;
        exe_branch = 1'b0;
        exe_jr_inst = 1'b0;
        exe_jr31_inst = 1'b0;
        exe_jal_inst = 1'b0;
        exe_branch_pc_bits = '0;
        exe_branch_other_addr = '0;
        lsb_rob_tag = '0;
        lsb_rd_phy_addr = '0;
        lsb_data = '0;
        lsb_rw = 1'b0;
        lsb_sw_addr = '0;
    endtask

    task automatic reset_dut();
        rst_n = 1'b0;
        rob_top_ptr = 4'd0;
        clear_sources();
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;
    endtask

    task automatic cycle();
        clear_sources();
        @(posedge clk); #1;
    endtask

    initial begin
        `ifdef FSDB_DUMP
        $fsdbDumpfile("CDB.fsdb");
        $fsdbDumpvars(0, CDB_tb);
        `endif

        reset_dut();
        check_bit("idle after reset", cdb_valid, 1'b0);

        $display("\n[Test 1] EXE result captured on next cycle");
        exe_valid       = 1'b1;
        exe_rob_tag     = 4'd4;
        exe_rd_phy_addr = 7'd15;
        exe_rd_data     = 64'hDEAD_BEEF_CAFE_0000;
        exe_reg_write   = 1'b1;
        rob_top_ptr     = 4'd2;
        @(posedge clk); #1;
        check_bit("cdb_valid", cdb_valid, 1'b1);
        check_val("cdb_rob_tag", cdb_rob_tag, 4'd4);
        check_val("cdb_rd_phy_addr", cdb_rd_phy_addr, 7'd15);
        check_val("cdb_rd_data", cdb_rd_data, 64'hDEAD_BEEF_CAFE_0000);
        check_bit("cdb_reg_write", cdb_reg_write, 1'b1);
        check_val("cdb_rob_depth", cdb_rob_depth, 4'd2);
        cycle();
        check_bit("cdb idle when no source", cdb_valid, 1'b0);

        $display("\n[Test 2] LSB load result on CDB");
        lsb_ready       = 1'b1;
        lsb_rob_tag     = 4'd6;
        lsb_rd_phy_addr = 7'd20;
        lsb_data        = 64'd1234;
        lsb_rw          = 1'b1;
        lsb_sw_addr     = 32'h1000;
        @(posedge clk); #1;
        check_bit("lsb cdb_valid", cdb_valid, 1'b1);
        check_val("lsb rob tag", cdb_rob_tag, 4'd6);
        check_val("lsb data", cdb_rd_data, 64'd1234);
        check_val("sw addr", cdb_sw_addr, 32'h1000);
        check_bit("no flush on load", cdb_flush, 1'b0);
        cycle();

        $display("\n[Test 3] Mispredicted branch sets flush");
        exe_valid               = 1'b1;
        exe_rob_tag             = 4'd8;
        exe_rd_phy_addr         = 7'd1;
        exe_rd_data             = 64'd0;
        exe_reg_write           = 1'b0;
        exe_branch              = 1'b1;
        exe_branch_mispredicted = 1'b1;
        exe_branch_other_addr   = 32'h4000;
        exe_branch_pc_bits      = 3'd2;
        @(posedge clk); #1;
        check_bit("branch flush", cdb_flush, 1'b1);
        check_bit("branch update", cdb_upd_branch, 1'b1);
        check_val("branch pc bits", cdb_upd_branch_addr, 3'd2);
        check_bit("branch outcome inverted flush", cdb_branch_outcome, 1'b0);
        cycle();

        $display("\n============================================");
        if (fail_cnt == 0)
            $display("CDB_tb PASSED (%0d checks)", pass_cnt);
        else
            $display("CDB_tb FAILED: %0d failures, %0d passes", fail_cnt, pass_cnt);
        $display("============================================");
        $finish;
    end
endmodule
