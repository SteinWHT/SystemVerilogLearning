// My IDE used now cannot directly include the packages, so I have to include them manually
`include "riscv_opcode_pkg.sv"
`include "riscv_funct_pkg.sv"
`include "riscv_types_pkg.sv"

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
    localparam int unsigned ARCH_REG_WIDTH = $clog2(ARCH_REG_COUNT),
    parameter int unsigned ALU_OP_WIDTH = 5,
    parameter int unsigned MUL_OP_WIDTH = 2,
    parameter int unsigned DIV_OP_WIDTH = 2,
    parameter int unsigned LD_ST_OP_WIDTH = 2
) (
    input  logic [INSTR_WIDTH-1:0] instr,

    output logic [4:0] rd_arch_addr,
    output logic [4:0] rs_arch_addr,
    output logic [4:0] rt_arch_addr,
    output logic [XLEN-1:0] imm,
    output logic [ALU_OP_WIDTH-1:0] alu_op,
    output logic [MUL_OP_WIDTH-1:0] mul_op,
    output logic [DIV_OP_WIDTH-1:0] div_op,
    output logic [LD_ST_OP_WIDTH-1:0] ld_st_op,
    output logic rw,
    output logic mw,
    output logic branch,
    output logic jr_inst,
    output logic jal_inst,
    output logic jr31_inst
);

    // Instruction field extraction
    logic [6:0] opcode;
    logic [4:0] rd, rs, rt;
    logic [2:0] funct3;
    logic [6:0] funct7;
    instr_e instr_type;

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
        alu_op = ALU_NONE;
        mul_op = MUL_NONE;
        div_op = DIV_NONE;
        ld_st_op = LD_ST_NONE;
        // optimized logic
        // TODO: is this useful or compiler will optimize it?
        // If directly assigning the output instead of using another instr_type variable, is it better?
        unique case (opcode)
            // R-type
            OP_REG: begin
                case (funct3)
                    FUNCT3_ADD_SUB: begin
                        unique case (funct7)
                            FUNCT7_ZERO:   begin instr_type = INSTR_ADD; alu_op = ALU_ADD; end
                            FUNCT7_ALT:    begin instr_type = INSTR_SUB; alu_op = ALU_SUB; end
                            FUNCT7_MULDIV: begin instr_type = INSTR_MUL; mul_op = MUL; end
                            default:       begin instr_type = INSTR_NONE; alu_op = ALU_NONE; end
                        endcase
                    end
                    FUNCT3_SLL:     begin instr_type = INSTR_SLL; alu_op = ALU_SLL; end
                    FUNCT3_SLT:     begin instr_type = INSTR_SLT; alu_op = ALU_SLT; end
                    FUNCT3_SLTU:    begin instr_type = INSTR_SLTU; alu_op = ALU_SLTU; end
                    FUNCT3_XOR: begin
                        unique case (funct7)
                            FUNCT7_ZERO: begin instr_type = INSTR_XOR; alu_op = ALU_XOR; end
                            FUNCT7_MULDIV:  begin instr_type = INSTR_DIV; div_op = DIV; end
                            default:     begin instr_type = INSTR_NONE; alu_op = ALU_NONE; end
                        endcase
                    end
                    FUNCT3_SRL_SRA: begin 
                        unique case (funct7)
                            FUNCT7_ZERO: begin instr_type = INSTR_SRL; alu_op = ALU_SRL; end
                            FUNCT7_ALT:  begin instr_type = INSTR_SRA; alu_op = ALU_SRA; end
                            default:     begin instr_type = INSTR_NONE; alu_op = ALU_NONE; end
                        endcase
                    end
                    FUNCT3_OR:  begin instr_type = INSTR_OR; alu_op = ALU_OR; end
                    FUNCT3_AND: begin
                        unique case (funct7)
                            FUNCT7_ZERO: begin instr_type = INSTR_AND; alu_op = ALU_AND; end
                            FUNCT7_MULDIV:  begin instr_type = INSTR_REM; div_op = REM; end
                            default:     begin instr_type = INSTR_NONE; alu_op = ALU_NONE; end
                        endcase
                    end
                    default:    begin instr_type = INSTR_NONE; alu_op = ALU_NONE; end
                endcase
            end

            // I-type
            OP_IMM: begin
                unique case (funct3)
                    FUNCT3_ADD_SUB: begin instr_type = INSTR_ADDI; alu_op = ALU_ADDI; end
                    FUNCT3_SLT:     begin instr_type = INSTR_SLTI; alu_op = ALU_SLTI; end
                    FUNCT3_SLTU:    begin instr_type = INSTR_SLTIU; alu_op = ALU_SLTIU; end
                    FUNCT3_XOR:     begin instr_type = INSTR_XORI; alu_op = ALU_XORI; end
                    FUNCT3_OR:      begin instr_type = INSTR_ORI; alu_op = ALU_ORI; end
                    FUNCT3_AND:     begin instr_type = INSTR_ANDI; alu_op = ALU_ANDI; end
                    FUNCT3_SLL:     begin instr_type = INSTR_SLLI; alu_op = ALU_SLLI; end
                    FUNCT3_SRL_SRA: begin
                        unique case (funct7)
                            FUNCT7_ZERO: begin instr_type = INSTR_SRLI; alu_op = ALU_SRLI; end
                            FUNCT7_ALT:  begin instr_type = INSTR_SRAI; alu_op = ALU_SRAI; end
                            default:     begin instr_type = INSTR_NONE; alu_op = ALU_NONE; end
                        endcase
                    end
                    default: begin instr_type = INSTR_NONE; alu_op = ALU_NONE; end
                endcase
            end

            // Load
            OP_LOAD: begin
                unique case (funct3)
                    // FUNCT3_LB:  ; // LB
                    // FUNCT3_LH:  ; // LH
                    FUNCT3_LW:  begin instr_type = INSTR_LW; ld_st_op = LW; end
                    // FUNCT3_LD:  ; // LD  (RV64)
                    // FUNCT3_LBU: ; // LBU
                    // FUNCT3_LHU: ; // LHU
                    // FUNCT3_LWU: ; // LWU (RV64)
                    default:    begin instr_type = INSTR_NONE; ld_st_op = LD_ST_NONE; end
                endcase
            end

            // Store
            OP_STORE: begin
                unique case (funct3)
                    //FUNCT3_SB: ; // SB
                    //FUNCT3_SH: ; // SH
                    FUNCT3_SW: begin instr_type = INSTR_SW; ld_st_op = SW; end
                    //FUNCT3_SD: ; // SD (RV64)
                    default:   begin instr_type = INSTR_NONE; ld_st_op = LD_ST_NONE; end
                endcase
            end

            // Branch
            OP_BRANCH: begin
                unique case (funct3)
                    FUNCT3_BEQ:  instr_type = INSTR_BEQ; // BEQ
                    FUNCT3_BNE:  instr_type = INSTR_BNE; // BNE
                    // FUNCT3_BLT:  ; // BLT
                    // FUNCT3_BGE:  ; // BGE
                    // FUNCT3_BLTU: ; // BLTU
                    // FUNCT3_BGEU: ; // BGEU
                    default:     instr_type = INSTR_NONE;
                endcase
            end

            // Jump
            OP_JAL:  instr_type = INSTR_JAL; // JAL
            OP_JALR: instr_type = INSTR_JALR; // JALR

            // Upper immediate
            // OP_LUI:   begin end // LUI
            // OP_AUIPC: begin end // AUIPC

            // Invalid / unsupported
            default: begin
                instr_type = INSTR_NONE;
            end
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
        case (instr_type)
            INSTR_ADD, INSTR_SUB, INSTR_SLT, INSTR_SLTU, INSTR_XOR, 
            INSTR_SRL, INSTR_SRA, INSTR_OR, INSTR_AND, INSTR_SLL,
            INSTR_MUL, INSTR_DIV, INSTR_REM,
            INSTR_ADDI, INSTR_SLTI, INSTR_SLTIU, INSTR_XORI, INSTR_ORI, INSTR_ANDI, 
            INSTR_SLLI, INSTR_SRLI, INSTR_SRAI: begin
                rw = 1;
                rd_arch_addr = rd;
                rs_arch_addr = rs;
                rt_arch_addr = rt;
                imm = imm_i;
            end
            INSTR_LW, INSTR_SW: begin
                rw = 1;
                mw = 1;
                rd_arch_addr = rd;
                rs_arch_addr = rs;
                rt_arch_addr = rt;
                imm = imm_i;
            end
            INSTR_BEQ, INSTR_BNE: begin
                branch = 1;
                rs_arch_addr = rs;
                rt_arch_addr = rt;
                imm = imm_b;
            end
            INSTR_JAL, INSTR_JALR: begin
                jal_inst = 1;
                rd_arch_addr = rd;
                imm = imm_j;
            end
            INSTR_JALR: begin
                jr_inst = 1;
                rs_arch_addr = rs;
                imm = imm_i;
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
