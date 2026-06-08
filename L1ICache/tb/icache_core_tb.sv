// Directed L1 I-cache tests with 4-instruction fetch.
//
// Geometry: 16 KiB, 4-way, 64 B lines, 128-bit (4-instruction) fetch.

`timescale 1ns / 1ps

module icache_core_tb;

    import icache_pkg::*;

    parameter int unsigned FETCH_INSTR_NUM = 4;

    logic clk;
    logic rst_n;

    logic        req_valid;
    logic        req_ready;
    cache_addr_t req_addr;
    logic        resp_valid;
    logic        resp_ready;
    logic [FETCH_INSTR_NUM*32-1:0] resp_data;
    logic [FETCH_INSTR_NUM-1:0]    resp_valid_mask;

    logic        inv_all;

    logic        mem_req;
    logic        mem_we;
    mem_idx_t    mem_idx;
    mem_word_t   mem_wdata;
    mem_word_t   mem_rdata;
    logic        mem_ack;

    logic        mem_init_en;
    mem_idx_t    mem_init_idx;
    mem_word_t   mem_init_data;

    logic [31:0] stat_hits;
    logic [31:0] stat_misses;

    int unsigned errors;
    int unsigned tests_run;

    mem_word_t shadow [MEM_DEPTH];

    icache_top #(
        .FETCH_INSTR_NUM(FETCH_INSTR_NUM)
    ) u_dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .req_valid   (req_valid),
        .req_ready   (req_ready),
        .req_addr    (req_addr),
        .resp_valid  (resp_valid),
        .resp_ready  (resp_ready),
        .resp_data   (resp_data),
        .resp_valid_mask (resp_valid_mask),
        .inv_all     (inv_all),
        .mem_req     (mem_req),
        .mem_we      (mem_we),
        .mem_idx     (mem_idx),
        .mem_wdata   (mem_wdata),
        .mem_rdata   (mem_rdata),
        .mem_ack     (mem_ack),
        .stat_hits   (stat_hits),
        .stat_misses (stat_misses)
    );

    icache_backing_mem u_mem (
        .clk       (clk),
        .rst_n     (rst_n),
        .req       (mem_req),
        .we        (mem_we),
        .idx       (mem_idx),
        .wdata     (mem_wdata),
        .rdata     (mem_rdata),
        .ack       (mem_ack),
        .init_en   (mem_init_en),
        .init_idx  (mem_init_idx),
        .init_data (mem_init_data)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function automatic mem_idx_t widx(input cache_addr_t addr);
        return addr[MEM_BYTE_OFF_BITS +: MEM_IDX_BITS];
    endfunction

    task automatic mem_back_write(input mem_idx_t idx, input mem_word_t data);
        @(posedge clk);
        mem_init_en   <= 1'b1;
        mem_init_idx  <= idx;
        mem_init_data <= data;
        @(posedge clk);
        mem_init_en   <= 1'b0;
    endtask

    task automatic mem_init_word(input cache_addr_t addr, input cache_instr_t instr);
        mem_idx_t idx;
        mem_word_t w;
        idx = widx(addr);
        w   = shadow[int'(idx)];
        if (addr[2])
            w[63:32] = instr;
        else
            w[31:0]  = instr;
        shadow[int'(idx)] = w;
        mem_back_write(idx, w);
    endtask

    task automatic mem_init_block(input cache_addr_t start_addr, input int num_instrs);
        for (int i = 0; i < num_instrs; i++) begin
            cache_addr_t a;
            a = start_addr + i*4;
            mem_init_word(a, cache_instr_t'(32'h1000_0000 + a));
        end
    endtask

    function automatic logic [FETCH_INSTR_NUM*32-1:0] get_expected_fetch(input cache_addr_t addr);
        logic [FETCH_INSTR_NUM*32-1:0] exp;
        for (int i = 0; i < FETCH_INSTR_NUM; i++) begin
            exp[i*32 +: 32] = 32'h1000_0000 + addr + i*4;
        end
        return exp;
    endfunction

    task automatic check_eq(input string label, input logic [FETCH_INSTR_NUM*32-1:0] exp, input logic [FETCH_INSTR_NUM*32-1:0] got);
        tests_run++;
        if (exp !== got) begin
            $error("[%s] exp=%h got=%h", label, exp, got);
            errors++;
        end else begin
            $display("[%s] PASS (got=%h)", label, got);
        end
    endtask

    task automatic cache_fetch(input cache_addr_t addr, output logic [FETCH_INSTR_NUM*32-1:0] data);
        req_valid      <= 1'b1;
        req_addr       <= addr;
        resp_ready     <= 1'b1;
        @(posedge clk);
        while (!req_ready) @(posedge clk);
        req_valid <= 1'b0;
        while (!resp_valid) @(posedge clk);
        data = resp_data;
        @(posedge clk);
    endtask

    initial begin
        logic [FETCH_INSTR_NUM*32-1:0] g;
        errors      = 0;
        tests_run   = 0;
        req_valid   = 1'b0;
        resp_ready  = 1'b1;
        inv_all     = 1'b0;
        mem_init_en = 1'b0;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // ==========================================
        // Test 1: Aligned Cache Miss & Cache Hit
        // ==========================================
        begin : t_aligned_test
            cache_addr_t a = 32'h0000_0000;
            mem_init_block(a, 16); // Load whole cache line 0

            // Cold miss
            cache_fetch(a, g);
            check_eq("aligned_cold_miss", get_expected_fetch(a), g);

            // Hit
            cache_fetch(a, g);
            check_eq("aligned_hit", get_expected_fetch(a), g);
        end

        // ==========================================
        // Test 2: Crossing Cache Line - Both Hit
        // ==========================================
        begin : t_cross_both_hit
            cache_addr_t a = 32'h0000_0038; // Last 2 words of line 0, first 2 words of line 1
            mem_init_block(32'h0000_0040, 16); // Initialize line 1 in memory

            // First fetch line 1 to make it a cache hit later
            cache_fetch(32'h0000_0040, g); 

            // Now fetch crossing line 0 and line 1. Both lines are in cache.
            cache_fetch(a, g);
            check_eq("cross_both_hit", get_expected_fetch(a), g);
        end

        // ==========================================
        // Test 3: Crossing Cache Line - First Hit, Second Miss
        // ==========================================
        begin : t_cross_hit_miss
            cache_addr_t a = 32'h0000_0078; // Last 2 words of line 1 (hit), first 2 words of line 2 (miss)
            mem_init_block(32'h0000_0080, 16); // Initialize line 2 in memory

            // Fetch from crossing address. Line 1 hits, Line 2 misses.
            cache_fetch(a, g);
            check_eq("cross_hit_miss", get_expected_fetch(a), g);
        end

        // ==========================================
        // Test 4: Crossing Cache Line - First Miss, Second Hit
        // ==========================================
        begin : t_cross_miss_hit
            cache_addr_t a = 32'h0000_00B8; // Last 2 words of line 2 (miss), first 2 of line 3 (hit)
            mem_init_block(32'h0000_00C0, 16); // Initialize line 3 in memory

            // First warm up line 3
            cache_fetch(32'h0000_00C0, g);

            // Invalidate line 2 only (we can't selectively invalidate, so invalidate all, then reload line 3)
            inv_all <= 1'b1;
            @(posedge clk);
            inv_all <= 1'b0;
            @(posedge clk);

            // Warm up line 3 again
            cache_fetch(32'h0000_00C0, g);

            // Now fetch from crossing. Line 2 misses, Line 3 hits.
            cache_fetch(a, g);
            check_eq("cross_miss_hit", get_expected_fetch(a), g);
        end

        // ==========================================
        // Test 5: Crossing Cache Line - Both Miss (Double Miss)
        // ==========================================
        begin : t_cross_both_miss
            cache_addr_t a = 32'h0000_0138; // Crossing line 4 (miss) and line 5 (miss)
            mem_init_block(32'h0000_0100, 32); // Initialize lines 4 and 5 in memory

            // Invalidate all to ensure clean slate
            inv_all <= 1'b1;
            @(posedge clk);
            inv_all <= 1'b0;
            @(posedge clk);

            // Fetch from crossing. Both lines miss.
            cache_fetch(a, g);
            check_eq("cross_both_miss", get_expected_fetch(a), g);
        end

        // ==========================================
        // Test 6: Invalidation
        // ==========================================
        begin : t_invalidation
            cache_addr_t a = 32'h0000_0200;
            mem_init_block(a, 16);

            cache_fetch(a, g);
            check_eq("pre_inv", get_expected_fetch(a), g);

            inv_all <= 1'b1;
            @(posedge clk);
            inv_all <= 1'b0;
            @(posedge clk);

            // Initialize new value in memory
            for (int i = 0; i < 4; i++) begin
                mem_init_word(a + i*4, 32'h9999_0000 + i);
            end

            cache_fetch(a, g);
            check_eq("post_inv_miss", {32'h9999_0003, 32'h9999_0002, 32'h9999_0001, 32'h9999_0000}, g);
        end

        if (errors == 0)
            $display("icache_core_tb: PASS (%0d checks)", tests_run);
        else
            $display("icache_core_tb: FAIL (%0d errors, %0d checks)", errors, tests_run);

        $display("  hits=%0d misses=%0d", stat_hits, stat_misses);
        $finish;
    end

endmodule
