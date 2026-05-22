// RISC-V 64 Decoder — template
// Combinational: outputs are not latched
// In the first version, we only support the basic instructions
// ADD, ADDI, SUB, AND , OR, SLT, MUL, DIV
// BNE, BEQ, J, JAL, JR (and JR $31)
// LW, SW
module RISC_V_DECODER
    import riscv_opcode_pkg::*;
    import riscv_funct_pkg::*;
    import riscv_types_pkg::*;
#(
    parameter int unsigned XLEN           = 64,
    parameter int unsigned INSTR_WIDTH    = 32,
    parameter int unsigned ARCH_REG_COUNT = 32,
    parameter int unsigned ARCH_REG_WIDTH = $clog2(ARCH_REG_COUNT)
) (
    input  logic [INSTR_WIDTH-1:0]      instr,

    output logic [ARCH_REG_WIDTH-1:0]   rd_arch_addr,
    output logic [ARCH_REG_WIDTH-1:0]   rs_arch_addr,
    output logic [ARCH_REG_WIDTH-1:0]   rt_arch_addr,
    output logic [XLEN-1:0]             imm,
    output instr_e                      instr_type,
    output logic                        rw,
    output logic                        mw,
    output logic                        branch,
    output logic                        jr_inst,
    output logic                        jal_inst,
    // In risc-v 64, using $1 or $5 as the jump target register is common.
    // I will modify the name later when starting realize more instructions.
    output logic                        jr31_inst
);

    // Instruction field extraction
    logic [6:0] opcode;
    logic [4:0] rd, rs, rt;
    logic [2:0] funct3;
    logic [6:0] funct7;

    assign opcode = instr[6:0];
    assign rd     = instr[11:7];
    assign funct3 = instr[14:12];
    assign rs    = instr[19:15];
    assign rt    = instr[24:20];
    assign funct7 = instr[31:25];

    // Immediate generation (sign-extended to XLEN)
    logic [XLEN-1:0] imm_i, imm_s, imm_b, imm_u, imm_j;

    assign imm_i = {{(XLEN-12){instr[31]}}, instr[31:20]};
    assign imm_s = {{(XLEN-12){instr[31]}}, instr[31:25], instr[11:7]};
    assign imm_b = {{(XLEN-13){instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    assign imm_u = {{(XLEN-32){instr[31]}}, instr[31:12], 12'b0};
    assign imm_j = {{(XLEN-21){instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};


    always_comb begin
        instr_type = INSTR_NONE;
        // optimized logic
        // TODO: is this useful or compiler will optimize it?
        // If directly assigning the output instead of using another instr_type variable, is it better?
        unique case (opcode)
            // R-type
            OP_REG: begin
                case (funct3)
                    FUNCT3_ADD_SUB: begin
                        unique case (funct7)
                            FUNCT7_ZERO:   instr_type = INSTR_ADD;
                            FUNCT7_ALT:    instr_type = INSTR_SUB;
                            FUNCT7_MULDIV: instr_type = INSTR_MUL;
                            default:       instr_type = INSTR_NONE;
                        endcase
                    end
                    FUNCT3_SLL:     instr_type = INSTR_SLL;
                    FUNCT3_SLT:     instr_type = INSTR_SLT;
                    FUNCT3_SLTU:    instr_type = INSTR_SLTU;
                    FUNCT3_XOR: begin
                        unique case (funct7)
                            FUNCT7_ZERO: instr_type = INSTR_XOR;
                            FUNCT7_MULDIV:  instr_type = INSTR_DIV;
                            default:     instr_type = INSTR_NONE;
                        endcase
                    end
                    FUNCT3_SRL_SRA: begin
                        unique case (funct7)
                            FUNCT7_ZERO: instr_type = INSTR_SRL;
                            FUNCT7_ALT:  instr_type = INSTR_SRA;
                            default:     instr_type = INSTR_NONE;
                        endcase
                    end
                    FUNCT3_OR:  instr_type = INSTR_OR;
                    FUNCT3_AND: begin
                        unique case (funct7)
                            FUNCT7_ZERO: instr_type = INSTR_AND;
                            FUNCT7_MULDIV:  instr_type = INSTR_REM;
                            default:     instr_type = INSTR_NONE;
                        endcase
                    end
                    default:    instr_type = INSTR_NONE;
                endcase
            end

            // I-type
            OP_IMM: begin
                unique case (funct3)
                    FUNCT3_ADD_SUB: instr_type = INSTR_ADDI;
                    FUNCT3_SLT:     instr_type = INSTR_SLTI;
                    FUNCT3_SLTU:    instr_type = INSTR_SLTIU;
                    FUNCT3_XOR:     instr_type = INSTR_XORI;
                    FUNCT3_OR:      instr_type = INSTR_ORI;
                    FUNCT3_AND:     instr_type = INSTR_ANDI;
                    FUNCT3_SLL:     instr_type = INSTR_SLLI;
                    FUNCT3_SRL_SRA: begin
                        unique case (funct7)
                            FUNCT7_ZERO: instr_type = INSTR_SRLI;
                            FUNCT7_ALT:  instr_type = INSTR_SRAI;
                            default:     instr_type = INSTR_NONE;
                        endcase
                    end
                    default: instr_type = INSTR_NONE;
                endcase
            end

            // Load
            OP_LOAD: begin
                unique case (funct3)
                    // FUNCT3_LB:  ; // LB
                    // FUNCT3_LH:  ; // LH
                    FUNCT3_LW:  instr_type = INSTR_LW;
                    FUNCT3_LD:  instr_type = INSTR_LD; // LD  (RV64)
                    // FUNCT3_LBU: ; // LBU
                    // FUNCT3_LHU: ; // LHU
                    // FUNCT3_LWU: ; // LWU (RV64)
                    default:    instr_type = INSTR_NONE;
                endcase
            end

            // Store
            OP_STORE: begin
                unique case (funct3)
                    FUNCT3_SB: instr_type = INSTR_SB;
                    FUNCT3_SH: instr_type = INSTR_SH;
                    FUNCT3_SW: instr_type = INSTR_SW;
                    FUNCT3_SD: instr_type = INSTR_SD;
                    default:   instr_type = INSTR_NONE;
                endcase
            end

            // Branch
            OP_BRANCH: begin
                unique case (funct3)
                    FUNCT3_BEQ: instr_type = INSTR_BEQ;
                    FUNCT3_BNE: instr_type = INSTR_BNE;
                    FUNCT3_BLT: instr_type = INSTR_BLT;
                    // FUNCT3_BGE: instr_type = INSTR_BGE;
                    FUNCT3_BLTU: instr_type = INSTR_BLTU;
                    // FUNCT3_BGEU: instr_type = INSTR_BGEU;
                    default:     instr_type = INSTR_NONE;
                endcase
            end

            // Jump
            OP_JAL:  instr_type = INSTR_JAL;
            OP_JALR: instr_type = INSTR_JALR;

            // Upper immediate
            OP_LUI:   instr_type = INSTR_LUI;
            OP_AUIPC: instr_type = INSTR_AUIPC;

            default: instr_type = INSTR_NONE;
        endcase
    end

    always_comb begin
        rw = 0;
        mw = 0;
        branch = 0;
        jr_inst = 0;
        jal_inst = 0;
        jr31_inst = 0;
        rd_arch_addr = 0;
        rs_arch_addr = 0;
        rt_arch_addr = 0;
        imm = 0;
        unique case (instr_type)
            INSTR_ADD, INSTR_SUB, INSTR_SLT, INSTR_SLTU, INSTR_XOR,
            INSTR_SRL, INSTR_SRA, INSTR_OR, INSTR_AND, INSTR_SLL,
            INSTR_MUL, INSTR_DIV, INSTR_REM,
            INSTR_ADDI, INSTR_SLTI, INSTR_SLTIU, INSTR_XORI, INSTR_ORI, INSTR_ANDI,
            INSTR_SLLI, INSTR_SRLI, INSTR_SRAI, INSTR_LW, INSTR_LD: begin
                rw = 1;
                rd_arch_addr = rd;
                rs_arch_addr = rs;
                rt_arch_addr = rt;
                imm = imm_i;
            end
            INSTR_SD, INSTR_SW, INSTR_SB, INSTR_SH: begin
                mw = 1;
                rs_arch_addr = rs;
                rt_arch_addr = rt;
                imm = imm_s;
            end
            INSTR_BEQ, INSTR_BNE, INSTR_BLT, INSTR_BLTU: begin
                branch = 1;
                rs_arch_addr = rs;
                rt_arch_addr = rt;
                imm = imm_b;
            end
            INSTR_JAL: begin
                jal_inst = 1;
                imm = imm_j;
                rw = 1;
                rd_arch_addr = rd;
            end
            INSTR_JALR: begin
                if (rs == 5'd1) begin
                    jr31_inst = 1;
                    imm = imm_i;
                    rw = 1;
                    rs_arch_addr = rs;
                    rd_arch_addr = rd;
                end else if (rd == 5'd0) begin
                    // This is a JR instruction (JALR with rd = x0)
                    jr_inst = 1;
                    rs_arch_addr = rs;
                    imm = imm_i;
                end else begin
                    jal_inst = 1;
                    jr_inst = 1;
                    rs_arch_addr = rs;
                    imm = imm_i;
                    rw = 1;
                    rd_arch_addr = rd;
                end
            end
            INSTR_LUI, INSTR_AUIPC: begin
                rw = 1;
                rd_arch_addr = rd;
                imm = imm_u;
            end
            default: begin
                rw = 0;
                mw = 0;
                branch = 0;
                jr_inst = 0;
                jal_inst = 0;
                jr31_inst = 0;
                rd_arch_addr = 0;
                rs_arch_addr = 0;
                rt_arch_addr = 0;
                imm = 0;
            end
        endcase
    end

endmodule
