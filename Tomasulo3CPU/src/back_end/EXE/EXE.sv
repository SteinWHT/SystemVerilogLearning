module EXE 
import riscv_types_pkg::*;
#(
    parameter int unsigned XLEN = 64,
    parameter int unsigned INSTR_WIDTH  = 32,
    parameter int unsigned OPCODE_WIDTH = 6,
    parameter int unsigned REG_FILE_DATA_WIDTH = 64,
    parameter int unsigned DMEM_WIDTH = 32,
    parameter int unsigned BPB_PC_BITS = 3,
    parameter int unsigned ROB_INDEX_WIDTH = 5,
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned ARCH_REG_COUNT = 32
) (
    input logic clk,
    input logic rst_n,

    // CDB interface
    input logic [ROB_INDEX_WIDTH-1:0]               cdb_rob_depth,
    
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
    output logic [DMEM_WIDTH-1:0]                   exe_branch_other_addr,
    
    // ISSUEQ interface 
    input logic [ROB_INDEX_WIDTH-1:0]               iss_rob_tag,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]       iss_rs_phy_addr,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]       iss_rt_phy_addr,
    input logic [OPCODE_WIDTH-1:0]                  iss_opcode,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]       iss_rd_phy_addr,
    input logic                                     iss_rw,
    input logic [15:0]                              iss_imm16,
    input logic [DMEM_WIDTH-1:0]                    iss_branch_other_addr,
    input logic                                     iss_branch_prediction,
    input logic                                     iss_branch,
    input logic                                     iss_jr_inst,
    input logic                                     iss_jr31_inst,
    input logic                                     iss_jal_inst,
    input logic [BPB_PC_BITS-1:0]                   iss_branch_pc_bits,

    input logic                                     issue_int_en,
    input logic                                     issue_div_en,
    input logic                                     issue_mul_en,

    // ISSUE UNIT interface
    output logic                                    div_exe_ready,
    
    // PRF interface
    input logic [REG_FILE_DATA_WIDTH-1:0]           exe_rs_data_alu,
    input logic [REG_FILE_DATA_WIDTH-1:0]           exe_rt_data_alu,
    input logic [REG_FILE_DATA_WIDTH-1:0]           exe_rs_data_div,
    input logic [REG_FILE_DATA_WIDTH-1:0]           exe_rt_data_div,
    input logic [REG_FILE_DATA_WIDTH-1:0]           exe_rs_data_mul,
    input logic [REG_FILE_DATA_WIDTH-1:0]           exe_rt_data_mul
);

    logic alu_exe_valid;
    logic alu_exe_rob_tag;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]      alu_exe_rd_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0]          alu_exe_rd_data;
    logic                                    alu_exe_reg_write;
    logic                                    alu_exe_branch_mispredicted;
    logic                                    alu_exe_branch;
    logic                                    alu_exe_jr_inst;
    logic                                    alu_exe_jr31_inst;
    logic                                    alu_exe_jal_inst;
    logic [BPB_PC_BITS-1:0]                  alu_exe_branch_pc_bits;
    logic [DMEM_WIDTH-1:0]                   alu_exe_branch_other_addr;

    logic div_exe_valid;
    logic [ROB_INDEX_WIDTH-1:0]              div_exe_rob_tag;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]      div_exe_rd_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0]          div_exe_rd_data;
    logic                                    div_exe_reg_write;
    logic                                    div_exe_result_valid;

    logic [ROB_INDEX_WIDTH-1:0]              mul_exe_rob_tag;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]      mul_exe_rd_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0]          mul_exe_rd_data;
    logic                                    mul_exe_reg_write;
    logic                                    mul_exe_result_valid;

    // one-stage ALU
    ALU #(
        .XLEN(XLEN),
        .INSTR_WIDTH(INSTR_WIDTH),
        .OPCODE_WIDTH(OPCODE_WIDTH),
        .REG_FILE_DATA_WIDTH(REG_FILE_DATA_WIDTH),
        .DMEM_WIDTH(DMEM_WIDTH),
        .BPB_PC_BITS(BPB_PC_BITS),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH)
    ) alu (
        .clk(clk),
        .rst_n(rst_n),

        .rs_data_alu(exe_rs_data_alu),
        .rt_data_alu(exe_rt_data_alu),

        .rob_tag(iss_rob_tag),
        .opcode(iss_opcode),
        .rd_phy_addr(iss_rd_phy_addr),
        .rw(iss_rw),
        .imm16(iss_imm16),
        .branch_other_addr(iss_branch_other_addr),
        .branch_prediction(iss_branch_prediction),
        .branch(iss_branch),
        .jr_inst(iss_jr_inst),
        .jr31_inst(iss_jr31_inst),
        .jal_inst(iss_jal_inst),
        .branch_pc_bits(iss_branch_pc_bits),
        .imm_alu(iss_imm16),
        .valid(issue_int_en),

        .cdb_flush(cdb_flush),

        .exe_valid(alu_exe_valid),
        .exe_rob_tag(alu_exe_rob_tag),
        .exe_rd_phy_addr(alu_exe_rd_phy_addr),
        .exe_rd_data(alu_exe_rd_data),
        .exe_reg_write(alu_exe_reg_write),
        .exe_branch_mispredicted(alu_exe_branch_mispredicted),
        .exe_branch(alu_exe_branch),
        .exe_jr_inst(alu_exe_jr_inst),
        .exe_jr31_inst(alu_exe_jr31_inst),
        .exe_jal_inst(alu_exe_jal_inst),
        .exe_branch_pc_bits(alu_exe_branch_pc_bits),
        .exe_branch_other_addr(alu_exe_branch_other_addr)
    );
    // seven-cycle DIV
    DIV #(
        .XLEN(XLEN),
        .INSTR_WIDTH(INSTR_WIDTH),
        .OPCODE_WIDTH(OPCODE_WIDTH),
        .REG_FILE_DATA_WIDTH(REG_FILE_DATA_WIDTH),
        .DMEM_WIDTH(DMEM_WIDTH),
        .BPB_PC_BITS(BPB_PC_BITS),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH)
    ) div (
        .clk(clk),
        .rst_n(rst_n),

        .rs_data_div(exe_rs_data_div),
        .rt_data_div(exe_rt_data_div),

        .rob_tag(iss_rob_tag),
        .opcode(iss_opcode),
        .rd_phy_addr(iss_rd_phy_addr),
        .valid(issue_div_en),

        .cdb_flush(cdb_flush),
        .cdb_rob_depth(cdb_rob_depth),
        .cdb_rob_tag(cdb_rob_tag),

        .exe_valid(div_exe_valid),
        .exe_rob_tag(div_exe_rob_tag),
        .exe_rd_phy_addr(div_exe_rd_phy_addr),
        .exe_rd_data(div_exe_rd_data),
        .exe_reg_write(div_exe_reg_write),
        .exe_result_valid(div_exe_result_valid)
    );
    // four-stage MUL
    MUL #(
        .XLEN(XLEN),
        .INSTR_WIDTH(INSTR_WIDTH),
        .OPCODE_WIDTH(OPCODE_WIDTH),
        .REG_FILE_DATA_WIDTH(REG_FILE_DATA_WIDTH),
        .DMEM_WIDTH(DMEM_WIDTH),
        .BPB_PC_BITS(BPB_PC_BITS),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH)
    ) mul (
        .clk(clk),
        .rst_n(rst_n),
        .rs_data_mul(exe_rs_data_mul),
        .rt_data_mul(exe_rt_data_mul),
        .rob_tag(iss_rob_tag),
        .opcode(iss_opcode),
        .rd_phy_addr(iss_rd_phy_addr),
        .valid(issue_mul_en),

        .cdb_flush(cdb_flush),
        .cdb_rob_depth(cdb_rob_depth),
        .cdb_rob_tag(cdb_rob_tag),

        .exe_valid(mul_exe_valid),
        .exe_rob_tag(mul_exe_rob_tag),
        .exe_rd_phy_addr(mul_exe_rd_phy_addr),
        .exe_rd_data(mul_exe_rd_data),
        .exe_reg_write(mul_exe_reg_write),
        .exe_result_valid(mul_exe_result_valid)
    );

    always_comb begin
        exe_valid = 1'b0;
        exe_rob_tag = '0;
        exe_rd_phy_addr = '0;
        exe_rd_data = '0;
        exe_reg_write = '0;
        exe_branch_mispredicted = '0;
        exe_branch = '0;
        exe_jr_inst = '0;
        exe_jr31_inst = '0;
        exe_jal_inst = '0;
        exe_branch_pc_bits = '0;
        exe_branch_other_addr = '0;

        if (alu_exe_valid) begin
            exe_valid = 1'b1;
            exe_rob_tag = alu_exe_rob_tag;
            exe_rd_phy_addr = alu_exe_rd_phy_addr;
            exe_rd_data = alu_exe_rd_data;
            exe_reg_write = alu_exe_reg_write;
            exe_branch_mispredicted = alu_exe_branch_mispredicted;
            exe_branch = alu_exe_branch;
            exe_jr_inst = alu_exe_jr_inst;
            exe_jr31_inst = alu_exe_jr31_inst;
            exe_jal_inst = alu_exe_jal_inst;
            exe_branch_pc_bits = alu_exe_branch_pc_bits;
            exe_branch_other_addr = alu_exe_branch_other_addr;
        end
        if (div_exe_valid) begin
            exe_valid = 1'b1;
            exe_rob_tag = div_exe_rob_tag;
            exe_rd_phy_addr = div_exe_rd_phy_addr;
            exe_rd_data = div_exe_rd_data;
            exe_reg_write = div_exe_reg_write;
        end
        if (mul_exe_valid) begin
            exe_valid = 1'b1;
            exe_rob_tag = mul_exe_rob_tag;
            exe_rd_phy_addr = mul_exe_rd_phy_addr;
            exe_rd_data = mul_exe_rd_data;
            exe_reg_write = mul_exe_reg_write;
        end
    end

    // synthesis translate_off
    EXE_COMPLETED_ASSERT: assert property (@(posedge clk) disable iff (!rst_n)
    !(alu_exe_valid && div_exe_valid && mul_exe_valid)) else 
        $error("ALU, DIV, or MUL completed execution at the same time");
    // synthesis translate_on
endmodule