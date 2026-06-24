// DIV QUEUE DATA STRUCTURE:
//  robtag      rs1      rsrdy       rs2      rtrdy       op      rd      valid       rw
//  5b          6b      1b          6b      1b          6b      6b      1b          1b

module DIVQ 
import riscv_types_pkg::*;
#(
    parameter int unsigned DIV_QUEUE_DEPTH = 8,
    parameter int unsigned ROB_INDEX_WIDTH = 5,
    parameter int unsigned PHY_REG_IDX_WIDTH = 7,
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
    // ALU interface
    input logic [PHY_REG_IDX_WIDTH-1:0]         int_rd_phy_addr,
    input logic                                 int_exe_ready,
    // MULT interface
    input logic [PHY_REG_IDX_WIDTH-1:0]         mul_rd_phy_addr,
    input logic                                 mul_exe_ready,
    // DIV interface
    input logic [PHY_REG_IDX_WIDTH-1:0]         div_rd_phy_addr,
    input logic                                 div_exe_ready,
    // LD/ST interface
    input logic [PHY_REG_IDX_WIDTH-1:0]         lsb_wake_phy_addr,
    input logic                                 lsb_wake_valid,

    // DIV interface
    output logic [ROB_INDEX_WIDTH-1:0]          iss_rob_tag_div,
    output logic [PHY_REG_IDX_WIDTH-1:0]        iss_rs1_phy_addr_div,
    output logic [PHY_REG_IDX_WIDTH-1:0]        iss_rs2_phy_addr_div,
    output logic [OPCODE_WIDTH-1:0]             iss_opcode_div,
    output logic [PHY_REG_IDX_WIDTH-1:0]        iss_rd_phy_addr_div,
    output logic                                iss_rw_div,
    output logic                                exe_div_grant,

    // ISSUEUNIT interface
    input logic                                 issue_div_en,

    output logic                                issue_div_rdy,

    // Dispatch interface
    input logic                                 dis_div_issue_en,
    input logic                                 dis_reg_write,
    input logic                                 dis_rs1_data_ready,
    input logic                                 dis_rs2_data_ready,
    input logic [PHY_REG_IDX_WIDTH-1:0]         dis_rs1_phy_addr,
    input logic [PHY_REG_IDX_WIDTH-1:0]         dis_rs2_phy_addr,
    input logic [PHY_REG_IDX_WIDTH-1:0]         dis_new_rd_phy_addr,
    input logic [ROB_INDEX_WIDTH-1:0]           dis_rob_tag,
    input logic [OPCODE_WIDTH-1:0]              dis_opcode,

    // Queue status
    output logic divq_full,
    output logic iss_divq_two_or_more_vacant
);

    localparam int unsigned IdxWidth = $clog2(DIV_QUEUE_DEPTH);

    // Entry Struct
    typedef struct packed {
        logic [ROB_INDEX_WIDTH-1:0]         rob_tag;
        logic [PHY_REG_IDX_WIDTH-1:0]       rs1;
        logic                               rs1_rdy;
        logic [PHY_REG_IDX_WIDTH-1:0]       rs2;
        logic                               rs2_rdy;
        logic [OPCODE_WIDTH-1:0]            op;
        logic [PHY_REG_IDX_WIDTH-1:0]       rd;
        logic                               rw;
    } divq_entry_t;

    // Queue Storage
    divq_entry_t                        q       [DIV_QUEUE_DEPTH];
    logic        [DIV_QUEUE_DEPTH-1:0]  q_valid;
    logic                               issue_div;

    // Wakeup Logic — snoop CDB, ALU, MUL, DIV, LD/ST forwarding buses
    logic wk_rs1_rdy [DIV_QUEUE_DEPTH];
    logic wk_rs2_rdy [DIV_QUEUE_DEPTH];

    always_comb begin
        for (int i = 0; i < DIV_QUEUE_DEPTH; i++) begin
            wk_rs1_rdy[i] = q[i].rs1_rdy;
            wk_rs2_rdy[i] = q[i].rs2_rdy;

            if (q_valid[i]) begin
                if (!q[i].rs1_rdy) begin
                    if (cdb_valid && cdb_phy_reg_write    && (q[i].rs1 == cdb_rd_phy_addr))     wk_rs1_rdy[i] = 1'b1;
                    if (int_exe_ready        && (q[i].rs1 == int_rd_phy_addr))     wk_rs1_rdy[i] = 1'b1;
                    if (mul_exe_ready        && (q[i].rs1 == mul_rd_phy_addr))     wk_rs1_rdy[i] = 1'b1;
                    if (div_exe_ready        && (q[i].rs1 == div_rd_phy_addr))     wk_rs1_rdy[i] = 1'b1;
                    if (lsb_wake_valid  && (q[i].rs1 == lsb_wake_phy_addr))  wk_rs1_rdy[i] = 1'b1;
                end
                if (!q[i].rs2_rdy) begin
                    if (cdb_valid && cdb_phy_reg_write    && (q[i].rs2 == cdb_rd_phy_addr))     wk_rs2_rdy[i] = 1'b1;
                    if (int_exe_ready        && (q[i].rs2 == int_rd_phy_addr))     wk_rs2_rdy[i] = 1'b1;
                    if (mul_exe_ready        && (q[i].rs2 == mul_rd_phy_addr))     wk_rs2_rdy[i] = 1'b1;
                    if (div_exe_ready        && (q[i].rs2 == div_rd_phy_addr))     wk_rs2_rdy[i] = 1'b1;
                    if (lsb_wake_valid  && (q[i].rs2 == lsb_wake_phy_addr))  wk_rs2_rdy[i] = 1'b1;
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
            if (cdb_valid && cdb_phy_reg_write    && (dis_rs1_phy_addr == cdb_rd_phy_addr))     dis_rs1_rdy_eff = 1'b1;
            if (int_exe_ready        && (dis_rs1_phy_addr == int_rd_phy_addr))     dis_rs1_rdy_eff = 1'b1;
            if (mul_exe_ready        && (dis_rs1_phy_addr == mul_rd_phy_addr))     dis_rs1_rdy_eff = 1'b1;
            if (div_exe_ready        && (dis_rs1_phy_addr == div_rd_phy_addr))     dis_rs1_rdy_eff = 1'b1;
            if (lsb_wake_valid  && (dis_rs1_phy_addr == lsb_wake_phy_addr))  dis_rs1_rdy_eff = 1'b1;
        end
        if (!dis_rs2_data_ready) begin
            if (cdb_valid && cdb_phy_reg_write    && (dis_rs2_phy_addr == cdb_rd_phy_addr))     dis_rs2_rdy_eff = 1'b1;
            if (int_exe_ready        && (dis_rs2_phy_addr == int_rd_phy_addr))     dis_rs2_rdy_eff = 1'b1;
            if (mul_exe_ready        && (dis_rs2_phy_addr == mul_rd_phy_addr))     dis_rs2_rdy_eff = 1'b1;
            if (div_exe_ready        && (dis_rs2_phy_addr == div_rd_phy_addr))     dis_rs2_rdy_eff = 1'b1;
            if (lsb_wake_valid  && (dis_rs2_phy_addr == lsb_wake_phy_addr))  dis_rs2_rdy_eff = 1'b1;
        end
    end

    // Ready Detection & Oldest-First Selection
    logic [DIV_QUEUE_DEPTH-1:0] q_ready;
    logic [ROB_INDEX_WIDTH-1:0] entry_depth [DIV_QUEUE_DEPTH];
    logic [IdxWidth-1:0]        sel_idx;
    logic                       sel_valid;

    always_comb begin
        for (int i = 0; i < DIV_QUEUE_DEPTH; i++) begin
            q_ready[i]     = q_valid[i] & wk_rs1_rdy[i] & wk_rs2_rdy[i];
            entry_depth[i] = q[i].rob_tag[ROB_INDEX_WIDTH-1:0] - rob_top_ptr;
        end

        sel_valid = 1'b0;
        sel_idx   = '0;

        for (int i = DIV_QUEUE_DEPTH - 1; i >= 0; i--) begin
            if (q_ready[i]) begin
                sel_idx   = i[IdxWidth-1:0];
                sel_valid = 1'b1;
            end
        end
    end

    // Flush Detection — entries younger than the mispredicting branch
    logic [DIV_QUEUE_DEPTH-1:0] flush_mask;

    always_comb begin
        for (int i = 0; i < DIV_QUEUE_DEPTH; i++) begin
            flush_mask[i] = cdb_flush & q_valid[i] & (entry_depth[i] > cdb_rob_depth);
        end
    end

    // Free Slot Allocation & Vacancy Count
    logic [IdxWidth-1:0]                  free_idx;
    logic                                 has_free;
    logic [$clog2(DIV_QUEUE_DEPTH+1)-1:0] vacant_count;

    always_comb begin
        has_free     = 1'b0;
        free_idx     = '0;
        vacant_count = '0;
        for (int i = 0; i < DIV_QUEUE_DEPTH; i++) begin
            if (!q_valid[i]) begin
                vacant_count += {{($clog2(DIV_QUEUE_DEPTH+1)-1){1'b0}}, 1'b1};
                if (!has_free) begin
                    free_idx = i[IdxWidth-1:0];
                    has_free = 1'b1;
                end
            end
        end
    end

    assign divq_full                   = &q_valid;
    assign iss_divq_two_or_more_vacant = (vacant_count >= 2);
    assign issue_div_rdy               = sel_valid & ~cdb_flush;
    assign issue_div                   = sel_valid & issue_div_en & ~cdb_flush;

    // State Update
    // Last-write-wins ordering: wakeup -> flush -> issue -> dispatch
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < DIV_QUEUE_DEPTH; i++) begin
                q[i]       <= '{
                    rob_tag : '0,
                    rs1     : '0,
                    rs1_rdy : 1'b0,
                    rs2     : '0,
                    rs2_rdy : 1'b0,
                    op      : INSTR_NONE,
                    rd      : '0,
                    rw      : 1'b0
                };
                q_valid[i] <= 1'b0;
            end
        end else begin
            for (int i = 0; i < DIV_QUEUE_DEPTH; i++) begin
                q[i].rs1_rdy <= wk_rs1_rdy[i];
                q[i].rs2_rdy <= wk_rs2_rdy[i];
            end

            for (int i = 0; i < DIV_QUEUE_DEPTH; i++) begin
                if (flush_mask[i])
                    q_valid[i] <= 1'b0;
            end

            if (issue_div) begin
                q_valid[sel_idx]    <= 1'b0;
                exe_div_grant       <= 1'b1;
                iss_rw_div          <= q[sel_idx].rw;
                iss_rd_phy_addr_div <= q[sel_idx].rd;
                iss_rob_tag_div     <= q[sel_idx].rob_tag;
                iss_opcode_div      <= q[sel_idx].op;
                iss_rs1_phy_addr_div<= q[sel_idx].rs1;
                iss_rs2_phy_addr_div<= q[sel_idx].rs2;
            end else begin
                exe_div_grant       <= '0;
                iss_rw_div          <= '0;
                iss_rd_phy_addr_div <= '0;
                iss_rob_tag_div     <= '0;
                iss_opcode_div      <= INSTR_NONE;
                iss_rs1_phy_addr_div<= '0;
                iss_rs2_phy_addr_div<= '0;
            end


            if (dis_div_issue_en && has_free && !cdb_flush) begin
                q_valid[free_idx] <= 1'b1;
                q[free_idx]       <= '{
                    rob_tag : dis_rob_tag,
                    rs1     : dis_rs1_phy_addr,
                    rs1_rdy : dis_rs1_rdy_eff,
                    rs2     : dis_rs2_phy_addr,
                    rs2_rdy : dis_rs2_rdy_eff,
                    op      : dis_opcode,
                    rd      : dis_new_rd_phy_addr,
                    rw      : dis_reg_write
                };
            end
        end
    end

endmodule
