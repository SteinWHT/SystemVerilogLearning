// Central RV64IM + Zicsr encoder / property table for the constrained-random
// generator and functional coverage. One source of truth for opcode/funct
// fields, instruction format, and operand usage so the stimulus, the IMEM
// image, and the Spike golden model always agree.
class cpu_isa_encoder;

    // ------------------------------------------------------------------
    // Static opcode constants (decoupled from RTL packages so the UVM side
    // can be compiled stand-alone).
    // ------------------------------------------------------------------
    localparam bit [6:0] OPC_REG     = 7'b0110011; // R-type RV64I/M
    localparam bit [6:0] OPC_REG_32  = 7'b0111011; // R-type word
    localparam bit [6:0] OPC_IMM     = 7'b0010011; // I-type ALU
    localparam bit [6:0] OPC_IMM_32  = 7'b0011011; // I-type word ALU
    localparam bit [6:0] OPC_LOAD    = 7'b0000011;
    localparam bit [6:0] OPC_STORE   = 7'b0100011;
    localparam bit [6:0] OPC_BRANCH  = 7'b1100011;
    localparam bit [6:0] OPC_JAL     = 7'b1101111;
    localparam bit [6:0] OPC_JALR    = 7'b1100111;
    localparam bit [6:0] OPC_LUI     = 7'b0110111;
    localparam bit [6:0] OPC_AUIPC   = 7'b0010111;
    localparam bit [6:0] OPC_SYSTEM  = 7'b1110011;

    localparam bit [6:0] F7_ZERO   = 7'b0000000;
    localparam bit [6:0] F7_ALT    = 7'b0100000;
    localparam bit [6:0] F7_MULDIV = 7'b0000001;

    // ------------------------------------------------------------------
    // Property lookups
    // ------------------------------------------------------------------
    static function automatic riscv_instr_format_e format_of(cpu_isa_op_e op);
        case (op)
            CPU_OP_ADD, CPU_OP_SUB, CPU_OP_SLL, CPU_OP_SLT, CPU_OP_SLTU,
            CPU_OP_XOR, CPU_OP_SRL, CPU_OP_SRA, CPU_OP_OR, CPU_OP_AND,
            CPU_OP_MUL, CPU_OP_MULH, CPU_OP_MULHSU, CPU_OP_MULHU,
            CPU_OP_DIV, CPU_OP_DIVU, CPU_OP_REM, CPU_OP_REMU,
            CPU_OP_ADDW, CPU_OP_SUBW, CPU_OP_SLLW, CPU_OP_SRLW, CPU_OP_SRAW,
            CPU_OP_MULW, CPU_OP_DIVW, CPU_OP_DIVUW, CPU_OP_REMW, CPU_OP_REMUW:
                return RISCV_FMT_R;
            CPU_OP_ADDI, CPU_OP_SLTI, CPU_OP_SLTIU, CPU_OP_XORI, CPU_OP_ORI,
            CPU_OP_ANDI, CPU_OP_SLLI, CPU_OP_SRLI, CPU_OP_SRAI,
            CPU_OP_ADDIW, CPU_OP_SLLIW, CPU_OP_SRLIW, CPU_OP_SRAIW,
            CPU_OP_LB, CPU_OP_LH, CPU_OP_LW, CPU_OP_LD,
            CPU_OP_LBU, CPU_OP_LHU, CPU_OP_LWU,
            CPU_OP_JALR,
            CPU_OP_CSRRW, CPU_OP_CSRRS, CPU_OP_CSRRC,
            CPU_OP_CSRRWI, CPU_OP_CSRRSI, CPU_OP_CSRRCI,
            CPU_OP_ECALL, CPU_OP_EBREAK, CPU_OP_MRET, CPU_OP_NOP:
                return RISCV_FMT_I;
            CPU_OP_SB, CPU_OP_SH, CPU_OP_SW, CPU_OP_SD:
                return RISCV_FMT_S;
            CPU_OP_BEQ, CPU_OP_BNE, CPU_OP_BLT, CPU_OP_BGE, CPU_OP_BLTU, CPU_OP_BGEU:
                return RISCV_FMT_B;
            CPU_OP_LUI, CPU_OP_AUIPC:
                return RISCV_FMT_U;
            CPU_OP_JAL:
                return RISCV_FMT_J;
            default:
                return RISCV_FMT_I;
        endcase
    endfunction

    static function automatic cpu_spike_instr_class_e class_of(cpu_isa_op_e op);
        case (op)
            CPU_OP_MUL, CPU_OP_MULH, CPU_OP_MULHSU, CPU_OP_MULHU, CPU_OP_MULW:
                return CPU_SPIKE_CLASS_MUL;
            CPU_OP_DIV, CPU_OP_DIVU, CPU_OP_REM, CPU_OP_REMU,
            CPU_OP_DIVW, CPU_OP_DIVUW, CPU_OP_REMW, CPU_OP_REMUW:
                return CPU_SPIKE_CLASS_DIV;
            CPU_OP_ADDW, CPU_OP_SUBW, CPU_OP_SLLW, CPU_OP_SRLW, CPU_OP_SRAW,
            CPU_OP_ADDIW, CPU_OP_SLLIW, CPU_OP_SRLIW, CPU_OP_SRAIW:
                return CPU_SPIKE_CLASS_WORD;
            CPU_OP_LB, CPU_OP_LH, CPU_OP_LW, CPU_OP_LD,
            CPU_OP_LBU, CPU_OP_LHU, CPU_OP_LWU:
                return CPU_SPIKE_CLASS_LOAD;
            CPU_OP_SB, CPU_OP_SH, CPU_OP_SW, CPU_OP_SD:
                return CPU_SPIKE_CLASS_STORE;
            CPU_OP_BEQ, CPU_OP_BNE, CPU_OP_BLT, CPU_OP_BGE, CPU_OP_BLTU, CPU_OP_BGEU:
                return CPU_SPIKE_CLASS_BRANCH;
            CPU_OP_JAL, CPU_OP_JALR:
                return CPU_SPIKE_CLASS_JUMP;
            CPU_OP_CSRRW, CPU_OP_CSRRS, CPU_OP_CSRRC,
            CPU_OP_CSRRWI, CPU_OP_CSRRSI, CPU_OP_CSRRCI,
            CPU_OP_ECALL, CPU_OP_EBREAK, CPU_OP_MRET:
                return CPU_SPIKE_CLASS_SYSTEM;
            default:
                return CPU_SPIKE_CLASS_ALU;
        endcase
    endfunction

    static function automatic bit writes_rd(cpu_isa_op_e op);
        case (op)
            CPU_OP_SB, CPU_OP_SH, CPU_OP_SW, CPU_OP_SD,
            CPU_OP_BEQ, CPU_OP_BNE, CPU_OP_BLT, CPU_OP_BGE, CPU_OP_BLTU, CPU_OP_BGEU,
            CPU_OP_ECALL, CPU_OP_EBREAK, CPU_OP_MRET, CPU_OP_NOP:
                return 1'b0;
            default:
                return 1'b1;
        endcase
    endfunction

    static function automatic bit reads_rs1(cpu_isa_op_e op);
        case (op)
            CPU_OP_LUI, CPU_OP_AUIPC, CPU_OP_JAL,
            CPU_OP_ECALL, CPU_OP_EBREAK, CPU_OP_MRET, CPU_OP_NOP,
            CPU_OP_CSRRWI, CPU_OP_CSRRSI, CPU_OP_CSRRCI:
                return 1'b0;
            default:
                return 1'b1;
        endcase
    endfunction

    static function automatic bit reads_rs2(cpu_isa_op_e op);
        return (format_of(op) == RISCV_FMT_R) ||
               (format_of(op) == RISCV_FMT_S) ||
               (format_of(op) == RISCV_FMT_B);
    endfunction

    static function automatic bit is_branch(cpu_isa_op_e op);
        return class_of(op) == CPU_SPIKE_CLASS_BRANCH;
    endfunction

    static function automatic bit is_load(cpu_isa_op_e op);
        return class_of(op) == CPU_SPIKE_CLASS_LOAD;
    endfunction

    static function automatic bit is_store(cpu_isa_op_e op);
        return class_of(op) == CPU_SPIKE_CLASS_STORE;
    endfunction

    // Access width in bytes for load/store ops (1/2/4/8).
    static function automatic int unsigned mem_bytes(cpu_isa_op_e op);
        case (op)
            CPU_OP_LB, CPU_OP_LBU, CPU_OP_SB: return 1;
            CPU_OP_LH, CPU_OP_LHU, CPU_OP_SH: return 2;
            CPU_OP_LW, CPU_OP_LWU, CPU_OP_SW: return 4;
            CPU_OP_LD, CPU_OP_SD:             return 8;
            default:                          return 0;
        endcase
    endfunction

    // ------------------------------------------------------------------
    // Field decode for a given op (opcode/funct3/funct7).
    // ------------------------------------------------------------------
    static function automatic void fields_of(
        input  cpu_isa_op_e op,
        output bit [6:0]    opcode,
        output bit [2:0]    funct3,
        output bit [6:0]    funct7
    );
        opcode = OPC_IMM; funct3 = 3'b000; funct7 = F7_ZERO;
        case (op)
            CPU_OP_ADD:    begin opcode=OPC_REG; funct3=3'b000; funct7=F7_ZERO;   end
            CPU_OP_SUB:    begin opcode=OPC_REG; funct3=3'b000; funct7=F7_ALT;    end
            CPU_OP_SLL:    begin opcode=OPC_REG; funct3=3'b001; funct7=F7_ZERO;   end
            CPU_OP_SLT:    begin opcode=OPC_REG; funct3=3'b010; funct7=F7_ZERO;   end
            CPU_OP_SLTU:   begin opcode=OPC_REG; funct3=3'b011; funct7=F7_ZERO;   end
            CPU_OP_XOR:    begin opcode=OPC_REG; funct3=3'b100; funct7=F7_ZERO;   end
            CPU_OP_SRL:    begin opcode=OPC_REG; funct3=3'b101; funct7=F7_ZERO;   end
            CPU_OP_SRA:    begin opcode=OPC_REG; funct3=3'b101; funct7=F7_ALT;    end
            CPU_OP_OR:     begin opcode=OPC_REG; funct3=3'b110; funct7=F7_ZERO;   end
            CPU_OP_AND:    begin opcode=OPC_REG; funct3=3'b111; funct7=F7_ZERO;   end
            CPU_OP_MUL:    begin opcode=OPC_REG; funct3=3'b000; funct7=F7_MULDIV; end
            CPU_OP_MULH:   begin opcode=OPC_REG; funct3=3'b001; funct7=F7_MULDIV; end
            CPU_OP_MULHSU: begin opcode=OPC_REG; funct3=3'b010; funct7=F7_MULDIV; end
            CPU_OP_MULHU:  begin opcode=OPC_REG; funct3=3'b011; funct7=F7_MULDIV; end
            CPU_OP_DIV:    begin opcode=OPC_REG; funct3=3'b100; funct7=F7_MULDIV; end
            CPU_OP_DIVU:   begin opcode=OPC_REG; funct3=3'b101; funct7=F7_MULDIV; end
            CPU_OP_REM:    begin opcode=OPC_REG; funct3=3'b110; funct7=F7_MULDIV; end
            CPU_OP_REMU:   begin opcode=OPC_REG; funct3=3'b111; funct7=F7_MULDIV; end

            CPU_OP_ADDW:   begin opcode=OPC_REG_32; funct3=3'b000; funct7=F7_ZERO;   end
            CPU_OP_SUBW:   begin opcode=OPC_REG_32; funct3=3'b000; funct7=F7_ALT;    end
            CPU_OP_SLLW:   begin opcode=OPC_REG_32; funct3=3'b001; funct7=F7_ZERO;   end
            CPU_OP_SRLW:   begin opcode=OPC_REG_32; funct3=3'b101; funct7=F7_ZERO;   end
            CPU_OP_SRAW:   begin opcode=OPC_REG_32; funct3=3'b101; funct7=F7_ALT;    end
            CPU_OP_MULW:   begin opcode=OPC_REG_32; funct3=3'b000; funct7=F7_MULDIV; end
            CPU_OP_DIVW:   begin opcode=OPC_REG_32; funct3=3'b100; funct7=F7_MULDIV; end
            CPU_OP_DIVUW:  begin opcode=OPC_REG_32; funct3=3'b101; funct7=F7_MULDIV; end
            CPU_OP_REMW:   begin opcode=OPC_REG_32; funct3=3'b110; funct7=F7_MULDIV; end
            CPU_OP_REMUW:  begin opcode=OPC_REG_32; funct3=3'b111; funct7=F7_MULDIV; end

            CPU_OP_ADDI:   begin opcode=OPC_IMM; funct3=3'b000; end
            CPU_OP_SLTI:   begin opcode=OPC_IMM; funct3=3'b010; end
            CPU_OP_SLTIU:  begin opcode=OPC_IMM; funct3=3'b011; end
            CPU_OP_XORI:   begin opcode=OPC_IMM; funct3=3'b100; end
            CPU_OP_ORI:    begin opcode=OPC_IMM; funct3=3'b110; end
            CPU_OP_ANDI:   begin opcode=OPC_IMM; funct3=3'b111; end
            CPU_OP_SLLI:   begin opcode=OPC_IMM; funct3=3'b001; funct7=F7_ZERO;   end
            CPU_OP_SRLI:   begin opcode=OPC_IMM; funct3=3'b101; funct7=F7_ZERO;   end
            CPU_OP_SRAI:   begin opcode=OPC_IMM; funct3=3'b101; funct7=F7_ALT;    end

            CPU_OP_ADDIW:  begin opcode=OPC_IMM_32; funct3=3'b000; end
            CPU_OP_SLLIW:  begin opcode=OPC_IMM_32; funct3=3'b001; funct7=F7_ZERO; end
            CPU_OP_SRLIW:  begin opcode=OPC_IMM_32; funct3=3'b101; funct7=F7_ZERO; end
            CPU_OP_SRAIW:  begin opcode=OPC_IMM_32; funct3=3'b101; funct7=F7_ALT;  end

            CPU_OP_LB:     begin opcode=OPC_LOAD; funct3=3'b000; end
            CPU_OP_LH:     begin opcode=OPC_LOAD; funct3=3'b001; end
            CPU_OP_LW:     begin opcode=OPC_LOAD; funct3=3'b010; end
            CPU_OP_LD:     begin opcode=OPC_LOAD; funct3=3'b011; end
            CPU_OP_LBU:    begin opcode=OPC_LOAD; funct3=3'b100; end
            CPU_OP_LHU:    begin opcode=OPC_LOAD; funct3=3'b101; end
            CPU_OP_LWU:    begin opcode=OPC_LOAD; funct3=3'b110; end

            CPU_OP_SB:     begin opcode=OPC_STORE; funct3=3'b000; end
            CPU_OP_SH:     begin opcode=OPC_STORE; funct3=3'b001; end
            CPU_OP_SW:     begin opcode=OPC_STORE; funct3=3'b010; end
            CPU_OP_SD:     begin opcode=OPC_STORE; funct3=3'b011; end

            CPU_OP_BEQ:    begin opcode=OPC_BRANCH; funct3=3'b000; end
            CPU_OP_BNE:    begin opcode=OPC_BRANCH; funct3=3'b001; end
            CPU_OP_BLT:    begin opcode=OPC_BRANCH; funct3=3'b100; end
            CPU_OP_BGE:    begin opcode=OPC_BRANCH; funct3=3'b101; end
            CPU_OP_BLTU:   begin opcode=OPC_BRANCH; funct3=3'b110; end
            CPU_OP_BGEU:   begin opcode=OPC_BRANCH; funct3=3'b111; end

            CPU_OP_JAL:    begin opcode=OPC_JAL;   funct3=3'b000; end
            CPU_OP_JALR:   begin opcode=OPC_JALR;  funct3=3'b000; end
            CPU_OP_LUI:    begin opcode=OPC_LUI;   funct3=3'b000; end
            CPU_OP_AUIPC:  begin opcode=OPC_AUIPC; funct3=3'b000; end

            CPU_OP_CSRRW:  begin opcode=OPC_SYSTEM; funct3=3'b001; end
            CPU_OP_CSRRS:  begin opcode=OPC_SYSTEM; funct3=3'b010; end
            CPU_OP_CSRRC:  begin opcode=OPC_SYSTEM; funct3=3'b011; end
            CPU_OP_CSRRWI: begin opcode=OPC_SYSTEM; funct3=3'b101; end
            CPU_OP_CSRRSI: begin opcode=OPC_SYSTEM; funct3=3'b110; end
            CPU_OP_CSRRCI: begin opcode=OPC_SYSTEM; funct3=3'b111; end
            CPU_OP_ECALL:  begin opcode=OPC_SYSTEM; funct3=3'b000; end
            CPU_OP_EBREAK: begin opcode=OPC_SYSTEM; funct3=3'b000; end
            CPU_OP_MRET:   begin opcode=OPC_SYSTEM; funct3=3'b000; end
            CPU_OP_NOP:    begin opcode=OPC_IMM;    funct3=3'b000; end
            default:       begin opcode=OPC_IMM;    funct3=3'b000; end
        endcase
    endfunction

    // ------------------------------------------------------------------
    // Encode a fully-resolved instruction. `imm` carries the architectural
    // immediate / branch-offset / CSR address. For shifts only the low bits
    // are used; for CSR-immediate forms `rs1` carries the 5-bit zimm.
    // ------------------------------------------------------------------
    static function automatic bit [31:0] encode(
        input cpu_isa_op_e op,
        input bit [4:0]    rd,
        input bit [4:0]    rs1,
        input bit [4:0]    rs2,
        input bit [63:0]   imm
    );
        bit [6:0] opcode;
        bit [2:0] funct3;
        bit [6:0] funct7;
        bit [31:0] imm32;
        riscv_instr_format_e fmt;

        fields_of(op, opcode, funct3, funct7);
        fmt   = format_of(op);
        imm32 = imm[31:0];

        // System / trap fixed encodings.
        case (op)
            CPU_OP_ECALL:  return {12'h000, 5'd0, 3'b000, 5'd0, opcode};
            CPU_OP_EBREAK: return {12'h001, 5'd0, 3'b000, 5'd0, opcode};
            CPU_OP_MRET:   return {12'h302, 5'd0, 3'b000, 5'd0, opcode};
            CPU_OP_NOP:    return 32'h0000_0013; // ADDI x0,x0,0
            default: ;
        endcase

        case (fmt)
            RISCV_FMT_R: return {funct7, rs2, rs1, funct3, rd, opcode};
            RISCV_FMT_I: begin
                // Shift-immediate ops pack funct7 (or funct6 for RV64) into imm[11:5].
                case (op)
                    CPU_OP_SLLI, CPU_OP_SRLI, CPU_OP_SRAI:
                        return {funct7[6:1], imm[5:0], rs1, funct3, rd, opcode};
                    CPU_OP_SLLIW, CPU_OP_SRLIW, CPU_OP_SRAIW:
                        return {funct7, imm[4:0], rs1, funct3, rd, opcode};
                    CPU_OP_CSRRW, CPU_OP_CSRRS, CPU_OP_CSRRC:
                        return {imm[11:0], rs1, funct3, rd, opcode};
                    CPU_OP_CSRRWI, CPU_OP_CSRRSI, CPU_OP_CSRRCI:
                        // rs1 carries the 5-bit zimm.
                        return {imm[11:0], rs1, funct3, rd, opcode};
                    default:
                        return {imm32[11:0], rs1, funct3, rd, opcode};
                endcase
            end
            RISCV_FMT_S: return {imm32[11:5], rs2, rs1, funct3, imm32[4:0], opcode};
            RISCV_FMT_B: return {imm32[12], imm32[10:5], rs2, rs1, funct3,
                                 imm32[4:1], imm32[11], opcode};
            RISCV_FMT_U: return {imm32[31:12], rd, opcode};
            RISCV_FMT_J: return {imm32[20], imm32[10:1], imm32[11],
                                 imm32[19:12], rd, opcode};
            default:     return 32'h0000_0013;
        endcase
    endfunction

endclass
