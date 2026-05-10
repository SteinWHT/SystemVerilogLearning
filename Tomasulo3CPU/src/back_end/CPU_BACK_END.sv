module CPU_BACK_END #(
    parameter int unsigned INSTR_WIDTH = 32,
    parameter int unsigned ARCH_REG_COUNT = 32,
    parameter int unsigned ARCH_REG_WIDTH = $clog2(ARCH_REG_COUNT),
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned DMEM_WIDTH = 32,
    parameter int unsigned ROB_DEPTH = 16,
    parameter int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH)
) (
    input logic clk,
    input logic rst_n,

    // D-CACHE interface

    // front-end interface
    // DISPATCH interface

    // ROB interface
    input logic [ROB_INDEX_WIDTH-1:0] rob_bottom_ptr,
    input logic rob_full,
    input logic rob_two_or_more_vacant,
    input logic [ROB_INDEX_WIDTH-1:0] rob_top_ptr,
    input logic rob_commit,
    input logic [ARCH_REG_WIDTH-1:0] rob_commit_rd_arch_addr,
    input logic rob_reg_write,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] rob_commit_curr_phy_addr,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] rob_commit_pre_phy_addr,
    input logic [DMEM_WIDTH-1:0] rob_sw_addr,
    input logic rob_commit_mem_write,
);

    // ISSUEQ
    ISSUEQ #(
        .INSTR_WIDTH(INSTR_WIDTH),
        .ISSUE_QUEUE_DEPTH(ISSUE_QUEUE_DEPTH),
        .ARCH_REG_WIDTH(ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .DMEM_WIDTH(DMEM_WIDTH),
        .ROB_DEPTH(ROB_DEPTH),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH)
    ) issueq (
        .clk(clk),
        .rst_n(rst_n),
        .cdb_flush(cdb_flush),
        .rob_bottom_ptr(rob_bottom_ptr),
        .cdb_rob_depth(cdb_rob_depth),
        .cdb_rd_phy_addr(cdb_rd_phy_addr),
        .cdb_phy_reg_write(cdb_phy_reg_write),
        .prf_rs_data_ready(prf_rs_data_ready),
        .prf_rt_data_ready(prf_rt_data_ready),
        .prf_rs_phy_addr(prf_rs_phy_addr),
        .prf_rt_phy_addr(prf_rt_phy_addr),
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
        .issue_int_en(issue_int_en),
        .issue_div_en(issue_div_en),
        .issue_mul_en(issue_mul_en),
        .issue_ld_st_en(issue_ld_st_en),
        .issue_int_rdy(issue_int_rdy),
        .issue_div_rdy(issue_div_rdy),
        .issue_mul_rdy(issue_mul_rdy),
        .issue_ld_st_rdy(issue_ld_st_rdy),
    )

    // ISSUEUNIT interface
    ISSUEUNIT #(
        .DIV_CYCLES(DIV_CYCLES),
        .MUL_CYCLES(MUL_CYCLES),
        .INT_CYCLES(INT_CYCLES),
        .LD_ST_CYCLES(LD_ST_CYCLES)
    ) issueunit (
        .clk(clk),
        .rst_n(rst_n),
    );

    // EXE interface
    EXE #(
        .INSTR_WIDTH(INSTR_WIDTH),
        .ARCH_REG_WIDTH(ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .DMEM_WIDTH(DMEM_WIDTH)
    ) exe (
        .clk(clk),
        .rst_n(rst_n),
    );

    // SAB interface
    // TODO:
    // SAB #(
    //     .INSTR_WIDTH(INSTR_WIDTH),
    //     .ARCH_REG_WIDTH(ARCH_REG_WIDTH),
    //     .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
    //     .DMEM_WIDTH(DMEM_WIDTH)
    // ) sab (
    //     .clk(clk),
    //     .rst_n(rst_n),
    // );

    // LSB
    // TODO:
    // LSB #(
    //     .INSTR_WIDTH(INSTR_WIDTH),
    //     .ARCH_REG_WIDTH(ARCH_REG_WIDTH),
    //     .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
    //     .DMEM_WIDTH(DMEM_WIDTH)
    // ) lsb (
    //     .clk(clk),
    //     .rst_n(rst_n),
    // );


endmodule