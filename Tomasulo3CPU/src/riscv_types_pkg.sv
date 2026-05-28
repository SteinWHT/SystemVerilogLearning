`ifndef RISCV_TYPES_PKG_SV
`define RISCV_TYPES_PKG_SV

package riscv_types_pkg;

    // ================================================================
    // Instruction format
    // ================================================================
    typedef enum logic [2:0] {
        FMT_R,
        FMT_I,
        FMT_S,
        FMT_B,
        FMT_U,
        FMT_J,
        FMT_SYS
    } instr_format_e;


    // ================================================================
    // All supported instructions
    // ================================================================
    typedef enum logic [6:0] {
        INSTR_ADD,
        INSTR_SUB,
        INSTR_SLL,
        INSTR_SLT,
        INSTR_SLTU,
        INSTR_XOR,
        INSTR_SRL,
        INSTR_SRA,
        INSTR_OR,
        INSTR_AND,
        INSTR_ADDI,
        INSTR_ADDIW,
        INSTR_SLTI,
        INSTR_SLTIU,
        INSTR_XORI,
        INSTR_ORI,
        INSTR_ANDI,
        INSTR_SLLI,
        INSTR_SRLI,
        INSTR_SRAI,
        INSTR_ADDW,
        INSTR_SUBW,
        INSTR_SLLW,
        INSTR_SRLW,
        INSTR_SRAW,
        INSTR_SLLIW,
        INSTR_SRLIW,
        INSTR_SRAIW,
        INSTR_MUL,
        INSTR_MULH,
        INSTR_MULHU,
        INSTR_MULHSU,
        INSTR_MULW,
        INSTR_DIV,
        INSTR_DIVU,
        INSTR_REM,
        INSTR_REMU,
        INSTR_DIVW,
        INSTR_DIVUW,
        INSTR_REMW,
        INSTR_REMUW,
        INSTR_LD,
        INSTR_LW,
        INSTR_LB,
        INSTR_LH,
        INSTR_LBU,
        INSTR_LHU,
        INSTR_LWU,
        INSTR_SD,
        INSTR_SW,
        INSTR_SB,
        INSTR_SH,
        INSTR_BEQ,
        INSTR_BNE,
        INSTR_BLT,
        INSTR_BGE,
        INSTR_BLTU,
        INSTR_BGEU,
        INSTR_JAL,
        INSTR_JALR,
        INSTR_LUI,
        INSTR_AUIPC,
        INSTR_ECALL,
        INSTR_EBREAK,
        INSTR_CSRRW,
        INSTR_CSRRS,
        INSTR_CSRRC,
        INSTR_CSRRWI,
        INSTR_CSRRSI,
        INSTR_CSRRCI,
        INSTR_MRET,
        INSTR_NONE
    } instr_e;

    // Align with the ISSUE_QUEUE.sv
    // ================================================================
    // ALU operation (decoded from opcode + funct3 + funct7)
    // ================================================================
    typedef enum logic [4:0] {
        ALU_ADD,
        ALU_SUB,
        ALU_SLL,
        ALU_SLT,
        ALU_SLTU,
        ALU_XOR,
        ALU_SRL,
        ALU_SRA,
        ALU_OR,
        ALU_AND,
        ALU_ADDI,
        ALU_SLTI,
        ALU_SLTIU,
        ALU_XORI,
        ALU_ORI,
        ALU_ANDI,
        ALU_SLLI,
        ALU_SRLI,
        ALU_SRAI,
        ALU_NONE
    } alu_op_e;

    typedef enum logic [2:0] {
        MUL_OP,
        MUL_H,
        MUL_HU,
        MUL_HSU,
        MUL_W,
        MUL_NONE
    } mul_op_e;

    typedef enum logic [3:0] {
        DIV_OP,
        DIV_U,
        REM_OP,
        REM_U,
        DIV_W,
        DIV_UW,
        REM_W,
        REM_UW,
        DIV_NONE
    } div_op_e;

    typedef enum logic [2:0] {
        LW,
        SW,
        LD_ST_NONE
    } ld_st_op_e;

    typedef enum logic [2:0] {
        CSR_CMD_NONE,
        CSR_CMD_RW,
        CSR_CMD_RS,
        CSR_CMD_RC,
        CSR_CMD_RWI,
        CSR_CMD_RSI,
        CSR_CMD_RCI
    } csr_cmd_e;

    typedef logic [11:0] csr_addr_t;

    localparam csr_addr_t CSR_ADDR_MSTATUS = 12'h300;
    localparam csr_addr_t CSR_ADDR_MTVEC   = 12'h305;
    localparam csr_addr_t CSR_ADDR_MSCRATCH = 12'h340;
    localparam csr_addr_t CSR_ADDR_MEPC    = 12'h341;
    localparam csr_addr_t CSR_ADDR_MCAUSE  = 12'h342;
    localparam csr_addr_t CSR_ADDR_MTVAL   = 12'h343;

    // Synchronous trap cause codes
    localparam int unsigned TRAP_CAUSE_WIDTH = 4;
    typedef logic [TRAP_CAUSE_WIDTH-1:0] trap_cause_t;
    localparam trap_cause_t TRAP_CAUSE_NONE    = 4'd0;
    localparam trap_cause_t TRAP_CAUSE_EBREAK  = 4'd3;
    localparam trap_cause_t TRAP_CAUSE_ECALL_M = 4'd11;
endpackage

`endif
