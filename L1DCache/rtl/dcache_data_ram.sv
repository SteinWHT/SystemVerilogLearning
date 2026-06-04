// Data array: one cache line (LINE_BITS) per (set, way).
// Combinational read of the selected way's full line; synchronous full-line write.
// (A real SRAM macro would register the read; the core's pipeline tolerates either.)

module dcache_data_ram #(
    parameter int unsigned NUM_SETS  = dcache_pkg::NUM_SETS,
    parameter int unsigned NUM_WAYS  = dcache_pkg::NUM_WAYS
) (
    input  logic                          clk,

    input  dcache_pkg::cache_set_t        r_set,
    input  dcache_pkg::cache_way_t        r_way,
    output dcache_pkg::cache_line_t       r_line,

    input  logic                          w_en,
    input  dcache_pkg::cache_set_t        w_set,
    input  dcache_pkg::cache_way_t        w_way,
    input  dcache_pkg::cache_line_t       w_line
);
    import dcache_pkg::*;

    cache_line_t data_array [NUM_SETS][NUM_WAYS];

    always_comb
        r_line = data_array[int'(r_set)][int'(r_way)];

    always_ff @(posedge clk) begin
        if (w_en)
            data_array[int'(w_set)][int'(w_way)] <= w_line;
    end

endmodule
