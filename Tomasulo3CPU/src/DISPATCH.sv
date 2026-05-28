// one-stage dispatch: takes instructions from IFQ and dispatches to reservation stations
// RISC-V 64 compatible ISA
// First step: Only the front-end part will be completed and tested
// Second step: integrate the back-end into the total design

// The very beginning version, this module will only have 2 stages
// I will further pipline it in the future according to the timing report

// First stage: get instruction from IFQ, decode it, read from FRAT and FRL
// Second stage: write to ROB and issue queues

module DISPATCH
import riscv_opcode_pkg::*;
import riscv_funct_pkg::*;
import riscv_types_pkg::*;
#(
    parameter int unsigned XLEN = 64,
    parameter int unsigned INSTR_WIDTH = 32,
    parameter int unsigned IMEM_DEPTH = 64,
    parameter int unsigned IMEM_WIDTH = 32,
    parameter int unsigned IMEM_DEPTH_WORD = IMEM_DEPTH - 1,
    parameter int unsigned DMEM_DEPTH = 64,
    parameter int unsigned DMEM_WIDTH = 64,
    parameter int unsigned ARCH_REG_COUNT = 32,
    parameter int unsigned ARCH_REG_WIDTH = $clog2(ARCH_REG_COUNT),
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned ROB_DEPTH = 32,
    parameter int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH),
    parameter int unsigned BPB_PC_BITS = 3,
    parameter int unsigned OPCODE_WIDTH = 7
   ) (
    input  logic clk,
    input  logic rst_n,

    // IFQ interface
    input  logic [INSTR_WIDTH-1:0]                  ifetch_instr_in,
    input  logic [IMEM_DEPTH-1:0]                   ifetch_pcplus4_in,
    input  logic [IMEM_DEPTH-1:0]                   ifetch_pc,
    input  logic                                    ifetch_empty,

    output logic                                    dis_ren,
    output logic                                    dis_jmpbr,
    output logic [IMEM_DEPTH_WORD-1:0]              dis_jmpbr_addr,
    output logic                                    dis_jmpbr_addr_valid,

    // BPB interface
    // 1: taken, 0: not taken
    input  logic                                    bpb_branch_prediction,

    output logic [BPB_PC_BITS-1:0]                  dis_bpb_branch_pc_bits,
    output logic                                    dis_bpb_branch,

    // RAS interface
    input  logic [IMEM_DEPTH_WORD-1:0]              ras_addr,

    output logic                                    dis_ras_jr31_inst,
    output logic                                    dis_ras_jal_inst,
    // = ifetch_pcplus4_in
    output logic [IMEM_DEPTH-1:0]                   dis_pc_plus4,

    // FRL interface
    input  logic                                    dis_frl_empty,
    input  logic [PHY_REGISTER_FILE_WIDTH-1:0]      dis_frl_rd_phy_addr,

    output logic                                    dis_frl_read,

    // CDB interface
    input  logic                                    cdb_valid,
    input  logic [IMEM_DEPTH-1:0]                   cdb_branch_addr,
    input  logic                                    cdb_flush,

    // FRAT interface
    input  logic                                    frat_full,
    input  logic [PHY_REGISTER_FILE_WIDTH-1:0]      frat_rs_phy_addr,
    input  logic [PHY_REGISTER_FILE_WIDTH-1:0]      frat_rt_phy_addr,
    input  logic [PHY_REGISTER_FILE_WIDTH-1:0]      frat_rd_phy_addr,

    output logic [ARCH_REG_WIDTH-1:0]               dis_rs_arch_addr,
    output logic [ARCH_REG_WIDTH-1:0]               dis_rt_arch_addr,
    output logic [ARCH_REG_WIDTH-1:0]               dis_rd_arch_addr,

    // Issue Queue interface
    input logic                                     issue_intq_full,
    input logic                                     issue_divq_full,
    input logic                                     issue_mulq_full,
    input logic                                     issue_ld_stq_full,
    input logic                                     issue_intq_two_or_more_vacant,
    input logic                                     issue_divq_two_or_more_vacant,
    input logic                                     issue_mulq_two_or_more_vacant,
    input logic                                     issue_ld_stq_two_or_more_vacant,

    // output logic dis_reg_write,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]      dis_rs_phy_addr,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]      dis_rt_phy_addr,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]      dis_new_rd_phy_addr,
    output logic [OPCODE_WIDTH-1:0]                 dis_opcode,
    output logic [XLEN-1:0]                         dis_imm,
    output logic [IMEM_DEPTH-1:0]                   dis_branch_other_addr,
    output logic                                    dis_branch_prediction,
    output logic                                    dis_branch,
    output logic [BPB_PC_BITS-1:0]                  dis_branch_pc_bits,
    output logic                                    dis_jr_inst,
    output logic                                    dis_jal_inst,
    output logic                                    dis_jr31_inst,

    output logic                                    dis_int_issue_en,
    output logic                                    dis_div_issue_en,
    output logic                                    dis_mul_issue_en,
    output logic                                    dis_ld_st_issue_en,

    // ROB interface
    // input logic [ROB_INDEX_WIDTH-1:0]               rob_bottom_ptr,
    input logic                                     rob_full,
    input logic                                     rob_two_or_more_vacant,
    input logic                                     rob_csr_committed,

    output logic [PHY_REGISTER_FILE_WIDTH-1:0]      dis_pre_phy_addr,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]      dis_new_phy_addr,
    output logic [ARCH_REG_WIDTH-1:0]               dis_rob_rd_arch_addr,
    output logic                                    dis_inst_valid,
    output logic [IMEM_DEPTH-1:0]                   dis_pc,
    output logic                                    dis_csr_inst,
    output csr_cmd_e                                dis_csr_cmd,
    output csr_addr_t                               dis_csr_addr,
    output logic                                    dis_trap_inst,
    output trap_cause_t                             dis_trap_cause,
    output logic                                    dis_mret_inst,
    output logic [ARCH_REG_WIDTH-1:0]               dis_csr_rs1_arch_addr,
    // output logic dis_reg_write,
    output logic                                    dis_inst_sw,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]      dis_sw_rt_phy_addr,

    // RBA interface
    // output logic [PHY_REGISTER_FILE_WIDTH-1:0]      dis_rs_phy_addr,
    // output logic                                    dis_rt_phy_addr,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]      dis_rba_new_rd_phy_addr,
    output logic                                    dis_rba_reg_write

   );

    // ------------------------------------------------------
    // Stage 1: Decode and read from FRAT and FRL
    // ------------------------------------------------------
    logic [XLEN-1:0] stage1_dis_imm;
    logic stage1_dis_mem_write, stage1_dis_reg_write, stage1_dis_branch,
          stage1_dis_jr_inst, stage1_dis_jal_inst, stage1_dis_jr31_inst,
          stage1_dis_csr_inst, stage1_dis_trap_inst,
          stage1_dis_mret_inst;
    trap_cause_t stage1_dis_trap_cause;
    csr_cmd_e stage1_dis_csr_cmd;
    csr_addr_t stage1_dis_csr_addr;
    instr_e stage1_dis_instr_type;
    logic [ARCH_REG_WIDTH-1:0] stage1_rd_arch_addr;
    logic [ARCH_REG_WIDTH-1:0] stage1_rs_arch_addr;
    logic [ARCH_REG_WIDTH-1:0] stage1_rt_arch_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] stage1_rs_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] stage1_rt_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] stage1_pre_phy_addr;
    logic stage1_branch_taken;
    logic stage1_valid;
    logic stage1_reg_write;
    logic stage1_needs_issue_entry;
    logic stage1_issue_entry_available;
    logic stage1_dis_int_issue_en, stage1_dis_div_issue_en,
          stage1_dis_mul_issue_en, stage1_dis_ld_st_issue_en;
    logic stage1_dis_rob_only;
    // only stage1 will be stalled
    logic stall;
    // if last cycle ifq is empty, it means dispatch didn't fetch data.
    // it needs one extra cycle to have the data ready.
    logic ifq_wait_after_empty;

    // ------------------------------------------------------
    // Stage 2: write to ROB and issue queues
    // ------------------------------------------------------
    logic [XLEN-1:0] stage2_dis_imm;
    logic stage2_dis_mem_write, stage2_dis_reg_write, stage2_dis_branch,
          stage2_dis_jr_inst, stage2_dis_jal_inst, stage2_dis_jr31_inst,
          stage2_dis_csr_inst, stage2_dis_trap_inst,
          stage2_dis_mret_inst;
    trap_cause_t stage2_dis_trap_cause;
    csr_cmd_e stage2_dis_csr_cmd;
    csr_addr_t stage2_dis_csr_addr;
    instr_e stage2_dis_instr_type;
    logic [ARCH_REG_WIDTH-1:0] stage2_rd_arch_addr;
    logic [IMEM_DEPTH-1:0] stage2_pc_plus4, stage2_pc;
    logic stage2_valid;
    logic stage2_fire;
    logic stage2_dis_int_issue_en, stage2_dis_div_issue_en,
          stage2_dis_mul_issue_en, stage2_dis_ld_st_issue_en;
    logic stage2_branch_prediction;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] stage2_rs_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] stage2_rt_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] stage2_pre_phy_addr;
    logic [IMEM_DEPTH_WORD-1:0] stage2_ras_address;
    logic [ARCH_REG_WIDTH-1:0] stage2_rs_arch_addr;

    // jalr $rd, imm($rs)
    logic jr_stall;
    // csr stall
    logic csr_stall;
    // ------------------------------------------------------
    // Stage 1: Decode and read from FRAT and FRL
    // ------------------------------------------------------
    // Get an instruction from IFQ (one instruction at a time in program order).
    // Decode the instruction (R-Type, Lw/Sw, Div, Mul, Jump,…etc).
    RISC_V_DECODER #(
                   .XLEN(XLEN),
                   .INSTR_WIDTH(INSTR_WIDTH)
                 ) decoder (
                   .instr(ifetch_instr_in),
                   .enable(dis_ren),
                   .rd_arch_addr(stage1_rd_arch_addr),
                   .rs_arch_addr(stage1_rs_arch_addr),
                   .rt_arch_addr(stage1_rt_arch_addr),
                   .imm(stage1_dis_imm),
                   .instr_type(stage1_dis_instr_type),
                   .rw(stage1_dis_reg_write),
                   .mw(stage1_dis_mem_write),
                   .branch(stage1_dis_branch),
                   .jr_inst(stage1_dis_jr_inst),
                   .jal_inst(stage1_dis_jal_inst),
                   .jr31_inst(stage1_dis_jr31_inst),
                   .csr_inst(stage1_dis_csr_inst),
                   .csr_cmd(stage1_dis_csr_cmd),
                   .csr_addr(stage1_dis_csr_addr),
                   .trap_inst(stage1_dis_trap_inst),
                   .mret_inst(stage1_dis_mret_inst)
                 );

    always_comb begin
        unique case (stage1_dis_instr_type)
            INSTR_ECALL:  stage1_dis_trap_cause = TRAP_CAUSE_ECALL_M;
            INSTR_EBREAK: stage1_dis_trap_cause = TRAP_CAUSE_EBREAK;
            default:      stage1_dis_trap_cause = TRAP_CAUSE_NONE;
        endcase
    end
    assign stage1_valid = (!stall) && !cdb_flush && !ifq_wait_after_empty;
    assign stage1_reg_write = stage1_dis_reg_write && (stage1_rd_arch_addr != '0);
    assign stage1_needs_issue_entry = (stage1_dis_instr_type != INSTR_NONE) &&
                                      !stage1_dis_rob_only;
    assign stage1_issue_entry_available = stage1_dis_int_issue_en ||
            stage1_dis_div_issue_en ||
            stage1_dis_mul_issue_en ||
            stage1_dis_ld_st_issue_en;

    // BPB logic
    assign dis_bpb_branch_pc_bits = ifetch_pc[BPB_PC_BITS+1:2];
    assign dis_bpb_branch = stage1_dis_branch;

    // RAS logic
    assign dis_pc_plus4 = ifetch_pcplus4_in;
    assign dis_ras_jr31_inst = stage1_dis_jr31_inst && stage1_valid;
    assign dis_ras_jal_inst = stage1_dis_jal_inst && stage1_valid;

    // IFQ logic
    // We allow the jr and csr instruction to be passed through stage1
    // But block the ifq
    assign dis_ren = (!stall) && !cdb_flush;
    assign stage1_branch_taken = stage1_dis_branch && bpb_branch_prediction;
    // redirect logic
    logic [IMEM_DEPTH-1:0] jmpbr_byte_addr;
    always_comb begin
        dis_jmpbr = '0;
        dis_jmpbr_addr_valid = '0;
        dis_jmpbr_addr = '0;
        jmpbr_byte_addr = stage2_dis_imm + stage2_pc;
        if (cdb_flush && cdb_valid) begin
            dis_jmpbr = 1'b1;
            dis_jmpbr_addr_valid = 1'b1;
            dis_jmpbr_addr = cdb_branch_addr[IMEM_DEPTH-1:1];
        end else if (stage2_valid && stage2_dis_jr31_inst) begin
            dis_jmpbr = 1'b1;
            dis_jmpbr_addr_valid = 1'b1;
            dis_jmpbr_addr = ras_addr;
        end else if (stage2_valid && stage2_dis_jal_inst && !stage2_dis_jr_inst) begin
            dis_jmpbr = 1'b1;
            dis_jmpbr_addr_valid = 1'b1;
            dis_jmpbr_addr = jmpbr_byte_addr[IMEM_DEPTH-1:1];
        end else if (stage2_valid && stage2_dis_branch && stage2_branch_prediction) begin
            dis_jmpbr = 1'b1;
            dis_jmpbr_addr_valid = 1'b1;
            dis_jmpbr_addr = jmpbr_byte_addr[IMEM_DEPTH-1:1];
        end else if (jr_stall) begin
            dis_jmpbr = 1'b1;
        end
    end
    // Rename source and destination registers.
    // The architectural source register IDs ($rs and $rt) are provided to FRAT and RRAT.
    // For register writing instructions, free register list (FRL) provides a free physical register
    // that will be mapped to the destination architectural register.
    // FRL logic
    assign dis_rs_arch_addr = stage1_rs_arch_addr;
    assign dis_rt_arch_addr = stage1_rt_arch_addr;
    assign dis_frl_read = stage1_valid && stage1_reg_write;
    // The architectural destination register ID ($rd) is also provided to FRAT to find the
    // "old" mapping which can be freed when this instruction commits
    // FRAT logic
    assign dis_rd_arch_addr = stage1_rd_arch_addr;

    // jalr $rs1 ($rs1 != $31) until the value of $rs1 is ready in CDB
    // jr -> 1 bit flag register(jr_stall) + 5-bit internal register(jr_rob_tag)
    // if jr_rob_tag is on the CDB and valid, then we can clear the jr_stall flag and proceed with dispatching the jr instruction
    // CSR/trap/mret serialization: stall dispatch after dispatching one
    // until the ROB commits it. Cleared by rob_csr_committed or flush.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            jr_stall <= 1'b0;
            csr_stall <= 1'b0;
            end else begin
                if (cdb_valid && cdb_flush)
                    jr_stall <= 1'b0;
                else if ((stage1_valid && stage1_dis_jr_inst && !jr_stall))
                    jr_stall <= 1'b1;

                if (rob_csr_committed || (cdb_valid && cdb_flush))
                    csr_stall <= 1'b0;
                else if (stage1_valid && !csr_stall &&
                        (stage1_dis_csr_inst || stage1_dis_trap_inst || stage1_dis_mret_inst))
                    csr_stall <= 1'b1;
        end
    end

    always_comb begin
        stage1_dis_int_issue_en = 1'b0;
        stage1_dis_div_issue_en = 1'b0;
        stage1_dis_mul_issue_en = 1'b0;
        stage1_dis_ld_st_issue_en = 1'b0;
        stage1_dis_rob_only = 1'b0;

        unique case (stage1_dis_instr_type)
            INSTR_ADD, INSTR_SUB, INSTR_SLT, INSTR_SLTU, INSTR_XOR,
            INSTR_SRL, INSTR_SRA, INSTR_OR, INSTR_AND, INSTR_SLL,
            INSTR_ADDW, INSTR_SUBW, INSTR_SLLW, INSTR_SRLW, INSTR_SRAW,
            INSTR_ADDI, INSTR_SLTI, INSTR_SLTIU, INSTR_XORI, INSTR_ORI, INSTR_ANDI,
            INSTR_ADDIW, INSTR_SLLIW, INSTR_SRLIW, INSTR_SRAIW,
            INSTR_SLLI, INSTR_SRLI, INSTR_SRAI,
            INSTR_BEQ, INSTR_BNE, INSTR_BLT, INSTR_BLTU, INSTR_BGE, INSTR_BGEU,
            INSTR_JAL, INSTR_JALR, INSTR_LUI, INSTR_AUIPC: begin
                if (!issue_intq_full) begin
                    stage1_dis_int_issue_en = 1'b1;
                end
            end
            INSTR_MUL, INSTR_MULH, INSTR_MULHU, INSTR_MULHSU, INSTR_MULW: begin
                if (!issue_mulq_full) begin
                    stage1_dis_mul_issue_en = 1'b1;
                end
            end
            INSTR_DIV, INSTR_DIVU, INSTR_REM, INSTR_REMU,
            INSTR_DIVW, INSTR_DIVUW, INSTR_REMW, INSTR_REMUW: begin
                if (!issue_divq_full) begin
                    stage1_dis_div_issue_en = 1'b1;
                end
            end
            INSTR_LD, INSTR_LW, INSTR_LB, INSTR_LH, INSTR_LBU, INSTR_LHU, INSTR_LWU,
            INSTR_SD, INSTR_SW, INSTR_SB, INSTR_SH: begin
                 if (!issue_ld_stq_full) begin
                    stage1_dis_ld_st_issue_en = 1'b1;
                end
            end
            INSTR_CSRRW, INSTR_CSRRS, INSTR_CSRRC,
            INSTR_CSRRWI, INSTR_CSRRSI, INSTR_CSRRCI,
            INSTR_ECALL, INSTR_EBREAK, INSTR_MRET: begin
                stage1_dis_rob_only = 1'b1;
            end
            default: begin
                stage1_dis_int_issue_en = 1'b0;
                stage1_dis_div_issue_en = 1'b0;
                stage1_dis_mul_issue_en = 1'b0;
                stage1_dis_ld_st_issue_en = 1'b0;
                stage1_dis_rob_only = 1'b0;
            end
        endcase
    end

    // Stalls if:
    // ROB is full
    // The ROB has a single ROB entry AND the instruction in the 2nd dispatch stage is valid
    // (requires an ROB entry)
    // desired issue queue is full
    // The desired issue queue has a single entry AND the instruction in the 2nd stage is of
    // the same type and hence will be using that entry.
    // IFQ is empty (no more instructions to dispatch)
    // FRL is empty (no more free physical registers for renaming) && regwrite
    // FRAT is full (no more checkpoints for branch instructions) && (is_branch or jr)
    // if jr
    // if the instruction can be issued but the corresponding issue queue is full, we should also stall
    always_comb begin
        stall = '0;

        if(ifetch_empty) begin
           stall = 1'b1;
        end else if (rob_full) begin
            stall = 1'b1;
        // check when the second stage is non-valid
        end else if (!rob_two_or_more_vacant && stage2_valid) begin
            stall = 1'b1;
        end else if (frat_full && stage1_dis_branch) begin
            stall = 1'b1;
        end else if (dis_frl_empty && stage1_reg_write) begin
            stall = 1'b1;
        end else if (stage1_needs_issue_entry && !stage1_issue_entry_available) begin
            stall = 1'b1;
        end else if ((stage2_dis_int_issue_en && stage1_dis_int_issue_en &&
                !issue_intq_two_or_more_vacant) || (stage2_dis_int_issue_en &&
                issue_intq_full)) begin
            stall = 1'b1;
        end else if ((stage2_dis_div_issue_en && stage1_dis_div_issue_en &&
                !issue_divq_two_or_more_vacant) || (stage2_dis_div_issue_en &&
                issue_divq_full)) begin
            stall = 1'b1;
        end else if ((stage2_dis_mul_issue_en && stage1_dis_mul_issue_en &&
                !issue_mulq_two_or_more_vacant) || (stage2_dis_mul_issue_en &&
                issue_mulq_full)) begin
            stall = 1'b1;
        end else if ((stage2_dis_ld_st_issue_en && stage1_dis_ld_st_issue_en &&
                !issue_ld_stq_two_or_more_vacant) || (stage2_dis_ld_st_issue_en &&
                issue_ld_stq_full)) begin
            stall = 1'b1;
        end else if (dis_jmpbr) begin
            stall = 1'b1;
        end else if (csr_stall) begin
            stall = 1'b1;
        end
    end

    // Rename forwarding: FRAT updates on the clock edge after stage2 dispatch,
    // so the instruction in stage1 must see stage2's newly allocated physical
    // register directly when it reads the same architectural register.
    assign stage1_rs_phy_addr = (stage2_valid && stage2_dis_reg_write &&
                                 (stage2_rd_arch_addr == stage1_rs_arch_addr)) ?
                                dis_frl_rd_phy_addr : frat_rs_phy_addr;
    assign stage1_rt_phy_addr = (stage2_valid && stage2_dis_reg_write &&
                                 (stage2_rd_arch_addr == stage1_rt_arch_addr)) ?
                                dis_frl_rd_phy_addr : frat_rt_phy_addr;
    assign stage1_pre_phy_addr = (stage2_valid && stage2_dis_reg_write &&
                                  (stage2_rd_arch_addr == stage1_rd_arch_addr)) ?
                                 dis_frl_rd_phy_addr : frat_rd_phy_addr;

    // ------------------------------------------------------
    // Stage 1 to Stage 2 pipeline register
    // ------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // reset logic
            stage2_valid                <= 1'b0;
            stage2_dis_branch           <= '0;
            stage2_dis_jr_inst          <= '0;
            stage2_dis_jal_inst         <= '0;
            stage2_dis_jr31_inst        <= '0;

            stage2_dis_instr_type       <= INSTR_NONE;
            stage2_dis_imm              <= '0;
            stage2_dis_mem_write        <= '0;
            stage2_dis_reg_write        <= '0;
            stage2_rd_arch_addr         <= '0;

            stage2_pc_plus4             <= '0;
            stage2_pc                   <= '0;

            stage2_dis_int_issue_en     <= '0;
            stage2_dis_div_issue_en     <= '0;
            stage2_dis_mul_issue_en     <= '0;
            stage2_dis_ld_st_issue_en   <= '0;
            stage2_branch_prediction    <= '0;
            stage2_rs_phy_addr          <= '0;
            stage2_rt_phy_addr          <= '0;
            stage2_pre_phy_addr         <= '0;
            stage2_ras_address          <= '0;
            stage2_rs_arch_addr         <= '0;

            stage2_dis_csr_inst        <= '0;
            stage2_dis_csr_cmd         <= CSR_CMD_NONE;
            stage2_dis_csr_addr        <= '0;

            stage2_dis_trap_inst       <= '0;
            stage2_dis_trap_cause      <= TRAP_CAUSE_NONE;
            stage2_dis_mret_inst       <= '0;

            ifq_wait_after_empty       <= 1'b1;
        end else begin
            ifq_wait_after_empty        <= ifetch_empty;
            if (!stage1_valid) begin
                // On flush, we need to invalidate the instruction in stage 2
                stage2_valid                <= 1'b0;
                stage2_dis_int_issue_en     <= 1'b0;
                stage2_dis_div_issue_en     <= 1'b0;
                stage2_dis_mul_issue_en     <= 1'b0;
                stage2_dis_ld_st_issue_en   <= 1'b0;
                stage2_dis_reg_write        <= 1'b0;
            end else begin
                // pipeline register for stage 1 to stage 2
                stage2_valid                <= stage1_valid;
                stage2_dis_branch           <= stage1_dis_branch;
                stage2_dis_jr_inst          <= stage1_dis_jr_inst;
                stage2_dis_jal_inst         <= stage1_dis_jal_inst;
                stage2_dis_jr31_inst        <= stage1_dis_jr31_inst;

                stage2_dis_instr_type       <= stage1_dis_instr_type;
                stage2_dis_imm              <= stage1_dis_imm;
                stage2_dis_mem_write        <= stage1_dis_mem_write;
                stage2_dis_reg_write        <= stage1_reg_write;
                stage2_rd_arch_addr         <= stage1_rd_arch_addr;

                stage2_pc_plus4             <= dis_pc_plus4;
                stage2_pc                   <= ifetch_pc;

                stage2_dis_int_issue_en     <= stage1_dis_int_issue_en;
                stage2_dis_div_issue_en     <= stage1_dis_div_issue_en;
                stage2_dis_mul_issue_en     <= stage1_dis_mul_issue_en;
                stage2_dis_ld_st_issue_en   <= stage1_dis_ld_st_issue_en;

                stage2_branch_prediction    <= stage1_branch_taken;
                stage2_rs_phy_addr          <= stage1_rs_phy_addr;
                stage2_rt_phy_addr          <= stage1_rt_phy_addr;
                stage2_pre_phy_addr         <= stage1_pre_phy_addr;
                stage2_ras_address          <= ras_addr;
                stage2_rs_arch_addr         <= stage1_rs_arch_addr;

                stage2_dis_csr_inst         <= stage1_dis_csr_inst;
                stage2_dis_csr_cmd          <= stage1_dis_csr_cmd;
                stage2_dis_csr_addr         <= stage1_dis_csr_addr;
                stage2_dis_trap_inst        <= stage1_dis_trap_inst;
                stage2_dis_trap_cause       <= stage1_dis_trap_cause;
                stage2_dis_mret_inst        <= stage1_dis_mret_inst;
            end
        end
    end


    // ------------------------------------------------------
    // Stage 2: write to ROB and issue queues
    // ------------------------------------------------------
    // Allocate an ROB entry for this instruction and write necessary information to the ROB entry.
    // The allocated ROB entry will be marked as "not ready" and will be updated when
    // Dispatch will allocate one ROB entry and one instruction issue queue entry if needed.
    // For example, Jump instruction is executed in the dispatch and hence there is no need
    // for an ROB or issue queue allocation.
    // Writes appropriate information (i.e. dispatches the instruction) to appropriate issue
    // queue and ROB entries
    // ROB
    assign stage2_fire = stage2_valid && !cdb_flush;
    assign dis_pre_phy_addr = stage2_pre_phy_addr;
    assign dis_new_phy_addr = dis_frl_rd_phy_addr;
    assign dis_rob_rd_arch_addr = stage2_rd_arch_addr;
    assign dis_inst_valid = stage2_fire;
    assign dis_inst_sw = stage2_dis_mem_write;
    assign dis_sw_rt_phy_addr = stage2_rt_phy_addr;
    // ISSUE QUEUE
    assign dis_rs_phy_addr = stage2_rs_phy_addr;
    assign dis_rt_phy_addr = stage2_rt_phy_addr;
    assign dis_new_rd_phy_addr = dis_frl_rd_phy_addr;
    assign dis_opcode = stage2_dis_instr_type;
    assign dis_imm = stage2_dis_imm;
    assign dis_branch_other_addr = stage2_dis_jr31_inst ? {stage2_ras_address,1'b0} :
            stage2_branch_prediction ? stage2_pc_plus4 : stage2_pc + IMEM_DEPTH'(stage2_dis_imm);
    assign dis_branch_prediction = stage2_branch_prediction;
    assign dis_branch = stage2_dis_branch;
    assign dis_branch_pc_bits = stage2_pc[BPB_PC_BITS+1:2];
    assign dis_jr_inst = stage2_dis_jr_inst;
    assign dis_jal_inst = stage2_dis_jal_inst;
    assign dis_jr31_inst = stage2_dis_jr31_inst;
    assign dis_int_issue_en = stage2_fire && stage2_dis_int_issue_en;
    assign dis_div_issue_en = stage2_fire && stage2_dis_div_issue_en;
    assign dis_mul_issue_en = stage2_fire && stage2_dis_mul_issue_en;
    assign dis_ld_st_issue_en = stage2_fire && stage2_dis_ld_st_issue_en;
    // CSR / trap outputs to ROB
    assign dis_pc = stage2_pc;
    assign dis_csr_inst = stage2_dis_csr_inst;
    assign dis_csr_cmd = stage2_dis_csr_cmd;
    assign dis_csr_addr = stage2_dis_csr_addr;
    assign dis_trap_inst = stage2_dis_trap_inst;
    assign dis_trap_cause = stage2_dis_trap_cause;
    assign dis_mret_inst = stage2_dis_mret_inst;
    assign dis_csr_rs1_arch_addr = stage2_rs_arch_addr;
    // RBA
    assign dis_rba_new_rd_phy_addr = dis_frl_rd_phy_addr;
    assign dis_rba_reg_write = stage2_fire && stage2_dis_reg_write;
endmodule
