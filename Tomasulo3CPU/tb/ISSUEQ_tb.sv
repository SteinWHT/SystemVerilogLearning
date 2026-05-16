`timescale 1ns/1ps

// Elaboration / reset smoke test for ISSUEQ wrapper (all sub-queues instantiated).
module ISSUEQ_tb;

    parameter int unsigned INSTR_WIDTH             = 32;
    parameter int unsigned ISSUE_QUEUE_DEPTH       = 4;
    parameter int unsigned ARCH_REG_WIDTH          = 5;
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7;
    parameter int unsigned REG_FILE_DATA_WIDTH     = 64;
    parameter int unsigned DMEM_WIDTH                = 32;
    parameter int unsigned ROB_DEPTH                 = 16;
    localparam int unsigned ROB_INDEX_WIDTH        = $clog2(ROB_DEPTH);
    parameter int unsigned DMEM_DEPTH                = 32;
    parameter int unsigned SB_DEPTH                  = 4;
    localparam int unsigned SB_INDEX_WIDTH           = $clog2(SB_DEPTH);
    parameter int unsigned LSB_DEPTH                 = 4;
    parameter int unsigned BPB_PC_BITS               = 2;
    parameter int unsigned LD_ST_OPCODE_WIDTH      = 1;

    logic clk, rst_n;
    logic cdb_flush;
    logic [ROB_INDEX_WIDTH-1:0] rob_top_ptr, cdb_rob_depth;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] cdb_rd_phy_addr;
    logic cdb_phy_reg_write;
    logic [REG_FILE_DATA_WIDTH-1:0] iss_rs_data_lsq;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rs_phy_addr_alu, iss_rt_phy_addr_alu;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rs_phy_addr_div, iss_rt_phy_addr_div;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rs_phy_addr_mul, iss_rt_phy_addr_mul;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rs_phy_addr_ls;
    logic dis_int_issq_en, dis_div_issq_en, dis_mul_issq_en, dis_ld_st_issq_en;
    logic dis_reg_write, dis_rs_data_ready, dis_rt_data_ready;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rs_phy_addr, dis_rt_phy_addr, dis_new_rd_phy_addr;
    logic [ROB_INDEX_WIDTH-1:0] dis_rob_tag;
    logic [2:0] dis_opcode;
    logic [15:0] dis_imm16;
    logic [DMEM_WIDTH-1:0] dis_branch_other_addr;
    logic [BPB_PC_BITS:0] dis_branch_pc_bits;
    logic dis_branch_prediction, dis_branch, dis_jr_inst, dis_jal_inst, dis_jr31_inst;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] mul_rd_phy_addr, div_rd_phy_addr, ls_buf_rd_phy_addr;
    logic mul_exe_ready, div_exe_ready, ls_buf_buf_rd_write;
    logic issq_intq_full, issq_divq_full, issq_mulq_full, issq_ld_stq_full;
    logic issq_intq_two_or_more_vacant, issq_divq_two_or_more_vacant;
    logic issq_mulq_two_or_more_vacant, issq_ld_stq_two_or_more_vacant;
    logic issue_int_en, issue_div_en, issue_mul_en, issue_ld_st_en;
    logic issue_int_rdy, issue_div_rdy, issue_mul_rdy, issue_ld_st_rdy;
    logic issue_int, issue_div, issue_mul;
    logic [SB_INDEX_WIDTH-1:0] sb_flush_sw_tag, sb_entry_sw_tag;
    logic sb_flush_sw;
    logic [DMEM_DEPTH-1:0] sb_entry_sw_addr;
    logic sb_entry_sw_en;
    logic [ROB_INDEX_WIDTH-1:0] rob_tag;
    logic rob_commit_mem_write;
    logic iss_lsb_ready;
    logic [LD_ST_OPCODE_WIDTH-1:0] iss_lsb_opcode;
    logic [ROB_INDEX_WIDTH-1:0] iss_lsb_rob_tag;
    logic [DMEM_DEPTH-1:0] iss_lsb_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_lsb_phy_addr;
    logic iss_lsb_rdy;
    logic dcache_read_busy;

    ISSUEQ #(
        .INSTR_WIDTH(INSTR_WIDTH),
        .ISSUE_QUEUE_DEPTH(ISSUE_QUEUE_DEPTH),
        .ARCH_REG_WIDTH(ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .REG_FILE_DATA_WIDTH(REG_FILE_DATA_WIDTH),
        .DMEM_WIDTH(DMEM_WIDTH),
        .ROB_DEPTH(ROB_DEPTH),
        .DMEM_DEPTH(DMEM_DEPTH),
        .SB_DEPTH(SB_DEPTH),
        .LSB_DEPTH(LSB_DEPTH),
        .BPB_PC_BITS(BPB_PC_BITS),
        .LD_ST_OPCODE_WIDTH(LD_ST_OPCODE_WIDTH)
    ) dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        cdb_flush = 0;
        rob_top_ptr = 0;
        cdb_rob_depth = 0;
        cdb_rd_phy_addr = 0;
        cdb_phy_reg_write = 0;
        iss_rs_data_lsq = 0;
        dis_int_issq_en = 0;
        dis_div_issq_en = 0;
        dis_mul_issq_en = 0;
        dis_ld_st_issq_en = 0;
        dis_reg_write = 0;
        dis_rs_data_ready = 0;
        dis_rt_data_ready = 0;
        dis_rs_phy_addr = 0;
        dis_rt_phy_addr = 0;
        dis_new_rd_phy_addr = 0;
        dis_rob_tag = 0;
        dis_opcode = 0;
        dis_imm16 = 0;
        dis_branch_other_addr = 0;
        dis_branch_pc_bits = 0;
        dis_branch_prediction = 0;
        dis_branch = 0;
        dis_jr_inst = 0;
        dis_jal_inst = 0;
        dis_jr31_inst = 0;
        mul_rd_phy_addr = 0;
        mul_exe_ready = 0;
        div_rd_phy_addr = 0;
        div_exe_ready = 0;
        ls_buf_rd_phy_addr = 0;
        ls_buf_buf_rd_write = 0;
        issue_int_en = 0;
        issue_div_en = 0;
        issue_mul_en = 0;
        issue_ld_st_en = 0;
        sb_flush_sw_tag = 0;
        sb_flush_sw = 0;
        sb_entry_sw_tag = 0;
        sb_entry_sw_addr = 0;
        sb_entry_sw_en = 0;
        rob_tag = 0;
        rob_commit_mem_write = 0;
        iss_lsb_ready = 1;
        dcache_read_busy = 0;

        rst_n = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        if (issq_intq_full || issq_divq_full || issq_mulq_full || issq_ld_stq_full)
            $fatal(1, "ISSUEQ: queues should not be full after reset");

        $display("ISSUEQ_tb: pass");
        $finish;
    end

endmodule
