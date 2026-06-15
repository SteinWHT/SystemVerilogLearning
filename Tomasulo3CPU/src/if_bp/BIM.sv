`timescale 1ns/1ps

module BIM
    import riscv_btb_pkg::*;
#(
    parameter int unsigned XLEN        = 64,
    parameter int unsigned NUM_ENTRIES = 1024,

    localparam int unsigned INST_ALIGN_BYTES = 4,
    localparam int unsigned ALIGN_BITS       = $clog2(INST_ALIGN_BYTES),
    localparam int unsigned INDEX_BITS       =
        (NUM_ENTRIES > 1) ? $clog2(NUM_ENTRIES) : 1
)(
    input  logic                clk,
    input  logic                rst_n,

    input  logic                lookup_valid_i,
    input  logic [XLEN-1:0]     lookup_pc_i,

    output logic                resp_valid_o,
    output logic [XLEN-1:0]     resp_pc_o,
    output logic                resp_taken_o,
    output bim_ctr_e            resp_counter_o,

    input  logic                update_valid_i,
    input  logic [XLEN-1:0]     update_pc_i,
    input  logic                update_taken_i,

    // Clears both the response pipeline and all learned counters.
    input  logic                flush_i
);

    logic [1:0] bim_mem [NUM_ENTRIES];

    function automatic logic [INDEX_BITS-1:0] get_index(
        input logic [XLEN-1:0] pc
    );
        if (NUM_ENTRIES == 1)
            get_index = '0;
        else
            get_index = INDEX_BITS'(pc >> ALIGN_BITS);
    endfunction

    function automatic logic [1:0] update_counter(
        input logic [1:0] old_counter,
        input logic       taken
    );
        begin
            unique case (old_counter)
                BIM_STRONGLY_NT:
                    update_counter = taken ? BIM_WEAKLY_NT : BIM_STRONGLY_NT;
                BIM_WEAKLY_NT:
                    update_counter = taken ? BIM_WEAKLY_T : BIM_STRONGLY_NT;
                BIM_WEAKLY_T:
                    update_counter = taken ? BIM_STRONGLY_T : BIM_WEAKLY_NT;
                BIM_STRONGLY_T:
                    update_counter = taken ? BIM_STRONGLY_T : BIM_WEAKLY_T;
                default:
                    update_counter = BIM_WEAKLY_NT;
            endcase
        end
    endfunction

    logic [INDEX_BITS-1:0] lookup_idx;
    logic [INDEX_BITS-1:0] update_idx;
    logic [1:0]            lookup_counter;
    logic [1:0]            update_counter_next;

    assign lookup_idx         = get_index(lookup_pc_i);
    assign update_idx         = get_index(update_pc_i);
    assign lookup_counter     = bim_mem[lookup_idx];
    assign update_counter_next =
        update_counter(bim_mem[update_idx], update_taken_i);

    // A simultaneous lookup/update to the same entry returns the old counter.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_i) begin
            resp_valid_o   <= 1'b0;
            resp_pc_o      <= '0;
            resp_taken_o   <= 1'b0;
            resp_counter_o <= bim_ctr_e'(BIM_WEAKLY_NT);

            for (int i = 0; i < NUM_ENTRIES; i++)
                bim_mem[i] <= 2'(BIM_WEAKLY_NT);
        end else begin
            resp_valid_o   <= lookup_valid_i;
            resp_pc_o      <= lookup_pc_i;
            resp_counter_o <= bim_ctr_e'(lookup_counter);
            resp_taken_o   <= lookup_counter[1];

            if (update_valid_i)
                bim_mem[update_idx] <= update_counter_next;
        end
    end

    // synthesis translate_off
    initial begin
        assert (NUM_ENTRIES > 0 &&
                (NUM_ENTRIES & (NUM_ENTRIES - 1)) == 0)
            else $fatal(1, "BIM: NUM_ENTRIES must be a power of two");
        assert (XLEN > ALIGN_BITS)
            else $fatal(1, "BIM: XLEN is too small");
    end
    // synthesis translate_on

endmodule
