// One-stage ALU
module ALU 
import riscv_types_pkg::*;
#(
    parameter int unsigned XLEN = 64,
    parameter int unsigned INSTR_WIDTH = 32,
    parameter int unsigned OPCODE_WIDTH = 6,
    parameter int unsigned REG_FILE_DATA_WIDTH = 64,
    parameter int unsigned DMEM_WIDTH = 32,
    parameter int unsigned BPB_PC_BITS = 3,
    parameter int unsigned ROB_INDEX_WIDTH = 5,
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7
) (
    input logic clk,
    input logic rst_n,

    // PRF interface
    input logic [REG_FILE_DATA_WIDTH-1:0]           rs_data_alu,
    input logic [REG_FILE_DATA_WIDTH-1:0]           rt_data_alu,

    // ISSUEQ interface
    input logic [ROB_INDEX_WIDTH-1:0]               rob_tag,
    input logic [OPCODE_WIDTH-1:0]                  opcode,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]       rd_phy_addr,
    input logic                                     rw,
    input logic [15:0]                              imm16,
    input logic [DMEM_WIDTH-1:0]                    branch_other_addr,
    input logic                                     branch_prediction,
    input logic                                     branch,
    input logic                                     jr_inst,
    input logic                                     jr31_inst,
    input logic                                     jal_inst,
    input logic [BPB_PC_BITS-1:0]                   branch_pc_bits,
    input logic [15:0]                              imm_alu,
    input logic                                     valid,

    // CDB interface
    input logic [ROB_INDEX_WIDTH-1:0]               cdb_flush,

    output logic                                    exe_valid,
    output logic [ROB_INDEX_WIDTH-1:0]              exe_rob_tag,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]      exe_rd_phy_addr,
    output logic [REG_FILE_DATA_WIDTH-1:0]          exe_rd_data,
    output logic                                    exe_reg_write,
    output logic                                    exe_branch_mispredicted,
    output logic                                    exe_branch,
    output logic                                    exe_jr_inst,
    output logic                                    exe_jr31_inst,
    output logic                                    exe_jal_inst,
    output logic [BPB_PC_BITS-1:0]                  exe_branch_pc_bits,
    output logic [DMEM_WIDTH-1:0]                   exe_branch_other_addr

);
    logic [REG_FILE_DATA_WIDTH-1:0]     result_alu;
    logic [DMEM_WIDTH-1:0]              jr31_result;
    always_comb begin
        jr31_result = '0;
        result_alu = '0;
        unique case (opcode)
            INSTR_ADD:      result_alu = rs_data_alu + rt_data_alu;

            INSTR_SUB, INSTR_BEQ, INSTR_BNE:      result_alu = rs_data_alu - rt_data_alu;

            INSTR_SLL:      result_alu = rs_data_alu << rt_data_alu;
            INSTR_SLT:      result_alu = rs_data_alu < rt_data_alu;
            INSTR_SLTU:     result_alu = rs_data_alu < rt_data_alu;
            INSTR_XOR:      result_alu = rs_data_alu ^ rt_data_alu;
            INSTR_SRL:      result_alu = rs_data_alu >> rt_data_alu;
            INSTR_SRA:      result_alu = rs_data_alu >>> rt_data_alu;
            INSTR_OR:       result_alu = rs_data_alu | rt_data_alu;
            INSTR_AND:      result_alu = rs_data_alu & rt_data_alu;
            INSTR_ADDI:     result_alu = rs_data_alu + imm_alu;

            INSTR_JALR:     begin
                if(jr31_inst) begin
                    result_alu = rs_data_alu + imm16;
                    jr31_result = rs_data_alu - branch_other_addr;
                end else begin
                    result_alu = rs_data_alu + imm_alu;
                end
            end

            INSTR_SLTI:     result_alu = rs_data_alu < imm_alu;
            INSTR_SLTIU:    result_alu = rs_data_alu < imm_alu;
            INSTR_XORI:     result_alu = rs_data_alu ^ imm_alu;
            INSTR_ORI:      result_alu = rs_data_alu | imm_alu;
            INSTR_ANDI:     result_alu = rs_data_alu & imm_alu;
            INSTR_SLLI:     result_alu = rs_data_alu << imm_alu;
            INSTR_SRLI:     result_alu = rs_data_alu >> imm_alu;
            INSTR_SRAI:     result_alu = rs_data_alu >>> imm_alu;
            INSTR_NONE:     result_alu = '0;
            default   :     result_alu = '0;
        endcase
    end

    logic branch_mispredicted;
    always_comb begin
        branch_mispredicted = 1'b0;
        if (opcode == INSTR_BEQ) begin
            if (branch_prediction && (result_alu != 0)) begin
                branch_mispredicted = 1'b0;
            end else if (!branch_prediction && (result_alu == 0)) begin
                branch_mispredicted = 1'b0;
            end else begin
                branch_mispredicted = 1'b1;
            end
        end else if (opcode == INSTR_BNE) begin
            if (branch_prediction && (result_alu == 0)) begin
                branch_mispredicted = 1'b0;
            end else if (!branch_prediction && (result_alu != 0)) begin
                branch_mispredicted = 1'b0;
            end else begin
                branch_mispredicted = 1'b1;
            end
        end else if (opcode == INSTR_JALR) begin
            branch_mispredicted = jr31_result != 0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exe_valid               <= 1'b0;
            exe_rob_tag             <= '0;
            exe_rd_phy_addr         <= '0;
            exe_rd_data             <= '0;
            exe_reg_write           <= 1'b0;
            exe_branch_mispredicted <= 1'b0;
            exe_branch              <= 1'b0;
            exe_jr_inst             <= 1'b0;
            exe_jr31_inst           <= 1'b0;
            exe_jal_inst            <= 1'b0;
            exe_branch_pc_bits      <= '0;
            exe_branch_other_addr   <= '0;
        end else begin
            if (cdb_flush) begin
                exe_valid <= 1'b0;
            end else if (valid) begin
                exe_valid               <= valid;
                exe_rob_tag             <= rob_tag;
                exe_rd_phy_addr         <= rd_phy_addr;
                exe_rd_data             <= result_alu;
                exe_reg_write           <= rw;
                exe_branch_mispredicted <= branch_mispredicted;
                exe_branch              <= branch;
                exe_jr_inst             <= jr_inst;
                exe_jr31_inst           <= jr31_inst;
                exe_jal_inst            <= jal_inst;
                exe_branch_pc_bits      <= branch_pc_bits;
                exe_branch_other_addr   <= branch_other_addr;
            end else begin
                exe_valid <= 1'b0;
            end
        end
    end
endmodule
