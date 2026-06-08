// Single-entry miss-status holding register (blocking cache).
//
// Captures the missing fetch address and chosen allocation way so the refill
// engine can fill the new line without re-reading the tag/data arrays.

module icache_mshr (
    input  logic                            clk,
    input  logic                            rst_n,

    output logic                            busy,
    output icache_pkg::cache_addr_t         addr,
    output icache_pkg::instr_sel_t          instr_sel,
    output icache_pkg::cache_set_t          set_idx,
    output icache_pkg::cache_tag_t          tag,
    output icache_pkg::cache_way_t          alloc_way,

    input  logic                            alloc,
    input  icache_pkg::cache_addr_t         alloc_addr,
    input  icache_pkg::cache_way_t          alloc_way_i,

    input  logic                            dealloc
);
    import icache_pkg::*;

    logic        valid_q;
    cache_addr_t addr_q;
    cache_way_t  alloc_way_q;

    assign busy      = valid_q;
    assign addr      = addr_q;
    assign instr_sel = addr_to_instr_sel(addr_q);
    assign set_idx   = addr_to_set(addr_q);
    assign tag       = addr_to_tag(addr_q);
    assign alloc_way = alloc_way_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_q <= 1'b0;
        end else if (dealloc) begin
            valid_q <= 1'b0;
        end else if (alloc && !valid_q) begin
            valid_q     <= 1'b1;
            addr_q      <= alloc_addr;
            alloc_way_q <= alloc_way_i;
        end
    end

endmodule
