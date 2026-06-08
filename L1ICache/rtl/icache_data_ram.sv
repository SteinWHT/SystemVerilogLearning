// Data array: one cache line (LINE_BITS) per (set, way).
// Combinational read of the selected way's full line; synchronous full-line write.

module icache_data_ram #(
    parameter int unsigned NUM_SETS = icache_pkg::NUM_SETS,
    parameter int unsigned NUM_WAYS = icache_pkg::NUM_WAYS
) (
    input  logic                          clk,

    input  icache_pkg::cache_set_t        r_set,
    input  icache_pkg::cache_way_t        r_way,
    output icache_pkg::cache_line_t       r_line,

    input  logic                          w_en,
    input  icache_pkg::cache_set_t        w_set,
    input  icache_pkg::cache_way_t        w_way,
    input  icache_pkg::cache_line_t       w_line
);
    import icache_pkg::*;

    cache_line_t data_array [NUM_SETS][NUM_WAYS];

    always_comb
        r_line = data_array[int'(r_set)][int'(r_way)];

    always_ff @(posedge clk) begin
        if (w_en)
            data_array[int'(w_set)][int'(w_way)] <= w_line;
    end

endmodule
