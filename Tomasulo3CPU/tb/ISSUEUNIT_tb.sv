// Standalone testbench for ISSUEUNIT issue arbitration and resource counters.
/* verilator lint_off WIDTH */
// verilog_lint: waive-start explicit-parameter-storage-type
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module ISSUEUNIT_tb;

    parameter int unsigned DIV_CYCLES = 7;
    parameter int unsigned MUL_CYCLES = 3;
    parameter int unsigned INT_CYCLES = 1;
    parameter int unsigned LD_ST_CYCLES = 1;

    logic clk;
    logic rst_n;

    logic ready_int;
    logic issue_int;

    logic ready_div;
    logic div_exe_ready;
    logic issue_div;

    logic ready_mul;
    logic issue_mul;

    logic ready_ld_buf;
    logic issue_ld_buf;

    ISSUEUNIT #(
        .DIV_CYCLES   (DIV_CYCLES),
        .MUL_CYCLES   (MUL_CYCLES),
        .INT_CYCLES   (INT_CYCLES),
        .LD_ST_CYCLES (LD_ST_CYCLES)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .ready_int      (ready_int),
        .issue_int      (issue_int),
        .ready_div      (ready_div),
        .div_exe_ready      (div_exe_ready),
        .issue_div      (issue_div),
        .ready_mul      (ready_mul),
        .issue_mul      (issue_mul),
        .ready_ld_buf   (ready_ld_buf),
        .issue_ld_buf   (issue_ld_buf)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    int pass_cnt = 0;
    int fail_cnt = 0;

    task automatic check_bit(
        input string tag,
        input logic  actual,
        input logic  expected
    );
        if (actual !== expected) begin
            $error("[FAIL] %s: got %0b, want %0b @ %0t",
                   tag, actual, expected, $time);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
    endtask

    task automatic check_onehot(
        input string tag,
        input logic  got_int,
        input logic  got_div,
        input logic  got_mul,
        input logic  got_ld,
        input logic  exp_int,
        input logic  exp_div,
        input logic  exp_mul,
        input logic  exp_ld
    );
        check_bit({tag, " issue_int"},    got_int, exp_int);
        check_bit({tag, " issue_div"},    got_div, exp_div);
        check_bit({tag, " issue_mul"},    got_mul, exp_mul);
        check_bit({tag, " issue_ld_buf"}, got_ld,  exp_ld);
    endtask

    task automatic clear_ready();
        ready_int     = 1'b0;
        ready_div     = 1'b0;
        div_exe_ready = 1'b0;
        ready_mul     = 1'b0;
        ready_ld_buf  = 1'b0;
    endtask

    task automatic reset_dut();
        rst_n = 1'b0;
        clear_ready();
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;
    endtask

    // Sample combinational grants after inputs settle (before posedge).
    task automatic expect_grants(
        input string tag,
        input logic  exp_int,
        input logic  exp_div,
        input logic  exp_mul,
        input logic  exp_ld
    );
        #1;
        check_onehot(tag, issue_int, issue_div, issue_mul, issue_ld_buf,
                     exp_int, exp_div, exp_mul, exp_ld);
    endtask

    task automatic cycle();
        @(posedge clk); #1;
    endtask

    initial begin
        `ifdef FSDB_DUMP
            $fsdbDumpfile("issueunit.fsdb");
            $fsdbDumpvars(0, ISSUEUNIT_tb);
        `else
            $dumpfile("issueunit.vcd");
            $dumpvars(0, ISSUEUNIT_tb);
        `endif

        $display("=======================================");
        $display("  ISSUEUNIT Testbench Start");
        $display("=======================================");

        $display("\n[Test 1] Reset: no grants");
        reset_dut();
        expect_grants("reset", 1'b0, 1'b0, 1'b0, 1'b0);

        $display("\n[Test 2] DIV has highest priority when executable");
        ready_div     = 1'b1;
        div_exe_ready = 1'b1;
        ready_mul     = 1'b1;
        ready_int     = 1'b1;
        ready_ld_buf  = 1'b1;
        expect_grants("all ready", 1'b0, 1'b1, 1'b0, 1'b0);
        cycle();
        clear_ready();
        expect_grants("after div issue", 1'b0, 1'b0, 1'b0, 1'b0);

        $display("\n[Test 3] DIV blocks re-issue for DIV_CYCLES-1 more cycles");
        ready_div     = 1'b1;
        div_exe_ready = 1'b1;
        expect_grants("div re-ready while busy", 1'b0, 1'b0, 1'b0, 1'b0);
        repeat (DIV_CYCLES - 2) cycle();
        ready_div     = 1'b1;
        div_exe_ready = 1'b1;
        expect_grants("div executable again", 1'b0, 1'b1, 1'b0, 1'b0);
        cycle();
        clear_ready();

        $display("\n[Test 4] MUL issues when DIV not completing next cycle and DIV counter != 4");
        reset_dut();
        ready_mul = 1'b1;
        expect_grants("mul alone", 1'b0, 1'b0, 1'b1, 1'b0);
        cycle();
        clear_ready();

        $display("\n[Test 5] MUL blocked when DIV will complete in 4 cycles (counter == 4)");
        reset_dut();
        ready_div     = 1'b1;
        div_exe_ready = 1'b1;
        expect_grants("issue div", 1'b0, 1'b1, 1'b0, 1'b0);
        cycle();
        clear_ready();
        repeat (3) cycle();
        ready_mul = 1'b1;
        expect_grants("mul blocked at div counter 4", 1'b0, 1'b0, 1'b0, 1'b0);
        cycle();
        clear_ready();
        cycle();
        ready_mul = 1'b1;
        expect_grants("mul after div counter leaves 4", 1'b0, 1'b0, 1'b1, 1'b0);
        cycle();
        clear_ready();

        $display("\n[Test 6] INT and LD/ST blocked when DIV counter == 1");
        reset_dut();
        ready_div     = 1'b1;
        div_exe_ready = 1'b1;
        expect_grants("start div", 1'b0, 1'b1, 1'b0, 1'b0);
        cycle();
        clear_ready();
        repeat (DIV_CYCLES - 2) cycle();
        ready_int    = 1'b1;
        ready_ld_buf = 1'b1;
        expect_grants("block int/ld at div counter 1", 1'b0, 1'b0, 1'b0, 1'b0);
        cycle();
        clear_ready();

        $display("\n[Test 7] INT and LD/ST blocked when MUL pipeline slot is active");
        reset_dut();
        ready_mul = 1'b1;
        expect_grants("issue mul", 1'b0, 1'b0, 1'b1, 1'b0);
        cycle();
        clear_ready();
        ready_int    = 1'b1;
        ready_ld_buf = 1'b1;
        expect_grants("block int/ld during mul counter[0]", 1'b0, 1'b0, 1'b0, 1'b0);
        cycle();
        clear_ready();
        repeat (MUL_CYCLES - 1) cycle();
        ready_int    = 1'b1;
        ready_ld_buf = 1'b1;
        expect_grants("int/ld after mul pipeline drains", 1'b1, 1'b0, 1'b0, 1'b0);
        cycle();
        clear_ready();

        $display("\n[Test 8] LRU alternates INT and LD/ST when both ready");
        reset_dut();
        ready_int    = 1'b1;
        ready_ld_buf = 1'b1;
        expect_grants("first pick int (priority=1)", 1'b1, 1'b0, 1'b0, 1'b0);
        cycle();
        clear_ready();
        ready_int    = 1'b1;
        ready_ld_buf = 1'b1;
        expect_grants("second pick ld (priority flipped)", 1'b0, 1'b0, 1'b0, 1'b1);
        cycle();
        clear_ready();
        ready_int    = 1'b1;
        ready_ld_buf = 1'b1;
        expect_grants("third pick int again", 1'b1, 1'b0, 1'b0, 1'b0);
        cycle();
        clear_ready();

        $display("\n[Test 9] Only LD/ST ready issues load buffer");
        reset_dut();
        ready_ld_buf = 1'b1;
        expect_grants("ld only", 1'b0, 1'b0, 1'b0, 1'b1);
        cycle();
        clear_ready();

        $display("\n[Test 10] Only INT ready issues ALU");
        reset_dut();
        ready_int = 1'b1;
        expect_grants("int only", 1'b1, 1'b0, 1'b0, 1'b0);
        cycle();
        clear_ready();

        $display("\n[Test 11] DIV not ready when divider busy (div_exe_ready=0)");
        reset_dut();
        ready_div     = 1'b1;
        div_exe_ready = 1'b0;
        ready_mul     = 1'b1;
        expect_grants("mul when div not executable", 1'b0, 1'b0, 1'b1, 1'b0);
        cycle();
        clear_ready();

        $display("\n=======================================");
        $display("  ISSUEUNIT Done: %0d passed, %0d failed", pass_cnt, fail_cnt);
        $display("=======================================");

        if (fail_cnt == 0) begin
            $display("[PASS] ISSUEUNIT_tb completed successfully");
        end else begin
            $fatal(1, "[FAIL] ISSUEUNIT_tb found %0d failure(s)", fail_cnt);
        end
        $finish;
    end

    initial begin
        #200_000;
        $error("TIMEOUT");
        $finish;
    end

endmodule
/* verilator lint_on WIDTH */
/* verilator lint_on BLKSEQ */
// verilog_lint: waive-stop explicit-parameter-storage-type
