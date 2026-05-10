module SB #(
    parameter int unsigned INSTR_WIDTH = 32,
    parameter int unsigned ARCH_REG_WIDTH = 5,
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned DMEM_WIDTH = 64,
    parameter int unsigned DMEM_DEPTH = 32,
    parameter int unsigned ROB_DEPTH = 32,
    parameter int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH)
) (
    input logic clk,
    input logic rst_n,

    // DISPATCH interface
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_sw_rt_phy_addr,
    input logic dis_inst_sw,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_pre_phy_addr,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_new_phy_addr,
    input logic dis_inst_valid,
    input logic [ARCH_REG_WIDTH-1:0] dis_rob_rd_arch_addr,
    input logic dis_reg_write
);


endmodule