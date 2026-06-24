// Shared instruction metadata for stimulus items (UVM-side, decoupled from RTL packages).

typedef enum bit [2:0] {
    RISCV_FMT_R,
    RISCV_FMT_I,
    RISCV_FMT_S,
    RISCV_FMT_B,
    RISCV_FMT_U,
    RISCV_FMT_J
} riscv_instr_format_e;

typedef enum bit [4:0] {
    RISCV_OP_ADD,
    RISCV_OP_ADDW,
    RISCV_OP_SUB,
    RISCV_OP_SUBW,

    // Future expansion
    RISCV_OP_AND,
    RISCV_OP_OR,
    RISCV_OP_XOR,
    RISCV_OP_SLL,
    RISCV_OP_SRL,
    RISCV_OP_SRA,
    RISCV_OP_ADDI,
    RISCV_OP_LW,
    RISCV_OP_LD,
    RISCV_OP_SW,
    RISCV_OP_BEQ,
    RISCV_OP_JAL
} riscv_instr_name_e;

typedef enum int unsigned {
    CPU_SPIKE_CLASS_UNKNOWN = 0,
    CPU_SPIKE_CLASS_ALU,
    CPU_SPIKE_CLASS_LOAD,
    CPU_SPIKE_CLASS_STORE,
    CPU_SPIKE_CLASS_BRANCH,
    CPU_SPIKE_CLASS_JUMP,
    CPU_SPIKE_CLASS_MUL,
    CPU_SPIKE_CLASS_DIV,
    CPU_SPIKE_CLASS_WORD,
    CPU_SPIKE_CLASS_SYSTEM
} cpu_spike_instr_class_e;

// ---------------------------------------------------------------------------
// Full RV64IM + Zicsr opcode menu for the constrained-random generator.
// FENCE / FENCE.I are intentionally excluded (out of scope per the test plan).
// ---------------------------------------------------------------------------
typedef enum int unsigned {
    // RV64I R-type (OP_REG)
    CPU_OP_ADD, CPU_OP_SUB, CPU_OP_SLL, CPU_OP_SLT, CPU_OP_SLTU,
    CPU_OP_XOR, CPU_OP_SRL, CPU_OP_SRA, CPU_OP_OR,  CPU_OP_AND,
    // RV64M R-type (OP_REG, funct7=0000001)
    CPU_OP_MUL, CPU_OP_MULH, CPU_OP_MULHSU, CPU_OP_MULHU,
    CPU_OP_DIV, CPU_OP_DIVU, CPU_OP_REM, CPU_OP_REMU,
    // RV64I word R-type (OP_REG_32)
    CPU_OP_ADDW, CPU_OP_SUBW, CPU_OP_SLLW, CPU_OP_SRLW, CPU_OP_SRAW,
    // RV64M word R-type (OP_REG_32, funct7=0000001)
    CPU_OP_MULW, CPU_OP_DIVW, CPU_OP_DIVUW, CPU_OP_REMW, CPU_OP_REMUW,
    // RV64I I-type ALU (OP_IMM)
    CPU_OP_ADDI, CPU_OP_SLTI, CPU_OP_SLTIU, CPU_OP_XORI, CPU_OP_ORI,
    CPU_OP_ANDI, CPU_OP_SLLI, CPU_OP_SRLI, CPU_OP_SRAI,
    // RV64I word I-type ALU (OP_IMM_32)
    CPU_OP_ADDIW, CPU_OP_SLLIW, CPU_OP_SRLIW, CPU_OP_SRAIW,
    // Loads (OP_LOAD)
    CPU_OP_LB, CPU_OP_LH, CPU_OP_LW, CPU_OP_LD,
    CPU_OP_LBU, CPU_OP_LHU, CPU_OP_LWU,
    // Stores (OP_STORE)
    CPU_OP_SB, CPU_OP_SH, CPU_OP_SW, CPU_OP_SD,
    // Branches (OP_BRANCH)
    CPU_OP_BEQ, CPU_OP_BNE, CPU_OP_BLT, CPU_OP_BGE, CPU_OP_BLTU, CPU_OP_BGEU,
    // Jumps and upper-immediate
    CPU_OP_JAL, CPU_OP_JALR, CPU_OP_LUI, CPU_OP_AUIPC,
    // Zicsr (register and immediate forms)
    CPU_OP_CSRRW, CPU_OP_CSRRS, CPU_OP_CSRRC,
    CPU_OP_CSRRWI, CPU_OP_CSRRSI, CPU_OP_CSRRCI,
    // System / trap
    CPU_OP_ECALL, CPU_OP_EBREAK, CPU_OP_MRET,
    CPU_OP_NOP
} cpu_isa_op_e;

// High-level dependency category for hazard-aware generation and coverage.
typedef enum int unsigned {
    CPU_HAZ_NONE = 0,   // no enforced producer for this instruction
    CPU_HAZ_RAW,        // a source register reads a recent producer's rd
    CPU_HAZ_WAW,        // rd re-targets a recent producer's rd
    CPU_HAZ_LOAD_USE,   // a source register reads the immediately prior load
    CPU_HAZ_BRANCH      // emitted as part of a branch cluster
} cpu_hazard_kind_e;
