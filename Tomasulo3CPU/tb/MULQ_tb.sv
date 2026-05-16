`timescale 1ns/1ps

module MULQ_tb;

    parameter int unsigned MUL_QUEUE_DEPTH           = 4;
    parameter int unsigned ROB_INDEX_WIDTH           = 5;
    parameter int unsigned PHY_REGISTER_FILE_WIDTH   = 7;

    logic clk, rst_n;
    logic cdb_flush;
    logic [ROB_INDEX_WIDTH-1:0] rob_top_ptr, cdb_rob_depth;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] cdb_rd_phy_addr;
    logic cdb_phy_reg_write;

    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rd_phy_addr_alu;
    logic iss_rd_reg_valid_alu;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] mul_rd_phy_addr, div_rd_phy_addr, ls_buf_rd_phy_addr;
    logic mul_exe_ready, div_exe_ready, ls_buf_buf_rd_write;

    logic [ROB_INDEX_WIDTH-1:0] iss_rob_tag_mul;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rs_phy_addr_mul, iss_rt_phy_addr_mul, iss_rd_phy_addr_mul;
    logic [2:0] iss_opcode_mul;
    logic iss_rw_mul;

    logic issue_mul_en;
    logic issue_mul_rdy, issue_mul;

    logic dis_mul_issq_en, dis_reg_write, dis_rs_data_ready, dis_rt_data_ready;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rs_phy_addr, dis_rt_phy_addr, dis_new_rd_phy_addr;
    logic [ROB_INDEX_WIDTH-1:0] dis_rob_tag;
    logic [2:0] dis_opcode;

    logic mulq_full, iss_mulq_two_or_more_vacant;

    MULQ #(
        .MUL_QUEUE_DEPTH(MUL_QUEUE_DEPTH),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH)
    ) dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        rst_n = 0;
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
        issue_mul_en = 0;
        dis_mul_issq_en = 0;
        dis_reg_write = 0;
        dis_rs_data_ready = 0;
        dis_rt_data_ready = 0;
        dis_rs_phy_addr = 0;
        dis_rt_phy_addr = 0;
        dis_new_rd_phy_addr = 0;
        dis_rob_tag = 0;
        dis_opcode = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        dis_mul_issq_en = 1;
        dis_rob_tag = 5'd2;
        dis_rs_phy_addr = 7'd4;
        dis_rt_phy_addr = 7'd5;
        dis_rs_data_ready = 1;
        dis_rt_data_ready = 1;
        dis_new_rd_phy_addr = 7'd11;
        dis_reg_write = 1;
        dis_opcode = 3'd2;
        @(posedge clk);
        dis_mul_issq_en = 0;

        if (!issue_mul_rdy) $fatal(1, "MULQ: not ready");
        issue_mul_en = 1;
        #1;
        if (!issue_mul || iss_rob_tag_mul !== 5'd2) $fatal(1, "MULQ issue");
        issue_mul_en = 0;
        @(posedge clk);
        $display("MULQ_tb: pass");
        $finish;
    end

endmodule
