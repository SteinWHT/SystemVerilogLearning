// Tag array: valid + tag per way (read-only cache — no dirty bit)

module icache_tag_ram #(
    parameter int unsigned NUM_SETS = icache_pkg::NUM_SETS,
    parameter int unsigned NUM_WAYS = icache_pkg::NUM_WAYS,
    parameter int unsigned TAG_BITS = icache_pkg::TAG_BITS
) (
    input  logic                          clk,
    input  logic                          rst_n,

    input  icache_pkg::cache_set_t        r_set,
    output logic [NUM_WAYS-1:0]           r_valid,
    output logic [NUM_WAYS*TAG_BITS-1:0]  r_tags_flat,

    input  logic                          w_en,
    input  icache_pkg::cache_set_t        w_set,
    input  icache_pkg::cache_way_t        w_way,
    input  icache_pkg::tag_entry_t        w_entry,

    // Optional full invalidation (fence.i / flush)
    input  logic                          inv_all
);
    import icache_pkg::*;

    logic                valid_ram [NUM_SETS][NUM_WAYS];
    logic [TAG_BITS-1:0] tag_ram   [NUM_SETS][NUM_WAYS];

    genvar gi;
    generate
        for (gi = 0; gi < NUM_WAYS; gi++) begin : g_rd
            assign r_valid[gi] = valid_ram[int'(r_set)][gi];
            assign r_tags_flat[gi*TAG_BITS +: TAG_BITS] = tag_ram[int'(r_set)][gi];
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int s = 0; s < NUM_SETS; s++)
                for (int w = 0; w < NUM_WAYS; w++) begin
                    valid_ram[s][w] <= 1'b0;
                    tag_ram[s][w]   <= '0;
                end
        end else if (inv_all) begin
            for (int s = 0; s < NUM_SETS; s++)
                for (int w = 0; w < NUM_WAYS; w++)
                    valid_ram[s][w] <= 1'b0;
        end else if (w_en) begin
            valid_ram[int'(w_set)][int'(w_way)] <= w_entry.valid;
            tag_ram[int'(w_set)][int'(w_way)]   <= w_entry.tag;
        end
    end

endmodule
