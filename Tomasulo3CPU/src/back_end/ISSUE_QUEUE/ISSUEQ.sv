module ISSUEQ #(
    parameter int unsigned INSTR_WIDTH = 32,
    parameter int unsigned ISSUE_QUEUE_DEPTH = 16,
    parameter int unsigned ARCH_REG_WIDTH = 5,
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned DMEM_WIDTH = 32,
    parameter int unsigned ROB_DEPTH = 16,
    parameter int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH)
) (
    input logic clk,
    input logic rst_n,

    // CDB interface
    input logic cdb_flush,
    input logic [ROB_INDEX_WIDTH-1:0] rob_bottom_ptr,
    input logic [ROB_INDEX_WIDTH-1:0] cdb_rob_depth,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] cdb_rd_phy_addr,
    input logic cdb_phy_reg_write,

    // PRF interface
    input logic prf_rs_data_ready,
    input logic prf_rt_data_ready,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] prf_rs_phy_addr,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] prf_rt_phy_addr,

    // DISPATCH interface
    input logic dis_int_issq_en,
    input logic dis_div_issq_en,
    input logic dis_mul_issq_en,
    input logic dis_ld_st_issq_en,
    input logic dis_reg_write,
    input logic dis_rs_data_ready,
    input logic dis_rt_data_ready,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rs_phy_addr,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rt_phy_addr,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_new_rd_phy_addr,
    input logic [ROB_INDEX_WIDTH-1:0] dis_rob_tag,
    input logic [2:0] dis_opcode,
    input logic [15:0] dis_imm16,
    input logic [DMEM_WIDTH-1:0] dis_branch_other_addr,
    input logic [2:0] dis_branch_pc_bits,
    input logic dis_branch_prediction,
    input logic dis_branch,
    input logic dis_jr_inst,
    input logic dis_jal_inst,
    
    output logic issq_intq_full,
    output logic issq_divq_full,
    output logic issq_mulq_full,
    output logic issq_ld_stq_full,
    output logic issq_intq_two_or_more_vacant,
    output logic issq_divq_two_or_more_vacant,
    output logic issq_mulq_two_or_more_vacant,
    output logic issq_ld_stq_two_or_more_vacant,

    // ISSUEUNIT interface
    input logic issue_int_en,
    input logic issue_div_en,
    input logic issue_mul_en,
    input logic issue_ld_st_en,

    output logic issue_int_rdy,
    output logic issue_div_rdy,
    output logic issue_mul_rdy,
    output logic issue_ld_st_rdy
);

    // INTQ
    INTQ #(
        .INT_QUEUE_DEPTH(ISSUE_QUEUE_DEPTH),
        .INSTR_WIDTH(INSTR_WIDTH),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .ARCH_REG_WIDTH(ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .DMEM_WIDTH(DMEM_WIDTH)
    ) intq (
        .clk(clk),
        .rst_n(rst_n),

        .cdb_flush(cdb_flush),
        .rob_bottom_ptr(rob_bottom_ptr),
        .cdb_rob_depth(cdb_rob_depth),
        .cdb_rd_phy_addr(cdb_rd_phy_addr),
        .cdb_phy_reg_write(cdb_phy_reg_write),

        .mul_rd_phy_addr(mul_rd_phy_addr),
        .mul_exe_ready(mul_exe_ready),
        .div_rd_phy_addr(div_rd_phy_addr),
        .div_exe_ready(div_exe_ready),
        .ls_buf_rd_phy_addr(ls_buf_rd_phy_addr),
        .ls_buf_buf_rd_write(ls_buf_buf_rd_write),

        .iss_reg_write_alu(iss_reg_write_alu),
        .iss_rd_phy_addr_alu(iss_rd_phy_addr_alu),
        .iss_rob_tag_alu(iss_rob_tag_alu),
        .iss_opcode_alu(iss_opcode_alu),
        .iss_imm16_alu(iss_imm16_alu),
        .iss_branch_other_addr_alu(iss_branch_other_addr_alu),
        .iss_branch_prediction_alu(iss_branch_prediction_alu),
        .iss_branch_alu(iss_branch_alu),
        .iss_branch_pc_bits_alu(iss_branch_pc_bits_alu),
        .iss_jr_inst_alu(iss_jr_inst_alu),
        .iss_jal_inst_alu(iss_jal_inst_alu),
        .iss_jr31_inst_alu(iss_jr31_inst_alu),

        .iss_rs_phy_addr_alu(iss_rs_phy_addr_alu),
        .iss_rt_phy_addr_alu(iss_rt_phy_addr_alu),

        .issue_int_en(issue_int_en),
        .issue_int_rdy(issue_int_rdy),
        .issue_int(issue_int),

        .dis_int_issq_en(dis_int_issq_en),
        .dis_div_issq_en(dis_div_issq_en),
        .dis_mul_issq_en(dis_mul_issq_en),
        .dis_ld_st_issq_en(dis_ld_st_issq_en),
        .dis_reg_write(dis_reg_write),
        .dis_rs_data_ready(dis_rs_data_ready),
        .dis_rt_data_ready(dis_rt_data_ready),
        .dis_rs_phy_addr(dis_rs_phy_addr),
        .dis_rt_phy_addr(dis_rt_phy_addr),
        .dis_new_rd_phy_addr(dis_new_rd_phy_addr),
        .dis_rob_tag(dis_rob_tag),
        .dis_opcode(dis_opcode),
        .dis_imm16(dis_imm16),
        .dis_branch_other_addr(dis_branch_other_addr),
        .dis_branch_prediction(dis_branch_prediction),
        .dis_branch(dis_branch),
        .dis_branch_pc_bits(dis_branch_pc_bits),
        .dis_jr_inst(dis_jr_inst),
        .dis_jal_inst(dis_jal_inst),
        .dis_jr31_inst(dis_jr31_inst),

        .iss_intq_full(issq_intq_full),
        .iss_intq_two_or_more_vacant(issq_intq_two_or_more_vacant),
    );

    // DIVQ
    DIVQ #(
        .DIV_QUEUE_DEPTH(ISSUE_QUEUE_DEPTH),
        .INSTR_WIDTH(INSTR_WIDTH),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .ARCH_REG_WIDTH(ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .DMEM_WIDTH(DMEM_WIDTH)
    ) divq (
        .clk(clk),
        .rst_n(rst_n),

        .cdb_flush(cdb_flush),
        .rob_bottom_ptr(rob_bottom_ptr),
        .cdb_rob_depth(cdb_rob_depth),
        .cdb_rd_phy_addr(cdb_rd_phy_addr),
        .cdb_phy_reg_write(cdb_phy_reg_write),

        .iss_rd_phy_addr_alu(iss_rd_phy_addr_alu),
        .iss_rd_reg_valid_alu(iss_rd_reg_valid_alu),
        .mul_rd_phy_addr(mul_rd_phy_addr),
        .mul_exe_ready(mul_exe_ready),
        .div_rd_phy_addr(div_rd_phy_addr),
        .div_exe_ready(div_exe_ready),
        .ls_buf_rd_phy_addr(ls_buf_rd_phy_addr),
        .ls_buf_buf_rd_write(ls_buf_buf_rd_write),

        .iss_reg_write_div(iss_reg_write_div),
        .iss_rd_phy_addr_div(iss_rd_phy_addr_div),
        .iss_rob_tag_div(iss_rob_tag_div),
        .iss_opcode_div(iss_opcode_div),

        .iss_rs_phy_addr_div(iss_rs_phy_addr_div),
        .iss_rt_phy_addr_div(iss_rt_phy_addr_div),

        .issue_div_en(issue_div_en),
        .issue_div_rdy(issue_div_rdy),
        .issue_div(issue_div),

        .dis_div_issq_en(dis_div_issq_en),
        .dis_mul_issq_en(dis_mul_issq_en),
        .dis_ld_st_issq_en(dis_ld_st_issq_en),
        .dis_reg_write(dis_reg_write),
        .dis_rs_data_ready(dis_rs_data_ready),
        .dis_rt_data_ready(dis_rt_data_ready),
        .dis_rs_phy_addr(dis_rs_phy_addr),
        .dis_rt_phy_addr(dis_rt_phy_addr),
        .dis_new_rd_phy_addr(dis_new_rd_phy_addr),
        .dis_rob_tag(dis_rob_tag),
        .dis_opcode(dis_opcode),

        .iss_divq_full(issq_divq_full),
        .iss_divq_two_or_more_vacant(issq_divq_two_or_more_vacant)
    );

    // MULQ
    MULQ #(
        .MUL_QUEUE_DEPTH(ISSUE_QUEUE_DEPTH),
        .INSTR_WIDTH(INSTR_WIDTH),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .ARCH_REG_WIDTH(ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .DMEM_WIDTH(DMEM_WIDTH)
    ) mulq (
        .clk(clk),
        .rst_n(rst_n),

        .cdb_flush(cdb_flush),
        .rob_bottom_ptr(rob_bottom_ptr),
        .cdb_rob_depth(cdb_rob_depth),
        .cdb_rd_phy_addr(cdb_rd_phy_addr),
        .cdb_phy_reg_write(cdb_phy_reg_write),

        .iss_rd_phy_addr_alu(iss_rd_phy_addr_alu),
        .iss_rd_reg_valid_alu(iss_rd_reg_valid_alu),
        .mul_rd_phy_addr(mul_rd_phy_addr),
        .mul_exe_ready(mul_exe_ready),
        .div_rd_phy_addr(div_rd_phy_addr),
        .div_exe_ready(div_exe_ready),
        .ls_buf_rd_phy_addr(ls_buf_rd_phy_addr),
        .ls_buf_buf_rd_write(ls_buf_buf_rd_write),

        .iss_reg_write_mul(iss_reg_write_mul),
        .iss_rd_phy_addr_mul(iss_rd_phy_addr_mul),
        .iss_rob_tag_mul(iss_rob_tag_mul),
        .iss_opcode_mul(iss_opcode_mul),

        .iss_rs_phy_addr_mul(iss_rs_phy_addr_mul),
        .iss_rt_phy_addr_mul(iss_rt_phy_addr_mul),

        .issue_mul_en(issue_mul_en),
        .issue_mul_rdy(issue_mul_rdy),
        .issue_mul(issue_mul),

        .dis_mul_issq_en(dis_mul_issq_en),
        .dis_ld_st_issq_en(dis_ld_st_issq_en),
        .dis_reg_write(dis_reg_write),
        .dis_rs_data_ready(dis_rs_data_ready),
        .dis_rt_data_ready(dis_rt_data_ready),
        .dis_rs_phy_addr(dis_rs_phy_addr),
        .dis_rt_phy_addr(dis_rt_phy_addr),
        .dis_new_rd_phy_addr(dis_new_rd_phy_addr),
        .dis_rob_tag(dis_rob_tag),
        .dis_opcode(dis_opcode),

        .iss_mulq_full(issq_mulq_full),
        .iss_mulq_two_or_more_vacant(issq_mulq_two_or_more_vacant)
    );

    // LD/STQ
    // TODO: implement LD/STQ
    // LDSTQ ldstq (
    //     .clk(clk),
    //     .rst_n(rst_n),
    //     .dis_ld_st_issq_en(dis_ld_st_issq_en),
    //     .dis_reg_write(dis_reg_write),
    // );

endmodule