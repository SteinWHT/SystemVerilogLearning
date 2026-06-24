// INT QUEUE DATA STRUCTURE:
//  robtag      rs1      rsrdy       rs2      rtrdy       op      rd      valid       rw      IMM     Branch      BrPred
//  5b          6b      1b          6b      1b          6b      6b      1b          1b      64b     1b          1b
//  jr          jr31    jal         BrPC    BrAddr
//  1b          1b      1b          3b      32b

module INTQ
import riscv_types_pkg::*;
#(
    parameter int unsigned XLEN = 64,
    parameter int unsigned INT_QUEUE_DEPTH = 8,
    parameter int unsigned ROB_INDEX_WIDTH = 5,
    parameter int unsigned PHY_REG_IDX_WIDTH = 7,
    parameter int unsigned PC_WIDTH = 64,
    parameter int unsigned BPB_PC_BITS = 3,
    parameter int unsigned OPCODE_WIDTH = 7
) (
    input logic clk,
    input logic rst_n,

    // CDB interface
    input logic                                 cdb_valid,
    input logic                                 cdb_flush,
    input logic [ROB_INDEX_WIDTH-1:0]           rob_top_ptr,
    input logic [ROB_INDEX_WIDTH-1:0]           cdb_rob_depth,
    input logic [PHY_REG_IDX_WIDTH-1:0]         cdb_rd_phy_addr,
    input logic                                 cdb_phy_reg_write,

    // forwarding logic interface
    // MULT interface
    input logic [PHY_REG_IDX_WIDTH-1:0]         mul_rd_phy_addr,
    input logic                                 mul_exe_ready,
    // DIV interface
    input logic [PHY_REG_IDX_WIDTH-1:0]         div_rd_phy_addr,
    input logic                                 div_exe_ready,
    // LD/ST interface
    input logic [PHY_REG_IDX_WIDTH-1:0]         lsb_wake_phy_addr,
    input logic                                 lsb_wake_valid,

    // ALU interface
    output logic [ROB_INDEX_WIDTH-1:0]          iss_rob_tag_alu,
    output logic [PHY_REG_IDX_WIDTH-1:0]        iss_rs1_phy_addr_alu,
    output logic [PHY_REG_IDX_WIDTH-1:0]        iss_rs2_phy_addr_alu,
    output logic [OPCODE_WIDTH-1:0]             iss_opcode_alu,
    output logic [PHY_REG_IDX_WIDTH-1:0]        iss_rd_phy_addr_alu,
    output logic                                iss_rw_alu,
    output logic [XLEN-1:0]                     iss_imm_alu,
    output logic                                iss_branch_prediction_alu,
    output logic                                iss_branch_alu,
    output logic                                iss_jr_inst_alu,
    output logic                                iss_jr31_inst_alu,
    output logic                                iss_jal_inst_alu,
    output logic [BPB_PC_BITS-1:0]              iss_branch_pc_bits_alu,
    output logic [PC_WIDTH-1:0]                 iss_branch_other_addr_alu,
    output logic [PC_WIDTH-1:0]                 iss_pc,
    output logic                                exe_int_grant,

    // ISSUEUNIT interface
    input logic                                 issue_int_en,

    output logic                                issue_int_rdy,

    // Dispatch interface
    input logic                                 dis_int_en,
    input logic                                 dis_reg_write,
    input logic                                 dis_rs1_data_ready,
    input logic                                 dis_rs2_data_ready,
    input logic [PHY_REG_IDX_WIDTH-1:0]         dis_rs1_phy_addr,
    input logic [PHY_REG_IDX_WIDTH-1:0]         dis_rs2_phy_addr,
    input logic [PHY_REG_IDX_WIDTH-1:0]         dis_new_rd_phy_addr,
    input logic [ROB_INDEX_WIDTH-1:0]           dis_rob_tag,
    input logic [OPCODE_WIDTH-1:0]              dis_opcode,
    input logic [XLEN-1:0]                      dis_imm,
    input logic [PC_WIDTH-1:0]                  dis_branch_other_addr,
    input logic                                 dis_branch_prediction,
    input logic                                 dis_branch,
    input logic [BPB_PC_BITS-1:0]               dis_branch_pc_bits,
    input logic                                 dis_jr_inst,
    input logic                                 dis_jal_inst,
    input logic                                 dis_jr31_inst,
    input logic [PC_WIDTH-1:0]                  dis_pc,

    // ISSUEQ interface
    output logic                                iss_intq_full,
    output logic                                iss_intq_two_or_more_vacant
);

    localparam int unsigned IdxWidth = $clog2(INT_QUEUE_DEPTH);

    // Entry Struct — groups all payload fields of one queue slot
    // valid is kept separate for easy vectorized operations
    typedef struct packed {
        logic [ROB_INDEX_WIDTH-1:0]         rob_tag;
        logic [PHY_REG_IDX_WIDTH-1:0]       rs1;
        logic                               rs1_rdy;
        logic [PHY_REG_IDX_WIDTH-1:0]       rs2;
        logic                               rs2_rdy;
        logic [OPCODE_WIDTH-1:0]            op;
        logic [PHY_REG_IDX_WIDTH-1:0]       rd;
        logic                               rw;
        logic [XLEN-1:0]                    imm;
        logic                               branch;
        logic                               br_pred;
        logic                               jr;
        logic                               jr31;
        logic                               jal;
        logic [BPB_PC_BITS-1:0]             br_pc;
        logic [PC_WIDTH-1:0]                br_addr;
        logic [PC_WIDTH-1:0]                pc;
    } intq_entry_t;

    // Queue
    intq_entry_t                        q       [INT_QUEUE_DEPTH];
    logic        [INT_QUEUE_DEPTH-1:0]  q_valid;
    logic                               issue_int;

    // Wakeup Logic — snoop CDB, MUL, DIV, LD/ST forwarding buses
    logic wk_rs1_rdy [INT_QUEUE_DEPTH];
    logic wk_rs2_rdy [INT_QUEUE_DEPTH];

    always_comb begin
        for (int i = 0; i < INT_QUEUE_DEPTH; i++) begin
            wk_rs1_rdy[i] = q[i].rs1_rdy;
            wk_rs2_rdy[i] = q[i].rs2_rdy;

            if (q_valid[i]) begin
                if (!q[i].rs1_rdy) begin
                    if (cdb_valid && cdb_phy_reg_write   && (q[i].rs1 == cdb_rd_phy_addr))     wk_rs1_rdy[i] = 1'b1;
                    if (mul_exe_ready       && (q[i].rs1 == mul_rd_phy_addr))     wk_rs1_rdy[i] = 1'b1;
                    if (div_exe_ready       && (q[i].rs1 == div_rd_phy_addr))     wk_rs1_rdy[i] = 1'b1;
                    if (lsb_wake_valid && (q[i].rs1 == lsb_wake_phy_addr))  wk_rs1_rdy[i] = 1'b1;
                end
                if (!q[i].rs2_rdy) begin
                    if (cdb_valid && cdb_phy_reg_write   && (q[i].rs2 == cdb_rd_phy_addr))     wk_rs2_rdy[i] = 1'b1;
                    if (mul_exe_ready       && (q[i].rs2 == mul_rd_phy_addr))     wk_rs2_rdy[i] = 1'b1;
                    if (div_exe_ready       && (q[i].rs2 == div_rd_phy_addr))     wk_rs2_rdy[i] = 1'b1;
                    if (lsb_wake_valid && (q[i].rs2 == lsb_wake_phy_addr))  wk_rs2_rdy[i] = 1'b1;
                end
            end
        end
    end

    // Dispatch-Time Wakeup — catch same-cycle forwarding for new entry
    logic dis_rs1_rdy_eff, dis_rs2_rdy_eff;

    always_comb begin
        dis_rs1_rdy_eff = dis_rs1_data_ready;
        dis_rs2_rdy_eff = dis_rs2_data_ready;

        if (!dis_rs1_data_ready) begin
            if (cdb_valid && cdb_phy_reg_write   && (dis_rs1_phy_addr == cdb_rd_phy_addr))     dis_rs1_rdy_eff = 1'b1;
            if (mul_exe_ready       && (dis_rs1_phy_addr == mul_rd_phy_addr))     dis_rs1_rdy_eff = 1'b1;
            if (div_exe_ready       && (dis_rs1_phy_addr == div_rd_phy_addr))     dis_rs1_rdy_eff = 1'b1;
            if (lsb_wake_valid && (dis_rs1_phy_addr == lsb_wake_phy_addr))  dis_rs1_rdy_eff = 1'b1;
        end
        if (!dis_rs2_data_ready) begin
            if (cdb_valid && cdb_phy_reg_write   && (dis_rs2_phy_addr == cdb_rd_phy_addr))     dis_rs2_rdy_eff = 1'b1;
            if (mul_exe_ready       && (dis_rs2_phy_addr == mul_rd_phy_addr))     dis_rs2_rdy_eff = 1'b1;
            if (div_exe_ready       && (dis_rs2_phy_addr == div_rd_phy_addr))     dis_rs2_rdy_eff = 1'b1;
            if (lsb_wake_valid && (dis_rs2_phy_addr == lsb_wake_phy_addr))  dis_rs2_rdy_eff = 1'b1;
        end
    end

    // Ready Detection & Oldest-First Selection
    // depth = rob_tag - rob_top_ptr (unsigned mod 2^N, smaller = older)
    logic [INT_QUEUE_DEPTH-1:0] q_ready;
    logic [ROB_INDEX_WIDTH-1:0] entry_depth [INT_QUEUE_DEPTH];
    logic [IdxWidth-1:0]        sel_idx;
    logic                       sel_valid;

    always_comb begin
        for (int i = 0; i < INT_QUEUE_DEPTH; i++) begin
            q_ready[i]     = q_valid[i] & wk_rs1_rdy[i] & wk_rs2_rdy[i];
            entry_depth[i] = q[i].rob_tag[ROB_INDEX_WIDTH-1:0] - rob_top_ptr;
        end

        sel_valid = 1'b0;
        sel_idx   = '0;

        for (int i = INT_QUEUE_DEPTH - 1; i >= 0; i--) begin
            if (q_ready[i]) begin
                sel_idx   = i[IdxWidth-1:0];
                sel_valid = 1'b1;
            end
        end
    end

    // Flush Detection — entries younger than the mispredicting branch
    logic [INT_QUEUE_DEPTH-1:0] flush_mask;

    always_comb begin
        for (int i = 0; i < INT_QUEUE_DEPTH; i++) begin
            flush_mask[i] = cdb_flush & q_valid[i] & (entry_depth[i] > cdb_rob_depth);
        end
    end

    // Free Slot Allocation & Vacancy Count
    logic [IdxWidth-1:0]                  free_idx;
    logic                                 has_free;
    logic [$clog2(INT_QUEUE_DEPTH+1)-1:0] vacant_count;

    always_comb begin
        has_free     = 1'b0;
        free_idx     = '0;
        vacant_count = '0;
        for (int i = 0; i < INT_QUEUE_DEPTH; i++) begin
            if (!q_valid[i]) begin
                vacant_count += {{($clog2(INT_QUEUE_DEPTH+1)-1){1'b0}}, 1'b1};
                if (!has_free) begin
                    free_idx = i[IdxWidth-1:0];
                    has_free = 1'b1;
                end
            end
        end
    end

    assign iss_intq_full               = &q_valid;
    assign iss_intq_two_or_more_vacant = (vacant_count >= 2);

    assign issue_int_rdy = sel_valid & ~cdb_flush;
    assign issue_int     = sel_valid & issue_int_en & ~cdb_flush;

    // State Update
    // Last-write-wins ordering: wakeup -> flush -> issue -> dispatch
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < INT_QUEUE_DEPTH; i++) begin
                q[i]       <= '{
                    rob_tag : '0,
                    rs1     : '0,
                    rs1_rdy : 1'b0,
                    rs2     : '0,
                    rs2_rdy : 1'b0,
                    op      : INSTR_NONE,
                    rd      : '0,
                    rw      : 1'b0,
                    imm     : '0,
                    branch  : 1'b0,
                    br_pred : 1'b0,
                    jr      : 1'b0,
                    jr31    : 1'b0,
                    jal     : 1'b0,
                    br_pc   : '0,
                    br_addr : '0,
                    pc      : '0
                };
                q_valid[i] <= 1'b0;
            end
        end else begin
            // Wakeup: latch updated ready bits
            for (int i = 0; i < INT_QUEUE_DEPTH; i++) begin
                q[i].rs1_rdy <= wk_rs1_rdy[i];
                q[i].rs2_rdy <= wk_rs2_rdy[i];
            end

            // Flush: invalidate entries younger than the branch
            for (int i = 0; i < INT_QUEUE_DEPTH; i++) begin
                if (flush_mask[i])
                    q_valid[i] <= 1'b0;
            end

            // Issue: dequeue the selected entry
            if (issue_int) begin
                q_valid[sel_idx]            <= 1'b0;
                exe_int_grant               <= 1'b1;
                iss_rw_alu                  <= q[sel_idx].rw;
                iss_rd_phy_addr_alu         <= q[sel_idx].rd;
                iss_rob_tag_alu             <= q[sel_idx].rob_tag;
                iss_opcode_alu              <= q[sel_idx].op;
                iss_imm_alu                 <= q[sel_idx].imm;
                iss_branch_other_addr_alu   <= q[sel_idx].br_addr;
                iss_branch_prediction_alu   <= q[sel_idx].br_pred;
                iss_branch_alu              <= q[sel_idx].branch;
                iss_branch_pc_bits_alu      <= q[sel_idx].br_pc;
                iss_jr_inst_alu             <= q[sel_idx].jr;
                iss_jal_inst_alu            <= q[sel_idx].jal;
                iss_jr31_inst_alu           <= q[sel_idx].jr31;
                iss_pc                      <= q[sel_idx].pc;
                iss_rs1_phy_addr_alu        <= q[sel_idx].rs1;
                iss_rs2_phy_addr_alu        <= q[sel_idx].rs2;
            end else begin
                exe_int_grant               <= '0;
                iss_rw_alu                  <= '0;
                iss_rd_phy_addr_alu         <= '0;
                iss_rob_tag_alu             <= '0;
                iss_opcode_alu              <= INSTR_NONE;
                iss_imm_alu                 <= '0;
                iss_branch_other_addr_alu   <= '0;
                iss_branch_prediction_alu   <= '0;
                iss_branch_alu              <= '0;
                iss_branch_pc_bits_alu      <= '0;
                iss_jr_inst_alu             <= '0;
                iss_jal_inst_alu            <= '0;
                iss_jr31_inst_alu           <= '0;
                iss_pc                      <= '0;
                iss_rs1_phy_addr_alu        <= '0;
                iss_rs2_phy_addr_alu        <= '0;
            end
            // Dispatch: enqueue new entry (suppressed during flush)
            if (dis_int_en && has_free && !cdb_flush) begin
                q_valid[free_idx] <= 1'b1;
                q[free_idx]       <= '{
                    rob_tag : dis_rob_tag,
                    rs1     : dis_rs1_phy_addr,
                    rs1_rdy : dis_rs1_rdy_eff,
                    rs2     : dis_rs2_phy_addr,
                    rs2_rdy : dis_rs2_rdy_eff,
                    op      : dis_opcode,
                    rd      : dis_new_rd_phy_addr,
                    rw      : dis_reg_write,
                    imm     : dis_imm,
                    branch  : dis_branch,
                    br_pred : dis_branch_prediction,
                    jr      : dis_jr_inst,
                    jr31    : dis_jr31_inst,
                    jal     : dis_jal_inst,
                    br_pc   : dis_branch_pc_bits,
                    br_addr : dis_branch_other_addr,
                    pc      : dis_pc
                };
            end
        end
    end

endmodule
