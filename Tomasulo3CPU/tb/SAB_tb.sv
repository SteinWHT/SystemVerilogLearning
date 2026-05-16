`timescale 1ns/1ps

module SAB_tb;

    parameter int unsigned SAB_DEPTH   = 8;
    parameter int unsigned SB_DEPTH    = 4;
    localparam int unsigned SB_INDEX_WIDTH = $clog2(SB_DEPTH);
    parameter int unsigned DMEM_DEPTH  = 32;
    parameter int unsigned ROB_DEPTH   = 16;
    localparam int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH);

    logic clk, rst_n;
    logic [SB_INDEX_WIDTH-1:0] sb_flush_sw_tag, sb_entry_sw_tag;
    logic sb_flush_sw;
    logic [ROB_INDEX_WIDTH-1:0] rob_tag, rob_bottom_ptr;
    logic rob_commit_mem_write;
    logic lsq_empty;
    logic valid_out;

    SAB #(
        .SAB_DEPTH(SAB_DEPTH),
        .SB_DEPTH(SB_DEPTH),
        .DMEM_DEPTH(DMEM_DEPTH),
        .ROB_DEPTH(ROB_DEPTH)
    ) dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        sb_flush_sw_tag = 0;
        sb_flush_sw = 0;
        sb_entry_sw_tag = 0;
        rob_tag = 0;
        rob_bottom_ptr = 0;
        rob_commit_mem_write = 0;
        lsq_empty = 1;
        rst_n = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        if (valid_out !== 0) $fatal(1, "SAB stub valid_out");
        $display("SAB_tb: pass");
        $finish;
    end

endmodule
