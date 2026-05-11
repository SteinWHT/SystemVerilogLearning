// INT QUEUE DATA STRUCTURE:
//  robtag      rs      rsrdy       rt      rtrdy       op      rd      valid       rw      IMM     Branch      BrPred
//  5b          6b      1b          6b      1b          3/b     6b      1b          1b      16b     1b          1b   
//  jr          jr31    jal         BrPC    BrAddr
//  1b          1b      1b          3b      32b

module INTQ #(
    parameter int unsigned INT_QUEUE_DEPTH = 8,
    parameter int unsigned INSTR_WIDTH = 32,
    parameter int unsigned ROB_INDEX_WIDTH = 5,
    parameter int unsigned ARCH_REG_WIDTH = 5,
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned DMEM_WIDTH = 32,
    parameter int unsigned BPB_PC_BITS = 3
) (
    input logic clk,
    input logic rst_n,

    // CDB interface
    input logic cdb_flush,
    input logic [ROB_INDEX_WIDTH-1:0] rob_top_ptr,
    input logic [ROB_INDEX_WIDTH-1:0] cdb_rob_depth,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] cdb_rd_phy_addr,
    input logic cdb_phy_reg_write,

    // forwarding logic interface
    // MULT interface
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] mul_rd_phy_addr,
    input logic mul_exe_ready,
    // DIV interface
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] div_rd_phy_addr,
    input logic div_exe_ready,
    // LD/ST interface
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] ls_buf_rd_phy_addr,
    input logic ls_buf_buf_rd_write,

    // ALU interface
    output logic [ROB_INDEX_WIDTH-1:0] iss_rob_tag_alu,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rs_phy_addr_alu,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rt_phy_addr_alu,
    output logic [2:0] iss_opcode_alu,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rd_phy_addr_alu,
    output logic iss_rw_alu,
    output logic [15:0] iss_imm16_alu,
    output logic iss_branch_prediction_alu,
    output logic iss_branch_alu,
    output logic iss_jr_inst_alu,
    output logic iss_jr31_inst_alu,
    output logic iss_jal_inst_alu,
    output logic [BPB_PC_BITS-1:0] iss_branch_pc_bits_alu,
    output logic [DMEM_WIDTH-1:0] iss_branch_other_addr_alu,
    
    // ISSUEUNIT interface
    input logic issue_int_en,
    output logic issue_int_rdy,
    output logic issue_int,

    // Dispatch interface
    input logic                               dis_int_en,
    input logic                               dis_reg_write,
    input logic                               dis_rs_data_ready,
    input logic                               dis_rt_data_ready,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rs_phy_addr,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rt_phy_addr,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_new_rd_phy_addr,
    input logic [ROB_INDEX_WIDTH-1:0]         dis_rob_tag,
    input logic [2:0]                         dis_opcode,
    input logic [15:0]                        dis_imm16,
    input logic [DMEM_WIDTH-1:0]              dis_branch_other_addr,
    input logic                               dis_branch_prediction,
    input logic                               dis_branch,
    input logic [BPB_PC_BITS-1:0]             dis_branch_pc_bits,
    input logic                               dis_jr_inst,
    input logic                               dis_jal_inst,
    input logic                               dis_jr31_inst,
    
    // ISSUEQ interface
    output logic iss_intq_full,
    output logic iss_intq_two_or_more_vacant
);

    localparam int unsigned IDX_WIDTH = $clog2(INT_QUEUE_DEPTH);

    // Entry Struct — groups all payload fields of one queue slot
    // valid is kept separate for easy vectorized operations
    typedef struct packed {
        logic [ROB_INDEX_WIDTH-1:0]         rob_tag;
        logic [PHY_REGISTER_FILE_WIDTH-1:0] rs;
        logic                               rs_rdy;
        logic [PHY_REGISTER_FILE_WIDTH-1:0] rt;
        logic                               rt_rdy;
        logic [2:0]                         op;
        logic [PHY_REGISTER_FILE_WIDTH-1:0] rd;
        logic                               rw;
        logic [15:0]                        imm;
        logic                               branch;
        logic                               br_pred;
        logic                               jr;
        logic                               jr31;
        logic                               jal;
        logic [BPB_PC_BITS-1:0]             br_pc;
        logic [DMEM_WIDTH-1:0]              br_addr;
    } intq_entry_t;

    // Queue
    intq_entry_t                        q       [INT_QUEUE_DEPTH];
    logic        [INT_QUEUE_DEPTH-1:0]  q_valid;

    // Wakeup Logic — snoop CDB, MUL, DIV, LD/ST forwarding buses
    logic wk_rs_rdy [INT_QUEUE_DEPTH];
    logic wk_rt_rdy [INT_QUEUE_DEPTH];

    always_comb begin
        for (int i = 0; i < INT_QUEUE_DEPTH; i++) begin
            wk_rs_rdy[i] = q[i].rs_rdy;
            wk_rt_rdy[i] = q[i].rt_rdy;

            if (q_valid[i]) begin
                if (!q[i].rs_rdy) begin
                    if (cdb_phy_reg_write   && (q[i].rs == cdb_rd_phy_addr))     wk_rs_rdy[i] = 1'b1;
                    if (mul_exe_ready        && (q[i].rs == mul_rd_phy_addr))     wk_rs_rdy[i] = 1'b1;
                    if (div_exe_ready        && (q[i].rs == div_rd_phy_addr))     wk_rs_rdy[i] = 1'b1;
                    if (ls_buf_buf_rd_write  && (q[i].rs == ls_buf_rd_phy_addr))  wk_rs_rdy[i] = 1'b1;
                end
                if (!q[i].rt_rdy) begin
                    if (cdb_phy_reg_write   && (q[i].rt == cdb_rd_phy_addr))     wk_rt_rdy[i] = 1'b1;
                    if (mul_exe_ready        && (q[i].rt == mul_rd_phy_addr))     wk_rt_rdy[i] = 1'b1;
                    if (div_exe_ready        && (q[i].rt == div_rd_phy_addr))     wk_rt_rdy[i] = 1'b1;
                    if (ls_buf_buf_rd_write  && (q[i].rt == ls_buf_rd_phy_addr))  wk_rt_rdy[i] = 1'b1;
                end
            end
        end
    end

    // Dispatch-Time Wakeup — catch same-cycle forwarding for new entry
    logic dis_rs_rdy_eff, dis_rt_rdy_eff;

    always_comb begin
        dis_rs_rdy_eff = dis_rs_data_ready;
        dis_rt_rdy_eff = dis_rt_data_ready;

        if (!dis_rs_data_ready) begin
            if (cdb_phy_reg_write   && (dis_rs_phy_addr == cdb_rd_phy_addr))     dis_rs_rdy_eff = 1'b1;
            if (mul_exe_ready        && (dis_rs_phy_addr == mul_rd_phy_addr))     dis_rs_rdy_eff = 1'b1;
            if (div_exe_ready        && (dis_rs_phy_addr == div_rd_phy_addr))     dis_rs_rdy_eff = 1'b1;
            if (ls_buf_buf_rd_write  && (dis_rs_phy_addr == ls_buf_rd_phy_addr))  dis_rs_rdy_eff = 1'b1;
        end
        if (!dis_rt_data_ready) begin
            if (cdb_phy_reg_write   && (dis_rt_phy_addr == cdb_rd_phy_addr))     dis_rt_rdy_eff = 1'b1;
            if (mul_exe_ready        && (dis_rt_phy_addr == mul_rd_phy_addr))     dis_rt_rdy_eff = 1'b1;
            if (div_exe_ready        && (dis_rt_phy_addr == div_rd_phy_addr))     dis_rt_rdy_eff = 1'b1;
            if (ls_buf_buf_rd_write  && (dis_rt_phy_addr == ls_buf_rd_phy_addr))  dis_rt_rdy_eff = 1'b1;
        end
    end

    // Ready Detection & Oldest-First Selection
    // depth = rob_tag - rob_top_ptr (unsigned mod 2^N, smaller = older)
    logic [INT_QUEUE_DEPTH-1:0] q_ready;
    logic [ROB_INDEX_WIDTH-1:0] entry_depth [INT_QUEUE_DEPTH];
    logic [IDX_WIDTH-1:0]       sel_idx;
    logic                       sel_valid;

    always_comb begin
        for (int i = 0; i < INT_QUEUE_DEPTH; i++) begin
            q_ready[i]     = q_valid[i] & wk_rs_rdy[i] & wk_rt_rdy[i];
            entry_depth[i] = q[i].rob_tag[ROB_INDEX_WIDTH-1:0] - rob_top_ptr;
        end

        sel_valid = 1'b0;
        sel_idx   = '0;

        for (int i = 0; i < INT_QUEUE_DEPTH; i++) begin
            if (q_ready[i]) begin
                sel_idx   = i[IDX_WIDTH-1:0];
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
    logic [IDX_WIDTH-1:0]                 free_idx;
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
                    free_idx = i[IDX_WIDTH-1:0];
                    has_free = 1'b1;
                end
            end
        end
    end

    assign iss_intq_full               = &q_valid;
    assign iss_intq_two_or_more_vacant = (vacant_count >= 2);

    assign issue_int_rdy = sel_valid & ~cdb_flush;
    assign issue_int     = sel_valid & issue_int_en & ~cdb_flush;

    // Issue Outputs — drive selected entry or zero
    always_comb begin
        if (issue_int) begin
            iss_rw_alu                = q[sel_idx].rw;
            iss_rd_phy_addr_alu       = q[sel_idx].rd;
            iss_rob_tag_alu           = q[sel_idx].rob_tag;
            iss_opcode_alu            = q[sel_idx].op;
            iss_imm16_alu             = q[sel_idx].imm;
            iss_branch_other_addr_alu = q[sel_idx].br_addr;
            iss_branch_prediction_alu = q[sel_idx].br_pred;
            iss_branch_alu            = q[sel_idx].branch;
            iss_branch_pc_bits_alu    = q[sel_idx].br_pc;
            iss_jr_inst_alu           = q[sel_idx].jr;
            iss_jal_inst_alu          = q[sel_idx].jal;
            iss_jr31_inst_alu         = q[sel_idx].jr31;
            iss_rs_phy_addr_alu       = q[sel_idx].rs;
            iss_rt_phy_addr_alu       = q[sel_idx].rt;
        end else begin
            iss_rw_alu                = 1'b0;
            iss_rd_phy_addr_alu       = '0;
            iss_rob_tag_alu           = '0;
            iss_opcode_alu            = '0;
            iss_imm16_alu             = '0;
            iss_branch_other_addr_alu = '0;
            iss_branch_prediction_alu = 1'b0;
            iss_branch_alu            = 1'b0;
            iss_branch_pc_bits_alu    = '0;
            iss_jr_inst_alu           = 1'b0;
            iss_jal_inst_alu          = 1'b0;
            iss_jr31_inst_alu         = 1'b0;
            iss_rs_phy_addr_alu       = '0;
            iss_rt_phy_addr_alu       = '0;
        end
    end

    // State Update
    // Last-write-wins ordering: wakeup -> flush -> issue -> dispatch
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < INT_QUEUE_DEPTH; i++) begin
                q[i]       <= '0;
                q_valid[i] <= 1'b0;
            end
        end else begin
            // Wakeup: latch updated ready bits
            for (int i = 0; i < INT_QUEUE_DEPTH; i++) begin
                q[i].rs_rdy <= wk_rs_rdy[i];
                q[i].rt_rdy <= wk_rt_rdy[i];
            end

            // Flush: invalidate entries younger than the branch
            for (int i = 0; i < INT_QUEUE_DEPTH; i++) begin
                if (flush_mask[i])
                    q_valid[i] <= 1'b0;
            end

            // Issue: dequeue the selected entry
            if (issue_int)
                q_valid[sel_idx] <= 1'b0;

            // Dispatch: enqueue new entry (suppressed during flush)
            if (dis_int_en && has_free && !cdb_flush) begin
                q_valid[free_idx] <= 1'b1;
                q[free_idx]       <= '{
                    rob_tag : dis_rob_tag,
                    rs      : dis_rs_phy_addr,
                    rs_rdy  : dis_rs_rdy_eff,
                    rt      : dis_rt_phy_addr,
                    rt_rdy  : dis_rt_rdy_eff,
                    op      : dis_opcode,
                    rd      : dis_new_rd_phy_addr,
                    rw      : dis_reg_write,
                    imm     : dis_imm16,
                    branch  : dis_branch,
                    br_pred : dis_branch_prediction,
                    jr      : dis_jr_inst,
                    jr31    : dis_jr31_inst,
                    jal     : dis_jal_inst,
                    br_pc   : dis_branch_pc_bits,
                    br_addr : dis_branch_other_addr
                };
            end
        end
    end

endmodule
