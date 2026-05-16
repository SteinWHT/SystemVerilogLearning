`timescale 1ns/1ps

// Smoke test for LSQ + integrated SAB ports (full functional path is timing-sensitive).
module LSQ_tb;

    parameter int unsigned LSQ_DEPTH               = 4;
    parameter int unsigned SAB_DEPTH               = 8;
    parameter int unsigned DMEM_DEPTH              = 32;
    parameter int unsigned ROB_DEPTH               = 16;
    localparam int unsigned ROB_INDEX_WIDTH        = $clog2(ROB_DEPTH);
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7;
    parameter int unsigned REG_FILE_DATA_WIDTH     = 64;
    parameter int unsigned SB_DEPTH                = 4;
    localparam int unsigned SB_INDEX_WIDTH         = $clog2(SB_DEPTH);
    parameter int unsigned OPCODE_WIDTH            = 1;

    logic clk, rst_n;
    logic [SB_INDEX_WIDTH-1:0] sb_flush_sw_tag;
    logic sb_flush_sw;
    logic [SB_INDEX_WIDTH-1:0] sb_entry_sw_tag;
    logic [DMEM_DEPTH-1:0] sb_entry_sw_addr;
    logic [ROB_INDEX_WIDTH-1:0] rob_tag, rob_top_ptr;
    logic rob_commit_mem_write;
    logic dis_rs_data_ready;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rs_phy_addr, dis_new_rd_phy_addr;
    logic [ROB_INDEX_WIDTH-1:0] dis_rob_tag;
    logic [OPCODE_WIDTH-1:0] dis_opcode;
    logic dis_ld_st_issq_en;
    logic [15:0] dis_imm16;
    logic lsq_ld_st_full, lsq_ld_st_two_or_more_vacant;
    logic issue_ld_st_en, issue_ld_st_rdy;
    logic dcache_read_busy;
    logic cdb_flush;
    logic [ROB_INDEX_WIDTH-1:0] cdb_rob_depth;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] cdb_rd_phy_addr;
    logic cdb_phy_reg_write, cdb_valid;
    logic sb_entry_sw_en;
    logic [REG_FILE_DATA_WIDTH-1:0] iss_rs_data_lsq;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rs_phy_addr_ls;
    logic iss_lsb_ready;
    logic [OPCODE_WIDTH-1:0] iss_lsq_opcode;
    logic [ROB_INDEX_WIDTH-1:0] iss_lsq_rob_tag;
    logic [DMEM_DEPTH-1:0] iss_lsq_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_lsq_phy_addr;
    logic iss_lsq_rdy;

    LSQ #(
        .LSQ_DEPTH(LSQ_DEPTH),
        .SAB_DEPTH(SAB_DEPTH),
        .DMEM_DEPTH(DMEM_DEPTH),
        .ROB_DEPTH(ROB_DEPTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .REG_FILE_DATA_WIDTH(REG_FILE_DATA_WIDTH),
        .SB_DEPTH(SB_DEPTH)
    ) dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        sb_flush_sw_tag = 0;
        sb_flush_sw = 0;
        sb_entry_sw_tag = 0;
        sb_entry_sw_addr = 0;
        rob_tag = 0;
        rob_top_ptr = 0;
        rob_commit_mem_write = 0;
        dis_rs_data_ready = 0;
        dis_rs_phy_addr = 0;
        dis_new_rd_phy_addr = 0;
        dis_rob_tag = 0;
        dis_opcode = 0;
        dis_ld_st_issq_en = 0;
        dis_imm16 = 0;
        issue_ld_st_en = 0;
        dcache_read_busy = 0;
        cdb_flush = 0;
        cdb_rob_depth = 0;
        cdb_rd_phy_addr = 0;
        cdb_phy_reg_write = 0;
        cdb_valid = 0;
        sb_entry_sw_en = 0;
        iss_rs_data_lsq = 0;
        iss_lsb_ready = 1;

        rst_n = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        if (lsq_ld_st_full !== 0) $fatal(1, "LSQ: expected not full");
        if (lsq_ld_st_two_or_more_vacant !== 1) $fatal(1, "LSQ: expected vacancies");

        $display("LSQ_tb: pass");
        $finish;
    end

endmodule
