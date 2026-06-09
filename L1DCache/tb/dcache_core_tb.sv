// Directed L1 D-cache tests against a word-granular shadow memory.
//
// Geometry under test: 16 KiB, 4-way, 64 B lines, 64-bit word access.
// Same-set conflict addresses are built with build_addr(tag, set, word).

`timescale 1ns / 1ps

module dcache_core_tb;

    import dcache_pkg::*;

    logic clk;
    logic rst_n;

    logic        rvalid;
    logic        rready;
    cache_addr_t raddr;
    logic        rresp_valid;
    logic        rresp_ready;
    cache_word_t rdata;

    logic        wvalid;
    logic        wready;
    cache_addr_t waddr;
    cache_word_t wdata;
    cache_strb_t wstrb;
    logic        wresp_valid;
    logic        wresp_ready;

    logic        mem_req;
    logic        mem_we;
    mem_idx_t    mem_idx;
    cache_word_t mem_wdata;
    cache_word_t mem_rdata;
    logic        mem_ack;

    logic        mem_init_en;
    mem_idx_t    mem_init_idx;
    cache_word_t mem_init_data;

    logic [31:0] stat_hits;
    logic [31:0] stat_misses;

    int unsigned errors;
    int unsigned tests_run;

    cache_word_t shadow [MEM_DEPTH];

    dcache_top u_dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .rvalid      (rvalid),
        .rready      (rready),
        .raddr       (raddr),
        .rresp_valid (rresp_valid),
        .rresp_ready (rresp_ready),
        .rdata       (rdata),
        .wvalid      (wvalid),
        .wready      (wready),
        .waddr       (waddr),
        .wdata       (wdata),
        .wstrb       (wstrb),
        .wresp_valid (wresp_valid),
        .wresp_ready (wresp_ready),
        .flush_req   (1'b0),
        .flush_busy  (),
        .flush_done  (),
        .mem_req     (mem_req),
        .mem_we      (mem_we),
        .mem_idx     (mem_idx),
        .mem_wdata   (mem_wdata),
        .mem_rdata   (mem_rdata),
        .mem_ack     (mem_ack),
        .stat_hits   (stat_hits),
        .stat_misses (stat_misses)
    );

    dcache_backing_mem u_mem (
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

    // ---------------------------------------------------------------- helpers
    function automatic mem_idx_t widx(input cache_addr_t addr);
        return addr[BYTE_OFF_BITS +: MEM_IDX_BITS];
    endfunction

    // Build a byte address from {tag, set, word, 0}.
    function automatic cache_addr_t build_addr(
        input int unsigned tag,
        input int unsigned set,
        input int unsigned word
    );
        build_addr = '0;
        build_addr[BYTE_OFF_BITS    +: WORD_SEL_BITS] = word_sel_t'(word);
        build_addr[OFFSET_BITS      +: INDEX_BITS]    = cache_set_t'(set);
        build_addr[INDEX_BITS+OFFSET_BITS +: TAG_BITS]= cache_tag_t'(tag);
    endfunction

    function automatic cache_word_t shadow_read(input cache_addr_t addr);
        return shadow[int'(widx(addr))];
    endfunction

    task automatic shadow_write(
        input cache_addr_t addr,
        input cache_word_t data,
        input cache_strb_t strb
    );
        int unsigned i;
        cache_word_t v;
        i = int'(widx(addr));
        v = shadow[i];
        for (int b = 0; b < WORD_BYTES; b++)
            if (strb[b]) v[b*8 +: 8] = data[b*8 +: 8];
        shadow[i] = v;
    endtask

    // Clock a single word into the backing SRAM (only legal writer for mem[]).
    task automatic mem_back_write(input mem_idx_t idx, input cache_word_t data);
        @(posedge clk);
        mem_init_en   <= 1'b1;
        mem_init_idx  <= idx;
        mem_init_data <= data;
        @(posedge clk);
        mem_init_en   <= 1'b0;
    endtask

    // Initialise one memory word in shadow and backing (VCS-safe; no hierarchical
    // writes to u_mem.mem). Other words in the same line are left unchanged.
    task automatic mem_init(input cache_addr_t addr, input cache_word_t data);
        mem_idx_t idx;
        idx = widx(addr);
        shadow[int'(idx)] = data;
        mem_back_write(idx, data);
    endtask

    task automatic check_eq(input string label, input cache_word_t exp, input cache_word_t got);
        tests_run++;
        if (exp !== got) begin
            $error("[%s] exp=%h got=%h", label, exp, got);
            errors++;
        end
    endtask

    task automatic cache_load(input cache_addr_t addr, output cache_word_t data);
        rvalid      <= 1'b1;
        raddr       <= addr;
        rresp_ready <= 1'b1;
        @(posedge clk);
        while (!rready) @(posedge clk);
        rvalid <= 1'b0;
        while (!rresp_valid) @(posedge clk);
        data = rdata;
        @(posedge clk);
    endtask

    task automatic cache_store(
        input cache_addr_t addr,
        input cache_word_t data,
        input cache_strb_t strb
    );
        wvalid      <= 1'b1;
        waddr       <= addr;
        wdata       <= data;
        wstrb       <= strb;
        wresp_ready <= 1'b1;
        @(posedge clk);
        while (!wready) @(posedge clk);
        wvalid <= 1'b0;
        while (!wresp_valid) @(posedge clk);
        @(posedge clk);
    endtask

    // ---------------------------------------------------------------- stimulus
    initial begin
        errors      = 0;
        tests_run   = 0;
        rvalid      = 1'b0;
        wvalid      = 1'b0;
        rresp_ready  = 1'b1;
        wresp_ready  = 1'b1;
        mem_init_en  = 1'b0;
        mem_init_idx = '0;
        mem_init_data = '0;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // 0) Reset hygiene: no spurious responses while in reset.
        begin : t_reset
            rst_n = 1'b0;
            repeat (2) @(posedge clk);
            if (rresp_valid || wresp_valid) begin
                $error("[reset] spurious resp during reset");
                errors++;
            end
            rst_n = 1'b1;
            @(posedge clk);
        end

        // 1) Cold load miss -> burst refill returns correct word.
        begin : t_cold_miss
            cache_addr_t a;
            cache_word_t g;
            a = build_addr(1, 2, 0);
            mem_init(a, 64'h1111_2222_3333_4444);
            cache_load(a, g);
            check_eq("cold_miss", 64'h1111_2222_3333_4444, g);
        end

        // 2) Load hit on the line just filled.
        begin : t_load_hit
            cache_addr_t a;
            cache_word_t g;
            int unsigned h0;
            a  = build_addr(1, 2, 0);
            h0 = stat_hits;
            cache_load(a, g);
            check_eq("load_hit_data", shadow_read(a), g);
            if (stat_hits != h0 + 1) begin
                $error("[load_hit] expected a hit (hits %0d->%0d)", h0, stat_hits);
                errors++;
            end
        end

        // 3) Different words in the same line are independent (word offset).
        begin : t_word_offset
            cache_addr_t w0, w3;
            cache_word_t g0, g3;
            w0 = build_addr(7, 5, 0);
            w3 = build_addr(7, 5, 3);
            mem_init(w0, 64'hAAAA_AAAA_AAAA_AAAA);
            mem_init(w3, 64'h5555_5555_5555_5555);
            cache_load(w0, g0);   // cold miss fills whole line
            cache_load(w3, g3);   // hit, different word of same line
            check_eq("woff_w0", 64'hAAAA_AAAA_AAAA_AAAA, g0);
            check_eq("woff_w3", 64'h5555_5555_5555_5555, g3);
        end

        // 4) Store hit with partial strobe, then load back (byte merge + dirty).
        begin : t_store_hit
            cache_addr_t a;
            cache_word_t g;
            a = build_addr(3, 8, 2);
            mem_init(a, 64'h0);
            cache_load(a, g);                              // resident
            cache_store(a, 64'h0000_0000_0000_00AA, 8'h01);
            shadow_write(a, 64'h0000_0000_0000_00AA, 8'h01);
            cache_load(a, g);
            check_eq("store_hit", shadow_read(a), g);
        end

        // 5) Store miss (write-allocate): refill then merge bytes.
        begin : t_store_miss
            cache_addr_t a;
            cache_word_t g;
            a = build_addr(9, 12, 1);
            mem_init(a, 64'hDEAD_BEEF_CAFE_BABE);
            cache_store(a, 64'h1234_5678_0000_0000, 8'hF0);
            shadow_write(a, 64'h1234_5678_0000_0000, 8'hF0);
            cache_load(a, g);
            check_eq("store_miss", shadow_read(a), g);
        end

        // 6) Four ways then a fifth tag in the same set -> PLRU eviction.
        begin : t_evict
            cache_word_t g;
            for (int t = 0; t < 4; t++) begin
                cache_addr_t a;
                a = build_addr(t+1, 20, 0);
                mem_init(a, cache_word_t'(64'hA000_0000_0000_0000 + t));
                cache_load(a, g);
            end
            begin
                cache_addr_t fifth;
                fifth = build_addr(99, 20, 0);
                mem_init(fifth, 64'hBAD0_BAD0_BAD0_BAD0);
                cache_load(fifth, g);
                check_eq("evict_fill", 64'hBAD0_BAD0_BAD0_BAD0, g);
            end
        end

        // 7) Dirty eviction: stored data must be written back to memory.
        begin : t_dirty_wb
            cache_addr_t a;
            cache_word_t g;
            a = build_addr(1, 30, 4);
            mem_init(a, 64'h0);
            cache_store(a, 64'h0123_4567_89AB_CDEF, 8'hFF);
            shadow_write(a, 64'h0123_4567_89AB_CDEF, 8'hFF);
            // Push 8 distinct tags through the same 4-way set to guarantee
            // the dirty line is evicted (and thus written back).
            for (int t = 10; t < 18; t++) begin
                cache_addr_t b;
                b = build_addr(t, 30, 0);
                mem_init(b, cache_word_t'(64'hB000_0000_0000_0000 + t));
                cache_load(b, g);
            end
            check_eq("dirty_wb_mem", 64'h0123_4567_89AB_CDEF, shadow_read(a));
        end

        // 8) Back-to-back loads to the same line: 1 miss + 1 hit.
        begin : t_b2b
            cache_addr_t a;
            cache_word_t v1, v2;
            int unsigned m0, h0;
            a  = build_addr(2, 40, 0);
            mem_init(a, 64'hCAFE_F00D_0000_0001);
            m0 = stat_misses;
            h0 = stat_hits;
            cache_load(a, v1);
            cache_load(a, v2);
            check_eq("b2b_v1", 64'hCAFE_F00D_0000_0001, v1);
            check_eq("b2b_v2", 64'hCAFE_F00D_0000_0001, v2);
            if (stat_misses != m0 + 1 || stat_hits != h0 + 1) begin
                $error("[b2b] expected 1 miss + 1 hit (miss %0d->%0d hit %0d->%0d)",
                       m0, stat_misses, h0, stat_hits);
                errors++;
            end
        end

        if (errors == 0)
            $display("dcache_core_tb: PASS (%0d checks)", tests_run);
        else
            $display("dcache_core_tb: FAIL (%0d errors, %0d checks)", errors, tests_run);

        $display("  hits=%0d misses=%0d", stat_hits, stat_misses);
        $finish;
    end

endmodule
