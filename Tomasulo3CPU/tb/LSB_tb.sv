`timescale 1ns/1ps

module LSB_tb;

    parameter int unsigned LSB_DEPTH               = 4;
    parameter int unsigned DMEM_DEPTH              = 32;
    parameter int unsigned ROB_DEPTH               = 16;
    localparam int unsigned ROB_INDEX_WIDTH        = $clog2(ROB_DEPTH);
    parameter int unsigned ARCH_REG_WIDTH          = 5;
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7;
    parameter int unsigned REG_FILE_DATA_WIDTH     = 64;
    parameter int unsigned LD_ST_OPCODE_WIDTH      = 1;

    logic clk, rst_n;
    logic dcache_read_done;
    logic [DMEM_DEPTH-1:0] dcache_data;
    logic dcache_ready;
    logic [DMEM_DEPTH-1:0] dcache_addr;
    logic [LD_ST_OPCODE_WIDTH-1:0] iss_lsb_opcode;
    logic [ROB_INDEX_WIDTH-1:0] iss_lsb_rob_tag;
    logic [DMEM_DEPTH-1:0] iss_lsb_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_lsb_phy_addr;
    logic iss_lsb_rdy, iss_lsb_ready;
    logic issue_ld_buf, ready_ld_buf;
    logic cdb_flush;
    logic [ROB_INDEX_WIDTH-1:0] cdb_rob_depth;
    logic [ROB_INDEX_WIDTH-1:0] lsb_rob_tag;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] lsb_rd_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0] lsb_data;
    logic lsb_rw;
    logic [DMEM_DEPTH-1:0] lsb_sw_addr;
    logic lsb_ready;
    logic [ROB_INDEX_WIDTH-1:0] rob_top_ptr;

    LSB #(
        .LSB_DEPTH(LSB_DEPTH),
        .DMEM_DEPTH(DMEM_DEPTH),
        .ROB_DEPTH(ROB_DEPTH),
        .ARCH_REG_WIDTH(ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .REG_FILE_DATA_WIDTH(REG_FILE_DATA_WIDTH),
        .LD_ST_OPCODE_WIDTH(LD_ST_OPCODE_WIDTH)
    ) dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        dcache_read_done = 0;
        dcache_data = 0;
        iss_lsb_opcode = 0;
        iss_lsb_rob_tag = 5'd1;
        iss_lsb_addr = 32'h1000;
        iss_lsb_phy_addr = 7'd3;
        iss_lsb_rdy = 0;
        issue_ld_buf = 0;
        cdb_flush = 0;
        cdb_rob_depth = 0;
        rob_top_ptr = 0;

        rst_n = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        if (!iss_lsb_ready) $fatal(1, "LSB should accept when empty");

        iss_lsb_rdy = 1;
        iss_lsb_opcode = 1'b0;
        @(posedge clk);
        iss_lsb_rdy = 0;

        if (!dcache_ready) $fatal(1, "LSB should request D$ for pending load");
        if (dcache_addr !== 32'h1000) $fatal(1, "LSB addr");

        dcache_read_done = 1;
        dcache_data = 64'h1234_5678;
        @(posedge clk);
        dcache_read_done = 0;

        if (!ready_ld_buf) $fatal(1, "LSB should have completed entry");

        issue_ld_buf = 1;
        @(posedge clk);
        issue_ld_buf = 0;

        if (!lsb_ready) $fatal(1, "LSB should signal CDB handshake");
        if (lsb_data !== 64'h1234_5678) $fatal(1, "LSB data");

        $display("LSB_tb: pass");
        $finish;
    end

endmodule
