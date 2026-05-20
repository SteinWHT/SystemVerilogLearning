`timescale 1ns/1ps
module CPU_FRONT_END #(
    // I-CACHE
    parameter int unsigned INSTR_WIDTH = 32,
    parameter int unsigned IMEM_DEPTH = 32,
    parameter int unsigned IMEM_WIDTH = 32,
    parameter int unsigned IMEM_DEPTH_WORD = IMEM_DEPTH - 1,

    // ARCH_REG
    parameter int unsigned XLEN = 64,
    parameter int unsigned ARCH_REG_COUNT = 32,
    parameter int unsigned ARCH_REG_WIDTH = $clog2(ARCH_REG_COUNT),
    parameter int unsigned REG_FILE_DATA_WIDTH = 64,

    // PHY_REGISTER_FILE
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,

    // D-CACHE
    parameter int unsigned DMEM_WIDTH = 64,
    parameter int unsigned DMEM_DEPTH = 32,

    // BPB
    parameter int unsigned BPB_PC_BITS = 3,

    // IFQ
    // NUM_WAYS now only support 2^N because of the valid_out signal
    parameter int unsigned NUM_WAYS = 4,
    parameter int unsigned IFQ_DEPTH = 16,

    // RAS
    parameter int unsigned RAS_DEPTH = 4,

    // FRL
    parameter int unsigned FRL_SIZE = 128,
    parameter int unsigned FRL_PTR_WIDTH = $clog2(FRL_SIZE),

    // FRAT
    parameter int unsigned NUM_CHECKPOINT = 8,

    // ROB
    parameter int unsigned ROB_DEPTH = 16,
    parameter int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH),

    // SB
    parameter int unsigned SB_DEPTH = 4,
    parameter int unsigned SB_INDEX_WIDTH = $clog2(SB_DEPTH),

    // ISSUEQ
    parameter int unsigned OPCODE_WIDTH = 6
) (
    input  logic clk,
    input  logic rst_n,

    // I-CACHE interface
    input  logic                                imem_valid,
    input  logic [INSTR_WIDTH-1:0]              imem_data,

    output logic                                imem_read_rdy,
    output logic [IMEM_DEPTH-1:0]               imem_addr,

    // D-CACHE interface
    input logic                                 dcache_valid,
    input logic                                 dcache_write_done,

    output logic [DMEM_DEPTH-1:0]               dcache_sw_addr,
    output logic [DMEM_WIDTH-1:0]               dcache_sw_data,
    output logic                                dcache_ready,

    // back-end interface
    // ISSUEQ interface
    input logic                                 issue_intq_full,
    input logic                                 issue_divq_full,
    input logic                                 issue_mulq_full,
    input logic                                 issue_ld_stq_full,
    input logic                                 issue_intq_two_or_more_vacant,
    input logic                                 issue_divq_two_or_more_vacant,
    input logic                                 issue_mulq_two_or_more_vacant,
    input logic                                 issue_ld_stq_two_or_more_vacant,

    output logic                                dis_rs_data_ready,
    output logic                                dis_rt_data_ready,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  dis_rs_phy_addr,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  dis_rt_phy_addr,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  dis_new_rd_phy_addr,
    output logic                                dis_reg_write,
    output logic [XLEN-1:0]                     dis_imm,
    output logic [IMEM_DEPTH-1:0]               dis_branch_other_addr,
    output logic                                dis_branch_prediction,
    output logic                                dis_branch,
    output logic [BPB_PC_BITS-1:0]              dis_branch_pc_bits,
    output logic                                dis_jr_inst,
    output logic                                dis_jal_inst,
    output logic                                dis_jr31_inst,
    output logic [OPCODE_WIDTH-1:0]             dis_opcode,

    output logic                                dis_int_issue_en,
    output logic                                dis_div_issue_en,
    output logic                                dis_mul_issue_en,
    output logic                                dis_ld_st_issue_en,

    // CDB interface
    input logic                                 cdb_valid,
    //input logic [ROB_INDEX_WIDTH-1:0] cdb_rob_depth,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   cdb_rd_phy_addr,
    //input logic [REG_FILE_DATA_WIDTH-1:0] cdb_rd_data,
    input logic                                 cdb_reg_write,
    input logic [ROB_INDEX_WIDTH-1:0]           cdb_rob_tag,
    input logic [DMEM_DEPTH-1:0]                cdb_sw_addr,
    input logic [DMEM_WIDTH-1:0]                cdb_sw_data,
    input logic [IMEM_DEPTH-1:0]                cdb_branch_addr,
    input logic [BPB_PC_BITS-1:0]               cdb_br_updt_addr,
    input logic                                 cdb_branch,
    input logic                                 cdb_branch_outcome,
    input logic                                 cdb_flush,
    input logic                                 cdb_jalr_resolved,

    // PRF interface
    // input logic prf_rs_data_ready,
    // input logic prf_rt_data_ready,
    // input logic [PHY_REGISTER_FILE_WIDTH-1:0] prf_rs_phy_addr,
    // input logic [PHY_REGISTER_FILE_WIDTH-1:0] prf_rt_phy_addr,
    // input logic [PHY_REGISTER_FILE_WIDTH-1:0] prf_rd_phy_addr,
    // input logic prf_reg_write,
    // input logic [ARCH_REG_WIDTH-1:0] prf_rd_arch_addr,
    // input logic [DMEM_DEPTH-1:0] prf_sw_addr,

    // SAB interface
    output logic [SB_INDEX_WIDTH-1:0]           sb_flush_sw_tag,
    output logic                                sb_flush_sw,
    output logic [SB_INDEX_WIDTH-1:0]           sb_entry_sw_tag,
    output logic [DMEM_DEPTH-1:0]               sb_entry_sw_addr,

    // Back-end ROB sideband
    output logic [ROB_INDEX_WIDTH-1:0]          rob_bottom_ptr_out,
    output logic [ROB_INDEX_WIDTH-1:0]          rob_top_ptr_out,
    output logic                                rob_commit_mem_write_out,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  rob_commit_curr_phy_addr_out
);
    // ------------------------------------------------------------
    // INTERFACE
    // ------------------------------------------------------------
    // IFQ interface
    logic [INSTR_WIDTH-1:0] ifq_instr_out;
    logic ifq_empty;
    logic [IMEM_WIDTH-1:0] ifq_pc;
    logic [IMEM_WIDTH-1:0] ifq_pc_plus4;

    // DISPATCH interface
    // DISPATCH <-> IFQ
    logic dis_ren;
    logic dis_jmpbr;
    logic [IMEM_DEPTH_WORD-1:0] dis_jmpbr_addr;
    logic dis_jmpbr_addr_valid;

    // DISPATCH <-> FRAT
    logic [ARCH_REG_WIDTH-1:0] dis_rs1_arch_address;
    logic [ARCH_REG_WIDTH-1:0] dis_rs2_arch_address;
    logic [ARCH_REG_WIDTH-1:0] dis_rd_arch_address;

    // DISPATCH <-> ROB
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_sw_rt_phy_addr;
    logic dis_inst_sw;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_pre_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_new_phy_addr;
    logic dis_inst_valid;
    logic [ARCH_REG_WIDTH-1:0] dis_rob_rd_arch_addr;

    // BPB interface
    logic bpb_branch_prediction;
    logic [BPB_PC_BITS-1:0] dis_bpb_branch_pc_bits;
    logic dis_bpb_branch;
    logic [BPB_PC_BITS-1:0] dis_cdb_upd_branch_addr;
    logic dis_cdb_branch_outcome;
    logic [IMEM_DEPTH-1:0] dis_branch_other_addr_int;

    // RAS interface
    logic [IMEM_DEPTH_WORD-1:0] ras_addr;
    logic dis_ras_jr31_inst;
    logic dis_ras_jal_inst;
    logic [IMEM_DEPTH-1:0] dis_pc_plus4;

    // FRL interface
    logic dis_frl_empty;
    logic dis_frl_read;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_frl_rd_phy_addr;
    logic [FRL_PTR_WIDTH:0] frl_head_ptr_to_frat;
    logic [FRL_PTR_WIDTH:0] frat_frl_head_ptr;

    // FRAT interface
    logic frat_full;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] frat_rs_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] frat_rt_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] frat_rd_phy_addr;
    //logic [5:0] dis_opcode;

    // ROB interface
    logic [ROB_INDEX_WIDTH-1:0] rob_bottom_ptr;
    logic rob_full;
    logic rob_two_or_more_vacant;
    logic [DMEM_DEPTH-1:0] rob_sw_addr;
    logic [DMEM_WIDTH-1:0] rob_sw_data;
    logic rob_commit_mem_write;
    logic [ROB_INDEX_WIDTH-1:0] rob_top_ptr;
    logic rob_commit;
    logic [ARCH_REG_WIDTH-1:0] rob_commit_rd_arch_addr;
    logic rob_reg_write;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] rob_commit_curr_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] rob_commit_pre_phy_addr;

    // SB interface
    logic sb_full;
    //logic sb_empty;
    //logic [DMEM_DEPTH-1:0] sb_entry_sw_addr;

    // RBA
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rba_new_rd_phy_addr;


    // ------------------------------------------------------------
    // SUB MODULES
    // ------------------------------------------------------------
    // IFQ
    IFQ #(
        .INSTR_WIDTH(INSTR_WIDTH),
        .IMEM_DEPTH(IMEM_DEPTH),
        .IMEM_WIDTH(IMEM_WIDTH),
        .DEPTH(IFQ_DEPTH),
        .NUM_WAYS(NUM_WAYS)
    ) ifq (
        .clk(clk),
        .rst_n(rst_n),

        .imem_data(imem_data),
        .imem_valid(imem_valid),
        .imem_addr(imem_addr),
        .imem_read_rdy(imem_read_rdy),

        .dis_ren(dis_ren),
        .dis_jmpbr(dis_jmpbr),
        .dis_jmpbr_addr(dis_jmpbr_addr),
        .dis_jmpbr_addr_valid(dis_jmpbr_addr_valid),

        .ifq_instr_out(ifq_instr_out),
        .ifq_pc(ifq_pc),
        .ifq_pc_plus4(ifq_pc_plus4),
        .ifq_empty(ifq_empty)
    );


    // DISPATCH
    DISPATCH #(
        .XLEN(REG_FILE_DATA_WIDTH),
        .INSTR_WIDTH(INSTR_WIDTH),
        .IMEM_DEPTH(IMEM_DEPTH),
        .IMEM_WIDTH(IMEM_WIDTH),
        .DMEM_DEPTH(DMEM_DEPTH),
        .DMEM_WIDTH(DMEM_WIDTH),
        .ARCH_REG_WIDTH(ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .ROB_DEPTH(ROB_DEPTH),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .BPB_PC_BITS(BPB_PC_BITS),
        .OPCODE_WIDTH(OPCODE_WIDTH)
    ) dispatch (
        .clk(clk),
        .rst_n(rst_n),

        .ifetch_instr_in(ifq_instr_out),
        .ifetch_pcplus4_in(ifq_pc_plus4),
        .ifetch_pc(ifq_pc),
        .ifetch_empty(ifq_empty),
        .dis_ren(dis_ren),
        .dis_jmpbr(dis_jmpbr),
        .dis_jmpbr_addr(dis_jmpbr_addr),
        .dis_jmpbr_addr_valid(dis_jmpbr_addr_valid),

        .bpb_branch_prediction(bpb_branch_prediction),
        .dis_bpb_branch_pc_bits(dis_bpb_branch_pc_bits),
        .dis_bpb_branch(dis_bpb_branch),

        .ras_addr(ras_addr),
        .dis_pc_plus4(dis_pc_plus4),
        .dis_ras_jr31_inst(dis_ras_jr31_inst),
        .dis_ras_jal_inst(dis_ras_jal_inst),

        .dis_frl_empty(dis_frl_empty),
        .dis_frl_rd_phy_addr(dis_frl_rd_phy_addr),
        .dis_frl_read(dis_frl_read),

        .cdb_valid(cdb_valid),
        .cdb_branch_addr(cdb_branch_addr[IMEM_DEPTH-1:1]),
        .cdb_flush(cdb_flush),
        .cdb_jalr_resolved(cdb_jalr_resolved),

        .frat_full(frat_full),
        .frat_rs_phy_addr(frat_rs_phy_addr),
        .frat_rt_phy_addr(frat_rt_phy_addr),
        .frat_rd_phy_addr(frat_rd_phy_addr),

        .dis_rs_arch_addr(dis_rs1_arch_address),
        .dis_rt_arch_addr(dis_rs2_arch_address),
        .dis_rd_arch_addr(dis_rd_arch_address),

        .issue_intq_full(issue_intq_full),
        .issue_divq_full(issue_divq_full),
        .issue_mulq_full(issue_mulq_full),
        .issue_ld_stq_full(issue_ld_stq_full),
        .issue_intq_two_or_more_vacant(issue_intq_two_or_more_vacant),
        .issue_divq_two_or_more_vacant(issue_divq_two_or_more_vacant),
        .issue_mulq_two_or_more_vacant(issue_mulq_two_or_more_vacant),
        .issue_ld_stq_two_or_more_vacant(issue_ld_stq_two_or_more_vacant),
        .dis_rs_phy_addr(dis_rs_phy_addr),
        .dis_rt_phy_addr(dis_rt_phy_addr),
        .dis_new_rd_phy_addr(dis_new_rd_phy_addr),
        .dis_opcode(dis_opcode),
        .dis_imm(dis_imm),
        .dis_branch_other_addr(dis_branch_other_addr_int),
        .dis_branch_prediction(dis_branch_prediction),
        .dis_branch(dis_branch),
        .dis_branch_pc_bits(dis_branch_pc_bits),
        .dis_jr_inst(dis_jr_inst),
        .dis_jal_inst(dis_jal_inst),
        .dis_jr31_inst(dis_jr31_inst),
        .dis_int_issue_en(dis_int_issue_en),
        .dis_div_issue_en(dis_div_issue_en),
        .dis_mul_issue_en(dis_mul_issue_en),
        .dis_ld_st_issue_en(dis_ld_st_issue_en),

        .rob_full(rob_full),
        .rob_two_or_more_vacant(rob_two_or_more_vacant),
        .dis_pre_phy_addr(dis_pre_phy_addr),
        .dis_new_phy_addr(dis_new_phy_addr),
        .dis_rob_rd_arch_addr(dis_rob_rd_arch_addr),
        .dis_inst_valid(dis_inst_valid),
        .dis_inst_sw(dis_inst_sw),
        .dis_sw_rt_phy_addr(dis_sw_rt_phy_addr),
        .dis_rba_new_rd_phy_addr(dis_rba_new_rd_phy_addr),
        .dis_rba_reg_write(dis_reg_write)
    );

    // BPB
    BPB #(
        .BUFFER_WIDTH(BPB_PC_BITS)
    ) bpb (
        .clk(clk),
        .rst_n(rst_n),

        .dis_bpb_branch_pc_bits(dis_bpb_branch_pc_bits),
        .dis_bpb_branch(dis_bpb_branch),
        .bpb_branch_prediction(bpb_branch_prediction),

        .dis_cdb_upd_branch(cdb_branch),
        .dis_cdb_upd_branch_addr(dis_cdb_upd_branch_addr),
        .dis_cdb_branch_outcome(dis_cdb_branch_outcome)
    );

    assign dis_cdb_upd_branch_addr = cdb_br_updt_addr;
    assign dis_cdb_branch_outcome = cdb_branch_outcome;
    assign dis_branch_other_addr = DMEM_WIDTH'(dis_branch_other_addr_int);

    // RAS
    RAS #(
        .IMEM_DEPTH(IMEM_DEPTH),
        .IMEM_DEPTH_WORD(IMEM_DEPTH_WORD),
        .DEPTH(RAS_DEPTH)
    ) ras (
        .clk(clk),
        .rst_n(rst_n),

        .dis_pc_plus4(dis_pc_plus4),
        .dis_ras_jr31_inst(dis_ras_jr31_inst),
        .dis_ras_jal_inst(dis_ras_jal_inst),
        .ras_addr(ras_addr)
    );

    // FRL
    FRL #(
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .ARCH_REG_COUNT(ARCH_REG_COUNT)
    ) frl (
        .clk(clk),
        .rst_n(rst_n),

        .rob_commit_pre_phy_addr(rob_commit_pre_phy_addr),
        .rob_commit(rob_commit),
        .rob_commit_reg_write(rob_reg_write),

        .frat_frl_head_ptr(frat_frl_head_ptr),

        .cdb_flush(cdb_flush),

        .dis_frl_read(dis_frl_read),
        .frl_read_phy_addr(dis_frl_rd_phy_addr),
        .frl_read_empty(dis_frl_empty),

        .frl_head_ptr_to_frat(frl_head_ptr_to_frat)
    );

    // FRAT
    FRAT #(
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .ARCH_REG_WIDTH(ARCH_REG_WIDTH),
        .NUM_CHECKPOINT(NUM_CHECKPOINT),
        .ROB_DEPTH(ROB_DEPTH)
    ) frat (
        .clk(clk),
        .rst_n(rst_n),

        .is_branch(dis_inst_valid && (dis_branch || dis_jr31_inst)),
        .rob_bottom_ptr(rob_bottom_ptr),
        .dis_frat_reg_write(dis_reg_write),
        .rd_new_phy_address_in(dis_new_rd_phy_addr),
        .rd_new_arch_address_in(dis_rob_rd_arch_addr),

        .cdb_valid(cdb_valid),
        .branch_mispredict(cdb_flush),
        .mispredict_rob_tag(cdb_rob_tag),
        .rob_commit(rob_commit),
        .rob_top_ptr(rob_top_ptr),

        .frl_head_ptr(frl_head_ptr_to_frat),
        .frat_frl_head_ptr(frat_frl_head_ptr),

        .rd_prev_arch_address_in(dis_rd_arch_address),
        .rs1_arch_address_in(dis_rs1_arch_address),
        .rs2_arch_address_in(dis_rs2_arch_address),

        .rd_prev_phy_address(frat_rd_phy_addr),
        .rs1_phy_address(frat_rs_phy_addr),
        .rs2_phy_address(frat_rt_phy_addr),

        .full(frat_full)
    );

    // RRAT
    RRAT #(
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .ARCH_REG_COUNT(ARCH_REG_COUNT),
        .NUM_CHECKPOINT(NUM_CHECKPOINT)
    ) rrat (
        .clk(clk),
        .rst_n(rst_n),

        .rob_commit_rd_arch_addr(rob_commit_rd_arch_addr),
        .rob_commit_curr_phy_addr(rob_commit_curr_phy_addr),
        .rob_commit(rob_commit),
        .rob_commit_reg_write(rob_reg_write)
    );

    // ROB
    ROB #(
        .ROB_DEPTH(ROB_DEPTH),
        .DMEM_WIDTH(DMEM_WIDTH),
        .DMEM_DEPTH(DMEM_DEPTH),
        .ARCH_REG_COUNT(ARCH_REG_COUNT),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH)
    ) rob (
        .clk(clk),
        .rst_n(rst_n),

        .dis_sw_rt_phy_addr(dis_sw_rt_phy_addr),
        .dis_inst_sw(dis_inst_sw),
        .dis_pre_phy_addr(dis_pre_phy_addr),
        .dis_new_phy_addr(dis_new_phy_addr),
        .dis_inst_valid(dis_inst_valid),
        .dis_rob_rd_arch_addr(dis_rob_rd_arch_addr),
        .dis_reg_write(dis_reg_write),

        .rob_bottom_ptr(rob_bottom_ptr),
        .rob_full(rob_full),
        .rob_two_or_more_vacant(rob_two_or_more_vacant),

        .cdb_valid(cdb_valid),
        .cdb_rob_tag(cdb_rob_tag),
        .cdb_sw_addr(cdb_sw_addr),
        .cdb_sw_data(cdb_sw_data),
        .cdb_flush(cdb_flush),

        .sb_full(sb_full),
        .rob_sw_addr(rob_sw_addr),
        .rob_sw_data(rob_sw_data),
        .rob_commit_mem_write(rob_commit_mem_write),

        .rob_top_ptr(rob_top_ptr),
        .rob_commit(rob_commit),

        .rob_commit_rd_arch_addr(rob_commit_rd_arch_addr),
        .rob_reg_write(rob_reg_write),
        .rob_commit_curr_phy_addr(rob_commit_curr_phy_addr),

        .rob_commit_pre_phy_addr(rob_commit_pre_phy_addr)
    );

    // SB
    SB #(
        .SB_DEPTH(SB_DEPTH),
        .DMEM_WIDTH(DMEM_WIDTH),
        .DMEM_DEPTH(DMEM_DEPTH)
    ) sb (
        .clk(clk),
        .rst_n(rst_n),

        .rob_sw_addr(rob_sw_addr),
        .rob_sw_data(rob_sw_data),
        .rob_commit_mem_write(rob_commit_mem_write),

        .dcache_valid(dcache_valid),
        .dcache_write_done(dcache_write_done),
        .dcache_sw_addr(dcache_sw_addr),
        .dcache_sw_data(dcache_sw_data),
        .dcache_ready(dcache_ready),

        .sb_flush_sw_tag(sb_flush_sw_tag),
        .sb_flush_sw(sb_flush_sw),
        .sb_entry_sw_tag(sb_entry_sw_tag),
        .sb_entry_sw_addr(sb_entry_sw_addr),

        .full(sb_full),
        .empty(sb_empty)
    );

    // RBA
    RBA #(
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .ARCH_REG_COUNT(ARCH_REG_COUNT)
    ) rba (
        .clk(clk),
        .rst_n(rst_n),

        .dis_rs_phy_addr(dis_rs_phy_addr),
        .dis_rt_phy_addr(dis_rt_phy_addr),
        .dis_new_rd_phy_addr(dis_rba_new_rd_phy_addr),
        .dis_reg_write(dis_reg_write),

        .rs_data_ready(dis_rs_data_ready),
        .rt_data_ready(dis_rt_data_ready),

        .rd_phy_addr(cdb_rd_phy_addr),
        .cdb_reg_write(cdb_reg_write)
    );

    assign rob_bottom_ptr_out          = rob_bottom_ptr;
    assign rob_top_ptr_out             = rob_top_ptr;
    assign rob_commit_mem_write_out    = rob_commit_mem_write;
    assign rob_commit_curr_phy_addr_out = rob_commit_curr_phy_addr;
endmodule
