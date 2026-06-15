`timescale 1ns/1ps

module FETCH_TARGET_BUFFER #(
    parameter int unsigned XLEN  = 32,
    parameter int unsigned DEPTH = 2
)(
    input  logic                clk,
    input  logic                rst_n,
    input  logic                clear_i,

    input  logic                push_valid_i,
    output logic                push_ready_o,
    input  logic [XLEN-1:0]     push_target_i,

    output logic                target_valid_o,
    input  logic                target_ready_i,
    output logic [XLEN-1:0]     target_o,

    output logic                empty_o,
    output logic                full_o
);

    logic pop;

    always_comb begin
        push_ready_o  = !full_o;
        target_valid_o = !empty_o;
    end

    always_comb begin
        pop = target_valid_o && target_ready_i;
    end

    sync_fifo #(
        .DATA_WIDTH (XLEN),
        .DEPTH      (DEPTH)
    ) target_fifo (
        .clk      (clk),
        .rst_n    (rst_n),
        .clear    (clear_i),
        .data_in  (push_target_i),
        .write_en (push_valid_i && push_ready_o),
        .read_en  (pop),
        .data_out (target_o),
        .empty    (empty_o),
        .full     (full_o)
    );

endmodule
