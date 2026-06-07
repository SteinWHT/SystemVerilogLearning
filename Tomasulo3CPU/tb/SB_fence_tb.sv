`timescale 1ns/1ps

module SB_fence_tb;
    localparam int unsigned SB_DEPTH = 4;
    localparam int unsigned SB_INDEX_WIDTH = $clog2(SB_DEPTH);
    localparam int unsigned ROB_DEPTH = 16;
    localparam int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH);
    localparam int unsigned DMEM_WIDTH = 64;
    localparam int unsigned DMEM_DEPTH = 32;
    localparam int unsigned W_BYTE_NUM = DMEM_WIDTH / 8;

    logic clk;
    logic rst_n;
    logic [ROB_INDEX_WIDTH-1:0] rob_top_ptr;
    logic [DMEM_DEPTH-1:0] rob_sw_addr;
    logic [W_BYTE_NUM-1:0] rob_sw_strb;
    logic rob_commit_mem_write;
    logic [DMEM_WIDTH-1:0] rt_sb_data;
    logic dcache_ready;
    logic dcache_resp_valid;
    logic [DMEM_DEPTH-1:0] dcache_sw_addr;
    logic [W_BYTE_NUM-1:0] dcache_wstrb;
    logic [DMEM_WIDTH-1:0] dcache_sw_data;
    logic dcache_valid;
    logic dcache_resp_ready;
    logic [SB_INDEX_WIDTH-1:0] sb_flush_sw_tag;
    logic sb_flush_sw;
    logic sb_entry_sw;
    logic [SB_INDEX_WIDTH-1:0] sb_entry_sw_tag;
    logic [ROB_INDEX_WIDTH-1:0] sb_entry_sw_rob_tag;
    logic full;
    logic empty;
    logic drained;

    SB #(
        .SB_DEPTH(SB_DEPTH),
        .SB_INDEX_WIDTH(SB_INDEX_WIDTH),
        .ROB_DEPTH(ROB_DEPTH),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .DMEM_WIDTH(DMEM_WIDTH),
        .DMEM_DEPTH(DMEM_DEPTH),
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

    initial begin
        failures = 0;
        rst_n = 1'b0;
        rob_top_ptr = '0;
        rob_sw_addr = 32'h100;
        rob_sw_strb = 8'hff;
        rob_commit_mem_write = 1'b0;
        rt_sb_data = 64'h0123_4567_89ab_cdef;
        dcache_ready = 1'b0;
        dcache_resp_valid = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        #1;

        check_bit("reset buffer is drained", drained, 1'b1);

        rob_commit_mem_write = 1'b1;
        @(posedge clk);
        #1;
        rob_commit_mem_write = 1'b0;
        check_bit("queued store makes buffer nonempty", empty, 1'b0);
        check_bit("queued store makes buffer not drained", drained, 1'b0);

        dcache_ready = 1'b1;
        @(posedge clk);
        #1;
        dcache_ready = 1'b0;
        check_bit("accepted request leaves no unsent store", empty, 1'b1);
        check_bit("outstanding response keeps buffer not drained", drained, 1'b0);
        check_bit("store buffer waits for response", dcache_resp_ready, 1'b1);

        dcache_resp_valid = 1'b1;
        @(posedge clk);
        #1;
        dcache_resp_valid = 1'b0;
        check_bit("completed response drains store buffer", drained, 1'b1);

        if (failures == 0)
            $display("[PASS] SB_fence_tb");
        else
            $fatal(1, "[FAIL] SB_fence_tb: %0d failure(s)", failures);
        $finish;
    end

    initial begin
        #100_000;
        $fatal(1, "[FAIL] SB_fence_tb timeout");
    end
endmodule
