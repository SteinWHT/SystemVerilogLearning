`timescale 1ns/1ps

module RESP_QUEUES
    import riscv_btb_pkg::*;
#(
    parameter int unsigned XLEN             = 32,
    parameter int unsigned IMEM_WIDTH       = 128,
    parameter int unsigned FETCH_INDEX_BITS = 2,
    parameter int unsigned DEPTH            = 2,

    localparam int unsigned IMEM_PAYLOAD_WIDTH =
        IMEM_WIDTH + (2 * XLEN) + FETCH_INDEX_BITS,
    localparam int unsigned BTB_PAYLOAD_WIDTH =
        (3 * XLEN) + 1 + 1 + 3
)(
    input  logic                            clk,
    input  logic                            rst_n,
    input  logic                            clear_i,

    input  logic                            imem_push_i,
    input  logic [IMEM_WIDTH-1:0]           imem_data_i,
    input  logic [XLEN-1:0]                 imem_start_pc_i,
    input  logic [XLEN-1:0]                 imem_block_pc_i,
    input  logic [FETCH_INDEX_BITS-1:0]     imem_start_index_i,
    output logic                            imem_full_o,
    output logic                            imem_empty_o,

    input  logic                            btb_push_i,
    input  logic [XLEN-1:0]                 btb_resp_pc_i,
    input  logic [XLEN-1:0]                 btb_branch_pc_i,
    input  logic [XLEN-1:0]                 btb_target_i,
    input  logic                            btb_hit_i,
    input  logic                            btb_taken_i,
    input  btb_br_type_e                    btb_br_type_i,
    output logic                            btb_full_o,
    output logic                            btb_empty_o,

    output logic                            pair_valid_o,
    input  logic                            pair_ready_i,

    output logic [IMEM_WIDTH-1:0]           pair_imem_data_o,
    output logic [XLEN-1:0]                 pair_start_pc_o,
    output logic [XLEN-1:0]                 pair_block_pc_o,
    output logic [FETCH_INDEX_BITS-1:0]     pair_start_index_o,

    output logic [XLEN-1:0]                 pair_btb_resp_pc_o,
    output logic [XLEN-1:0]                 pair_btb_branch_pc_o,
    output logic [XLEN-1:0]                 pair_btb_target_o,
    output logic                            pair_btb_hit_o,
    output logic                            pair_btb_taken_o,
    output btb_br_type_e                    pair_btb_br_type_o
);

    logic [IMEM_PAYLOAD_WIDTH-1:0] imem_data_in;
    logic [IMEM_PAYLOAD_WIDTH-1:0] imem_data_out;
    logic [BTB_PAYLOAD_WIDTH-1:0]  btb_data_in;
    logic [BTB_PAYLOAD_WIDTH-1:0]  btb_data_out;
    logic [2:0]                    pair_btb_br_type_bits;
    logic                          pair_pop;

    always_comb begin
        imem_data_in = {
            imem_data_i,
            imem_start_pc_i,
            imem_block_pc_i,
            imem_start_index_i
        };

        btb_data_in = {
            btb_resp_pc_i,
            btb_branch_pc_i,
            btb_target_i,
            btb_hit_i,
            btb_taken_i,
            btb_br_type_i
        };

        {
            pair_imem_data_o,
            pair_start_pc_o,
            pair_block_pc_o,
            pair_start_index_o
        } = imem_data_out;

        {
            pair_btb_resp_pc_o,
            pair_btb_branch_pc_o,
            pair_btb_target_o,
            pair_btb_hit_o,
            pair_btb_taken_o,
            pair_btb_br_type_bits
        } = btb_data_out;

        pair_btb_br_type_o =
            btb_br_type_e'(pair_btb_br_type_bits);
    end

    always_comb begin
        pair_valid_o = !imem_empty_o && !btb_empty_o;
    end

    always_comb begin
        pair_pop = pair_valid_o && pair_ready_i;
    end

    sync_fifo #(
        .DATA_WIDTH (IMEM_PAYLOAD_WIDTH),
        .DEPTH      (DEPTH)
    ) imem_response_queue (
        .clk      (clk),
        .rst_n    (rst_n),
        .clear    (clear_i),
        .data_in  (imem_data_in),
        .write_en (imem_push_i),
        .read_en  (pair_pop),
        .data_out (imem_data_out),
        .empty    (imem_empty_o),
        .full     (imem_full_o)
    );

    sync_fifo #(
        .DATA_WIDTH (BTB_PAYLOAD_WIDTH),
        .DEPTH      (DEPTH)
    ) btb_response_queue (
        .clk      (clk),
        .rst_n    (rst_n),
        .clear    (clear_i),
        .data_in  (btb_data_in),
        .write_en (btb_push_i),
        .read_en  (pair_pop),
        .data_out (btb_data_out),
        .empty    (btb_empty_o),
        .full     (btb_full_o)
    );

    // synthesis translate_off
    initial begin
        assert (DEPTH >= 2 && (DEPTH & (DEPTH - 1)) == 0)
            else $fatal(1, "RESP_QUEUES: DEPTH must be a power of two >= 2");
    end

    always_ff @(posedge clk) begin
        if (rst_n && !clear_i) begin
            assert (!(imem_push_i && imem_full_o))
                else $error("RESP_QUEUES: I-memory response queue overflow");
            assert (!(btb_push_i && btb_full_o))
                else $error("RESP_QUEUES: BTB response queue overflow");
        end
    end
    // synthesis translate_on

endmodule
