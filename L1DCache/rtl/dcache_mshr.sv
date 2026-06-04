// Single-entry miss-status holding register (blocking cache)
//
// Captures the missing request plus the chosen victim's metadata/data so the
// refill engine can write back a dirty victim and fill the new line without
// re-reading the arrays

module dcache_mshr (
    input  logic                            clk,
    input  logic                            rst_n,

    output logic                            busy,
    output dcache_pkg::dcache_op_e          op,
    output dcache_pkg::cache_addr_t         addr,
    output dcache_pkg::cache_word_t         wdata,
    output dcache_pkg::cache_strb_t         wstrb,
    output dcache_pkg::word_sel_t           word_sel,
    output dcache_pkg::cache_set_t          set_idx,
    output dcache_pkg::cache_tag_t          tag,
    output dcache_pkg::cache_way_t          alloc_way,
    output logic                            needs_writeback,
    output dcache_pkg::cache_line_t         victim_data,
    output dcache_pkg::tag_entry_t          victim_entry,

    input  logic                            alloc,
    input  dcache_pkg::dcache_op_e          alloc_op,
    input  dcache_pkg::cache_addr_t         alloc_addr,
    input  dcache_pkg::cache_word_t         alloc_wdata,
    input  dcache_pkg::cache_strb_t         alloc_wstrb,
    input  dcache_pkg::cache_way_t          alloc_way_i,
    input  logic                            alloc_needs_wb,
    input  dcache_pkg::cache_line_t         alloc_victim_data,
    input  dcache_pkg::tag_entry_t          alloc_victim_entry,

    input  logic                            dealloc
);
    import dcache_pkg::*;

    logic              valid_q;
    dcache_op_e        op_q;
    cache_addr_t       addr_q;
    cache_word_t       wdata_q;
    cache_strb_t       wstrb_q;
    cache_way_t        alloc_way_q;
    logic              needs_wb_q;
    cache_line_t       victim_data_q;
    tag_entry_t        victim_entry_q;

    assign busy            = valid_q;
    assign op              = op_q;
    assign addr            = addr_q;
    assign wdata           = wdata_q;
    assign wstrb           = wstrb_q;
    assign word_sel        = addr_to_word_sel(addr_q);
    assign set_idx         = addr_to_set(addr_q);
    assign tag             = addr_to_tag(addr_q);
    assign alloc_way       = alloc_way_q;
    assign needs_writeback = needs_wb_q;
    assign victim_data     = victim_data_q;
    assign victim_entry    = victim_entry_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_q <= 1'b0;
        end else if (dealloc) begin
            valid_q <= 1'b0;
        end else if (alloc && !valid_q) begin
            valid_q        <= 1'b1;
            op_q           <= alloc_op;
            addr_q         <= alloc_addr;
            wdata_q        <= alloc_wdata;
            wstrb_q        <= alloc_wstrb;
            alloc_way_q    <= alloc_way_i;
            needs_wb_q     <= alloc_needs_wb;
            victim_data_q  <= alloc_victim_data;
            victim_entry_q <= alloc_victim_entry;
        end
    end

endmodule
