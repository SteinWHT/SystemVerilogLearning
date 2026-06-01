// RISC-V instruction encoders for UVM stimulus (register setup, etc.).
class cpu_instr_encoder;

    static function automatic bit [31:0] i_type(
        input bit [11:0] imm,
        input bit [4:0]  rs1,
        input bit [2:0]  funct3,
        input bit [4:0]  rd,
        input bit [6:0]  opcode
    );
        return {imm, rs1, funct3, rd, opcode};
    endfunction

    static function automatic bit [31:0] addi(
        input bit [4:0]  rd,
        input bit [4:0]  rs1,
        input bit [11:0] imm
    );
        return i_type(imm, rs1, FUNCT3_ADD_SUB, rd, OP_IMM);
    endfunction

    static function automatic bit [31:0] addiw(
        input bit [4:0]  rd,
        input bit [4:0]  rs1,
        input bit [11:0] imm
    );
        return i_type(imm, rs1, FUNCT3_ADD_SUB, rd, OP_IMM_32);
    endfunction

    static function automatic bit [31:0] lui(
        input bit [4:0]  rd,
        input bit [19:0] imm20
    );
        return {imm20, rd, OP_LUI};
    endfunction

    static function automatic bit [31:0] ld(
        input bit [4:0]  rd,
        input bit [4:0]  rs1,
        input bit [11:0] offset
    );
        return i_type(offset, rs1, FUNCT3_LD, rd, OP_LOAD);
    endfunction

    static function automatic bit [31:0] sd(
        input bit [4:0]  rs2,
        input bit [4:0]  rs1,
        input bit [11:0] offset
    );
        return {offset[11:5], rs2, rs1, FUNCT3_SD, offset[4:0], OP_STORE};
    endfunction

    static function automatic bit fits_addi_imm(input bit [63:0] value);
        bit [63:0] sext12 = {{52{value[11]}}, value[11:0]};
        return sext12 == value;
    endfunction

    static function automatic bit fits_lui_addi(input bit [63:0] value);
        return value == {{32{value[31]}}, value[31:0]};
    endfunction

    static function automatic void lui_addi_parts(
        input  bit [63:0] value,
        output bit [19:0] hi20,
        output bit [11:0] lo12
    );
        bit [31:0] imm32;
        bit [31:0] hi;
        bit [31:0] lo;

        imm32 = value[31:0];
        hi    = (imm32 + 32'd2048) >> 12;
        lo    = imm32 - (hi << 12);
        hi20  = hi[19:0];
        lo12  = lo[11:0];
    endfunction

endclass
