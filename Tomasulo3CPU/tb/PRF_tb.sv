`timescale 1ns/1ps

module PRF_tb;

    parameter int unsigned REG_FILE_DATA_WIDTH     = 64;
    parameter int unsigned ARCH_REG_COUNT          = 32;
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7;
    parameter int unsigned ROB_DEPTH                 = 16;
    parameter int unsigned SB_DEPTH                  = 4;
    parameter int unsigned SAB_DEPTH                 = 8;

    logic clk, rst_n;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] rt_sb_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0] rt_sb_data;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] cdb_rd_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0] cdb_rd_data;
    logic cdb_reg_write;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] issue_rs_phy_addr_alu, issue_rt_phy_addr_alu;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] issue_rs_phy_addr_div, issue_rt_phy_addr_div;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] issue_rs_phy_addr_mul, issue_rt_phy_addr_mul;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] issue_rs_phy_addr_lsq;
    logic [REG_FILE_DATA_WIDTH-1:0] issue_rs_data_lsq;
    logic [REG_FILE_DATA_WIDTH-1:0] exe_rs_data_alu, exe_rt_data_alu;
    logic [REG_FILE_DATA_WIDTH-1:0] exe_rs_data_div, exe_rt_data_div;
    logic [REG_FILE_DATA_WIDTH-1:0] exe_rs_data_mul, exe_rt_data_mul;

    PRF #(
        .REG_FILE_DATA_WIDTH(REG_FILE_DATA_WIDTH),
        .ARCH_REG_COUNT(ARCH_REG_COUNT),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .ROB_DEPTH(ROB_DEPTH),
        .SB_DEPTH(SB_DEPTH),
        .SAB_DEPTH(SAB_DEPTH)
    ) dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        rt_sb_phy_addr = 0;
        cdb_rd_phy_addr = 0;
        cdb_rd_data = 0;
        cdb_reg_write = 0;
        issue_rs_phy_addr_alu = 7'd1;
        issue_rt_phy_addr_alu = 7'd2;
        issue_rs_phy_addr_div = 0;
        issue_rt_phy_addr_div = 0;
        issue_rs_phy_addr_mul = 0;
        issue_rt_phy_addr_mul = 0;
        issue_rs_phy_addr_lsq = 0;

        rst_n = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;

        @(posedge clk);
        cdb_reg_write = 1;
        cdb_rd_phy_addr = 7'd1;
        cdb_rd_data = 64'hdeadbeef;
        @(posedge clk);
        cdb_reg_write = 0;

        issue_rs_phy_addr_alu = 7'd1;
        #1;
        if (exe_rs_data_alu !== 64'hdeadbeef) $fatal(1, "PRF read miss");

        $display("PRF_tb: pass");
        $finish;
    end

endmodule
