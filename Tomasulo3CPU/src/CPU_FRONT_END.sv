`timescale 1ns/1ps
module CPU_FRONT_END
    import riscv_types_pkg::*;
#(
    // I-CACHE
    parameter int unsigned INSTR_WIDTH = 32,
    parameter int unsigned IMEM_DEPTH = 64,
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
    parameter int unsigned W_BYTE_NUM = DMEM_WIDTH / 8,

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
    input logic                                 dcache_resp_valid,

    output logic [DMEM_DEPTH-1:0]               dcache_sw_addr,
    output logic [DMEM_WIDTH-1:0]               dcache_sw_data,
    output logic [W_BYTE_NUM-1:0]               dcache_sw_strb,
    output logic                                dcache_ready,
    output logic                                dcache_resp_ready,

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
    output logic [IMEM_DEPTH-1:0]               dis_pc,

    output logic                                dis_int_issue_en,
    output logic                                dis_div_issue_en,
    output logic                                dis_mul_issue_en,
    output logic                                dis_ld_st_issue_en,

    // CDB interface
    input logic                                 cdb_valid,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   cdb_rd_phy_addr,
    input logic                                 cdb_reg_write,
    input logic [ROB_INDEX_WIDTH-1:0]           cdb_rob_tag,
    input logic [DMEM_DEPTH-1:0]                cdb_sw_addr,
    input logic [W_BYTE_NUM-1:0]                cdb_sw_strb,
    input logic [IMEM_DEPTH-1:0]                cdb_branch_addr,
    input logic [BPB_PC_BITS-1:0]               cdb_br_updt_addr,
    input logic                                 cdb_branch,
    input logic                                 cdb_branch_outcome,
    input logic                                 cdb_flush,

    // PRF interface (store-data / CSR rs1 read)
    input  logic [DMEM_WIDTH-1:0]               rt_sb_data,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  rt_sb_phy_addr,

    // CSR write-back to PRF (new port from commit path)
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  csr_wr_phy_addr,
    output logic [REG_FILE_DATA_WIDTH-1:0]      csr_wr_data,
    output logic                                csr_wr_en,

    // SAB interface
    output logic [SB_INDEX_WIDTH-1:0]           sb_flush_sw_tag,
    output logic                                sb_flush_sw,
    output logic                                sb_entry_sw,
    output logic [SB_INDEX_WIDTH-1:0]           sb_entry_sw_tag,
    output logic [ROB_INDEX_WIDTH-1:0]          sb_entry_sw_rob_tag,

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
    logic [IMEM_DEPTH-1:0] ifq_pc;
    logic [IMEM_DEPTH-1:0] ifq_pc_plus4;

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

    // DISPATCH CSR/trap -> ROB
    logic dis_csr_inst;
    csr_cmd_e dis_csr_cmd;
    csr_addr_t dis_csr_addr;
    logic dis_trap_inst;
    trap_cause_t dis_trap_cause;
    logic dis_mret_inst;
    logic [ARCH_REG_WIDTH-1:0] dis_csr_rs1_arch_addr;

    // BPB interface
    logic bpb_branch_prediction;
    logic [BPB_PC_BITS-1:0] dis_bpb_branch_pc_bits;
    logic dis_bpb_branch;
    logic [BPB_PC_BITS-1:0] dis_cdb_upd_branch_addr;
    logic dis_cdb_branch_outcome;

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

    // ROB interface
    logic [ROB_INDEX_WIDTH-1:0] rob_bottom_ptr;
    logic rob_full;
    logic rob_two_or_more_vacant;
    logic [DMEM_DEPTH-1:0] rob_sw_addr;
    logic [W_BYTE_NUM-1:0] rob_sw_strb;
    logic rob_commit_mem_write;
    logic [ROB_INDEX_WIDTH-1:0] rob_top_ptr;
    logic rob_commit;
    logic [ARCH_REG_WIDTH-1:0] rob_commit_rd_arch_addr;
    logic rob_reg_write;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] rob_commit_curr_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] rob_commit_pre_phy_addr;
    logic rob_csr_committed;

    // ROB -> CSR interface
    logic csr_commit_valid;
    csr_addr_t csr_commit_addr;
    csr_cmd_e csr_commit_cmd;
    logic csr_commit_rs1_is_x0;
    logic [4:0] csr_commit_zimm;
    logic ecall_commit;
    logic ebreak_commit;
    logic mret_commit;
    logic [IMEM_DEPTH-1:0] trap_commit_pc;

    // CSR -> ROB results
    logic [REG_FILE_DATA_WIDTH-1:0] csr_rdata;
    logic csr_redirect_valid;
    logic [REG_FILE_DATA_WIDTH-1:0] csr_redirect_pc;

    // RRAT -> ROB: committed phy reg for CSR rs1 (read at commit time)
    logic [PHY_REGISTER_FILE_WIDTH-1:0] rrat_csr_rs1_phy;

    // ROB trap flush
    logic trap_commit_flush;
    logic [IMEM_DEPTH-1:0] trap_redirect_pc;

    // SB interface
    logic sb_full;

    // RBA
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rba_new_rd_phy_addr;

    // Combined flush: CDB branch mispredict OR trap commit flush
    logic combined_flush;
    logic [IMEM_DEPTH-1:0] combined_flush_addr;
    assign combined_flush = cdb_flush || trap_commit_flush;
    assign combined_flush_addr = trap_commit_flush ? trap_redirect_pc : cdb_branch_addr;

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

        .cdb_valid(cdb_valid || trap_commit_flush),
        .cdb_branch_addr(combined_flush_addr),
        .cdb_flush(combined_flush),

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
        .dis_branch_other_addr(dis_branch_other_addr),
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
        .rob_csr_committed(rob_csr_committed),
        .dis_pre_phy_addr(dis_pre_phy_addr),
        .dis_new_phy_addr(dis_new_phy_addr),
        .dis_rob_rd_arch_addr(dis_rob_rd_arch_addr),
        .dis_inst_valid(dis_inst_valid),
        .dis_pc(dis_pc),
        .dis_csr_inst(dis_csr_inst),
        .dis_csr_cmd(dis_csr_cmd),
        .dis_csr_addr(dis_csr_addr),
        .dis_trap_inst(dis_trap_inst),
        .dis_trap_cause(dis_trap_cause),
        .dis_mret_inst(dis_mret_inst),
        .dis_csr_rs1_arch_addr(dis_csr_rs1_arch_addr),
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

        .cdb_flush(combined_flush),

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
        .branch_mispredict(combined_flush),
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
        .rob_commit_reg_write(rob_reg_write),

        .csr_rs1_arch_addr(csr_commit_zimm),
        .csr_rs1_phy_addr(rrat_csr_rs1_phy)
    );

    // ROB
    ROB #(
        .ROB_DEPTH(ROB_DEPTH),
        .DMEM_WIDTH(DMEM_WIDTH),
        .DMEM_DEPTH(DMEM_DEPTH),
        .IMEM_DEPTH(IMEM_DEPTH),
        .REG_FILE_DATA_WIDTH(REG_FILE_DATA_WIDTH),
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
        .dis_pc(dis_pc),
        .dis_csr_inst(dis_csr_inst),
        .dis_csr_cmd(dis_csr_cmd),
        .dis_csr_addr(dis_csr_addr),
        .dis_trap_inst(dis_trap_inst),
        .dis_trap_cause(dis_trap_cause),
        .dis_mret_inst(dis_mret_inst),
        .dis_csr_rs1_arch_addr(dis_csr_rs1_arch_addr),

        .rrat_csr_rs1_phy(rrat_csr_rs1_phy),

        .rob_bottom_ptr(rob_bottom_ptr),
        .rob_full(rob_full),
        .rob_two_or_more_vacant(rob_two_or_more_vacant),

        .cdb_valid(cdb_valid),
        .cdb_rob_tag(cdb_rob_tag),
        .cdb_sw_addr(cdb_sw_addr),
        .cdb_sw_strb(cdb_sw_strb),
        .cdb_flush(cdb_flush),

        .rt_sb_phy_addr(rt_sb_phy_addr),

        .sb_full(sb_full),
        .rob_sw_addr(rob_sw_addr),
        .rob_sw_strb(rob_sw_strb),
        .rob_commit_mem_write(rob_commit_mem_write),

        .rob_top_ptr(rob_top_ptr),
        .rob_commit(rob_commit),

        .rob_commit_rd_arch_addr(rob_commit_rd_arch_addr),
        .rob_reg_write(rob_reg_write),
        .rob_commit_curr_phy_addr(rob_commit_curr_phy_addr),

        .rob_commit_pre_phy_addr(rob_commit_pre_phy_addr),
        .rob_csr_committed(rob_csr_committed),

        .csr_commit_valid(csr_commit_valid),
        .csr_commit_addr(csr_commit_addr),
        .csr_commit_cmd(csr_commit_cmd),
        .csr_commit_rs1_is_x0(csr_commit_rs1_is_x0),
        .csr_commit_zimm(csr_commit_zimm),
        .ecall_commit(ecall_commit),
        .ebreak_commit(ebreak_commit),
        .mret_commit(mret_commit),
        .trap_commit_pc(trap_commit_pc),

        .csr_rdata(csr_rdata),
        .csr_redirect_valid(csr_redirect_valid),
        .csr_redirect_pc(csr_redirect_pc),

        .csr_wr_phy_addr(csr_wr_phy_addr),
        .csr_wr_data(csr_wr_data),
        .csr_wr_en(csr_wr_en),

        .trap_commit_flush(trap_commit_flush),
        .trap_redirect_pc(trap_redirect_pc)
    );

    // CSR
    CSR #(
        .REG_FILE_WIDTH(REG_FILE_DATA_WIDTH)
    ) csr_unit (
        .clk(clk),
        .rst_n(rst_n),

        .csr_valid(csr_commit_valid),
        .csr_cmd(csr_commit_cmd),
        .csr_addr(csr_commit_addr),
        .csr_rs1_data(rt_sb_data),
        .csr_rs1_is_x0(csr_commit_rs1_is_x0),
        .csr_zimm(csr_commit_zimm),

        .csr_rdata(csr_rdata),
        .csr_result_valid(),
        .csr_illegal_access(),

        .ecall_valid(ecall_commit),
        .ebreak_valid(ebreak_commit),
        .mret_valid(mret_commit),
        .current_pc(REG_FILE_DATA_WIDTH'(trap_commit_pc)),
        .trap_value('0),

        .redirect_valid(csr_redirect_valid),
        .redirect_pc(csr_redirect_pc),

        .mstatus(),
        .mtvec(),
        .mscratch(),
        .mepc(),
        .mcause(),
        .mtval()
    );

    // SB
    SB #(
        .SB_DEPTH(SB_DEPTH),
        .DMEM_WIDTH(DMEM_WIDTH),
        .DMEM_DEPTH(DMEM_DEPTH),
        .ROB_DEPTH(ROB_DEPTH)
    ) sb (
        .clk(clk),
        .rst_n(rst_n),

        .rob_top_ptr(rob_top_ptr),
        .rob_sw_addr(rob_sw_addr),
        .rob_sw_strb(rob_sw_strb),
        .rob_commit_mem_write(rob_commit_mem_write),

        .rt_sb_data(rt_sb_data),

        .dcache_valid(dcache_valid),
        .dcache_resp_valid(dcache_resp_valid),
        .dcache_ready(dcache_ready),
        .dcache_resp_ready(dcache_resp_ready),
        .dcache_sw_addr(dcache_sw_addr),
        .dcache_sw_data(dcache_sw_data),
        .dcache_wstrb(dcache_sw_strb),

        .sb_flush_sw_tag(sb_flush_sw_tag),
        .sb_flush_sw(sb_flush_sw),
        .sb_entry_sw(sb_entry_sw),
        .sb_entry_sw_tag(sb_entry_sw_tag),
        .sb_entry_sw_rob_tag(sb_entry_sw_rob_tag),

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
        .cdb_reg_write(cdb_reg_write),

        .csr_wr_phy_addr(csr_wr_phy_addr),
        .csr_wr_en(csr_wr_en)
    );

    assign rob_bottom_ptr_out          = rob_bottom_ptr;
    assign rob_top_ptr_out             = rob_top_ptr;
    assign rob_commit_mem_write_out    = rob_commit_mem_write;
    assign rob_commit_curr_phy_addr_out = rob_commit_curr_phy_addr;
endmodule
