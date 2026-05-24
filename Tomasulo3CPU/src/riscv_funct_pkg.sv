`ifndef RISCV_FUNCT_PKG_SV
`define RISCV_FUNCT_PKG_SV

package riscv_funct_pkg;

    // ================================================================
    // Funct3 — ALU (shared by R-type OP_REG, I-type OP_IMM,
    //               and their 32-bit variants OP_REG_32, OP_IMM_32)
    // ================================================================
    localparam logic [2:0] FUNCT3_ADD_SUB = 3'b000;
    localparam logic [2:0] FUNCT3_SLL     = 3'b001;
    localparam logic [2:0] FUNCT3_SLT     = 3'b010;
    localparam logic [2:0] FUNCT3_SLTU    = 3'b011;
    localparam logic [2:0] FUNCT3_XOR     = 3'b100;
    localparam logic [2:0] FUNCT3_SRL_SRA = 3'b101;
    localparam logic [2:0] FUNCT3_OR      = 3'b110;
    localparam logic [2:0] FUNCT3_AND     = 3'b111;

    // ================================================================
    // Funct3 — Load
    // ================================================================
    localparam logic [2:0] FUNCT3_LB  = 3'b000;
    localparam logic [2:0] FUNCT3_LH  = 3'b001;
    localparam logic [2:0] FUNCT3_LW  = 3'b010;
    localparam logic [2:0] FUNCT3_LD  = 3'b011;
    localparam logic [2:0] FUNCT3_LBU = 3'b100;
    localparam logic [2:0] FUNCT3_LHU = 3'b101;
    localparam logic [2:0] FUNCT3_LWU = 3'b110;

    // ================================================================
    // Funct3 — Store
    // ================================================================
    localparam logic [2:0] FUNCT3_SB = 3'b000;
    localparam logic [2:0] FUNCT3_SH = 3'b001;
    localparam logic [2:0] FUNCT3_SW = 3'b010;
    localparam logic [2:0] FUNCT3_SD = 3'b011;

    // ================================================================
    // Funct3 — Branch
    // ================================================================
    localparam logic [2:0] FUNCT3_BEQ  = 3'b000;
    localparam logic [2:0] FUNCT3_BNE  = 3'b001;
    localparam logic [2:0] FUNCT3_BLT  = 3'b100;
    localparam logic [2:0] FUNCT3_BGE  = 3'b101;
    localparam logic [2:0] FUNCT3_BLTU = 3'b110;
    localparam logic [2:0] FUNCT3_BGEU = 3'b111;

    // ================================================================
    // Funct3 — SYSTEM / CSR
    // ================================================================
    localparam logic [2:0] FUNCT3_PRIV   = 3'b000; // ECALL, EBREAK, xRET
    localparam logic [2:0] FUNCT3_CSRRW  = 3'b001;
    localparam logic [2:0] FUNCT3_CSRRS  = 3'b010;
    localparam logic [2:0] FUNCT3_CSRRC  = 3'b011;
    localparam logic [2:0] FUNCT3_CSRRWI = 3'b101;
    localparam logic [2:0] FUNCT3_CSRRSI = 3'b110;
    localparam logic [2:0] FUNCT3_CSRRCI = 3'b111;

    // ================================================================
    // Funct12 — SYSTEM privilege instructions
    // ================================================================
    localparam logic [11:0] FUNCT12_ECALL  = 12'h000;
    localparam logic [11:0] FUNCT12_EBREAK = 12'h001;
    localparam logic [11:0] FUNCT12_MRET   = 12'h302;

    // ================================================================
    // Funct7
    // ================================================================
    localparam logic [6:0] FUNCT7_ZERO   = 7'b0000000; // ADD, SLL, SLT, XOR, SRL, OR, AND ...
    localparam logic [6:0] FUNCT7_ALT    = 7'b0100000; // SUB, SRA, SRAI
    localparam logic [6:0] FUNCT7_MULDIV = 7'b0000001; // M-extension: MUL, DIV, REM ...
    localparam logic [6:0] FUNCT7_NOP    = 7'b1111111; // NOP only for test

endpackage

`endif
