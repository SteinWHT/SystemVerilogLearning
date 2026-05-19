// LS QUEUE DATA STRUCTURE:
//  valid   rs_data_valid   opcode      addr_rdy      robtag        rs_phy_addr     rd_phy_addr    addr/offset
//  1b      1b              6b           1b           5b            6b              6b             32b
// The LSQ and SAB are intergrated into one module, and the SAB is used to store the store addresses.
// Because they are fully coupled, I don't want to use so many ports to connect them.
module LSQ 
import riscv_types_pkg::*;
#(
    parameter int unsigned LSQ_DEPTH = 8,
    parameter int unsigned LSQ_INDEX_WIDTH = $clog2(LSQ_DEPTH),
    parameter int unsigned SAB_DEPTH = 8,
    parameter int unsigned SAB_INDEX_WIDTH = $clog2(SAB_DEPTH),
    parameter int unsigned DMEM_WIDTH = 64,
    parameter int unsigned DMEM_DEPTH = 32,
    parameter int unsigned ROB_DEPTH = 16,
    parameter int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH),
    parameter int unsigned ARCH_REG_WIDTH = 5,
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned REG_FILE_DATA_WIDTH = 64,
    parameter int unsigned SB_DEPTH = 4,
    parameter int unsigned SB_INDEX_WIDTH = $clog2(SB_DEPTH),
    parameter int unsigned OPCODE_WIDTH = 6
) (
    input logic clk,
    input logic rst_n,

    // --------------------------------------------------------
    // SAB part
    // --------------------------------------------------------
     // SB interface
    input logic [SB_INDEX_WIDTH-1:0]            sb_flush_sw_tag,
    input logic                                 sb_flush_sw,
    input logic [SB_INDEX_WIDTH-1:0]            sb_entry_sw_tag,
    input logic [DMEM_DEPTH-1:0]                sb_entry_sw_addr,

    // ROB interface
    input logic [ROB_INDEX_WIDTH-1:0]           rob_tag,
    input logic [ROB_INDEX_WIDTH-1:0]           rob_top_ptr,
    input logic                                 rob_commit_mem_write,

    // --------------------------------------------------------
    // LSQ part
    // --------------------------------------------------------
    // DISPATCH interface
    input logic                                 dis_ld_st_issue_en,
    input logic                                 dis_rs_data_ready,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   dis_rs_phy_addr,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   dis_new_rd_phy_addr,
    input logic [ROB_INDEX_WIDTH-1:0]           dis_rob_tag,
    input logic [OPCODE_WIDTH-1:0]              dis_opcode,
    input logic [15:0]                          dis_imm16,

    output logic                                lsq_ld_st_full,
    output logic                                lsq_ld_st_two_or_more_vacant,

    // D-Cache interface
    input logic                                 dcache_read_busy,

    // CDB interface
    input logic                                 cdb_valid,
    input logic                                 cdb_flush,
    input logic [ROB_INDEX_WIDTH-1:0]           cdb_rob_depth,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   cdb_rd_phy_addr,
    input logic                                 cdb_phy_reg_write,

    // no forwarding in LSQ
    // because it needs to obtain the data from the PRF
    // and add offset to get the address
    // LSQ interface

    // PRF interface
    input logic [REG_FILE_DATA_WIDTH-1:0]       iss_rs_data_lsq,

    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  iss_rs_phy_addr_ls,

    // LSB interface
    input logic                                 lsb_rdy,

    output logic [OPCODE_WIDTH-1:0]             iss_lsq_opcode,
    output logic [ROB_INDEX_WIDTH-1:0]          iss_lsq_rob_tag,
    output logic [DMEM_DEPTH-1:0]               iss_lsq_addr,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  iss_lsq_phy_addr,
    output logic                                iss_lsq_rdy
);
    // --------------------------------------------------------
    // SAB part
    // --------------------------------------------------------
    typedef struct packed {
        logic [DMEM_DEPTH-1:0] addr;
        logic [ROB_INDEX_WIDTH-1:0] rob_tag;
        logic [SB_INDEX_WIDTH-1:0] sb_tag;
        logic tag_sel;
    } sab_entry_t;

    sab_entry_t sab_array [SAB_DEPTH];
    logic [SAB_DEPTH-1:0] sab_valid;
    logic sab_full;
    logic sab_empty;
    // flush
    logic [ROB_INDEX_WIDTH-1:0] sab_entry_depth [SAB_DEPTH];


    // --------------------------------------------------------
    // LSQ part
    // --------------------------------------------------------
    typedef struct packed {
        logic rs_data_valid;
        logic [OPCODE_WIDTH-1:0] opcode;
        logic addr_rdy;
        logic [ROB_INDEX_WIDTH-1:0] rob_tag;
        logic [PHY_REGISTER_FILE_WIDTH-1:0] rs_phy_addr;
        logic [PHY_REGISTER_FILE_WIDTH-1:0] rd_phy_addr;
        logic [DMEM_DEPTH-1:0] addr_offset;
    } lsq_entry_t;

    lsq_entry_t q [LSQ_DEPTH];
    logic [LSQ_DEPTH-1:0] q_valid;
    logic [SAB_INDEX_WIDTH-1:0] junior_counter [LSQ_DEPTH];

    logic [LSQ_INDEX_WIDTH-1:0] issue_idx;

     // Wakeup Logic — snoop CDB forwarding bus
    logic wk_rs_rdy [LSQ_DEPTH];

    always_comb begin
        for (int i = 0; i < LSQ_DEPTH; i++) begin
            wk_rs_rdy[i] = q[i].rs_data_valid;

            if (q_valid[i]) begin
                if (!q[i].rs_data_valid) begin
                    if (cdb_valid && cdb_phy_reg_write   && (q[i].rs_phy_addr == cdb_rd_phy_addr))      wk_rs_rdy[i] = 1'b1;
                end
            end
        end
    end

    // Get the register data from the PRF and add offset to get the address
    logic addr_calculating_valid;
    logic [LSQ_INDEX_WIDTH-1:0] addr_calculating_idx;
    logic [DMEM_DEPTH-1:0] lsq_addr_next;
    assign iss_rs_phy_addr_ls = q[addr_calculating_idx].rs_phy_addr;
    assign lsq_addr_next = q[addr_calculating_idx].addr_offset + iss_rs_data_lsq;

    always_comb begin
        addr_calculating_valid = 1'b0;
        addr_calculating_idx = '0;
        for (int i = 0; i < LSQ_DEPTH; i++) begin
            if (wk_rs_rdy[i] && !q[i].addr_rdy) begin
                addr_calculating_valid = 1'b1;
                addr_calculating_idx = i;
            end
        end
    end

    // Dispatch-Time Wakeup — catch same-cycle forwarding for new entry
    // TODO: check if no this forwarding, will the cdb data be lost?
    logic dis_rs_rdy_eff;

    always_comb begin
        dis_rs_rdy_eff = dis_rs_data_ready;

        if (!dis_rs_data_ready) begin
            if (cdb_valid && cdb_phy_reg_write   && (dis_rs_phy_addr == cdb_rd_phy_addr))     dis_rs_rdy_eff = 1'b1;
        end
    end

    // Match Number Detection
    logic [SAB_INDEX_WIDTH-1:0] match_number [LSQ_DEPTH];
    always_comb begin
        for (int i = 0; i < LSQ_DEPTH; i++) begin
            match_number[i] = '0;
        end
        for (int i = 0; i < LSQ_DEPTH; i++) begin
            if (q[i].opcode == INSTR_LW) begin
                for (int j = 0; j < SAB_DEPTH; j++) begin
                    if (sab_array[j].addr == q[i].addr_offset && sab_valid[j] == 1'b1) begin
                        match_number[i] = match_number[i] + 1;
                    end
                end
            end
        end
    end

    // Ready Detection & Oldest-First Selection
    // depth = rob_tag - rob_top_ptr (unsigned mod 2^N, smaller = older)
    logic [LSQ_DEPTH-1:0] q_ready;
    logic [ROB_INDEX_WIDTH-1:0] entry_depth [LSQ_DEPTH];
    logic [LSQ_INDEX_WIDTH-1:0] sel_idx;
    logic                       sel_valid, sw_valid, lw_valid;
    logic debug_sw, debug_lw, debug_in;

    // ISSUE LOGIC:
    // 1. for sw: all the older lw addresses are known, so we can check if the sw address is in the LSQ
    // 2. for sw: sab is not full
    // 3. for lw: junior counter equals to the match number
    // 4. for lw: dcache is not busy
    always_comb begin
        for (int i = 0; i < LSQ_DEPTH; i++) begin
            q_ready[i]     = q_valid[i] & wk_rs_rdy[i] && q[i].addr_rdy;
            entry_depth[i] = q[i].rob_tag[ROB_INDEX_WIDTH-1:0] - rob_top_ptr;
        end

        sel_valid = 1'b1;
        sw_valid  = 1'b0;
        lw_valid  = 1'b0;
        sel_idx   = '0;

        debug_sw = 1'b0;
        debug_lw = 1'b0;
        debug_in = 1'b0;


        for (int i = LSQ_DEPTH - 1; i >= 0; i--) begin
            if (q_ready[i]) begin
                debug_in = 1'b1;
                if (q[i].opcode == INSTR_SW) begin
                    debug_sw = 1'b1;
                    for (int j = 0; j < LSQ_DEPTH; j++) begin
                        // 1. for sw: all the older lw addresses are known
                        // 2. for sw: sab is not full
                        if(!sab_full && (j != i) && (q[j].opcode == INSTR_LW) &&
                        (entry_depth[j] < entry_depth[i])
                            && ((q[j].addr_rdy == 1'b0)) ) begin
                            sel_valid = 1'b0;
                            break;
                        end
                    end
                    if (sel_valid) begin
                        sw_valid = 1'b1;
                        sel_idx = i[LSQ_INDEX_WIDTH-1:0];
                    end
                end else begin
                    debug_lw = 1'b1;
                    // 3. for lw: junior counter equals to the match number
                    // 4. for lw: dcache is not busy
                    if (!dcache_read_busy && junior_counter[i] == match_number[i]) begin
                        sel_idx = i[LSQ_INDEX_WIDTH-1:0];
                        lw_valid = 1'b1;
                    end
                end
            end
        end
        sel_valid = sw_valid | lw_valid;
    end

    // Flush Detection — entries younger than the mispredicting branch
    logic [LSQ_DEPTH-1:0] flush_mask;

    always_comb begin
        for (int i = 0; i < LSQ_DEPTH; i++) begin
            flush_mask[i] = cdb_flush & q_valid[i] & (entry_depth[i] > cdb_rob_depth);
        end
    end

    // Free Slot Allocation & Vacancy Count
    logic [LSQ_INDEX_WIDTH-1:0]           free_idx;
    logic                                 has_free;
    logic [$clog2(LSQ_DEPTH+1)-1:0] vacant_count;

    always_comb begin
        has_free     = 1'b0;
        free_idx     = '0;
        vacant_count = '0;
        for (int i = 0; i < LSQ_DEPTH; i++) begin
            if (!q_valid[i]) begin
                vacant_count += {{($clog2(LSQ_DEPTH+1)-1){1'b0}}, 1'b1};
                if (!has_free) begin
                    free_idx = i[LSQ_INDEX_WIDTH-1:0];
                    has_free = 1'b1;
                end
            end
        end
    end

    assign lsq_ld_st_full              = &q_valid;
    assign lsq_ld_st_two_or_more_vacant= (vacant_count >= 2);

    // LSQ issues to LSB when an entry is ready and LSB can accept (not ISSUEUNIT).
    logic issue_lsq;
    assign issue_lsq = sel_valid & ~cdb_flush & lsb_rdy;

    // Issue Outputs — drive selected entry or zero
    always_comb begin
        if (issue_lsq) begin
            iss_lsq_rob_tag           = q[sel_idx].rob_tag;
            iss_lsq_opcode            = q[sel_idx].opcode;
            iss_lsq_addr              = q[sel_idx].addr_offset;
            iss_lsq_phy_addr          = q[sel_idx].rd_phy_addr;
            iss_lsq_rdy               = '1;
        end else begin
            iss_lsq_rob_tag           = '0;
            iss_lsq_opcode            =  INSTR_NONE;
            iss_lsq_addr              = '0;
            iss_lsq_phy_addr          = '0;
            iss_lsq_rdy               = '0;
        end
    end

    // State Update
    // Last-write-wins ordering: wakeup -> flush -> addr_calculating -> issue -> dispatch
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < LSQ_DEPTH; i++) begin
                q[i]       <= '{
                    rs_data_valid : 1'b0,
                    opcode : INSTR_NONE,
                    addr_rdy : 1'b0,
                    rob_tag : '0,
                    rs_phy_addr : '0,
                    rd_phy_addr : '0,
                    addr_offset : '0
                };
                q_valid[i] <= 1'b0;
                junior_counter[i] <= '0;
            end
        end else begin
            // Wakeup: latch updated ready bits
            for (int i = 0; i < LSQ_DEPTH; i++) begin
                q[i].rs_data_valid <= wk_rs_rdy[i];
            end

            // Addr Calculating: calculate the address
            if (addr_calculating_valid) begin
                q[addr_calculating_idx].addr_offset <= lsq_addr_next;
                q[addr_calculating_idx].addr_rdy <= 1'b1;
            end

            // Flush: invalidate entries younger than the branch
            for (int i = 0; i < LSQ_DEPTH; i++) begin
                if (flush_mask[i] && q_valid[i]) begin
                    if (q[i].opcode == INSTR_LW) begin
                        for (int j = 0; j < SAB_DEPTH; j++) begin
                            if (sab_array[j].addr == q[i].addr_offset && sab_valid[j] == 1'b1 &&
                                sab_entry_depth[j] > cdb_rob_depth) begin
                                junior_counter[i] <= junior_counter[i] - 1;
                            end
                        end
                    end
                    q_valid[i] <= 1'b0;
                end
            end

            // Issue: dequeue into LSB (issue_lsq already requires lsb_rdy)
            if (issue_lsq) begin
                q_valid[sel_idx] <= 1'b0;
                if (q[sel_idx].opcode == INSTR_SW) begin
                    for (int i = 0; i < LSQ_DEPTH; i++) begin
                        // when sw is issued, the junior counter of the older lw is incremented
                        if (q[i].opcode == INSTR_LW && (entry_depth[i] < entry_depth[sel_idx]) &&
                            (q[i].addr_offset == q[sel_idx].addr_offset)) begin
                            junior_counter[i] <= junior_counter[i] + 1;
                        end
                    end
                end
            end

            // Dispatch: enqueue new entry (suppressed during flush)
            if (dis_ld_st_issue_en && has_free && !cdb_flush) begin
                q_valid[free_idx] <= 1'b1;
                q[free_idx]       <= '{
                    rs_data_valid : dis_rs_rdy_eff,
                    opcode : dis_opcode,
                    addr_rdy : 1'b0,
                    rob_tag   : dis_rob_tag,
                    rs_phy_addr : dis_rs_phy_addr,
                    rd_phy_addr : dis_new_rd_phy_addr,
                    addr_offset : dis_imm16
                };
                junior_counter[free_idx] <= '0;
            end
        end
    end



    // --------------------------------------------------------
    // SAB part
    // --------------------------------------------------------
    logic [LSQ_INDEX_WIDTH-1:0]           sab_free_idx;
    logic                                 sab_has_free;
    logic [$clog2(SAB_DEPTH+1)-1:0]   sab_vacant_count;

    always_comb begin
        sab_has_free     = 1'b0;
        sab_free_idx     = '0;
        sab_vacant_count = '0;
        for (int i = 0; i < SAB_DEPTH; i++) begin
            if (!sab_valid[i]) begin
                sab_vacant_count += {{($clog2(SAB_DEPTH+1)-1){1'b0}}, 1'b1};
                if (!sab_has_free) begin
                    sab_free_idx = i[LSQ_INDEX_WIDTH-1:0];
                    sab_has_free = 1'b1;
                end
            end
        end
    end

    // Entry Depth
    always_comb begin
        for (int i = 0; i < SAB_DEPTH; i++) begin
            sab_entry_depth[i] = sab_array[i].tag_sel ?
            (0) : (sab_array[i].rob_tag[ROB_INDEX_WIDTH-1:0] - rob_top_ptr);
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < SAB_DEPTH; i++) begin
                sab_valid[i] <= 1'b0;
                sab_array[i] <= '{
                    addr    : '0,
                    rob_tag : '0,
                    sb_tag  : '0,
                    tag_sel : '0
                };
            end
        end else begin
            // Issue Store
            if (issue_lsq && q[sel_idx].opcode == INSTR_SW) begin
                sab_valid[q[sel_idx].addr_offset] <= 1'b1;
                sab_array[q[sel_idx].addr_offset] <= '{
                    addr: q[sel_idx].addr_offset,
                    rob_tag: q[sel_idx].rob_tag,
                    sb_tag: '0,
                    tag_sel: 1'b0
                };
            end

            // SB Entry
            if (sb_entry_sw_tag) begin
                for (int i = 0; i < SAB_DEPTH; i++) begin
                    if (sab_array[i].addr == sb_entry_sw_addr && sab_valid[i] == 1'b0) begin
                        sab_array[i].tag_sel <= 1'b1;
                        sab_array[i].sb_tag <= sb_entry_sw_tag;
                    end
                end
            end

            // SB Flush
            if (sb_flush_sw) begin
                for (int i = 0; i < SAB_DEPTH; i++) begin
                    if (sab_array[i].sb_tag == sb_flush_sw_tag &&
                        sab_array[i].tag_sel == 1'b1) begin
                        sab_valid[i] <= 1'b0;
                    end
                end
            end

            // SAB Flush
            if (cdb_flush) begin
                for (int i = 0; i < SAB_DEPTH; i++) begin
                    if (sab_entry_depth[i] > cdb_rob_depth) begin
                        sab_valid[i] <= 1'b0;
                    end
                end
            end
        end
    end

    assign sab_full = &sab_valid;
    assign sab_empty = ~|sab_valid;


endmodule
