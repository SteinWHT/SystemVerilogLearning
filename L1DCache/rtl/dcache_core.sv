// L1 D-cache core: hit/miss control, write-back / write-allocate, PLRU eviction.
//
// Pipeline (blocking, single outstanding miss):
//   ACCEPT  : latch a load or store request (load has priority).
//   RESOLVE : combinational tag compare on the latched address.
//             hit  -> read: select word & register response (1-cycle resp);
//                     write: read-modify-write the line word, set dirty.
//             miss -> allocate MSHR with victim metadata/data.
//   MISS_WB : if victim dirty, burst-write it back to memory.
//   MISS_FILL : burst-read the requested line from memory.
//   MISS_FINISH : install line (merge store word on write-allocate), update
//                 tags / PLRU, deallocate MSHR, and return the response.

module dcache_core (
    input  logic                       clk,
    input  logic                       rst_n,

    // CPU load port (64-bit word)
    input  logic                       rvalid,
    output logic                       rready,
    input  dcache_pkg::cache_addr_t    raddr,
    output logic                       rresp_valid,
    input  logic                       rresp_ready,
    output dcache_pkg::cache_word_t    rdata,

    // CPU store port
    input  logic                       wvalid,
    output logic                       wready,
    input  dcache_pkg::cache_addr_t    waddr,
    input  dcache_pkg::cache_word_t    wdata,
    input  dcache_pkg::cache_strb_t    wstrb,
    output logic                       wresp_valid,
    input  logic                       wresp_ready,

    // 64-bit memory bus
    output logic                       mem_req,
    output logic                       mem_we,
    output dcache_pkg::mem_idx_t       mem_idx,
    output dcache_pkg::cache_word_t    mem_wdata,
    input  dcache_pkg::cache_word_t    mem_rdata,
    input  logic                       mem_ack,

    output logic [31:0]                stat_hits,
    output logic [31:0]                stat_misses
);
    import dcache_pkg::*;

    typedef enum logic [2:0] {
        ST_IDLE        = 3'd0,
        ST_MISS_WB     = 3'd1,
        ST_MISS_FILL   = 3'd2,
        ST_MISS_FINISH = 3'd3
    } core_state_e;

    core_state_e       state_q;

    // Latched request under resolution
    cache_addr_t       lookup_addr;
    dcache_op_e        lookup_op;
    cache_word_t       lookup_wdata;
    cache_strb_t       lookup_wstrb;
    logic              resolve_pending;

    cache_set_t        lookup_set;
    cache_tag_t        lookup_tag;
    word_sel_t         lookup_wsel;
    cache_set_t        tag_read_set;

    // Tag array read-back
    logic [NUM_WAYS-1:0]          tag_valid;
    logic [NUM_WAYS-1:0]          tag_dirty;
    logic [NUM_WAYS*TAG_BITS-1:0] tag_flat;
    way_mask_t         hit_mask;
    way_mask_t         invalid_mask;
    logic              lookup_hit;
    cache_way_t        hit_way;
    cache_way_t        victim_way;
    cache_way_t        alloc_way;
    cache_way_t        data_rd_way;
    cache_line_t       line_rdata;
    tag_entry_t        victim_meta;

    // Response holding
    logic              hold_rresp;
    logic              hold_wresp;
    cache_word_t       hold_rdata;

    // Tag/data array write
    logic              tag_w_en;
    cache_set_t        tag_w_set;
    cache_way_t        tag_w_way;
    tag_entry_t        tag_w_entry;
    logic              data_w_en;
    cache_set_t        data_w_set;
    cache_way_t        data_w_way;
    cache_line_t       data_w_line;

    // PLRU update
    logic              plru_upd_en;
    cache_set_t        plru_set;
    cache_way_t        plru_touch_way;

    // MSHR
    logic              mshr_alloc;
    logic              mshr_dealloc;
    logic              mshr_busy;
    dcache_op_e        mshr_op;
    cache_addr_t       mshr_addr;
    cache_word_t       mshr_wdata;
    cache_strb_t       mshr_wstrb;
    word_sel_t         mshr_wsel;
    cache_set_t        mshr_set;
    cache_tag_t        mshr_tag;
    cache_way_t        mshr_way;
    logic              mshr_needs_wb;
    cache_line_t       mshr_victim_data;
    tag_entry_t        mshr_victim_entry;

    // Refill engine
    logic              rf_start_read;
    logic              rf_start_write;
    mem_idx_t          rf_base_widx;
    logic              rf_busy;
    logic              rf_done;
    cache_line_t       rf_read_line;

    logic              accept_read;
    logic              accept_write;

    // ---------------------------------------------------------------- stats
    logic [31:0]       hits_q;
    logic [31:0]       misses_q;
    assign stat_hits   = hits_q;
    assign stat_misses = misses_q;

    // ---------------------------------------------------------------- handshakes
    // Single port, load priority. The cache is free to accept a new access only
    // in IDLE with no resolve/miss/response in flight.
    assign rready = (state_q == ST_IDLE) && !resolve_pending && !mshr_busy
                    && !rf_busy && !hold_rresp && !hold_wresp;

    // wready must reflect load priority: a store can only be accepted when the
    // cache is free AND no load is competing this cycle. Tying wready=rready
    // would assert ready for a store the cache silently drops whenever a load
    // arrives at the same time (valid/ready violation).
    assign wready = rready && !rvalid;

    assign accept_read  = rvalid && rready;
    assign accept_write = wvalid && wready;   // wready already encodes load priority

    assign rresp_valid = hold_rresp;
    assign rdata       = hold_rdata;
    assign wresp_valid = hold_wresp;

    assign lookup_set  = addr_to_set(lookup_addr);
    assign lookup_tag  = addr_to_tag(lookup_addr);
    assign lookup_wsel = addr_to_word_sel(lookup_addr);
    assign tag_read_set = (state_q == ST_IDLE) ? lookup_set : mshr_set;
    assign data_rd_way  = lookup_hit ? hit_way : alloc_way;

    // ---------------------------------------------------------------- arrays
    dcache_tag_ram u_tag (
        .clk         (clk),
        .rst_n       (rst_n),
        .r_set       (tag_read_set),
        .r_valid     (tag_valid),
        .r_dirty     (tag_dirty),
        .r_tags_flat (tag_flat),
        .w_en        (tag_w_en),
        .w_set       (tag_w_set),
        .w_way       (tag_w_way),
        .w_entry     (tag_w_entry)
    );

    dcache_data_ram u_data (
        .clk    (clk),
        .r_set  (lookup_set),
        .r_way  (data_rd_way),
        .r_line (line_rdata),
        .w_en   (data_w_en),
        .w_set  (data_w_set),
        .w_way  (data_w_way),
        .w_line (data_w_line)
    );

    dcache_plru u_plru (
        .clk        (clk),
        .rst_n      (rst_n),
        .set_idx    (plru_set),
        .victim_way (victim_way),
        .update_en  (plru_upd_en),
        .touch_way  (plru_touch_way)
    );

    dcache_mshr u_mshr (
        .clk                (clk),
        .rst_n              (rst_n),
        .busy               (mshr_busy),
        .op                 (mshr_op),
        .addr               (mshr_addr),
        .wdata              (mshr_wdata),
        .wstrb              (mshr_wstrb),
        .word_sel           (mshr_wsel),
        .set_idx            (mshr_set),
        .tag                (mshr_tag),
        .alloc_way          (mshr_way),
        .needs_writeback    (mshr_needs_wb),
        .victim_data        (mshr_victim_data),
        .victim_entry       (mshr_victim_entry),
        .alloc              (mshr_alloc),
        .alloc_op           (lookup_op),
        .alloc_addr         (lookup_addr),
        .alloc_wdata        (lookup_wdata),
        .alloc_wstrb        (lookup_wstrb),
        .alloc_way_i        (alloc_way),
        .alloc_needs_wb     (victim_meta.valid && victim_meta.dirty),
        .alloc_victim_data  (line_rdata),
        .alloc_victim_entry (victim_meta),
        .dealloc            (mshr_dealloc)
    );

    dcache_refill u_refill (
        .clk         (clk),
        .rst_n       (rst_n),
        .start_read  (rf_start_read),
        .start_write (rf_start_write),
        .base_widx   (rf_base_widx),
        .write_line  (mshr_victim_data),
        .busy        (rf_busy),
        .done        (rf_done),
        .read_line   (rf_read_line),
        .mem_req     (mem_req),
        .mem_we      (mem_we),
        .mem_idx     (mem_idx),
        .mem_wdata   (mem_wdata),
        .mem_rdata   (mem_rdata),
        .mem_ack     (mem_ack)
    );

    // ---------------------------------------------------------------- tag compare
    genvar gi;
    generate
        for (gi = 0; gi < NUM_WAYS; gi++) begin : g_hit
            wire [TAG_BITS-1:0] way_tag = tag_flat[gi*TAG_BITS +: TAG_BITS];
            assign hit_mask[gi]     = tag_valid[gi] && (way_tag == lookup_tag);
            assign invalid_mask[gi] = !tag_valid[gi];
        end
    endgenerate

    assign lookup_hit = |hit_mask;
    assign hit_way    = onehot_to_way(hit_mask);

    // Allocation: fill the lowest-numbered invalid way first; once the set is
    // full, evict the PLRU victim.
    cache_way_t first_invalid_way;
    always_comb begin
        first_invalid_way = '0;
        for (int w = NUM_WAYS-1; w >= 0; w--)
            if (invalid_mask[w])
                first_invalid_way = cache_way_t'(w);
    end
    assign alloc_way = (|invalid_mask) ? first_invalid_way : victim_way;

    always_comb begin
        victim_meta.valid = tag_valid[int'(alloc_way)];
        victim_meta.dirty = tag_dirty[int'(alloc_way)];
        victim_meta.tag   = tag_flat[int'(alloc_way)*TAG_BITS +: TAG_BITS];
    end

    // datapath comb
    cache_line_t fill_line;
    tag_entry_t  fill_tag_entry;

    always_comb begin
        tag_w_en       = 1'b0;
        tag_w_set      = mshr_set;
        tag_w_way      = mshr_way;
        tag_w_entry    = '0;
        data_w_en      = 1'b0;
        data_w_set     = mshr_set;
        data_w_way     = mshr_way;
        data_w_line    = '0;
        plru_upd_en    = 1'b0;
        plru_set       = lookup_set;
        plru_touch_way = hit_way;
        mshr_alloc     = 1'b0;
        mshr_dealloc   = 1'b0;
        rf_start_read  = 1'b0;
        rf_start_write = 1'b0;
        rf_base_widx   = addr_to_line_base_widx(mshr_addr);

        fill_line      = rf_read_line;
        fill_tag_entry = '0;

        unique case (state_q)
            ST_IDLE: begin
                if (resolve_pending && lookup_hit && lookup_op == DCACHE_OP_WRITE) begin
                    // Store hit: read-modify-write the selected word.
                    data_w_en   = 1'b1;
                    data_w_set  = lookup_set;
                    data_w_way  = hit_way;
                    data_w_line = line_merge_word(line_rdata, lookup_wsel,
                                                  lookup_wdata, lookup_wstrb);
                    tag_w_en          = 1'b1;
                    tag_w_set         = lookup_set;
                    tag_w_way         = hit_way;
                    tag_w_entry.valid = 1'b1;
                    tag_w_entry.dirty = 1'b1;
                    tag_w_entry.tag   = lookup_tag;
                    plru_upd_en       = 1'b1;
                    plru_set          = lookup_set;
                    plru_touch_way    = hit_way;
                end else if (resolve_pending && lookup_hit) begin
                    // Load hit: just touch PLRU (response handled in seq block).
                    plru_upd_en    = 1'b1;
                    plru_set       = lookup_set;
                    plru_touch_way = hit_way;
                end else if (resolve_pending && !lookup_hit) begin
                    mshr_alloc = 1'b1;
                end
            end

            ST_MISS_WB: begin
                if (!rf_busy && !rf_done)
                    rf_start_write = 1'b1;
                rf_base_widx = addr_to_line_base_widx(
                    set_tag_to_addr(mshr_set, mshr_victim_entry.tag));
            end

            ST_MISS_FILL: begin
                if (!rf_busy && !rf_done)
                    rf_start_read = 1'b1;
                rf_base_widx = addr_to_line_base_widx(mshr_addr);
            end

            ST_MISS_FINISH: begin
                fill_line = rf_read_line;
                if (mshr_op == DCACHE_OP_WRITE)
                    fill_line = line_merge_word(rf_read_line, mshr_wsel,
                                                mshr_wdata, mshr_wstrb);
                fill_tag_entry.valid = 1'b1;
                fill_tag_entry.dirty = (mshr_op == DCACHE_OP_WRITE);
                fill_tag_entry.tag   = mshr_tag;

                tag_w_en    = 1'b1;
                tag_w_set   = mshr_set;
                tag_w_way   = mshr_way;
                tag_w_entry = fill_tag_entry;

                data_w_en   = 1'b1;
                data_w_set  = mshr_set;
                data_w_way  = mshr_way;
                data_w_line = fill_line;

                plru_upd_en    = 1'b1;
                plru_set       = mshr_set;
                plru_touch_way = mshr_way;
                mshr_dealloc   = 1'b1;
            end

            default: ;
        endcase
    end

    // control seq
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q         <= ST_IDLE;
            lookup_addr     <= '0;
            lookup_op       <= DCACHE_OP_READ;
            lookup_wdata    <= '0;
            lookup_wstrb    <= '0;
            resolve_pending <= 1'b0;
            hold_rresp      <= 1'b0;
            hold_wresp      <= 1'b0;
            hold_rdata      <= '0;
            hits_q          <= '0;
            misses_q        <= '0;
        end else begin
            if (hold_rresp && rresp_ready)
                hold_rresp <= 1'b0;
            if (hold_wresp && wresp_ready)
                hold_wresp <= 1'b0;

            unique case (state_q)
                ST_IDLE: begin
                    if (accept_read) begin
                        lookup_addr     <= raddr;
                        lookup_op       <= DCACHE_OP_READ;
                        resolve_pending <= 1'b1;
                    end else if (accept_write) begin
                        lookup_addr     <= waddr;
                        lookup_op       <= DCACHE_OP_WRITE;
                        lookup_wdata    <= wdata;
                        lookup_wstrb    <= wstrb;
                        resolve_pending <= 1'b1;
                    end else if (resolve_pending) begin
                        resolve_pending <= 1'b0;
                        if (lookup_hit) begin
                            hits_q <= hits_q + 32'd1;
                            if (lookup_op == DCACHE_OP_READ) begin
                                hold_rdata <= line_get_word(line_rdata, lookup_wsel);
                                hold_rresp <= 1'b1;
                            end else begin
                                hold_wresp <= 1'b1;
                            end
                        end else begin
                            misses_q <= misses_q + 32'd1;
                            if (victim_meta.valid && victim_meta.dirty)
                                state_q <= ST_MISS_WB;
                            else
                                state_q <= ST_MISS_FILL;
                        end
                    end
                end

                ST_MISS_WB: begin
                    if (rf_done)
                        state_q <= ST_MISS_FILL;
                end

                ST_MISS_FILL: begin
                    if (rf_done)
                        state_q <= ST_MISS_FINISH;
                end

                ST_MISS_FINISH: begin
                    if (mshr_op == DCACHE_OP_READ) begin
                        hold_rdata <= line_get_word(fill_line, mshr_wsel);
                        hold_rresp <= 1'b1;
                    end else begin
                        hold_wresp <= 1'b1;
                    end
                    state_q <= ST_IDLE;
                end

                default: state_q <= ST_IDLE;
            endcase
        end
    end

endmodule
