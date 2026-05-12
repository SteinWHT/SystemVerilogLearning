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
        FMT_J
    } instr_format_e;


    // ================================================================
    // All supported instructions
    // ================================================================
    typedef enum logic [5:0] {
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
        INSTR_SLTI,
        INSTR_SLTIU,
        INSTR_XORI,
        INSTR_ORI,
        INSTR_ANDI,
        INSTR_SLLI,
        INSTR_SRLI,
        INSTR_SRAI,
        INSTR_MUL,
        INSTR_DIV,
        INSTR_REM,
        //INSTR_MULH,
        //INSTR_MULHU,
        //INSTR_DIVH,
        //INSTR_DIVHU,
        //INSTR_REMH,
        //INSTR_REMHU,
        INSTR_LW,
        INSTR_SW,
        //INSTR_LB,
        //INSTR_LH,
        //INSTR_LBU,
        //INSTR_LHU,
        //INSTR_LWU,
        //INSTR_SB,
        //INSTR_SH,
        //INSTR_SD,
        INSTR_BEQ,
        INSTR_BNE,
        //INSTR_BLT,
        //INSTR_BGE,
        //INSTR_BLTU,
        //INSTR_BGEU,
        INSTR_JAL,
        INSTR_JALR,
        //INSTR_LUI,
        //INSTR_AUIPC,
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
        MUL,
        MUL_H,
        MUL_HU,
        MUL_NONE
    } mul_op_e;

    typedef enum logic [2:0] {
        DIV,
        REM,
        // DIV_H,
        // DIV_HU,
        DIV_NONE
    } div_op_e;

    typedef enum logic [2:0] {
        LW,
        SW,
        LD_ST_NONE
    } ld_st_op_e;
endpackage

`endif
