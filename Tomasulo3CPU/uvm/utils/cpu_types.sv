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
