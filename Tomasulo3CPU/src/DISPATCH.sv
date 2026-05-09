// one-stage dispatch: takes instructions from IFQ and dispatches to reservation stations
// ARM64 compatible ISA
// First step: Only the front-end part will be completed and tested
// Second step: integrate the back-end into the total design
module DISPATCH #(
    parameter int unsigned INSTR_WIDTH = 64,
    parameter int unsigned IMEM_WIDTH = 64,
    parameter int unsigned ARCH_REG_COUNT = 32,
    parameter int unsigned ARCH_REG_WIDTH = $clog2(ARCH_REG_COUNT),
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned NUM_CHECKPOINT = 8,
    parameter int unsigned CHECKPOINT_PTR_WIDTH = $clog2(NUM_CHECKPOINT)
) (
    input  logic clk,
    input  logic rst_n,

    // IFQ interface
    input  logic [INSTR_WIDTH-1:0]      ifetch_instr_in,
    input  logic [IMEM_WIDTH-1:0]       ifetch_pcplus4_in,
    input  logic                        ifetch_empty_flag,

    output logic                        dis_ren,
    output logic                        dis_jmpbr,
    output logic [IMEM_WIDTH-1:0]       dis_jmpbr_addr,
    output logic                        dis_jmpbr_addr_valid,

    // BPB interface
    input  logic                        bpb_branch_prediction,

    output logic [2:0]                  dis_bpb_branch_pc_bits, // TODO: check the width
    output logic                        dis_bpb_branch,

    // RAS interface
    input  logic [IMEM_WIDTH-1:0]       ras_addr,

    output logic                        dis_ras_jr31_inst,
    output logic                        dis_ras_jal_inst,
    output logic [IMEM_WIDTH-1:0]       dis_pcplus4,

    // FRL interface
    input  logic                                    frl_empty,
    input  logic [PHY_REGISTER_FILE_WIDTH-1:0]      frl_rd_phy_addr,

    output logic                                    dis_frl_read,

    // CDB interface
    input  logic                        cdb_branch
    input  logic                        cdb_branch_outcome,
    input  logic [IMEM_WIDTH-1:0]       cdb_branch_addr,
    input  logic [2:0]                  cdb_br_updt_addr,
    input  logic                        cdb_flush,
    input  logic [4:0]                  cdb_rob_tag,

    // CFC interface
    input  logic                        cfc_full,




);
    // The decision-making logic
    // Interacts with IFQ, RAS, BPB, FRL, CFC
    // Stalls if:
    // ROB is full
    // desired IFQ is full
    // IFQ is empty (no more instructions to dispatch)
    // FRL is empty (no more free physical registers for renaming) && regwrite
    // CFC is full (no more checkpoints for branch instructions) && (is_branch or jr)
    // jr $rs1 ($rs1 != $31) until the value of $rs1 is ready in CDB
    // jr -> 1 bit flag register(jr_stall) + 5-bit internal register(jr_rob_tag) 
    // if jr_rob_tag is on the CDB and valid, then we can clear the jr_stall flag and proceed with dispatching the jr instruction
    



    // Execute logic
    // Interacts with CFC, Issue Queue, ROB, RBA
endmodule