// one-stage dispatch: takes instructions from IFQ and dispatches to reservation stations
// RISC-V 64 compatible ISA
// First step: Only the front-end part will be completed and tested
// Second step: integrate the back-end into the total design

// The very beginning version, this module will only have 1 stage
// I will further pipline it in the future according to the timing report

module DISPATCH #(
    parameter int unsigned XLEN = 64,
    parameter int unsigned IMEM_DEPTH = 64,
    parameter int unsigned IMEM_WIDTH = 32,
    parameter int unsigned DMEM_DEPTH = 64,
    parameter int unsigned DMEM_WIDTH = 64,
    parameter int unsigned ARCH_REG_COUNT = 32,
    parameter int unsigned ARCH_REG_WIDTH = $clog2(ARCH_REG_COUNT),
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned NUM_CHECKPOINT = 8,
    parameter int unsigned CHECKPOINT_PTR_WIDTH = $clog2(NUM_CHECKPOINT),
    parameter int unsigned ROB_DEPTH = 32,
    parameter int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH),
    parameter int unsigned BPB_PC_BITS = 3,
    parameter int unsigned ALU_OP_WIDTH = 5,
    parameter int unsigned MUL_OP_WIDTH = 2,
    parameter int unsigned DIV_OP_WIDTH = 2,
    parameter int unsigned LD_ST_OP_WIDTH = 2
) (
    input  logic clk,
    input  logic rst_n,

    // IFQ interface
    input  logic [IMEM_WIDTH-1:0]       ifetch_instr_in,
    input  logic [IMEM_DEPTH-1:0]       ifetch_pcplus4_in,
    input  logic                        ifetch_empty_flag,

    output logic                        dis_ren,
    output logic                        dis_jmpbr,
    output logic [IMEM_DEPTH-1:0]       dis_jmpbr_addr,
    output logic                        dis_jmpbr_addr_valid,

    // BPB interface
    input  logic                        bpb_branch_prediction,

    output logic [BPB_PC_BITS-1:0]      dis_bpb_branch_pc_bits,
    output logic                        dis_bpb_branch,

    // RAS interface
    input  logic [IMEM_DEPTH-1:0]       ras_addr,

    output logic                        dis_ras_jr31_inst,
    output logic                        dis_ras_jal_inst,
    // = ifetch_pcplus4_in
    // output logic [IMEM_DEPTH-1:0]       dis_pcplus4,

    // FRL interface
    input  logic                                    frl_empty,
    input  logic [PHY_REGISTER_FILE_WIDTH-1:0]      frl_rd_phy_addr,

    output logic                                    dis_frl_read,

    // CDB interface
    input  logic                        cdb_branch,
    input  logic                        cdb_branch_outcome,
    input  logic [IMEM_DEPTH-1:0]       cdb_branch_addr,
    input  logic [2:0]                  cdb_br_updt_addr,
    input  logic                        cdb_flush,
    input  logic [4:0]                  cdb_rob_tag,

    // FRAT interface
    input  logic                               frat_full,
    input  logic [PHY_REGISTER_FILE_WIDTH-1:0] frat_rs_phy_addr,
    input  logic [PHY_REGISTER_FILE_WIDTH-1:0] frat_rt_phy_addr,
    input  logic [PHY_REGISTER_FILE_WIDTH-1:0] frat_rd_phy_addr,

    // PRF
    input  logic prf_rs_data_ready,
    input  logic prf_rt_data_ready,
    
    output logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_new_rd_phy_addr,
    output logic dis_reg_write,

    // Issue Queue interface
    input logic                         issue_intq_full,
    input logic                         issue_divq_full,
    input logic                         issue_mulq_full,  
    input logic                         issue_ld_stq_full,
    input logic                         issue_intq_two_or_more_vacant,
    input logic                         issue_divq_two_or_more_vacant,
    input logic                         issue_mulq_two_or_more_vacant,
    input logic                         issue_ld_stq_two_or_more_vacant,

    // output logic dis_reg_write,
    output logic dis_rs_data_ready,
    output logic dis_rt_data_ready,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rs_phy_addr,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rt_phy_addr,
    // output logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_new_rd_phy_addr,
    output logic [15:0] dis_imm16,
    output logic [DMEM_WIDTH-1:0] dis_branch_other_addr,
    output logic dis_branch_prediction,
    output logic dis_branch,
    output logic [2:0] dis_branch_pc_bits,
    output logic dis_jr_inst,
    output logic dis_jal_inst,
    output logic dis_jr31_inst,

    output logic dis_int_issue_en,
    output logic dis_div_issue_en,
    output logic dis_mul_issue_en,
    output logic dis_ld_st_issue_en,

    // ROB interface
    input logic [ROB_INDEX_WIDTH-1:0] rob_bottom_ptr,
    input logic rob_full,
    input logic rob_two_or_more_vacant,

    output logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_pre_phy_addr,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_new_phy_addr,
    output logic [ARCH_REG_WIDTH-1:0] dis_rob_rd_arch_addr,
    // output logic dis_reg_write,
    output logic dis_inst_sw,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_sw_rt_phy_addr

);
// Get an instruction from IFQ (one instruction at a time in program order).
// Decode the instruction (R-Type, Lw/Sw, Div, Mul, Jump,…etc).
// Rename source and destination registers.
// The architectural source register IDs ($rs and $rt) are provided to FRAT and RRAT.
// The architectural destination register ID ($rd) is also provided to FRAT to find the 
// "old" mapping which can be freed when this instruction commits
// For register writing instructions, free register list (FRL) provides a free physical register 
// that will be mapped to the destination architectural register. 
// Dispatch will allocate one ROB entry and one instruction issue queue entry if needed. 
// For example, Jump instruction is executed in the dispatch and hence there is no need 
// for an ROB or issue queue allocation.
// Writes appropriate information (i.e. dispatches the instruction) to appropriate issue 
// queue and ROB entries
    RISC_V_DECODER #(
        .XLEN(XLEN),
        .INSTR_WIDTH(IMEM_WIDTH),
        .ARCH_REG_COUNT(ARCH_REG_COUNT),
        .ARCH_REG_WIDTH(ARCH_REG_WIDTH),
        .ALU_OP_WIDTH(ALU_OP_WIDTH),
        .MUL_OP_WIDTH(MUL_OP_WIDTH),
        .DIV_OP_WIDTH(DIV_OP_WIDTH),
        .LD_ST_OP_WIDTH(LD_ST_OP_WIDTH)
    ) decoder (
        .instr(ifetch_instr_in),
        .rd_arch_addr(dis_rob_rd_arch_addr),
        .rs_arch_addr(dis_rs_arch_addr),
        .rt_arch_addr(dis_rt_arch_addr),
        .imm(dis_imm),
        .alu_op(dis_alu_op),
        .mul_op(dis_mul_op),
        .div_op(dis_div_op),
        .ld_st_op(dis_ld_st_op),
        .rw(dis_rw),
        .mw(dis_mw),
        .branch(dis_branch),
        .jr_inst(dis_jr_inst),
        .jal_inst(dis_jal_inst),
        .jr31_inst(dis_jr31_inst)
    );



    // The decision-making logic
    // Interacts with IFQ, RAS, BPB, FRL, CFC
    // Stalls if:
    // ROB is full
    // desired IFQ is full
    // IFQ is empty (no more instructions to dispatch)
    // FRL is empty (no more free physical registers for renaming) && regwrite
    // FRAT is full (no more checkpoints for branch instructions) && (is_branch or jr)
    // jr $rs1 ($rs1 != $31) until the value of $rs1 is ready in CDB
    // jr -> 1 bit flag register(jr_stall) + 5-bit internal register(jr_rob_tag) 
    // if jr_rob_tag is on the CDB and valid, then we can clear the jr_stall flag and proceed with dispatching the jr instruction
    



    // Execute logic
    // Interacts with CFC, Issue Queue, ROB, RBA
endmodule