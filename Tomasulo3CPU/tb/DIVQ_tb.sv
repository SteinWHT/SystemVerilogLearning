`timescale 1ns/1ps

module DIVQ_tb;

    parameter int unsigned DIV_QUEUE_DEPTH           = 4;
    parameter int unsigned INSTR_WIDTH               = 32;
    parameter int unsigned ROB_INDEX_WIDTH         = 5;
    parameter int unsigned ARCH_REG_WIDTH          = 5;
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7;
    parameter int unsigned DMEM_WIDTH                = 32;

    logic clk;
    logic rst_n;

    logic                               cdb_flush;
    logic [ROB_INDEX_WIDTH-1:0]         rob_top_ptr;
    logic [ROB_INDEX_WIDTH-1:0]         cdb_rob_depth;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] cdb_rd_phy_addr;
    logic                               cdb_phy_reg_write;

    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rd_phy_addr_alu;
    logic                               iss_rd_reg_valid_alu;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] mul_rd_phy_addr;
    logic                               mul_exe_ready;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] div_rd_phy_addr;
    logic                               div_exe_ready;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] ls_buf_rd_phy_addr;
    logic                               ls_buf_buf_rd_write;

    logic [ROB_INDEX_WIDTH-1:0]         iss_rob_tag_div;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rs_phy_addr_div;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rt_phy_addr_div;
    logic [2:0]                         iss_opcode_div;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rd_phy_addr_div;
    logic                               iss_rw_div;

    logic                               issue_div_en;
    logic                               issue_div_rdy;
    logic                               issue_div;

    logic                               dis_div_issq_en;
    logic                               dis_reg_write;
    logic                               dis_rs_data_ready;
    logic                               dis_rt_data_ready;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rs_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rt_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_new_rd_phy_addr;
    logic [ROB_INDEX_WIDTH-1:0]         dis_rob_tag;
    logic [2:0]                         dis_opcode;

    logic                               divq_full;
    logic                               iss_divq_two_or_more_vacant;

    DIVQ #(
        .DIV_QUEUE_DEPTH(DIV_QUEUE_DEPTH),
        .INSTR_WIDTH(INSTR_WIDTH),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .ARCH_REG_WIDTH(ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .DMEM_WIDTH(DMEM_WIDTH)
    ) dut (
        .*
    );

    initial clk = 0;
    always #5 clk = ~clk;

    task automatic clear_in();
        cdb_flush = 0;
        rob_top_ptr = 0;
        cdb_rob_depth = 0;
        cdb_rd_phy_addr = 0;
        cdb_phy_reg_write = 0;
        iss_rd_phy_addr_alu = 0;
        iss_rd_reg_valid_alu = 0;
        mul_rd_phy_addr = 0;
        mul_exe_ready = 0;
        div_rd_phy_addr = 0;
        div_exe_ready = 0;
        ls_buf_rd_phy_addr = 0;
        ls_buf_buf_rd_write = 0;
        issue_div_en = 0;
        dis_div_issq_en = 0;
        dis_reg_write = 0;
        dis_rs_data_ready = 0;
        dis_rt_data_ready = 0;
        dis_rs_phy_addr = 0;
        dis_rt_phy_addr = 0;
        dis_new_rd_phy_addr = 0;
        dis_rob_tag = 0;
        dis_opcode = 0;
    endtask

    initial begin
        rst_n = 0;
        clear_in();
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        dis_div_issq_en = 1;
        dis_rob_tag = 5'd1;
        dis_rs_phy_addr = 7'd2;
        dis_rt_phy_addr = 7'd3;
        dis_rs_data_ready = 1;
        dis_rt_data_ready = 1;
        dis_new_rd_phy_addr = 7'd10;
        dis_reg_write = 1;
        dis_opcode = 3'd1;
        @(posedge clk);
        dis_div_issq_en = 0;

        if (!issue_div_rdy) $fatal(1, "DIVQ: expected ready after dispatch");
        issue_div_en = 1;
        #1;
        if (!issue_div) $fatal(1, "DIVQ: expected issue with grant");
        if (iss_rob_tag_div !== 5'd1) $fatal(1, "DIVQ rob tag");
        issue_div_en = 0;
        @(posedge clk);

        $display("DIVQ_tb: pass");
        $finish;
    end

endmodule
