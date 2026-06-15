`timescale 1ns/1ps

module BR_CHECKER
    import riscv_btb_pkg::*;
#(
    parameter int unsigned XLEN        = 32,
    parameter int unsigned IMEM_WIDTH  = 128,
    parameter int unsigned FETCH_BYTES = IMEM_WIDTH / 8
)(
    input  logic                    valid_i,
    input  logic [XLEN-1:0]         block_pc_i,

    input  logic                    decode_branch_valid_i,
    input  logic [XLEN-1:0]         decode_branch_pc_i,
    input  logic [XLEN-1:0]         decode_direct_target_i,
    input  logic                    decode_direct_target_valid_i,
    input  btb_br_type_e            decode_branch_type_i,

    input  logic                    btb_hit_i,
    input  logic [XLEN-1:0]         btb_branch_pc_i,
    input  logic [XLEN-1:0]         btb_target_i,
    input  logic                    btb_taken_i,
    input  btb_br_type_e            btb_branch_type_i,

    input  logic                    backing_valid_i,
    input  logic                    backing_taken_i,

    output logic                    result_valid_o,
    output logic                    prediction_valid_o,
    output logic [XLEN-1:0]         branch_pc_o,
    output logic [XLEN-1:0]         target_o,
    output logic                    taken_o,
    output btb_br_type_e            branch_type_o,
    output logic [XLEN-1:0]         next_pc_o,

    output logic                    btb_repair_valid_o,
    output logic [XLEN-1:0]         btb_repair_pc_o,
    output logic [XLEN-1:0]         btb_repair_target_o,
    output btb_br_type_e            btb_repair_type_o
);

    logic btb_matches_decode;
    logic prediction_ready;

    always_comb begin
        btb_matches_decode =
            btb_hit_i &&
            decode_branch_valid_i &&
            (btb_branch_pc_i == decode_branch_pc_i) &&
            (btb_branch_type_i == decode_branch_type_i);

        prediction_ready =
            !decode_branch_valid_i ||
            (decode_branch_type_i != BTB_COND) ||
            backing_valid_i;

        result_valid_o      = valid_i && prediction_ready;
        prediction_valid_o  = decode_branch_valid_i;
        branch_pc_o         = decode_branch_pc_i;
        target_o            = '0;
        taken_o             = 1'b0;
        branch_type_o = BTB_NONE;
        if (decode_branch_valid_i)
            branch_type_o = decode_branch_type_i;
        next_pc_o           = block_pc_i + XLEN'(FETCH_BYTES);

        if (decode_branch_valid_i) begin
            if (decode_direct_target_valid_i)
                target_o = decode_direct_target_i;
            else if (btb_matches_decode)
                target_o = btb_target_i;

            unique case (decode_branch_type_i)
                BTB_COND:
                    taken_o =
                        backing_valid_i &&
                        backing_taken_i &&
                        decode_direct_target_valid_i;

                BTB_JUMP,
                BTB_CALL:
                    taken_o = decode_direct_target_valid_i;

                BTB_IND,
                BTB_ICALL,
                BTB_RET:
                    taken_o = btb_matches_decode && btb_taken_i;

                default:
                    taken_o = 1'b0;
            endcase

            if (taken_o)
                next_pc_o = target_o;
        end

        // F3 can repair direct unconditional entries without training BIM.
        btb_repair_valid_o =
            result_valid_o &&
            decode_direct_target_valid_i &&
            (decode_branch_type_i == BTB_JUMP ||
             decode_branch_type_i == BTB_CALL) &&
            (!btb_matches_decode ||
             (btb_target_i != decode_direct_target_i));
        btb_repair_pc_o     = decode_branch_pc_i;
        btb_repair_target_o = decode_direct_target_i;
        btb_repair_type_o   = decode_branch_type_i;
    end

endmodule
