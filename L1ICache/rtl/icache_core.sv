// L1 I-cache core: hit/miss control, read-only, PLRU eviction.
//
// Pipeline (blocking, single outstanding miss):
//   ACCEPT  : latch a fetch request.
//   RESOLVE : combinational tag compare on the latched PC.
//             hit  -> select instruction & register response (1-cycle resp).
//             miss -> allocate MSHR with victim way metadata.
//   MISS_FILL : burst-read the requested line from memory.
//   MISS_FINISH : install line, update tags / PLRU, deallocate MSHR, respond.

module icache_core #(
    parameter int unsigned FETCH_INSTR_NUM = 1
) (
    input  logic                       clk,
    input  logic                       rst_n,

    // CPU fetch port
    input  logic                            req_valid,
    output logic                            req_ready,
    input  icache_pkg::cache_addr_t         req_addr,
    output logic                            resp_valid,
    input  logic                            resp_ready,
    output logic [FETCH_INSTR_NUM*32-1:0]   resp_data,
    output logic [FETCH_INSTR_NUM-1:0]      resp_valid_mask,

    // Full invalidation (fence.i)
    input  logic                            inv_all,

    // 64-bit memory bus (read-only)
    output logic                            mem_req,
    output logic                            mem_we,
    output icache_pkg::mem_idx_t            mem_idx,
    output icache_pkg::mem_word_t           mem_wdata,
    input  icache_pkg::mem_word_t           mem_rdata,
    input  logic                            mem_ack,

    output logic [31:0]                     stat_hits,
    output logic [31:0]                     stat_misses
);
    import icache_pkg::*;

    typedef enum logic [1:0] {
        ST_IDLE        = 2'd0,
        ST_MISS_FILL   = 2'd1,
        ST_MISS_FINISH = 2'd2
    } core_state_e;

    core_state_e       state_q;

    cache_addr_t       lookup_addr;
    logic              resolve_pending;

    cache_set_t        lookup_set;
    cache_tag_t        lookup_tag;
    instr_sel_t        lookup_isel;
    cache_set_t        tag_read_set;

    logic [NUM_WAYS-1:0]          tag_valid;
    logic [NUM_WAYS*TAG_BITS-1:0] tag_flat;
    way_mask_t         hit_mask;
    way_mask_t         invalid_mask;
    logic              lookup_hit;
    cache_way_t        hit_way;
    cache_way_t        victim_way;
    cache_way_t        alloc_way;
    cache_way_t        data_rd_way;
    cache_line_t       line_rdata;

    logic              hold_resp;
    logic [FETCH_INSTR_NUM*32-1:0] hold_rdata;

    logic              tag_w_en;
    cache_set_t        tag_w_set;
    cache_way_t        tag_w_way;
    tag_entry_t        tag_w_entry;

    logic              data_w_en;
    cache_set_t        data_w_set;
    cache_way_t        data_w_way;
    cache_line_t       data_w_line;

    logic              plru_upd_en;
    cache_set_t        plru_set;
    cache_way_t        plru_touch_way;

    logic              mshr_alloc;
    logic              mshr_dealloc;
    logic              mshr_busy;
    cache_addr_t       mshr_addr;
    instr_sel_t        mshr_isel;
    cache_set_t        mshr_set;
    cache_tag_t        mshr_tag;
    cache_way_t        mshr_way;

    logic              rf_start_read;
    logic              rf_busy;
    logic              rf_done;
    cache_line_t       rf_read_line;

    logic              accept_req;

    logic [31:0]       hits_q;
    logic [31:0]       misses_q;

    logic              cross_q;
    logic              mshr_cross_q;
    logic [4:0]        cross_num_avail;
    logic              cross_pending;
    wire               req_crosses = (FETCH_INSTR_NUM > 1) && (addr_to_instr_sel(req_addr) + FETCH_INSTR_NUM > 16);

    assign stat_hits   = hits_q;
    assign stat_misses = misses_q;

    assign req_ready = (state_q == ST_IDLE) && !resolve_pending && !mshr_busy
                       && !rf_busy && !hold_resp && !inv_all && !cross_q;

    assign accept_req = req_valid && req_ready;

    assign resp_valid = hold_resp;
    assign resp_data  = hold_rdata;
    assign resp_valid_mask = hold_resp ? {FETCH_INSTR_NUM{1'b1}} : '0;

    assign lookup_set  = addr_to_set(lookup_addr);
    assign lookup_tag  = addr_to_tag(lookup_addr);
    assign lookup_isel = addr_to_instr_sel(lookup_addr);
    assign tag_read_set = (state_q == ST_IDLE) ? lookup_set : mshr_set;
    assign data_rd_way  = lookup_hit ? hit_way : alloc_way;

    icache_tag_ram u_tag (
        .clk         (clk),
        .rst_n       (rst_n),
        .r_set       (tag_read_set),
        .r_valid     (tag_valid),
        .r_tags_flat (tag_flat),
        .w_en        (tag_w_en),
        .w_set       (tag_w_set),
        .w_way       (tag_w_way),
        .w_entry     (tag_w_entry),
        .inv_all     (inv_all)
    );

    icache_data_ram u_data (
        .clk    (clk),
        .r_set  (lookup_set),
        .r_way  (data_rd_way),
        .r_line (line_rdata),
        .w_en   (data_w_en),
        .w_set  (data_w_set),
        .w_way  (data_w_way),
        .w_line (data_w_line)
    );

    icache_plru u_plru (
        .clk        (clk),
        .rst_n      (rst_n),
        .set_idx    (plru_set),
        .victim_way (victim_way),
        .update_en  (plru_upd_en),
        .touch_way  (plru_touch_way)
    );

    icache_mshr u_mshr (
        .clk         (clk),
        .rst_n       (rst_n),
        .busy        (mshr_busy),
        .addr        (mshr_addr),
        .instr_sel   (mshr_isel),
        .set_idx     (mshr_set),
        .tag         (mshr_tag),
        .alloc_way   (mshr_way),
        .alloc       (mshr_alloc),
        .alloc_addr  (lookup_addr),
        .alloc_way_i (alloc_way),
        .dealloc     (mshr_dealloc)
    );

    icache_refill u_refill (
        .clk         (clk),
        .rst_n       (rst_n),
        .start_read  (rf_start_read),
        .base_widx   (addr_to_line_base_widx(mshr_addr)),
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

    cache_way_t first_invalid_way;
    always_comb begin
        first_invalid_way = '0;
        for (int w = NUM_WAYS-1; w >= 0; w--)
            if (invalid_mask[w])
                first_invalid_way = cache_way_t'(w);
    end
    assign alloc_way = (|invalid_mask) ? first_invalid_way : victim_way;

    cache_line_t fill_line;
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
        fill_line      = rf_read_line;

        unique case (state_q)
            ST_IDLE: begin
                if (resolve_pending && lookup_hit) begin
                    plru_upd_en    = 1'b1;
                    plru_set       = lookup_set;
                    plru_touch_way = hit_way;
                end else if (resolve_pending && !lookup_hit) begin
                    mshr_alloc = 1'b1;
                end
            end

            ST_MISS_FILL: begin
                if (!rf_busy && !rf_done)
                    rf_start_read = 1'b1;
            end

            ST_MISS_FINISH: begin
                tag_w_en          = 1'b1;
                tag_w_set         = mshr_set;
                tag_w_way         = mshr_way;
                tag_w_entry.valid = 1'b1;
                tag_w_entry.tag   = mshr_tag;

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

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q         <= ST_IDLE;
            lookup_addr     <= '0;
            resolve_pending <= 1'b0;
            hold_resp       <= 1'b0;
            hold_rdata      <= '0;
            hits_q          <= '0;
            misses_q        <= '0;
            cross_q         <= 1'b0;
            mshr_cross_q    <= 1'b0;
            cross_num_avail <= '0;
            cross_pending   <= 1'b0;
        end else begin
            if (hold_resp && resp_ready)
                hold_resp <= 1'b0;

            unique case (state_q)
                ST_IDLE: begin
                    if (accept_req) begin
                        lookup_addr     <= req_addr;
                        resolve_pending <= 1'b1;
                        cross_q         <= 1'b0;
                        mshr_cross_q    <= 1'b0;
                        cross_pending   <= req_crosses;
                        cross_num_avail <= 5'(16 - addr_to_instr_sel(req_addr));
                    end else if (resolve_pending) begin
                        resolve_pending <= 1'b0;
                        if (lookup_hit) begin
                            hits_q <= hits_q + 32'd1;
                            if (cross_pending) begin
                                for (int i = 0; i < FETCH_INSTR_NUM; i++) begin
                                    if (i < cross_num_avail) begin
                                        hold_rdata[i*32 +: 32] <= line_rdata[(lookup_isel + i)*32 +: 32];
                                    end
                                end
                                lookup_addr     <= {lookup_addr[31:6] + 1'b1, 6'd0};
                                resolve_pending <= 1'b1;
                                cross_pending   <= 1'b0;
                                cross_q         <= 1'b1;
                            end else if (cross_q) begin
                                for (int i = 0; i < FETCH_INSTR_NUM; i++) begin
                                    if (i < FETCH_INSTR_NUM - cross_num_avail) begin
                                        hold_rdata[(cross_num_avail + i)*32 +: 32] <= line_rdata[i*32 +: 32];
                                    end
                                end
                                hold_resp       <= 1'b1;
                                cross_q         <= 1'b0;
                            end else begin
                                for (int i = 0; i < FETCH_INSTR_NUM; i++) begin
                                    hold_rdata[i*32 +: 32] <= line_rdata[(lookup_isel + i)*32 +: 32];
                                end
                                hold_resp       <= 1'b1;
                            end
                        end else begin
                            misses_q <= misses_q + 32'd1;
                            state_q  <= ST_MISS_FILL;
                            if (cross_pending) begin
                                mshr_cross_q  <= 1'b1;
                                cross_pending <= 1'b0;
                            end else begin
                                mshr_cross_q  <= 1'b0;
                            end
                        end
                    end
                end

                ST_MISS_FILL: begin
                    if (rf_done)
                        state_q <= ST_MISS_FINISH;
                end

                ST_MISS_FINISH: begin
                    if (mshr_cross_q) begin
                        for (int i = 0; i < FETCH_INSTR_NUM; i++) begin
                            if (i < cross_num_avail) begin
                                hold_rdata[i*32 +: 32] <= fill_line[(mshr_isel + i)*32 +: 32];
                            end
                        end
                        lookup_addr     <= {mshr_addr[31:6] + 1'b1, 6'd0};
                        resolve_pending <= 1'b1;
                        cross_q         <= 1'b1;
                        mshr_cross_q    <= 1'b0;
                        state_q         <= ST_IDLE;
                    end else if (cross_q) begin
                        for (int i = 0; i < FETCH_INSTR_NUM; i++) begin
                            if (i < FETCH_INSTR_NUM - cross_num_avail) begin
                                hold_rdata[(cross_num_avail + i)*32 +: 32] <= fill_line[i*32 +: 32];
                            end
                        end
                        hold_resp <= 1'b1;
                        cross_q   <= 1'b0;
                        state_q   <= ST_IDLE;
                    end else begin
                        for (int i = 0; i < FETCH_INSTR_NUM; i++) begin
                            hold_rdata[i*32 +: 32] <= fill_line[(mshr_isel + i)*32 +: 32];
                        end
                        hold_resp <= 1'b1;
                        state_q   <= ST_IDLE;
                    end
                end

                default: state_q <= ST_IDLE;
            endcase
        end
    end

endmodule
