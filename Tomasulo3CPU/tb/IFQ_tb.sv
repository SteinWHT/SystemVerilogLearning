// Disable width mismatch in my IDE which uses verilator.
// The warning still works when I actually run simulation in Verdi.
/* verilator lint_off WIDTH */
// verilog_lint: waive-start explicit-parameter-storage-type
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module IFQ_tb;

    parameter INSTR_WIDTH = 32;
    parameter IMEM_DEPTH  = 64;
    parameter IMEM_WIDTH  = 32;   // 1 instr per fetch
    parameter IMEM_WIDTH_WORD = IMEM_DEPTH - 1; // number of bits needed to index IMEM_DEPTH words
    parameter DEPTH       = 16;
    parameter NUM_WAYS    = 4;

    logic                       clk;
    logic                       rst_n;
    logic [IMEM_WIDTH-1:0]      imem_data;
    logic                       imem_valid;
    logic [IMEM_DEPTH-1:0]      imem_addr;
    logic                       imem_read_rdy;
    logic                       dis_ren;
    logic                       dis_jmpbr;
    logic [IMEM_WIDTH_WORD-1:0] dis_jmpbr_addr;
    logic                       dis_jmpbr_addr_valid;
    logic [INSTR_WIDTH-1:0]     ifq_instr_out;
    logic [IMEM_DEPTH-1:0]      ifq_pc;
    logic [IMEM_DEPTH-1:0]      ifq_pc_plus4;
    logic                       ifq_empty;

    IFQ #(
        .INSTR_WIDTH (INSTR_WIDTH),
        .IMEM_DEPTH  (IMEM_DEPTH),
        .IMEM_WIDTH  (IMEM_WIDTH),
        .IMEM_WIDTH_WORD(IMEM_WIDTH_WORD),
        .DEPTH       (DEPTH),
        .NUM_WAYS    (NUM_WAYS)
    ) dut (.*);

    // ---- clock ----
    initial clk = 0;
    always #5 clk = ~clk;   // 100 MHz

    // ---- scoreboard ----
    int pass_cnt = 0;
    int fail_cnt = 0;

    task automatic check(string tag, logic [63:0] actual, logic [63:0] expected);
        if (actual !== expected) begin
            $error("[FAIL] %s: got 0x%0h, want 0x%0h  @ %0t", tag, actual, expected, $time);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
    endtask

    // ---- helper tasks ----
    task automatic reset_dut();
        rst_n            = 0;
        imem_valid       = 0;
        imem_data        = '0;
        dis_ren          = 0;
        dis_jmpbr        = 0;
        dis_jmpbr_addr   = '0;
        dis_jmpbr_addr_valid = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        @(posedge clk); #1;
    endtask

    // Feed one instruction (drives for exactly 1 cycle)
    task automatic feed_one(logic [INSTR_WIDTH-1:0] instr);
        imem_data  = instr;
        imem_valid = 1;
        @(posedge clk); #1;
        imem_valid = 0;
    endtask

    // Read head instruction. IFQ/sync_fifo expose the current head before the read edge.
    task automatic read_one(output logic [INSTR_WIDTH-1:0] data);
        data    = ifq_instr_out;
        dis_ren = 1;
        @(posedge clk); #1;
        dis_ren = 0;
    endtask

    // idle for 1 cycle
    task automatic idle();
        @(posedge clk); #1;
    endtask

    // ---- tests ----
    logic [INSTR_WIDTH-1:0] rdata;

    initial begin
        // Waveform dump (Synopsys FSDB for Verdi; VCD as fallback)
        `ifdef FSDB_DUMP
            $fsdbDumpfile("ifq.fsdb");
            $fsdbDumpvars(0, IFQ_tb);
        `else
            $dumpfile("ifq.vcd");
            $dumpvars(0, IFQ_tb);
        `endif

        $display("=======================================");
        $display("  IFQ Testbench Start");
        $display("=======================================");

        // ------------------------------------------------
        // Test 1 : Reset state
        // ------------------------------------------------
        $display("\n[Test 1] Reset");
        reset_dut();
        check("empty after reset",     ifq_empty,  1);
        check("imem_addr after reset",  imem_addr,  '0);
        check("imem_read_rdy after rst", imem_read_rdy, 1);

        // ------------------------------------------------
        // Test 2 : Write 1 -> read 1
        // ------------------------------------------------
        $display("\n[Test 2] Write 1, read 1");
        feed_one(32'hDEAD_BEEF);
        check("not empty",    ifq_empty,     0);
        check("head instr",   ifq_instr_out, 32'hDEAD_BEEF);
        check("pc",           ifq_pc,        64'd0);
        check("pc+4",         ifq_pc_plus4,  64'd4);

        read_one(rdata);
        check("read data",    rdata,         32'hDEAD_BEEF);
        check("empty again",  ifq_empty,     1);

        // ------------------------------------------------
        // Test 3 : Fill 8, drain 8 — ordering check
        // ------------------------------------------------
        $display("\n[Test 3] Fill 8, drain 8 (ordering)");
        for (int i = 0; i < 8; i++) feed_one(32'hA000_0000 + i);

        check("not empty after fill", ifq_empty, 0);

        for (int i = 0; i < 8; i++) begin
            check($sformatf("order[%0d] instr", i), ifq_instr_out, 32'hA000_0000 + i);
            check($sformatf("order[%0d] pc+4",  i), ifq_pc_plus4,  64'(4*(i+2)));
            // i+2 because we already consumed 1 instr (test2) + i instrs read so far:
            // head_pc = (1+i)*4, pc+4 = (2+i)*4
            read_one(rdata);
        end
        check("empty after drain", ifq_empty, 1);

        // ------------------------------------------------
        // Test 4 : Simultaneous read & write
        // ------------------------------------------------
        $display("\n[Test 4] Simultaneous read + write");
        feed_one(32'h1111_1111);
        feed_one(32'h2222_2222);

        // write 0x3333 while reading 0x1111
        check("head before simul", ifq_instr_out, 32'h1111_1111);
        imem_data  = 32'h3333_3333;
        imem_valid = 1;
        dis_ren    = 1;
        @(posedge clk); #1;
        imem_valid = 0;
        dis_ren    = 0;

        check("head after simul",  ifq_instr_out, 32'h2222_2222);
        read_one(rdata);
        check("second entry",      rdata,         32'h2222_2222);
        check("third entry",       ifq_instr_out, 32'h3333_3333);
        read_one(rdata);
        check("empty after simul", ifq_empty, 1);

        // ------------------------------------------------
        // Test 5 : Fill to DEPTH
        // ------------------------------------------------
        $display("\n[Test 5] Fill to capacity (DEPTH=%0d)", DEPTH);
        reset_dut();
        for (int i = 0; i < DEPTH; i++) feed_one(32'hB000_0000 + i);

        check("not empty when full", ifq_empty, 0);
        check("read_rdy 0 when full", imem_read_rdy, 0);

        // one more write should be ignored
        imem_data  = 32'hBAD0_FACE;
        imem_valid = 1;
        @(posedge clk); #1;
        imem_valid = 0;

        // drain and verify ordering
        for (int i = 0; i < DEPTH; i++) begin
            check($sformatf("full[%0d]", i), ifq_instr_out, 32'hB000_0000 + i);
            read_one(rdata);
        end
        check("empty after full drain", ifq_empty, 1);

        // ------------------------------------------------
        // Test 6 : Flush (branch misprediction)
        // ------------------------------------------------
        $display("\n[Test 6] Flush");
        reset_dut();
        feed_one(32'hAAAA_AAAA);
        feed_one(32'hBBBB_BBBB);
        feed_one(32'hCCCC_CCCC);
        check("not empty pre-flush", ifq_empty, 0);

        dis_jmpbr           = 1;
        dis_jmpbr_addr      = 64'h100;
        dis_jmpbr_addr_valid = 1;
        @(posedge clk); #1;
        dis_jmpbr           = 0;
        dis_jmpbr_addr_valid = 0;

        check("empty after flush",   ifq_empty,  1);
        check("imem_addr after flush", imem_addr, 64'h200);

        // feed at new PC
        feed_one(32'h1234_5678);
        check("new instr",   ifq_instr_out, 32'h1234_5678);
        check("pc flush",    ifq_pc,        64'h200);
        check("pc+4 flush",  ifq_pc_plus4,  64'h204);
        read_one(rdata);

        // ------------------------------------------------
        // Test 7 : Branch stall (jmpbr=1, addr_valid=0)
        // ------------------------------------------------
        $display("\n[Test 7] Branch stall");
        reset_dut();
        feed_one(32'h0000_0001);
        feed_one(32'h0000_0002);

        // stall: jmpbr high, addr not valid — no reads or writes
        dis_jmpbr           = 1;
        dis_jmpbr_addr_valid = 0;
        dis_ren             = 1;
        imem_data           = 32'hFFFF_FFFF;
        imem_valid          = 1;
        @(posedge clk); #1;
        dis_jmpbr   = 0;
        dis_ren     = 0;
        imem_valid  = 0;

        // queue should still hold original two entries
        check("stall: head unchanged", ifq_instr_out, 32'h0000_0001);
        read_one(rdata);
        check("stall: first",          rdata,         32'h0000_0001);
        check("stall: second",         ifq_instr_out, 32'h0000_0002);
        read_one(rdata);
        check("stall: second",         rdata,         32'h0000_0002);
        check("stall: empty",          ifq_empty, 1);

        // ------------------------------------------------
        // Test 8 : PC tracking across reset & flush
        // ------------------------------------------------
        $display("\n[Test 8] PC tracking");
        reset_dut();

        for (int i = 0; i < 4; i++) feed_one(32'hC000_0000 + i);

        for (int i = 0; i < 4; i++) begin
            check($sformatf("pc[%0d]",   i), ifq_pc,      64'(4*i));
            check($sformatf("pc+4[%0d]", i), ifq_pc_plus4, 64'(4*(i+1)));
            read_one(rdata);
        end

        // ------------------------------------------------
        // Test 9 : imem_addr advances correctly
        // ------------------------------------------------
        $display("\n[Test 9] imem_addr tracking");
        reset_dut();
        check("addr init", imem_addr, 64'h0);
        feed_one(32'h0);
        check("addr +4",  imem_addr, 64'h4);
        feed_one(32'h0);
        check("addr +8",  imem_addr, 64'h8);
        feed_one(32'h0);
        check("addr +c",  imem_addr, 64'hC);

        // ------------------------------------------------
        // Summary
        // ------------------------------------------------
        $display("\n=======================================");
        $display("  Passed: %0d   Failed: %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("  ** ALL TESTS PASSED **");
        else               $display("  !! SOME TESTS FAILED !!");
        $display("=======================================");
        $finish;
    end

    // Timeout guard
    initial begin
        #100_000;
        $error("TIMEOUT");
        $finish;
    end

endmodule
/* verilator lint_on WIDTH */
/* verilator lint_on BLKSEQ */
// verilog_lint: waive-stop explicit-parameter-storage-type
