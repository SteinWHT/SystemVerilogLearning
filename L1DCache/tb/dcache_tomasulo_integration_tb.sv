// Integration test for dcache_tomasulo_wrap.
//
// The Tomasulo CPU itself needs VCS+DesignWare (or Questa) to elaborate, so
// this TB stands in a *behavioural model of the CPU memory interface* that
// reproduces exactly how the real RTL drives the cache:
//
//   * LSQ  : asserts the load request only while the cache is available
//            (dcache_rvalid = load_pending && dcache_rready), one in flight.
//   * LSB  : asserts dcache_rresp_ready while waiting for the load word.
//   * SB   : a FIFO that advances its lead pointer whenever write-available is
//            high (dcache_wvalid = !empty), and its trail pointer on each write
//            response (mirrors src/SB.sv).
//
// It checks load/store hit & miss, and the critical simultaneous load+store
// case (load priority must not let the SB silently drop a store), plus the
// "tohost" backdoor used by the bare-metal C testbench.

`timescale 1ns / 1ps

module dcache_tomasulo_integration_tb;
    import dcache_pkg::*;

    localparam int unsigned AW = 64;   // CPU DMEM_DEPTH width

    logic clk, rst_n;

    // CPU read port
    logic            dcache_rvalid;       // load request (CPU out)
    logic [AW-1:0]   dcache_raddr;
    logic            dcache_rresp_ready;
    logic            dcache_rready;       // cache available (CPU in)
    logic            dcache_rresp_valid;
    logic [63:0]     dcache_rdata;

    // CPU write port
    logic            dcache_wvalid;       // store request (CPU out, = SB !empty)
    logic            dcache_write;
    logic [AW-1:0]   dcache_sw_addr;
    logic [63:0]     dcache_sw_data;
    logic [7:0]      dcache_wstrb;
    logic            dcache_wresp_ready;
    logic            dcache_wready;       // cache available (CPU in)
    logic            dcache_wresp_valid;

    // Backing-memory preload
    logic            mem_init_en;
    mem_idx_t        mem_init_idx;
    logic [63:0]     mem_init_data;

    logic [31:0]     stat_hits, stat_misses;

    int unsigned errors;
    int unsigned tests_run;

    dcache_tomasulo_wrap #(
        .CPU_ADDR_WIDTH (AW)
    ) u_dwrap (
        .clk                (clk),
        .rst_n              (rst_n),
        .dcache_rvalid      (dcache_rvalid),
        .dcache_raddr       (dcache_raddr),
        .dcache_rresp_ready (dcache_rresp_ready),
        .dcache_rready      (dcache_rready),
        .dcache_rresp_valid (dcache_rresp_valid),
        .dcache_rdata       (dcache_rdata),
        .dcache_wvalid      (dcache_wvalid),
        .dcache_write       (dcache_write),
        .dcache_sw_addr     (dcache_sw_addr),
        .dcache_sw_data     (dcache_sw_data),
        .dcache_wstrb       (dcache_wstrb),
        .dcache_wresp_ready (dcache_wresp_ready),
        .dcache_wready      (dcache_wready),
        .dcache_wresp_valid (dcache_wresp_valid),
        .mem_init_en        (mem_init_en),
        .mem_init_idx       (mem_init_idx),
        .mem_init_data      (mem_init_data),
        .stat_hits          (stat_hits),
        .stat_misses        (stat_misses)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------ shadow mem
    cache_word_t shadow [MEM_DEPTH];

    function automatic mem_idx_t widx(input logic [AW-1:0] addr);
        return addr[BYTE_OFF_BITS +: MEM_IDX_BITS];
    endfunction

    function automatic cache_addr_t build_addr(
        input int unsigned tag, input int unsigned set, input int unsigned word
    );
        build_addr = '0;
        build_addr[BYTE_OFF_BITS          +: WORD_SEL_BITS] = word_sel_t'(word);
        build_addr[OFFSET_BITS            +: INDEX_BITS]    = cache_set_t'(set);
        build_addr[INDEX_BITS+OFFSET_BITS +: TAG_BITS]      = cache_tag_t'(tag);
    endfunction

    task automatic mem_init(input logic [AW-1:0] addr, input cache_word_t data);
        mem_idx_t idx;
        idx = widx(addr);
        shadow[int'(idx)] = data;
        @(posedge clk);
        mem_init_en   <= 1'b1;
        mem_init_idx  <= idx;
        mem_init_data <= data;
        @(posedge clk);
        mem_init_en   <= 1'b0;
    endtask

    // ------------------------------------------------------------ load engine (LSQ/LSB)
    logic        load_pending;
    logic        load_inflight;
    logic [AW-1:0] load_addr_q;
    logic [63:0] load_result;
    logic        load_done;

    // LSQ: only request while the cache says it is available.
    assign dcache_rvalid      = load_pending && dcache_rready;
    assign dcache_raddr       = load_addr_q;
    assign dcache_rresp_ready = load_inflight;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            load_inflight <= 1'b0;
            load_result   <= '0;
            load_done     <= 1'b0;
        end else begin
            if (dcache_rvalid) begin            // accepted (already &&available)
                load_inflight <= 1'b1;
            end
            if (dcache_rresp_valid && load_inflight) begin
                load_result   <= dcache_rdata;
                load_inflight <= 1'b0;
                load_done     <= 1'b1;
            end
            if (load_done && !load_pending)
                load_done <= 1'b0;
        end
    end

    // load_pending is cleared by the issuing task once accepted.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            load_pending <= 1'b0;
        else if (dcache_rvalid)
            load_pending <= 1'b0;
    end

    task automatic issue_load(input logic [AW-1:0] addr);
        @(posedge clk);
        load_addr_q  <= addr;
        load_pending <= 1'b1;
    endtask

    task automatic wait_load(output logic [63:0] data);
        while (!load_done) @(posedge clk);
        data = load_result;
    endtask

    task automatic do_load(input logic [AW-1:0] addr, output logic [63:0] data);
        issue_load(addr);
        wait_load(data);
    endtask

    // ------------------------------------------------------------ store engine (SB FIFO)
    localparam int unsigned SB_N = 16;
    logic [AW-1:0] sb_addr [SB_N];
    logic [63:0]   sb_data [SB_N];
    logic [7:0]    sb_strb [SB_N];
    logic [4:0]    sb_wr, sb_lead, sb_trail;   // 5-bit (1 wrap bit + 4 idx)

    assign dcache_wvalid      = (sb_lead != sb_wr);           // !empty (something to issue)
    assign dcache_write       = (sb_lead != sb_wr);
    assign dcache_sw_addr     = sb_addr[sb_lead[3:0]];
    assign dcache_sw_data     = sb_data[sb_lead[3:0]];
    assign dcache_wstrb       = sb_strb[sb_lead[3:0]];
    assign dcache_wresp_ready = (sb_lead != sb_trail);        // issued, awaiting resp

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sb_lead  <= '0;
            sb_trail <= '0;
        end else begin
            if (dcache_wready && (sb_lead != sb_wr))
                sb_lead <= sb_lead + 5'd1;
            if (dcache_wresp_valid)
                sb_trail <= sb_trail + 5'd1;
        end
    end

    task automatic push_store(input logic [AW-1:0] addr, input logic [63:0] data,
                              input logic [7:0] strb);
        cache_word_t v;
        // shadow update (byte merge)
        v = shadow[int'(widx(addr))];
        for (int b = 0; b < 8; b++)
            if (strb[b]) v[b*8 +: 8] = data[b*8 +: 8];
        shadow[int'(widx(addr))] = v;
        // enqueue into SB FIFO
        sb_addr[sb_wr[3:0]] = addr;
        sb_data[sb_wr[3:0]] = data;
        sb_strb[sb_wr[3:0]] = strb;
        @(posedge clk);
        sb_wr <= sb_wr + 5'd1;
    endtask

    task automatic drain_sb();
        while (sb_trail != sb_wr) @(posedge clk);
        @(posedge clk);
    endtask

    // ------------------------------------------------------------ backdoor peek
    // Read the current architectural value of a word: prefer a resident (and
    // possibly dirty) cache line, else fall back to backing memory.  This is
    // exactly what the bare-metal C testbench uses to observe `tohost`.
    function automatic logic [63:0] peek_qword(input logic [AW-1:0] byte_addr);
        cache_set_t  set;
        cache_tag_t  tag;
        word_sel_t   wsel;
        cache_line_t line;
        logic        found;
        peek_qword = '0;
        set  = byte_addr[OFFSET_BITS +: INDEX_BITS];
        tag  = byte_addr[INDEX_BITS+OFFSET_BITS +: TAG_BITS];
        wsel = byte_addr[BYTE_OFF_BITS +: WORD_SEL_BITS];
        found = 1'b0;
        for (int w = 0; w < NUM_WAYS; w++) begin
            if (u_dwrap.u_cache.u_core.u_tag.valid_ram[int'(set)][w] &&
                (u_dwrap.u_cache.u_core.u_tag.tag_ram[int'(set)][w] == tag)) begin
                line = u_dwrap.u_cache.u_core.u_data.data_array[int'(set)][w];
                peek_qword = line[int'(wsel)*64 +: 64];
                found = 1'b1;
            end
        end
        if (!found)
            peek_qword = u_dwrap.u_mem.mem[int'(widx(byte_addr))];
    endfunction

    task automatic check_eq(input string label, input logic [63:0] exp, input logic [63:0] got);
        tests_run++;
        if (exp !== got) begin
            $error("[%s] exp=%h got=%h", label, exp, got);
            errors++;
        end
    endtask

    // ------------------------------------------------------------ stimulus
    initial begin
        errors        = 0;
        tests_run     = 0;
        load_pending  = 1'b0;
        load_addr_q   = '0;
        sb_wr         = '0;
        mem_init_en   = 1'b0;
        mem_init_idx  = '0;
        mem_init_data = '0;
        for (int i = 0; i < SB_N; i++) begin
            sb_addr[i] = '0; sb_data[i] = '0; sb_strb[i] = '0;
        end

        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        // 1) Cold load miss + load hit.
        begin
            logic [AW-1:0] a; logic [63:0] g;
            a = build_addr(4, 2, 0);
            mem_init(a, 64'hCAFE_0001_1234_5678);
            do_load(a, g);
            check_eq("cold_miss", 64'hCAFE_0001_1234_5678, g);
            do_load(a, g);
            check_eq("load_hit", 64'hCAFE_0001_1234_5678, g);
        end

        // 2) Store hit then load back (byte merge, dirty line).
        begin
            logic [AW-1:0] a; logic [63:0] g;
            a = build_addr(4, 3, 1);
            mem_init(a, 64'h0);
            do_load(a, g);                                   // make line resident
            push_store(a, 64'h0000_0000_0000_00AB, 8'h01);
            drain_sb();
            do_load(a, g);
            check_eq("store_hit", shadow[int'(widx(a))], g);
        end

        // 3) Store miss (write-allocate) then load back.
        begin
            logic [AW-1:0] a; logic [63:0] g;
            a = build_addr(11, 9, 3);
            mem_init(a, 64'hDEAD_BEEF_0000_0000);
            push_store(a, 64'h0000_0000_99AA_BBCC, 8'h0F);
            drain_sb();
            do_load(a, g);
            check_eq("store_miss", shadow[int'(widx(a))], g);
        end

        // 4) SIMULTANEOUS load + store (the load-priority gating case).
        //    Issue a load to one line while a store to a different line is
        //    queued; the store must NOT be dropped.
        begin
            logic [AW-1:0] la, sa; logic [63:0] g;
            logic [63:0] sd; logic [7:0] ss;
            cache_word_t v;
            la = build_addr(20, 15, 0);     // load target
            sa = build_addr(21, 16, 2);     // store target (different set)
            sd = 64'h0000_0000_DEAD_C0DE;
            ss = 8'h0F;
            mem_init(la, 64'h1111_1111_2222_2222);
            mem_init(sa, 64'h0);
            // update shadow for the store (byte merge)
            v = shadow[int'(widx(sa))];
            for (int b = 0; b < 8; b++)
                if (ss[b]) v[b*8 +: 8] = sd[b*8 +: 8];
            shadow[int'(widx(sa))] = v;
            // Kick both off on the same cycle.
            @(posedge clk);
            load_addr_q  <= la;
            load_pending <= 1'b1;
            sb_addr[sb_wr[3:0]] = sa;
            sb_data[sb_wr[3:0]] = sd;
            sb_strb[sb_wr[3:0]] = ss;
            @(posedge clk);
            sb_wr <= sb_wr + 5'd1;
            // wait for both to retire
            wait_load(g);
            check_eq("concurrent_load", 64'h1111_1111_2222_2222, g);
            drain_sb();
            do_load(sa, g);
            check_eq("concurrent_store_survived", shadow[int'(widx(sa))], g);
        end

        // 5) tohost backdoor: a dirty store is visible via peek while backing
        //    memory still holds the stale value.
        begin
            logic [AW-1:0] tohost; logic [63:0] peeked, backing;
            tohost = 64'h0000_0000_0000_1008;        // matches c_suite link map
            mem_init(tohost, 64'h0);
            push_store(tohost, 64'h0000_0000_0000_0001, 8'hFF);   // tohost = 1 (PASS)
            drain_sb();
            do_load(tohost, peeked);                  // datapath read-back
            check_eq("tohost_datapath_sees_pass", 64'h1, peeked);
            peeked  = peek_qword(tohost);
            backing = u_dwrap.u_mem.mem[int'(widx(tohost))];
            check_eq("tohost_backdoor_sees_pass", 64'h1, peeked);
            if (backing !== 64'h0)
                $display("  note: tohost reached backing mem (=%0h) via eviction", backing);
        end

        if (errors == 0)
            $display("dcache_tomasulo_integration_tb: PASS (%0d checks)", tests_run);
        else
            $display("dcache_tomasulo_integration_tb: FAIL (%0d errors, %0d checks)", errors, tests_run);
        $display("  hits=%0d misses=%0d", stat_hits, stat_misses);
        $finish;
    end

    initial begin
        #500000;
        $error("integration TB timeout");
        $finish;
    end

endmodule
