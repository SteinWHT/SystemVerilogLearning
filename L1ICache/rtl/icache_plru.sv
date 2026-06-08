// Per-set 4-way tree PLRU state (victim pick + update on hit/allocate)

module icache_plru #(
    parameter int unsigned NUM_SETS = icache_pkg::NUM_SETS,
    parameter int unsigned NUM_WAYS = icache_pkg::NUM_WAYS
) (
    input  logic                          clk,
    input  logic                          rst_n,

    input  icache_pkg::cache_set_t        set_idx,
    output icache_pkg::cache_way_t        victim_way,

    input  logic                          update_en,
    input  icache_pkg::cache_way_t        touch_way
);
    import icache_pkg::*;

    plru_state_t plru_ram [NUM_SETS];
    plru_state_t set_state;

    always_comb begin
        set_state  = plru_ram[int'(set_idx)];
        victim_way = plru_victim(set_state);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int s = 0; s < NUM_SETS; s++)
                plru_ram[s] <= '0;
        end else if (update_en) begin
            plru_ram[int'(set_idx)] <= plru_touch(plru_ram[int'(set_idx)], touch_way);
        end
    end

endmodule
