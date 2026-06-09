// Directed test for the FENCE.I cache-coherence controller sequencing.
// Verifies the ordered handshake: D$ clean -> I$ invalidate -> coh_done,
// and that inv_all stays asserted through coh_done until the FENCE.I commits.

`timescale 1ns/1ps

module cache_coherence_ctrl_tb;
    logic clk = 0;
    logic rst_n;
    logic coh_start;
    logic dcache_flush_req, dcache_flush_done;
    logic icache_inv_all;
    logic coh_done;

    int errors = 0;

    always #5 clk = ~clk;

    cache_coherence_ctrl u_dut (
        .clk (clk), .rst_n (rst_n),
        .coh_start (coh_start),
        .dcache_flush_req (dcache_flush_req),
        .dcache_flush_done (dcache_flush_done),
        .icache_inv_all (icache_inv_all),
        .coh_done (coh_done)
    );

    task automatic chk(input bit cond, input string msg);
        if (!cond) begin $display("[FAIL] %s", msg); errors++; end
        else         $display("[PASS] %s", msg);
    endtask

    initial begin
        coh_start = 0; dcache_flush_done = 0; rst_n = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        @(negedge clk);

        chk(!dcache_flush_req && !icache_inv_all && !coh_done, "idle: all outputs low");

        // FENCE.I reaches head, SB drained.
        coh_start = 1;
        @(negedge clk); // -> S_FLUSH
        chk(dcache_flush_req, "S_FLUSH: dcache_flush_req asserted");
        chk(!icache_inv_all, "S_FLUSH: I$ not yet invalidated (clean first)");
        chk(!coh_done, "S_FLUSH: coh_done still low");

        // Model the D$ taking several cycles to clean.
        repeat (5) @(negedge clk);
        chk(dcache_flush_req && !icache_inv_all, "still cleaning while flush not done");

        dcache_flush_done = 1;
        @(negedge clk);
        dcache_flush_done = 0; // pulse
        // now in S_INV
        chk(!dcache_flush_req, "S_INV: flush_req dropped after clean done");
        chk(icache_inv_all, "S_INV: I$ invalidation asserted after D$ clean");
        chk(!coh_done, "S_INV: coh_done still low");

        @(negedge clk); // -> S_DONE
        chk(coh_done, "S_DONE: coh_done asserted");
        chk(icache_inv_all, "S_DONE: inv_all held through commit");

        // Commit happens: coh_start drops.
        coh_start = 0;
        @(negedge clk); // -> S_IDLE
        chk(!coh_done && !icache_inv_all && !dcache_flush_req, "returned to idle after commit");

        if (errors == 0) $display("\n==== cache_coherence_ctrl_tb PASSED ====");
        else             $display("\n==== cache_coherence_ctrl_tb FAILED: %0d ====", errors);
        $finish;
    end

    initial begin #10000; $display("[FAIL] timeout"); $finish; end
endmodule
