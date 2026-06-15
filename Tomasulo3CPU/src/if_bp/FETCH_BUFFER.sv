`timescale 1ns/1ps

module FETCH_BUFFER
    import riscv_btb_pkg::*;
#(
    parameter int unsigned XLEN             = 32,
    parameter int unsigned INSTR_WIDTH      = 32,
    parameter int unsigned IMEM_WIDTH       = 128,
    parameter int unsigned FETCH_INDEX_BITS = 2,
    parameter int unsigned DEPTH            = 2,

    localparam int unsigned INSTR_BYTES = INSTR_WIDTH / 8,
    localparam int unsigned PAYLOAD_WIDTH =
        IMEM_WIDTH + (3 * XLEN) + FETCH_INDEX_BITS + 1 + 1 + 3
)(
    input  logic                            clk,
    input  logic                            rst_n,
    input  logic                            clear_i,

    input  logic                            push_valid_i,
    output logic                            push_ready_o,
    input  logic [IMEM_WIDTH-1:0]           push_data_i,
    input  logic [XLEN-1:0]                 push_block_pc_i,
    input  logic [FETCH_INDEX_BITS-1:0]     push_start_index_i,
    input  logic                            push_prediction_valid_i,
    input  logic [XLEN-1:0]                 push_branch_pc_i,
    input  logic [XLEN-1:0]                 push_target_i,
    input  logic                            push_taken_i,
    input  btb_br_type_e                    push_branch_type_i,

    input  logic                            read_i,
    output logic [INSTR_WIDTH-1:0]          instr_o,
    output logic [XLEN-1:0]                 pc_o,
    output logic [XLEN-1:0]                 pc_plus_o,
    output logic                            empty_o,
    output logic                            prediction_valid_o,
    output logic                            prediction_taken_o,
    output logic [XLEN-1:0]                 prediction_target_o,
    output btb_br_type_e                    prediction_branch_type_o
);

    logic [PAYLOAD_WIDTH-1:0] fifo_data_in;
    logic [PAYLOAD_WIDTH-1:0] fifo_data_out;
    logic fifo_empty;
    logic fifo_full;
    logic fifo_pop;

    logic active_valid_q;
    logic [IMEM_WIDTH-1:0] active_data_q;
    logic [XLEN-1:0] active_block_pc_q;
    logic [FETCH_INDEX_BITS-1:0] active_index_q;
    logic active_prediction_valid_q;
    logic [XLEN-1:0] active_branch_pc_q;
    logic [XLEN-1:0] active_target_q;
    logic active_taken_q;
    btb_br_type_e active_branch_type_q;

    logic [IMEM_WIDTH-1:0] fifo_data;
    logic [XLEN-1:0] fifo_block_pc;
    logic [FETCH_INDEX_BITS-1:0] fifo_start_index;
    logic fifo_prediction_valid;
    logic [XLEN-1:0] fifo_branch_pc;
    logic [XLEN-1:0] fifo_target;
    logic fifo_taken;
    logic [2:0] fifo_branch_type_bits;
    btb_br_type_e fifo_branch_type;
    logic current_is_branch;
    logic current_is_last;
    logic consume;
    logic finish_packet;

    always_comb begin
        fifo_data_in = {
            push_data_i,
            push_block_pc_i,
            push_start_index_i,
            push_prediction_valid_i,
            push_branch_pc_i,
            push_target_i,
            push_taken_i,
            push_branch_type_i
        };

        {
            fifo_data,
            fifo_block_pc,
            fifo_start_index,
            fifo_prediction_valid,
            fifo_branch_pc,
            fifo_target,
            fifo_taken,
            fifo_branch_type_bits
        } = fifo_data_out;
        fifo_branch_type = btb_br_type_e'(fifo_branch_type_bits);

        push_ready_o = !fifo_full;
        fifo_pop     = !active_valid_q && !fifo_empty;

        pc_o =
            active_block_pc_q +
            XLEN'(active_index_q * INSTR_BYTES);
        pc_plus_o = pc_o + XLEN'(INSTR_BYTES);
        instr_o =
            active_data_q[active_index_q * INSTR_WIDTH +: INSTR_WIDTH];
        empty_o = !active_valid_q;

        current_is_branch =
            active_valid_q &&
            active_prediction_valid_q &&
            (pc_o == active_branch_pc_q);
        current_is_last =
            (active_index_q ==
             FETCH_INDEX_BITS'(IMEM_WIDTH / INSTR_WIDTH - 1));
        consume = read_i && active_valid_q;
        finish_packet =
            consume &&
            (current_is_last ||
             (current_is_branch && active_taken_q));

        prediction_valid_o       = current_is_branch;
        prediction_taken_o       = current_is_branch && active_taken_q;
        prediction_target_o      = active_target_q;
        prediction_branch_type_o = BTB_NONE;
        if (current_is_branch)
            prediction_branch_type_o = active_branch_type_q;
    end

    sync_fifo #(
        .DATA_WIDTH (PAYLOAD_WIDTH),
        .DEPTH      (DEPTH)
    ) packet_fifo (
        .clk      (clk),
        .rst_n    (rst_n),
        .clear    (clear_i),
        .data_in  (fifo_data_in),
        .write_en (push_valid_i && push_ready_o),
        .read_en  (fifo_pop),
        .data_out (fifo_data_out),
        .empty    (fifo_empty),
        .full     (fifo_full)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || clear_i) begin
            active_valid_q            <= 1'b0;
            active_data_q             <= '0;
            active_block_pc_q         <= '0;
            active_index_q            <= '0;
            active_prediction_valid_q <= 1'b0;
            active_branch_pc_q        <= '0;
            active_target_q           <= '0;
            active_taken_q            <= 1'b0;
            active_branch_type_q      <= BTB_NONE;
        end else begin
            if (fifo_pop) begin
                active_data_q             <= fifo_data;
                active_block_pc_q         <= fifo_block_pc;
                active_index_q            <= fifo_start_index;
                active_prediction_valid_q <= fifo_prediction_valid;
                active_branch_pc_q        <= fifo_branch_pc;
                active_target_q           <= fifo_target;
                active_taken_q            <= fifo_taken;
                active_branch_type_q      <= fifo_branch_type;
                active_valid_q            <= 1'b1;
            end else if (finish_packet) begin
                active_valid_q <= 1'b0;
                active_index_q <= '0;
                active_prediction_valid_q <= 1'b0;
            end else if (consume) begin
                active_index_q <=
                    active_index_q + FETCH_INDEX_BITS'(1);
            end
        end
    end

endmodule
