`timescale 1ns/1ps

module ISSUEUNIT_tb;

    logic clk, rst_n;
    logic ready_int, issue_int;
    logic ready_div, div_exe_ready, issue_div;
    logic ready_mul, issue_mul;
    logic ready_ld_buf, issue_ld_buf;

    ISSUEUNIT dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        ready_int = 0;
        ready_div = 0;
        ready_mul = 0;
        ready_ld_buf = 0;
        div_exe_ready = 1;

        rst_n = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;

        ready_int = 1;
        @(posedge clk);
        if (!issue_int) $fatal(1, "expected int issue when only int ready");

        ready_int = 0;
        ready_div = 1;
        @(posedge clk);
        if (!issue_div) $fatal(1, "expected div issue when div ready and div_exe_ready");

        $display("ISSUEUNIT_tb: pass");
        $finish;
    end

endmodule
