// ====================================================================
// cpu_core_ifs.sv
// SystemVerilog interfaces for the internal front-end <-> back-end
// boundary of the OoO core. Each interface carries one logical channel
// and exposes producer/consumer modports so direction is self-documenting.
//
// These bundle the flat inter-module wires that used to live in CPU.sv.
// The CPU's *external* ports (clk, rst_n, imem_*, dcache_*, fence_i_coh_*)
// and all sub-module ports remain flat; front_end/back_end unpack these
// interfaces to identically-named local nets at their boundary.
// ====================================================================

// --------------------------------------------------------------------
// DISPATCH: front-end DISPATCH -> back-end issue queues (front drives)
// --------------------------------------------------------------------
interface dispatch_if #(
    parameter int unsigned PHY_REG_IDX_WIDTH = 7,
    parameter int unsigned XLEN              = 64,
    parameter int unsigned PC_WIDTH          = 64,
    parameter int unsigned OPCODE_WIDTH      = 7,
    parameter int unsigned BPB_PC_BITS       = 3
);
    logic                          int_issue_en;
    logic                          div_issue_en;
    logic                          mul_issue_en;
    logic                          ld_st_issue_en;
    logic                          reg_write;
    logic                          rs1_data_ready;
    logic                          rs2_data_ready;
    logic [PHY_REG_IDX_WIDTH-1:0]  rs1_phy_addr;
    logic [PHY_REG_IDX_WIDTH-1:0]  rs2_phy_addr;
    logic [PHY_REG_IDX_WIDTH-1:0]  new_rd_phy_addr;
    logic [OPCODE_WIDTH-1:0]       opcode;
    logic [XLEN-1:0]               imm;
    logic [PC_WIDTH-1:0]           branch_other_addr;
    logic [BPB_PC_BITS:0]          branch_pc_bits;   // zero-extended (4-bit) form
    logic                          branch_prediction;
    logic                          branch;
    logic                          jr_inst;
    logic                          jal_inst;
    logic                          jr31_inst;
    logic [PC_WIDTH-1:0]           pc;

    modport producer (
        output int_issue_en, div_issue_en, mul_issue_en, ld_st_issue_en,
               reg_write, rs1_data_ready, rs2_data_ready, rs1_phy_addr,
               rs2_phy_addr, new_rd_phy_addr, opcode, imm, branch_other_addr,
               branch_pc_bits, branch_prediction, branch, jr_inst, jal_inst,
               jr31_inst, pc
    );
    modport consumer (
        input  int_issue_en, div_issue_en, mul_issue_en, ld_st_issue_en,
               reg_write, rs1_data_ready, rs2_data_ready, rs1_phy_addr,
               rs2_phy_addr, new_rd_phy_addr, opcode, imm, branch_other_addr,
               branch_pc_bits, branch_prediction, branch, jr_inst, jal_inst,
               jr31_inst, pc
    );
endinterface

// --------------------------------------------------------------------
// CDB: back-end common data bus -> front-end (back drives, broadcast)
// --------------------------------------------------------------------
interface cdb_if #(
    parameter int unsigned PHY_REG_IDX_WIDTH   = 7,
    parameter int unsigned ROB_INDEX_WIDTH     = 4,
    parameter int unsigned REG_FILE_DATA_WIDTH = 64,
    parameter int unsigned DMEM_ADDR_WIDTH     = 32,
    parameter int unsigned W_BYTE_NUM          = 8,
    parameter int unsigned PC_WIDTH            = 64,
    parameter int unsigned BPB_PC_BITS         = 3
);
    logic                              valid;
    logic [ROB_INDEX_WIDTH-1:0]        rob_tag;
    logic [PHY_REG_IDX_WIDTH-1:0]      rd_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0]    rd_data;
    logic                              reg_write;
    logic                              flush;
    logic [ROB_INDEX_WIDTH-1:0]        rob_depth;
    logic [DMEM_ADDR_WIDTH-1:0]        sw_addr;
    logic [W_BYTE_NUM-1:0]             sw_strb;
    logic                              upd_branch;
    logic [BPB_PC_BITS-1:0]            upd_branch_addr;
    logic                              branch_outcome;
    logic [PC_WIDTH-1:0]               branch_addr;

    modport producer (
        output valid, rob_tag, rd_phy_addr, rd_data, reg_write, flush,
               rob_depth, sw_addr, sw_strb, upd_branch, upd_branch_addr,
               branch_outcome, branch_addr
    );
    modport consumer (
        input  valid, rob_tag, rd_phy_addr, rd_data, reg_write, flush,
               rob_depth, sw_addr, sw_strb, upd_branch, upd_branch_addr,
               branch_outcome, branch_addr
    );
