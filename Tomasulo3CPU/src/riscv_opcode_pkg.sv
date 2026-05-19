`ifndef RISCV_OPCODE_PKG_SV
`define RISCV_OPCODE_PKG_SV

package riscv_opcode_pkg;

    typedef enum logic [6:0] {
        OP_LOAD     = 7'b0000011,
        OP_MISC_MEM = 7'b0001111, // FENCE
        OP_IMM      = 7'b0010011,
        OP_AUIPC    = 7'b0010111,
        OP_IMM_32   = 7'b0011011, // RV64: ADDIW, SLLIW, SRLIW, SRAIW
        OP_STORE    = 7'b0100011,
        OP_REG      = 7'b0110011,
        OP_LUI      = 7'b0110111,
        OP_REG_32   = 7'b0111011, // RV64: ADDW, SUBW, SLLW, SRLW, SRAW
        OP_BRANCH   = 7'b1100011,
        OP_JALR     = 7'b1100111,
        OP_JAL      = 7'b1101111,
        OP_SYSTEM   = 7'b1110011,
        OP_NOP      = 7'b1111111  // Only for test
    } opcode_e;

endpackage

`endif
