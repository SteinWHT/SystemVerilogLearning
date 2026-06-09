// Directed test for the D-cache clean-all (FENCE.I coherence) engine.
//
// Scenario mirrors the I/D coherence hazard: the CPU writes data that lands as
// *dirty* lines in the write-back D-cache (so the shared backing memory still
// holds stale bytes). After asserting flush_req, every dirty line must be
// written back, leaving the backing memory consistent with the cache — which
// is exactly what lets the (separate) I-cache later refill correct bytes.

`timescale 1ns/1ps

module dcache_flush_tb;
    import dcache_pkg::*;

    logic clk = 1'b0;
    logic rst_n;

    // CPU load port
    logic            rvalid, rready, rresp_valid, rresp_ready;
    cache_addr_t     raddr;
    cache_word_t     rdata;

    // CPU store port
    logic            wvalid, wready, wresp_valid, wresp_ready;
    cache_addr_t     waddr;
    cache_word_t     wdata;
    cache_strb_t     wstrb;

    // Clean-all
    logic            flush_req, flush_busy, flush_done;

    // Memory bus
    logic            mem_req, mem_we, mem_ack;
    mem_idx_t        mem_idx;
    cache_word_t     mem_wdata, mem_rdata;

    logic [31:0]     stat_hits, stat_misses;

    int              errors = 0;

    always #5 clk = ~clk;

    dcache_top u_dut (
        .clk (clk), .rst_n (rst_n),
        .rvalid (rvalid), .rready (rready), .raddr (raddr),
        .rresp_valid (rresp_valid), .rresp_ready (rresp_ready), .rdata (rdata),
        .wvalid (wvalid), .wready (wready), .waddr (waddr),
        .wdata (wdata), .wstrb (wstrb),
        .wresp_valid (wresp_valid), .wresp_ready (wresp_ready),
        .flush_req (flush_req), .flush_busy (flush_busy), .flush_done (flush_done),
        .mem_req (mem_req), .mem_we (mem_we), .mem_idx (mem_idx),
        .mem_wdata (mem_wdata), .mem_rdata (mem_rdata), .mem_ack (mem_ack),
        .stat_hits (stat_hits), .stat_misses (stat_misses)
    );

    dcache_backing_mem u_mem (
        .clk (clk), .rst_n (rst_n),
        .req (mem_req), .we (mem_we), .idx (mem_idx),
        .wdata (mem_wdata), .rdata (mem_rdata), .ack (mem_ack),
        .init_en (1'b0), .init_idx ('0), .init_data ('0)
    );

    function automatic mem_idx_t word_idx(input cache_addr_t a);
        return a[BYTE_OFF_BITS +: MEM_IDX_BITS];
    endfunction

    // wresp_ready / rresp_ready are held high throughout (see initial block),
    // so responses are always consumed.
    task automatic do_store(input cache_addr_t a, input cache_word_t d);
        @(negedge clk);
        wvalid = 1'b1; waddr = a; wdata = d; wstrb = '1;
        // wready high at a negedge => the store is accepted at the next posedge.
        while (!wready) @(negedge clk);
        @(negedge clk);
        wvalid = 1'b0;
        // wait for the write response to be produced (and consumed).
        while (!wresp_valid) @(negedge clk);
        @(negedge clk);
    endtask

    task automatic check_mem(input cache_addr_t a, input cache_word_t exp,
                             input string name);
        cache_word_t got;
        got = u_mem.mem[word_idx(a)];
        if (got !== exp) begin
            $display("[FAIL] %s: mem[0x%0h] = 0x%016h, expected 0x%016h",
                     name, word_idx(a), got, exp);
            errors++;
        end else begin
            $display("[PASS] %s: mem[0x%0h] = 0x%016h", name, word_idx(a), got);
        end
    endtask

    // Three lines in distinct sets so each becomes its own dirty victim.
    localparam cache_addr_t A0 = 32'h0000_0040; // set 1
    localparam cache_addr_t A1 = 32'h0000_0800; // set 32
    localparam cache_addr_t A2 = 32'h0000_0FC0; // set 63
    localparam cache_word_t D0 = 64'hA5A5_A5A5_1111_2222;
    localparam cache_word_t D1 = 64'hDEAD_BEEF_CAFE_F00D;
    localparam cache_word_t D2 = 64'h0123_4567_89AB_CDEF;

    initial begin
        rvalid=0; raddr=0; rresp_ready=1'b1;
        wvalid=0; waddr=0; wdata=0; wstrb=0; wresp_ready=1'b1;
        flush_req=0;
        rst_n=0;
        repeat (4) @(negedge clk);
        rst_n=1;
        repeat (2) @(negedge clk);

        // Create three dirty lines (write-allocate misses).
        do_store(A0, D0);
        do_store(A1, D1);
        do_store(A2, D2);

        // Backing memory must still be stale (write-back, not yet evicted).
        if (u_mem.mem[word_idx(A0)] === D0) begin
            $display("[FAIL] backing memory updated before flush (not write-back!)");
            errors++;
        end else begin
            $display("[INFO] pre-flush: backing memory still stale, as expected");
        end

        // ---- FENCE.I clean-all ----
        @(negedge clk);
        flush_req = 1'b1;
        // wait for completion pulse
        do @(negedge clk); while (!flush_done);
        flush_req = 1'b0;
        $display("[INFO] flush_done observed");
        repeat (2) @(negedge clk);

        // After the clean, the shared memory must hold the cached values.
        check_mem(A0, D0, "line A0 cleaned");
        check_mem(A1, D1, "line A1 cleaned");
        check_mem(A2, D2, "line A2 cleaned");

        // A second flush with no dirty lines must still complete (and not
        // re-write memory): cleaned lines have their dirty bit cleared.
        @(negedge clk);
        flush_req = 1'b1;
        do @(negedge clk); while (!flush_done);
        flush_req = 1'b0;
        $display("[INFO] second (clean) flush completed");

        if (errors == 0)
            $display("\n==== dcache_flush_tb PASSED ====");
        else
            $display("\n==== dcache_flush_tb FAILED: %0d error(s) ====", errors);
        $finish;
    end

    // Watchdog
    initial begin
        #100000;
        $display("[FAIL] timeout");
        $finish;
    end

endmodule
