`timescale 1ns/1ps

// Simulation/synthesis shell for a future TAGE, GShare, or similar predictor.
// The current placeholder preserves the BIM direction supplied by the BTB.
module BACKING_PREDICTOR #(
    parameter int unsigned XLEN = 32
)(
    input  logic                lookup_valid_i,
    input  logic [XLEN-1:0]     lookup_pc_i,
    input  logic                base_taken_i,

    output logic                resp_valid_o,
    output logic                resp_taken_o,

    input  logic                update_valid_i,
    input  logic [XLEN-1:0]     update_pc_i,
    input  logic                update_taken_i
);

    always_comb begin
        resp_valid_o = lookup_valid_i;
        resp_taken_o = base_taken_i;
    end

    // Keep the replacement interface visible while this module is a shell.
    logic unused_inputs;
    always_comb begin
        unused_inputs =
            ^lookup_pc_i ^
            update_valid_i ^
            ^update_pc_i ^
            update_taken_i;
    end

endmodule