endinterface

// --------------------------------------------------------------------
// ISSUE-QUEUE STATUS: back-end issue queues -> front-end DISPATCH
// (back drives the occupancy/back-pressure flags)
// --------------------------------------------------------------------
interface issq_status_if;
    logic intq_full;
    logic divq_full;
    logic mulq_full;
    logic ld_stq_full;
    logic intq_two_or_more_vacant;
    logic divq_two_or_more_vacant;
    logic mulq_two_or_more_vacant;
    logic ld_stq_two_or_more_vacant;

    modport producer (
        output intq_full, divq_full, mulq_full, ld_stq_full,
               intq_two_or_more_vacant, divq_two_or_more_vacant,
               mulq_two_or_more_vacant, ld_stq_two_or_more_vacant
    );
    modport consumer (
        input  intq_full, divq_full, mulq_full, ld_stq_full,
               intq_two_or_more_vacant, divq_two_or_more_vacant,
               mulq_two_or_more_vacant, ld_stq_two_or_more_vacant
    );
endinterface

// --------------------------------------------------------------------
// ROB SIDEBAND: front-end ROB -> back-end (commit/fence/pointer info)
// --------------------------------------------------------------------
interface rob_sideband_if #(
    parameter int unsigned ROB_INDEX_WIDTH   = 4,
    parameter int unsigned PHY_REG_IDX_WIDTH = 7
);
    logic [ROB_INDEX_WIDTH-1:0]   bottom_ptr;            // ROB write ptr (also dispatch rob_tag)
    logic [ROB_INDEX_WIDTH-1:0]   top_ptr;
    logic                         commit_mem_write;
    logic [PHY_REG_IDX_WIDTH-1:0] commit_curr_phy_addr;
    logic                         fence_pending;
    logic [ROB_INDEX_WIDTH-1:0]   fence_tag;

    modport producer (
        output bottom_ptr, top_ptr, commit_mem_write, commit_curr_phy_addr,
               fence_pending, fence_tag
    );
    modport consumer (
        input  bottom_ptr, top_ptr, commit_mem_write, commit_curr_phy_addr,
               fence_pending, fence_tag
    );
endinterface

// --------------------------------------------------------------------
// STORE-BUFFER ALLOC: front-end SB -> back-end LSQ store-address buffer
// --------------------------------------------------------------------
interface sb_alloc_if #(
    parameter int unsigned SB_INDEX_WIDTH  = 2,
    parameter int unsigned ROB_INDEX_WIDTH = 4
);
    logic                         flush_sw;
    logic [SB_INDEX_WIDTH-1:0]    flush_sw_tag;
    logic                         entry_sw;
    logic [SB_INDEX_WIDTH-1:0]    entry_sw_tag;
    logic [ROB_INDEX_WIDTH-1:0]   entry_sw_rob_tag;

    modport producer (
        output flush_sw, flush_sw_tag, entry_sw, entry_sw_tag, entry_sw_rob_tag
    );
    modport consumer (
        input  flush_sw, flush_sw_tag, entry_sw, entry_sw_tag, entry_sw_rob_tag
    );
endinterface
