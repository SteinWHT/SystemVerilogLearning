// Refer to Tomasulo3CPU/image/if_bp.png.
`timescale 1ns/1ps

module IF_BP
    import riscv_btb_pkg::*;
#(
    parameter int unsigned INSTR_WIDTH      = 32,
    parameter int unsigned PC_WIDTH       = 32,
    parameter int unsigned IMEM_WIDTH       = 32,
    parameter int unsigned PC_WORD_WIDTH  = PC_WIDTH - 1,

    parameter int unsigned BTB_NUM_SETS     = 128,
    parameter int unsigned BTB_NUM_WAYS     = 4,
    parameter int unsigned BIM_ENTRIES      = 1024,
    parameter int unsigned RAS_DEPTH        = 16,
    parameter int unsigned RAS_CKPT_NUM     = 8,
    parameter int unsigned F2_QUEUE_DEPTH   = 2,
    parameter int unsigned FETCH_BUF_DEPTH  = 2,
    parameter int unsigned TARGET_BUF_DEPTH = 2,

    localparam int unsigned RAS_CKPT_BITS =
        (RAS_CKPT_NUM > 1) ? $clog2(RAS_CKPT_NUM) : 1
)(
    input  logic                            clk,
    input  logic                            rst_n,

    output logic [PC_WIDTH-1:0]           imem_addr,
    output logic                            imem_req_valid,
    input  logic                            imem_req_ready,
    input  logic [IMEM_WIDTH-1:0]           imem_resp_data,
    input  logic                            imem_resp_valid,
    output logic                            imem_resp_ready,

    input  logic                            dis_ren,
    input  logic                            dis_jmpbr,
    input  logic [PC_WORD_WIDTH-1:0]      dis_jmpbr_addr,
    input  logic                            dis_jmpbr_addr_valid,

    output logic [INSTR_WIDTH-1:0]          ifq_instr_out,
    output logic [PC_WIDTH-1:0]           ifq_pc,
    output logic [PC_WIDTH-1:0]           ifq_pc_plus4,
    output logic                            ifq_empty,
    output logic                            ifq_pred_valid,
    output logic                            ifq_pred_taken,
    output logic [PC_WIDTH-1:0]           ifq_pred_target,
    output btb_br_type_e                    ifq_pred_br_type,

    input  logic                            btb_update_valid_i,
    input  logic [PC_WIDTH-1:0]           btb_update_pc_i,
    input  logic [PC_WIDTH-1:0]           btb_update_target_i,
    input  btb_br_type_e                    btb_update_br_type_i,
    input  logic                            btb_update_taken_i,
    input  logic                            btb_update_allocate_i,

    input  logic                            ras_spec_valid_i,
    input  ras_op_e                         ras_spec_op_i,
    input  logic [PC_WIDTH-1:0]           ras_spec_return_addr_i,
    input  logic                            ras_ckpt_alloc_i,
    output logic [RAS_CKPT_BITS-1:0]        ras_ckpt_id_o,
    input  logic                            ras_restore_i,
    input  logic [RAS_CKPT_BITS-1:0]        ras_restore_id_i,

    input  logic                            predictor_clear_i
);

    localparam int unsigned INSTR_BYTES       = INSTR_WIDTH / 8;
    localparam int unsigned INSTR_OFFSET_BITS = $clog2(INSTR_BYTES);
    localparam int unsigned FETCH_BYTES       = IMEM_WIDTH / 8;
    localparam int unsigned FETCH_INSTRS      = IMEM_WIDTH / INSTR_WIDTH;
    localparam int unsigned FETCH_OFFSET_BITS = $clog2(FETCH_BYTES);
    localparam int unsigned FETCH_INDEX_BITS  =
        (FETCH_INSTRS > 1) ? $clog2(FETCH_INSTRS) : 1;

    // F0/F1 request state
    logic [PC_WIDTH-1:0] fetch_pc_q;
    logic [PC_WIDTH-1:0] request_start_pc_q;
    logic [PC_WIDTH-1:0] request_block_pc_q;
    logic [FETCH_INDEX_BITS-1:0] request_start_index_q;
    logic                  imem_inflight_q;
    logic                  btb_waiting_q;
    logic                  discard_imem_q;
    logic                  drop_btb_q;

    // BTB response
    logic                  btb_lookup_valid;
    logic                  btb_resp_valid;
    logic                  btb_resp_hit;
    logic [PC_WIDTH-1:0] btb_resp_pc;
    logic [PC_WIDTH-1:0] btb_resp_branch_pc;
    logic [PC_WIDTH-1:0] btb_resp_target;
    logic                  btb_resp_taken;
    btb_br_type_e          btb_resp_br_type;

    // F2 response queues
    logic                  f2_clear;
    logic                  f2_imem_push;
    logic                  f2_imem_full;
    logic                  f2_imem_empty;
    logic                  f2_btb_push;
    logic                  f2_btb_full;
    logic                  f2_btb_empty;
    logic                  f2_pair_valid;
    logic                  f2_pair_ready;
    logic [IMEM_WIDTH-1:0] f2_pair_imem_data;
    logic [PC_WIDTH-1:0] f2_pair_block_pc;
    logic [FETCH_INDEX_BITS-1:0] f2_pair_start_index;
    logic [PC_WIDTH-1:0] f2_pair_btb_branch_pc;
    logic [PC_WIDTH-1:0] f2_pair_btb_target;
    logic                  f2_pair_btb_hit;
    logic                  f2_pair_btb_taken;
    btb_br_type_e          f2_pair_btb_br_type;

    // F3 branch decode
    logic                  br_decode_valid;
    logic                  decoded_branch_valid;
    logic [PC_WIDTH-1:0] decoded_branch_pc;
    logic [PC_WIDTH-1:0] decoded_direct_target;
    logic                  decoded_direct_target_valid;
    btb_br_type_e          decoded_branch_type;

    // Backing predictor
    logic                  backing_lookup_valid;
    logic                  backing_base_taken;
    logic                  backing_resp_valid;
    logic                  backing_resp_taken;

    // F3 branch checker
    logic                  checker_result_valid;
    logic                  checker_prediction_valid;
    logic [PC_WIDTH-1:0] checker_branch_pc;
    logic [PC_WIDTH-1:0] checker_target;
    logic                  checker_taken;
    btb_br_type_e          checker_branch_type;
    logic [PC_WIDTH-1:0] checker_next_pc;
    logic                  checker_repair_valid;
    logic [PC_WIDTH-1:0] checker_repair_pc;
    logic [PC_WIDTH-1:0] checker_repair_target;
    btb_br_type_e          checker_repair_type;
    logic                  checker_fire;

    // Fetch and target buffers
    logic                  fetch_buffer_push_ready;
    logic                  fetch_target_push_ready;
    logic                  fetch_target_valid;
    logic                  fetch_target_ready;
    logic                  fetch_target_fire;
    logic [PC_WIDTH-1:0] fetch_target;
    logic                  fetch_target_empty;

    // BTB update arbitration
    logic                  selected_btb_update_valid;
    logic [PC_WIDTH-1:0] selected_btb_update_pc;
    logic [PC_WIDTH-1:0] selected_btb_update_target;
    btb_br_type_e          selected_btb_update_type;
    logic                  selected_btb_update_taken;
    logic                  selected_btb_update_allocate;

    // RAS arbitration
    logic                  auto_ras_valid;
    ras_op_e               auto_ras_op;
    logic [PC_WIDTH-1:0] auto_ras_return_addr;
    logic                  ras_spec_valid;
    ras_op_e               ras_spec_op;
    logic [PC_WIDTH-1:0] ras_spec_return_addr;

    // Pipeline control
    logic                  redirect;
    logic [PC_WIDTH-1:0] redirect_target;
    logic                  can_issue_request;
    logic                  request_fire;
    logic                  imem_response_fire;
    logic                  btb_response_accepted;
    logic [PC_WIDTH-1:0] f2_imem_start_pc;
    logic [PC_WIDTH-1:0] f2_imem_block_pc;
    logic [FETCH_INDEX_BITS-1:0] f2_imem_start_index;

    function automatic logic [PC_WIDTH-1:0] align_fetch_address(
        input logic [PC_WIDTH-1:0] address
    );
        align_fetch_address =
            (address >> FETCH_OFFSET_BITS) << FETCH_OFFSET_BITS;
    endfunction

    // ---------------------------------------------------------------------
    // F0: redirect and next request address
    // ---------------------------------------------------------------------
    always_comb begin
        redirect        = dis_jmpbr && dis_jmpbr_addr_valid;
        redirect_target = {dis_jmpbr_addr, 1'b0};
        imem_addr       = align_fetch_address(fetch_pc_q);
    end

    // ---------------------------------------------------------------------
    // F1: issue a paired I-cache/BTB request
    // ---------------------------------------------------------------------
    always_comb begin
        can_issue_request =
            !redirect &&
            !predictor_clear_i &&
            ifq_empty &&
            !imem_inflight_q &&
            !btb_waiting_q &&
            !discard_imem_q &&
            f2_imem_empty &&
            f2_btb_empty &&
            fetch_target_empty &&
            !f2_imem_full &&
            !f2_btb_full;

        imem_req_valid   = can_issue_request;
        request_fire     = imem_req_valid && imem_req_ready;
        btb_lookup_valid = request_fire;
    end

    // ---------------------------------------------------------------------
    // F2: enqueue independent cache and BTB responses
    // ---------------------------------------------------------------------
    always_comb begin
        f2_clear = redirect || predictor_clear_i;

        imem_resp_ready =
            discard_imem_q ||
            redirect ||
            predictor_clear_i ||
            ((imem_inflight_q || request_fire) && !f2_imem_full);
        imem_response_fire = imem_resp_valid && imem_resp_ready;
        f2_imem_push =
            imem_response_fire &&
            !discard_imem_q &&
            !redirect &&
            !predictor_clear_i;

        f2_imem_start_pc    = request_start_pc_q;
        f2_imem_block_pc    = request_block_pc_q;
        f2_imem_start_index = request_start_index_q;

        if (request_fire) begin
            f2_imem_start_pc = fetch_pc_q;
            f2_imem_block_pc = imem_addr;
            if (FETCH_INSTRS == 1)
                f2_imem_start_index = '0;
            else
                f2_imem_start_index =
                    fetch_pc_q[INSTR_OFFSET_BITS +: FETCH_INDEX_BITS];
        end

        btb_response_accepted =
            btb_resp_valid &&
            !drop_btb_q &&
            !redirect &&
            !predictor_clear_i;
        f2_btb_push = btb_response_accepted;
    end

    // ---------------------------------------------------------------------
    // F3: checker handshake, buffers, RAS action, and BTB repair
    // ---------------------------------------------------------------------
    always_comb begin
        backing_lookup_valid =
            f2_pair_valid &&
            decoded_branch_valid &&
            (decoded_branch_type == BTB_COND);
        backing_base_taken =
            f2_pair_btb_hit &&
            (f2_pair_btb_branch_pc == decoded_branch_pc) &&
            (f2_pair_btb_br_type == decoded_branch_type) &&
            f2_pair_btb_taken;

        checker_fire =
            checker_result_valid &&
            fetch_buffer_push_ready &&
            fetch_target_push_ready;
        f2_pair_ready = checker_fire;

        auto_ras_valid       = 1'b0;
        auto_ras_op          = RAS_OP_NONE;
        auto_ras_return_addr =
            checker_branch_pc + PC_WIDTH'(INSTR_BYTES);

        if (checker_fire &&
            checker_prediction_valid &&
            checker_taken) begin
            unique case (checker_branch_type)
                BTB_CALL,
                BTB_ICALL: begin
                    auto_ras_valid = 1'b1;
                    auto_ras_op    = RAS_OP_PUSH;
                end

                BTB_RET: begin
                    auto_ras_valid = 1'b1;
                    auto_ras_op    = RAS_OP_POP;
                end

                default: begin
                    auto_ras_valid = 1'b0;
                    auto_ras_op    = RAS_OP_NONE;
                end
            endcase
        end

        ras_spec_valid       = auto_ras_valid;
        ras_spec_op          = auto_ras_op;
        ras_spec_return_addr = auto_ras_return_addr;

        if (ras_spec_valid_i) begin
            ras_spec_valid       = 1'b1;
            ras_spec_op          = ras_spec_op_i;
            ras_spec_return_addr = ras_spec_return_addr_i;
        end

        selected_btb_update_valid    = checker_fire && checker_repair_valid;
        selected_btb_update_pc       = checker_repair_pc;
        selected_btb_update_target   = checker_repair_target;
        selected_btb_update_type     = checker_repair_type;
        selected_btb_update_taken    = 1'b1;
        selected_btb_update_allocate = 1'b1;

        if (btb_update_valid_i) begin
            selected_btb_update_valid    = 1'b1;
            selected_btb_update_pc       = btb_update_pc_i;
            selected_btb_update_target   = btb_update_target_i;
            selected_btb_update_type     = btb_update_br_type_i;
            selected_btb_update_taken    = btb_update_taken_i;
            selected_btb_update_allocate = btb_update_allocate_i;
        end
    end

    always_comb begin
        fetch_target_ready =
            !redirect && !predictor_clear_i;
        fetch_target_fire =
            fetch_target_valid && fetch_target_ready;
    end

    BTB #(
        .XLEN          (PC_WIDTH),
        .FETCH_BYTES   (FETCH_BYTES),
        .NUM_SETS      (BTB_NUM_SETS),
        .NUM_WAYS      (BTB_NUM_WAYS),
        .BIM_ENTRIES   (BIM_ENTRIES),
        .RAS_DEPTH     (RAS_DEPTH),
        .RAS_CKPT_NUM  (RAS_CKPT_NUM)
    ) btb (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .lookup_valid_i         (btb_lookup_valid),
        .lookup_pc_i            (imem_addr),
        .resp_valid_o           (btb_resp_valid),
        .resp_hit_o             (btb_resp_hit),
        .resp_pc_o              (btb_resp_pc),
        .resp_branch_pc_o       (btb_resp_branch_pc),
        .resp_target_o          (btb_resp_target),
        .resp_taken_o           (btb_resp_taken),
        .resp_br_type_o         (btb_resp_br_type),
        .resp_bim_counter_o     (),
        .resp_ras_used_o        (),
        .update_valid_i         (selected_btb_update_valid),
        .update_pc_i            (selected_btb_update_pc),
        .update_target_i        (selected_btb_update_target),
        .update_br_type_i       (selected_btb_update_type),
        .update_taken_i         (selected_btb_update_taken),
        .update_allocate_i      (selected_btb_update_allocate),
        .ras_spec_valid_i       (ras_spec_valid),
        .ras_spec_op_i          (ras_spec_op),
        .ras_spec_return_addr_i (ras_spec_return_addr),
        .ras_ckpt_alloc_i       (ras_ckpt_alloc_i),
        .ras_ckpt_id_o          (ras_ckpt_id_o),
        .ras_restore_i          (ras_restore_i),
        .ras_restore_id_i       (ras_restore_id_i),
        .clear_i                (predictor_clear_i)
    );

    RESP_QUEUES #(
        .XLEN             (PC_WIDTH),
        .IMEM_WIDTH       (IMEM_WIDTH),
        .FETCH_INDEX_BITS (FETCH_INDEX_BITS),
        .DEPTH            (F2_QUEUE_DEPTH)
    ) f2_response_queues (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .clear_i                   (f2_clear),
        .imem_push_i               (f2_imem_push),
        .imem_data_i               (imem_resp_data),
        .imem_start_pc_i           (f2_imem_start_pc),
        .imem_block_pc_i           (f2_imem_block_pc),
        .imem_start_index_i        (f2_imem_start_index),
        .imem_full_o               (f2_imem_full),
        .imem_empty_o              (f2_imem_empty),
        .btb_push_i                (f2_btb_push),
        .btb_resp_pc_i             (btb_resp_pc),
        .btb_branch_pc_i           (btb_resp_branch_pc),
        .btb_target_i              (btb_resp_target),
        .btb_hit_i                 (btb_resp_hit),
        .btb_taken_i               (btb_resp_taken),
        .btb_br_type_i             (btb_resp_br_type),
        .btb_full_o                (f2_btb_full),
        .btb_empty_o               (f2_btb_empty),
        .pair_valid_o              (f2_pair_valid),
        .pair_ready_i              (f2_pair_ready),
        .pair_imem_data_o          (f2_pair_imem_data),
        .pair_start_pc_o           (),
        .pair_block_pc_o           (f2_pair_block_pc),
        .pair_start_index_o        (f2_pair_start_index),
        .pair_btb_resp_pc_o        (),
        .pair_btb_branch_pc_o      (f2_pair_btb_branch_pc),
        .pair_btb_target_o         (f2_pair_btb_target),
        .pair_btb_hit_o            (f2_pair_btb_hit),
        .pair_btb_taken_o          (f2_pair_btb_taken),
        .pair_btb_br_type_o        (f2_pair_btb_br_type)
    );

    BR_DECODER #(
        .XLEN             (PC_WIDTH),
        .INSTR_WIDTH      (INSTR_WIDTH),
        .IMEM_WIDTH       (IMEM_WIDTH),
        .FETCH_INDEX_BITS (FETCH_INDEX_BITS)
    ) br_decode (
        .packet_valid_i        (f2_pair_valid),
        .packet_data_i         (f2_pair_imem_data),
        .packet_block_pc_i     (f2_pair_block_pc),
        .packet_start_index_i  (f2_pair_start_index),
        .decode_valid_o        (br_decode_valid),
        .branch_valid_o        (decoded_branch_valid),
        .branch_pc_o           (decoded_branch_pc),
        .direct_target_o       (decoded_direct_target),
        .direct_target_valid_o (decoded_direct_target_valid),
        .branch_type_o         (decoded_branch_type)
    );

    BACKING_PREDICTOR #(
        .XLEN (PC_WIDTH)
    ) backing_predictor (
        .lookup_valid_i (backing_lookup_valid),
        .lookup_pc_i    (decoded_branch_pc),
        .base_taken_i   (backing_base_taken),
        .resp_valid_o   (backing_resp_valid),
        .resp_taken_o   (backing_resp_taken),
        .update_valid_i (
            btb_update_valid_i &&
            (btb_update_br_type_i == BTB_COND)
        ),
        .update_pc_i    (btb_update_pc_i),
        .update_taken_i (btb_update_taken_i)
    );

    BR_CHECKER #(
        .XLEN        (PC_WIDTH),
        .IMEM_WIDTH  (IMEM_WIDTH),
        .FETCH_BYTES (FETCH_BYTES)
    ) br_checker (
        .valid_i                      (br_decode_valid),
        .block_pc_i                   (f2_pair_block_pc),
        .decode_branch_valid_i        (decoded_branch_valid),
        .decode_branch_pc_i           (decoded_branch_pc),
        .decode_direct_target_i       (decoded_direct_target),
        .decode_direct_target_valid_i (decoded_direct_target_valid),
        .decode_branch_type_i         (decoded_branch_type),
        .btb_hit_i                    (f2_pair_btb_hit),
        .btb_branch_pc_i              (f2_pair_btb_branch_pc),
        .btb_target_i                 (f2_pair_btb_target),
        .btb_taken_i                  (f2_pair_btb_taken),
        .btb_branch_type_i            (f2_pair_btb_br_type),
        .backing_valid_i              (backing_resp_valid),
        .backing_taken_i              (backing_resp_taken),
        .result_valid_o               (checker_result_valid),
        .prediction_valid_o           (checker_prediction_valid),
        .branch_pc_o                  (checker_branch_pc),
        .target_o                     (checker_target),
        .taken_o                      (checker_taken),
        .branch_type_o                (checker_branch_type),
        .next_pc_o                    (checker_next_pc),
        .btb_repair_valid_o           (checker_repair_valid),
        .btb_repair_pc_o              (checker_repair_pc),
        .btb_repair_target_o          (checker_repair_target),
        .btb_repair_type_o            (checker_repair_type)
    );

    FETCH_BUFFER #(
        .XLEN             (PC_WIDTH),
        .INSTR_WIDTH      (INSTR_WIDTH),
        .IMEM_WIDTH       (IMEM_WIDTH),
        .FETCH_INDEX_BITS (FETCH_INDEX_BITS),
        .DEPTH            (FETCH_BUF_DEPTH)
    ) fetch_buffer (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .clear_i                   (f2_clear),
        .push_valid_i              (checker_fire),
        .push_ready_o              (fetch_buffer_push_ready),
        .push_data_i               (f2_pair_imem_data),
        .push_block_pc_i           (f2_pair_block_pc),
        .push_start_index_i        (f2_pair_start_index),
        .push_prediction_valid_i   (checker_prediction_valid),
        .push_branch_pc_i          (checker_branch_pc),
        .push_target_i             (checker_target),
        .push_taken_i              (checker_taken),
        .push_branch_type_i        (checker_branch_type),
        .read_i                    (dis_ren),
        .instr_o                   (ifq_instr_out),
        .pc_o                      (ifq_pc),
        .pc_plus_o                 (ifq_pc_plus4),
        .empty_o                   (ifq_empty),
        .prediction_valid_o        (ifq_pred_valid),
        .prediction_taken_o        (ifq_pred_taken),
        .prediction_target_o       (ifq_pred_target),
        .prediction_branch_type_o  (ifq_pred_br_type)
    );

    FETCH_TARGET_BUFFER #(
        .XLEN  (PC_WIDTH),
        .DEPTH (TARGET_BUF_DEPTH)
    ) fetch_target_buffer (
        .clk            (clk),
        .rst_n          (rst_n),
        .clear_i        (f2_clear),
        .push_valid_i   (checker_fire),
        .push_ready_o   (fetch_target_push_ready),
        .push_target_i  (checker_next_pc),
        .target_valid_o (fetch_target_valid),
        .target_ready_i (fetch_target_ready),
        .target_o       (fetch_target),
        .empty_o        (fetch_target_empty),
        .full_o         ()
    );

    // F0 next-PC state
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fetch_pc_q <= '0;
        end else if (redirect) begin
            fetch_pc_q <= redirect_target;
        end else if (!predictor_clear_i && fetch_target_fire) begin
            fetch_pc_q <= fetch_target;
        end
    end

    // F1 request identity
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            request_start_pc_q    <= '0;
            request_block_pc_q    <= '0;
            request_start_index_q <= '0;
        end else if (request_fire) begin
            request_start_pc_q <= fetch_pc_q;
            request_block_pc_q <= imem_addr;
            if (FETCH_INSTRS == 1)
                request_start_index_q <= '0;
            else
                request_start_index_q <=
                    fetch_pc_q[INSTR_OFFSET_BITS +: FETCH_INDEX_BITS];
        end
    end

    // I-cache request lifetime and stale-response cancellation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            imem_inflight_q <= 1'b0;
            discard_imem_q  <= 1'b0;
        end else if (redirect || predictor_clear_i) begin
            if (imem_inflight_q && !imem_response_fire) begin
                discard_imem_q <= 1'b1;
            end else begin
                imem_inflight_q <= 1'b0;
                discard_imem_q  <= 1'b0;
            end
        end else begin
            if (request_fire)
                imem_inflight_q <= 1'b1;

            if (imem_response_fire) begin
                imem_inflight_q <= 1'b0;
                if (discard_imem_q)
                    discard_imem_q <= 1'b0;
            end
        end
    end

    // BTB request lifetime and stale-response cancellation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btb_waiting_q <= 1'b0;
            drop_btb_q    <= 1'b0;
        end else if (redirect) begin
            if (btb_waiting_q && !btb_resp_valid) begin
                drop_btb_q <= 1'b1;
            end else begin
                btb_waiting_q <= 1'b0;
                drop_btb_q    <= 1'b0;
            end
        end else if (predictor_clear_i) begin
            btb_waiting_q <= 1'b0;
            drop_btb_q    <= 1'b0;
        end else begin
            if (request_fire)
                btb_waiting_q <= 1'b1;

            if (btb_resp_valid) begin
                btb_waiting_q <= 1'b0;
                if (drop_btb_q)
                    drop_btb_q <= 1'b0;
            end
        end
    end

    // synthesis translate_off
    initial begin
        assert (INSTR_WIDTH == 32)
            else $fatal(1, "IF_BP: branch decode currently requires 32-bit instructions");
        assert (IMEM_WIDTH >= INSTR_WIDTH &&
                (IMEM_WIDTH % INSTR_WIDTH) == 0)
            else $fatal(1, "IF_BP: IMEM_WIDTH must contain whole instructions");
        assert ((FETCH_BYTES & (FETCH_BYTES - 1)) == 0)
            else $fatal(1, "IF_BP: fetch width in bytes must be a power of two");
        assert (PC_WORD_WIDTH == PC_WIDTH - 1)
            else $fatal(1, "IF_BP: redirect address must omit exactly bit zero");
    end
    // synthesis translate_on

endmodule
