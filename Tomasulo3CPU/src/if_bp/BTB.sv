`timescale 1ns/1ps

module BTB
    import riscv_btb_pkg::*;
#(
    parameter int unsigned XLEN            = 64,
    parameter int unsigned FETCH_BYTES     = 16,
    parameter int unsigned NUM_SETS        = 128,
    parameter int unsigned NUM_WAYS        = 4,
    parameter int unsigned BIM_ENTRIES     = 1024,
    parameter int unsigned RAS_DEPTH       = 16,
    parameter int unsigned RAS_CKPT_NUM    = 8,

    localparam int unsigned RAS_CKPT_BITS =
        (RAS_CKPT_NUM > 1) ? $clog2(RAS_CKPT_NUM) : 1
)(
    input  logic                         clk,
    input  logic                         rst_n,

    // Stage 0 interface
    input  logic                         lookup_valid_i,
    input  logic [XLEN-1:0]              lookup_pc_i,

    // Stage 2 interface
    output logic                         resp_valid_o,
    output logic                         resp_hit_o,
    output logic [XLEN-1:0]              resp_pc_o,
    output logic [XLEN-1:0]              resp_branch_pc_o,
    output logic [XLEN-1:0]              resp_target_o,
    output logic                         resp_taken_o,
    output btb_br_type_e                 resp_br_type_o,
    output bim_ctr_e                     resp_bim_counter_o,
    output logic                         resp_ras_used_o,

    // Branch checker interface
    input  logic                         update_valid_i,
    input  logic [XLEN-1:0]              update_pc_i,
    input  logic [XLEN-1:0]              update_target_i,
    input  btb_br_type_e                 update_br_type_i,
    input  logic                         update_taken_i,
    input  logic                         update_allocate_i,

    // Speculative RAS update from prediction or predecode.
    input  logic                         ras_spec_valid_i,
    input  ras_op_e                      ras_spec_op_i,
    input  logic [XLEN-1:0]              ras_spec_return_addr_i,

    input  logic                         ras_ckpt_alloc_i,
    output logic [RAS_CKPT_BITS-1:0]     ras_ckpt_id_o,
    input  logic                         ras_restore_i,
    input  logic [RAS_CKPT_BITS-1:0]     ras_restore_id_i,

    // Explicit predictor-state clear. Normal redirects must not assert this.
    input  logic                         clear_i
);

    logic                    tag_resp_valid;
    logic                    tag_resp_hit;
    logic [XLEN-1:0]         tag_resp_pc;
    logic [XLEN-1:0]         tag_resp_branch_pc;
    logic [XLEN-1:0]         tag_resp_target;
    btb_br_type_e            tag_resp_br_type;

    logic                    bim_resp_valid;
    logic [XLEN-1:0]         bim_resp_pc;
    logic                    bim_resp_taken;
    bim_ctr_e                bim_resp_counter;
    logic [XLEN-1:0]         bim_lookup_pc;
    logic                    bim_update_valid;

    logic                    ras_pred_req;
    logic                    ras_pred_valid;
    logic [XLEN-1:0]         ras_pred_target;

    logic                    tag_stage_valid_q;
    logic                    tag_stage_hit_q;
    logic [XLEN-1:0]         tag_stage_pc_q;
    logic [XLEN-1:0]         tag_stage_branch_pc_q;
    logic [XLEN-1:0]         tag_stage_target_q;
    btb_br_type_e            tag_stage_br_type_q;
    logic                    ras_stage_valid_q;
    logic [XLEN-1:0]         ras_stage_target_q;

    BTB_TAG #(
        .XLEN        (XLEN),
        .FETCH_BYTES (FETCH_BYTES),
        .NUM_SETS    (NUM_SETS),
        .NUM_WAYS    (NUM_WAYS)
    ) btb_tag (
        .clk               (clk),
        .rst_n             (rst_n),
        .lookup_valid_i    (lookup_valid_i),
        .lookup_pc_i       (lookup_pc_i),
        .resp_valid_o      (tag_resp_valid),
        .resp_hit_o        (tag_resp_hit),
        .resp_pc_o         (tag_resp_pc),
        .resp_branch_pc_o  (tag_resp_branch_pc),
        .resp_target_o     (tag_resp_target),
        .resp_br_type_o    (tag_resp_br_type),
        .update_valid_i    (update_valid_i),
        .update_pc_i       (update_pc_i),
        .update_target_i   (update_target_i),
        .update_br_type_i  (update_br_type_i),
        .update_taken_i    (update_taken_i),
        .update_allocate_i (update_allocate_i),
        .flush_i           (clear_i)
    );

    assign bim_lookup_pc = tag_resp_hit ? tag_resp_branch_pc : tag_resp_pc;
    assign bim_update_valid =
        update_valid_i && (update_br_type_i == BTB_COND);

    BIM #(
        .XLEN        (XLEN),
        .NUM_ENTRIES (BIM_ENTRIES)
    ) bim (
        .clk              (clk),
        .rst_n            (rst_n),
        .lookup_valid_i   (tag_resp_valid),
        .lookup_pc_i      (bim_lookup_pc),
        .resp_valid_o     (bim_resp_valid),
        .resp_pc_o        (bim_resp_pc),
        .resp_taken_o     (bim_resp_taken),
        .resp_counter_o   (bim_resp_counter),
        .update_valid_i   (bim_update_valid),
        .update_pc_i      (update_pc_i),
        .update_taken_i   (update_taken_i),
        .flush_i          (clear_i)
    );

    assign ras_pred_req =
        tag_resp_valid && tag_resp_hit && (tag_resp_br_type == BTB_RET);

    RAS #(
        .XLEN     (XLEN),
        .DEPTH    (RAS_DEPTH),
        .CKPT_NUM (RAS_CKPT_NUM)
    ) ras (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .pred_req_i             (ras_pred_req),
        .pred_valid_o           (ras_pred_valid),
        .pred_target_o          (ras_pred_target),
        .spec_valid_i           (ras_spec_valid_i),
        .spec_op_i              (ras_spec_op_i),
        .spec_return_addr_i     (ras_spec_return_addr_i),
        .ckpt_alloc_i           (ras_ckpt_alloc_i),
        .ckpt_id_o              (ras_ckpt_id_o),
        .restore_i              (ras_restore_i),
        .restore_id_i           (ras_restore_id_i),
        .flush_i                (clear_i)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || clear_i) begin
            tag_stage_valid_q     <= 1'b0;
            tag_stage_hit_q       <= 1'b0;
            tag_stage_pc_q        <= '0;
            tag_stage_branch_pc_q <= '0;
            tag_stage_target_q    <= '0;
            tag_stage_br_type_q   <= BTB_NONE;
            ras_stage_valid_q     <= 1'b0;
            ras_stage_target_q    <= '0;
        end else begin
            tag_stage_valid_q     <= tag_resp_valid;
            tag_stage_hit_q       <= tag_resp_hit;
            tag_stage_pc_q        <= tag_resp_pc;
            tag_stage_branch_pc_q <= tag_resp_branch_pc;
            tag_stage_target_q    <= tag_resp_target;
            tag_stage_br_type_q   <= tag_resp_br_type;
            ras_stage_valid_q     <= ras_pred_valid;
            ras_stage_target_q    <= ras_pred_target;
        end
    end

    always_comb begin
        resp_valid_o       = bim_resp_valid && tag_stage_valid_q;
        resp_hit_o         = resp_valid_o && tag_stage_hit_q;
        resp_pc_o          = tag_stage_pc_q;
        resp_branch_pc_o   = tag_stage_branch_pc_q;
        resp_target_o      = tag_stage_target_q;
        resp_taken_o       = 1'b0;
        resp_br_type_o     = tag_stage_br_type_q;
        resp_bim_counter_o = bim_resp_counter;
        resp_ras_used_o    = 1'b0;

        if (resp_hit_o) begin
            unique case (tag_stage_br_type_q)
                BTB_COND:
                    resp_taken_o = bim_resp_taken;

                BTB_RET: begin
                    resp_taken_o = 1'b1;
                    if (ras_stage_valid_q) begin
                        resp_target_o   = ras_stage_target_q;
                        resp_ras_used_o = 1'b1;
                    end
                end

                BTB_JUMP,
                BTB_CALL,
                BTB_IND,
                BTB_ICALL:
                    resp_taken_o = 1'b1;

                default:
                    resp_taken_o = 1'b0;
            endcase
        end
    end

    // synthesis translate_off
    always_ff @(posedge clk) begin
        if (rst_n && resp_valid_o) begin
            assert (bim_resp_pc == tag_stage_branch_pc_q ||
                    !tag_stage_hit_q)
                else $error("BTB: BIM response is not aligned with BTBTAG");
        end
    end
    // synthesis translate_on

endmodule
