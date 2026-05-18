// Integration testbench: ISSUEQ + ISSUEUNIT + LSB (LSQ issues when LSB ready; UNIT drains LSB).
/* verilator lint_off WIDTH */
// verilog_lint: waive-start explicit-parameter-storage-type
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module ISSUEQ_tb;
import riscv_types_pkg::*;

    parameter int unsigned INSTR_WIDTH             = 32;
    parameter int unsigned ISSUE_QUEUE_DEPTH       = 4;
    parameter int unsigned ARCH_REG_WIDTH          = 5;
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7;
    parameter int unsigned REG_FILE_DATA_WIDTH     = 64;
    parameter int unsigned DMEM_WIDTH              = 64;
    parameter int unsigned ROB_DEPTH               = 16;
    localparam  int unsigned ROB_INDEX_WIDTH       = $clog2(ROB_DEPTH);
    parameter int unsigned DMEM_DEPTH              = 32;
    parameter int unsigned SB_DEPTH                = 4;
    localparam  int unsigned SB_INDEX_WIDTH        = $clog2(SB_DEPTH);
    parameter int unsigned LSB_DEPTH               = 4;
    parameter int unsigned BPB_PC_BITS             = 3;
    parameter int unsigned OPCODE_WIDTH            = 6;
    parameter int unsigned DIV_CYCLES              = 7;
    parameter int unsigned MUL_CYCLES              = 3;

    logic clk;
    logic rst_n;

    logic                               cdb_flush;
    logic [ROB_INDEX_WIDTH-1:0]         cdb_rob_depth;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] cdb_rd_phy_addr;
    logic                               cdb_phy_reg_write;
    logic                               cdb_valid;

    logic [REG_FILE_DATA_WIDTH-1:0] iss_rs_data_lsq;

    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rs_phy_addr_alu;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rt_phy_addr_alu;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rs_phy_addr_div;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rt_phy_addr_div;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rs_phy_addr_mul;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rt_phy_addr_mul;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rs_phy_addr_ls;

    logic dis_int_issq_en;
    logic dis_div_issq_en;
    logic dis_mul_issq_en;
    logic dis_ld_st_issq_en;
    logic dis_reg_write;
    logic dis_rs_data_ready;
    logic dis_rt_data_ready;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rs_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rt_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_new_rd_phy_addr;
    logic [ROB_INDEX_WIDTH-1:0]         dis_rob_tag;
    logic [OPCODE_WIDTH-1:0]            dis_opcode;
    logic [15:0]                        dis_imm16;
    logic [DMEM_WIDTH-1:0]              dis_branch_other_addr;
    logic [BPB_PC_BITS:0]               dis_branch_pc_bits;
    logic                               dis_branch_prediction;
    logic                               dis_branch;
    logic                               dis_jr_inst;
    logic                               dis_jal_inst;
    logic                               dis_jr31_inst;

    logic issq_intq_full;
    logic issq_divq_full;
    logic issq_mulq_full;
    logic issq_ld_stq_full;
    logic issq_intq_two_or_more_vacant;
    logic issq_divq_two_or_more_vacant;
    logic issq_mulq_two_or_more_vacant;
    logic issq_ld_stq_two_or_more_vacant;

    logic [PHY_REGISTER_FILE_WIDTH-1:0] mul_rd_phy_addr;
    logic                               mul_exe_ready;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] div_rd_phy_addr;
    logic                               div_exe_ready;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] ls_buf_rd_phy_addr;
    logic                               ls_buf_buf_rd_write;

    logic issue_int_en;
    logic issue_div_en;
    logic issue_mul_en;

    logic issue_int_rdy;
    logic issue_div_rdy;
    logic issue_mul_rdy;

    logic exe_int_grant;
    logic exe_div_grant;
    logic exe_mul_grant;

    logic [SB_INDEX_WIDTH-1:0]  sb_flush_sw_tag;
    logic                       sb_flush_sw;
    logic [SB_INDEX_WIDTH-1:0]  sb_entry_sw_tag;
    logic [DMEM_DEPTH-1:0]      sb_entry_sw_addr;

    logic [ROB_INDEX_WIDTH-1:0] rob_tag;
    logic [ROB_INDEX_WIDTH-1:0] rob_top_ptr;
    logic                       rob_commit_mem_write;

    logic                       iss_lsb_ready;
    logic [OPCODE_WIDTH-1:0]    iss_lsb_opcode;
    logic [ROB_INDEX_WIDTH-1:0] iss_lsb_rob_tag;
    logic [DMEM_DEPTH-1:0]      iss_lsb_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_lsb_phy_addr;
    logic                       iss_lsb_rdy;

    logic [OPCODE_WIDTH-1:0]       lsb_opcode;
    logic                          dcache_read_busy;
    logic                          dcache_read_done;
    logic [DMEM_WIDTH-1:0]         dcache_rdata;
    logic                          dcache_req;
    logic                          dcache_ready;
    logic [DMEM_DEPTH-1:0]         dcache_addr;

    logic issue_int;
    logic issue_div;
    logic issue_mul;
    logic issue_ld_buf;
    logic ready_ld_buf;

    logic lsb_ready;
    logic [ROB_INDEX_WIDTH-1:0]         lsb_rob_tag;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] lsb_rd_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0]     lsb_data;
    logic                               lsb_rw;
    logic [DMEM_DEPTH-1:0]              lsb_sw_addr;

    assign issue_int_en = issue_int;
    assign issue_div_en = issue_div;
    assign issue_mul_en = issue_mul;

    assign dcache_read_done = dcache_ready;
    assign dcache_read_busy = !dcache_ready;

    ISSUEQ #(
        .INSTR_WIDTH            (INSTR_WIDTH),
        .ISSUE_QUEUE_DEPTH      (ISSUE_QUEUE_DEPTH),
        .ARCH_REG_WIDTH         (ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .REG_FILE_DATA_WIDTH    (REG_FILE_DATA_WIDTH),
        .DMEM_WIDTH             (DMEM_WIDTH),
        .ROB_DEPTH              (ROB_DEPTH),
        .DMEM_DEPTH             (DMEM_DEPTH),
        .SB_DEPTH               (SB_DEPTH),
        .LSB_DEPTH              (LSB_DEPTH),
        .BPB_PC_BITS            (BPB_PC_BITS),
        .OPCODE_WIDTH           (OPCODE_WIDTH)
    ) issueq (
        .clk                          (clk),
        .rst_n                        (rst_n),
        .cdb_valid                    (cdb_valid),
        .cdb_flush                    (cdb_flush),
        .cdb_rob_depth                (cdb_rob_depth),
        .cdb_rd_phy_addr              (cdb_rd_phy_addr),
        .cdb_phy_reg_write            (cdb_phy_reg_write),
        .iss_rs_data_lsq              (iss_rs_data_lsq),
        .iss_rs_phy_addr_alu          (iss_rs_phy_addr_alu),
        .iss_rt_phy_addr_alu          (iss_rt_phy_addr_alu),
        .iss_rs_phy_addr_div          (iss_rs_phy_addr_div),
        .iss_rt_phy_addr_div          (iss_rt_phy_addr_div),
        .iss_rs_phy_addr_mul          (iss_rs_phy_addr_mul),
        .iss_rt_phy_addr_mul          (iss_rt_phy_addr_mul),
        .iss_rs_phy_addr_ls           (iss_rs_phy_addr_ls),
        .dis_int_issq_en              (dis_int_issq_en),
        .dis_div_issq_en              (dis_div_issq_en),
        .dis_mul_issq_en              (dis_mul_issq_en),
        .dis_ld_st_issq_en            (dis_ld_st_issq_en),
        .dis_reg_write                (dis_reg_write),
        .dis_rs_data_ready            (dis_rs_data_ready),
        .dis_rt_data_ready            (dis_rt_data_ready),
        .dis_rs_phy_addr              (dis_rs_phy_addr),
        .dis_rt_phy_addr              (dis_rt_phy_addr),
        .dis_new_rd_phy_addr          (dis_new_rd_phy_addr),
        .dis_rob_tag                  (dis_rob_tag),
        .dis_opcode                   (dis_opcode),
        .dis_imm16                    (dis_imm16),
        .dis_branch_other_addr        (dis_branch_other_addr),
        .dis_branch_pc_bits           (dis_branch_pc_bits),
        .dis_branch_prediction        (dis_branch_prediction),
        .dis_branch                   (dis_branch),
        .dis_jr_inst                  (dis_jr_inst),
        .dis_jal_inst                 (dis_jal_inst),
        .dis_jr31_inst                (dis_jr31_inst),
        .mul_rd_phy_addr              (mul_rd_phy_addr),
        .mul_exe_ready                (mul_exe_ready),
        .div_rd_phy_addr              (div_rd_phy_addr),
        .div_exe_ready                (div_exe_ready),
        .ls_buf_rd_phy_addr           (ls_buf_rd_phy_addr),
        .ls_buf_buf_rd_write          (ls_buf_buf_rd_write),
        .issq_intq_full               (issq_intq_full),
        .issq_divq_full               (issq_divq_full),
        .issq_mulq_full               (issq_mulq_full),
        .issq_ld_stq_full             (issq_ld_stq_full),
        .issq_intq_two_or_more_vacant (issq_intq_two_or_more_vacant),
        .issq_divq_two_or_more_vacant (issq_divq_two_or_more_vacant),
        .issq_mulq_two_or_more_vacant (issq_mulq_two_or_more_vacant),
        .issq_ld_stq_two_or_more_vacant(issq_ld_stq_two_or_more_vacant),
        .issue_int_en                 (issue_int_en),
        .issue_div_en                 (issue_div_en),
        .issue_mul_en                 (issue_mul_en),
        .issue_int_rdy                (issue_int_rdy),
        .issue_div_rdy                (issue_div_rdy),
        .issue_mul_rdy                (issue_mul_rdy),
        .exe_int_grant                (exe_int_grant),
        .exe_div_grant                (exe_div_grant),
        .exe_mul_grant                (exe_mul_grant),
        .sb_flush_sw_tag              (sb_flush_sw_tag),
        .sb_flush_sw                  (sb_flush_sw),
        .sb_entry_sw_tag              (sb_entry_sw_tag),
        .sb_entry_sw_addr             (sb_entry_sw_addr),
        .rob_tag                      (rob_tag),
        .rob_top_ptr                  (rob_top_ptr),
        .rob_commit_mem_write         (rob_commit_mem_write),
        .iss_lsb_ready                (iss_lsb_ready),
        .iss_lsb_opcode               (iss_lsb_opcode),
        .iss_lsb_rob_tag              (iss_lsb_rob_tag),
        .iss_lsb_addr                 (iss_lsb_addr),
        .iss_lsb_phy_addr             (iss_lsb_phy_addr),
        .iss_lsb_rdy                  (iss_lsb_rdy),
        .dcache_read_busy             (dcache_read_busy)
    );

    ISSUEUNIT #(
        .DIV_CYCLES   (DIV_CYCLES),
        .MUL_CYCLES   (MUL_CYCLES),
        .INT_CYCLES   (1),
        .LD_ST_CYCLES (1)
    ) issueunit (
        .clk            (clk),
        .rst_n          (rst_n),
        .ready_int      (issue_int_rdy),
        .issue_int      (issue_int),
        .ready_div      (issue_div_rdy),
        .div_exe_ready  (div_exe_ready),
        .issue_div      (issue_div),
        .ready_mul      (issue_mul_rdy),
        .issue_mul      (issue_mul),
        .ready_ld_buf   (ready_ld_buf),
        .issue_ld_buf   (issue_ld_buf)
    );

    LSB #(
        .LSB_DEPTH              (LSB_DEPTH),
        .DMEM_DEPTH             (DMEM_DEPTH),
        .ROB_DEPTH              (ROB_DEPTH),
        .ARCH_REG_WIDTH         (ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .REG_FILE_DATA_WIDTH    (REG_FILE_DATA_WIDTH),
        .OPCODE_WIDTH           (OPCODE_WIDTH)
    ) lsb (
        .clk              (clk),
        .rst_n            (rst_n),
        .dcache_read_done (dcache_read_done),
        .dcache_data      (dcache_rdata),
        .dcache_ready     (dcache_req),
        .dcache_addr      (dcache_addr),
        .iss_lsb_opcode   (iss_lsb_opcode),
        .iss_lsb_rob_tag  (iss_lsb_rob_tag),
        .iss_lsb_addr     (iss_lsb_addr),
        .iss_lsb_phy_addr (iss_lsb_phy_addr),
        .iss_lsb_rdy      (iss_lsb_rdy),
        .iss_lsb_ready    (iss_lsb_ready),
        .issue_ld_buf     (issue_ld_buf),
        .ready_ld_buf     (ready_ld_buf),
        .cdb_flush        (cdb_flush),
        .cdb_rob_depth    (cdb_rob_depth),
        .lsb_rob_tag      (lsb_rob_tag),
        .lsb_rd_phy_addr  (lsb_rd_phy_addr),
        .lsb_data         (lsb_data),
        .lsb_rw           (lsb_rw),
        .lsb_sw_addr      (lsb_sw_addr),
        .lsb_ready        (lsb_ready),
        .rob_top_ptr      (rob_top_ptr)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    int pass_cnt = 0;
    int fail_cnt = 0;

    task automatic check_bit(
        input string tag,
        input logic  actual,
        input logic  expected
    );
        if (actual !== expected) begin
            $error("[FAIL] %s: got %0b, want %0b @ %0t",
                   tag, actual, expected, $time);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
    endtask

    task automatic check_val(
        input string       tag,
        input logic [63:0] actual,
        input logic [63:0] expected
    );
        if (actual !== expected) begin
            $error("[FAIL] %s: got 0x%0h, want 0x%0h @ %0t",
                   tag, actual, expected, $time);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
    endtask

    task automatic clear_dispatch();
        dis_int_issq_en     = 1'b0;
        dis_div_issq_en     = 1'b0;
        dis_mul_issq_en     = 1'b0;
        dis_ld_st_issq_en   = 1'b0;
        dis_reg_write       = 1'b0;
        dis_rs_data_ready   = 1'b0;
        dis_rt_data_ready   = 1'b0;
        dis_rs_phy_addr     = '0;
        dis_rt_phy_addr     = '0;
        dis_new_rd_phy_addr = '0;
        dis_rob_tag         = '0;
        dis_opcode          = '0;
        dis_imm16           = '0;
        dis_branch_other_addr = '0;
        dis_branch_pc_bits  = '0;
        dis_branch_prediction = 1'b0;
        dis_branch          = 1'b0;
        dis_jr_inst         = 1'b0;
        dis_jal_inst        = 1'b0;
        dis_jr31_inst       = 1'b0;
    endtask

    task automatic clear_sideband();
        cdb_flush            = 1'b0;
        cdb_rob_depth        = '0;
        cdb_rd_phy_addr      = '0;
        cdb_phy_reg_write    = 1'b0;
        mul_rd_phy_addr      = '0;
        mul_exe_ready        = 1'b0;
        div_rd_phy_addr      = '0;
        div_exe_ready        = 1'b1;
        ls_buf_rd_phy_addr   = '0;
        ls_buf_buf_rd_write  = 1'b0;
        sb_flush_sw_tag      = '0;
        sb_flush_sw          = 1'b0;
        sb_entry_sw_tag      = '0;
        sb_entry_sw_addr     = '0;
        rob_tag              = '0;
        rob_top_ptr          = '0;
        rob_commit_mem_write = 1'b0;
        iss_rs_data_lsq      = '0;
        dcache_rdata         = '0;
        dcache_ready         = '0;
        cdb_valid            = '0;
        //issue_ld_buf         = 1'b0;
    endtask

    task automatic reset_dut();
        rst_n = 1'b0;
        clear_dispatch();
        clear_sideband();
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;
    endtask

    task automatic dispatch_int(
        input logic [ROB_INDEX_WIDTH-1:0]         rob_tag_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rt,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd
    );
        clear_dispatch();
        dis_int_issq_en       = 1'b1;
        dis_reg_write         = 1'b1;
        dis_rs_data_ready     = 1'b1;
        dis_rt_data_ready     = 1'b1;
        dis_rs_phy_addr       = rs;
        dis_rt_phy_addr       = rt;
        dis_new_rd_phy_addr   = rd;
        dis_rob_tag           = rob_tag_i;
        dis_opcode            = INSTR_ADD;
        @(posedge clk); #1;
        dis_int_issq_en = 1'b0;
    endtask

    task automatic dispatch_int_this_cycle(
        input logic [ROB_INDEX_WIDTH-1:0]         rob_tag_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rt,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd
    );
        clear_dispatch();
        dis_int_issq_en       = 1'b1;
        dis_reg_write         = 1'b1;
        dis_rs_data_ready     = 1'b0;
        dis_rt_data_ready     = 1'b1;
        dis_rs_phy_addr       = rs;
        dis_rt_phy_addr       = rt;
        dis_new_rd_phy_addr   = rd;
        dis_rob_tag           = rob_tag_i;
        dis_opcode            = INSTR_ADD;
        @(posedge clk); #1;
        dis_int_issq_en = 1'b0;
    endtask

    task automatic dispatch_mul(
        input logic [ROB_INDEX_WIDTH-1:0]         rob_tag_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rt,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd
    );
        clear_dispatch();
        dis_mul_issq_en       = 1'b1;
        dis_reg_write         = 1'b1;
        dis_rs_data_ready     = 1'b1;
        dis_rt_data_ready     = 1'b1;
        dis_rs_phy_addr       = rs;
        dis_rt_phy_addr       = rt;
        dis_new_rd_phy_addr   = rd;
        dis_rob_tag           = rob_tag_i;
        dis_opcode            = INSTR_MUL;
        @(posedge clk); #1;
        dis_mul_issq_en = 1'b0;
    endtask

    task automatic dispatch_mul_not_rdy(
        input logic [ROB_INDEX_WIDTH-1:0]         rob_tag_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rt,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd
    );
        clear_dispatch();
        dis_mul_issq_en       = 1'b1;
        dis_reg_write         = 1'b1;
        dis_rs_data_ready     = 1'b0;
        dis_rt_data_ready     = 1'b1;
        dis_rs_phy_addr       = rs;
        dis_rt_phy_addr       = rt;
        dis_new_rd_phy_addr   = rd;
        dis_rob_tag           = rob_tag_i;
        dis_opcode            = INSTR_MUL;
        @(posedge clk); #1;
        dis_mul_issq_en = 1'b0;
    endtask

    task automatic dispatch_div(
        input logic [ROB_INDEX_WIDTH-1:0]         rob_tag_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rt,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd
    );
        clear_dispatch();
        dis_div_issq_en       = 1'b1;
        dis_reg_write         = 1'b1;
        dis_rs_data_ready     = 1'b1;
        dis_rt_data_ready     = 1'b1;
        dis_rs_phy_addr       = rs;
        dis_rt_phy_addr       = rt;
        dis_new_rd_phy_addr   = rd;
        dis_rob_tag           = rob_tag_i;
        dis_opcode            = INSTR_DIV;
        @(posedge clk); #1;
        dis_div_issq_en = 1'b0;
    endtask

    task automatic dispatch_div_this_cycle(
        input logic [ROB_INDEX_WIDTH-1:0]         rob_tag_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rt,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd
    );
        clear_dispatch();
        dis_div_issq_en       = 1'b1;
        dis_reg_write         = 1'b1;
        dis_rs_data_ready     = 1'b1;
        dis_rt_data_ready     = 1'b1;
        dis_rs_phy_addr       = rs;
        dis_rt_phy_addr       = rt;
        dis_new_rd_phy_addr   = rd;
        dis_rob_tag           = rob_tag_i;
        dis_opcode            = INSTR_DIV;
        @(posedge clk); #1;
        dis_div_issq_en = 1'b0;
    endtask

    task automatic dispatch_lw(
        input logic [ROB_INDEX_WIDTH-1:0]         rob_tag_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd,
        input logic [15:0]                        imm
    );
        clear_dispatch();
        dis_ld_st_issq_en     = 1'b1;
        dis_reg_write         = 1'b1;
        dis_rs_data_ready     = 1'b1;
        dis_rs_phy_addr       = rs;
        dis_new_rd_phy_addr   = rd;
        dis_rob_tag           = rob_tag_i;
        dis_opcode            = INSTR_LW;
        dis_imm16             = imm;
        @(posedge clk); #1;
        dis_ld_st_issq_en = 1'b0;
    endtask

    task automatic cdb_forwarding(
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd
    );
        cdb_valid            = 1'b1;
        cdb_rd_phy_addr      = rd;
        cdb_phy_reg_write    = 1'b1;
        @(posedge clk);
        cdb_valid            = 1'b0;
        cdb_phy_reg_write    = 1'b0;
    endtask


    task automatic wait_issue_int_no_extra_latency(input int max_cycles = 20);
        int c;
        c = 0;
        while (!exe_int_grant && c < max_cycles) begin
            @(posedge clk);
            c++;
        end
        if (!exe_int_grant)
            $error("[FAIL] timeout waiting for exe_int_grant @ %0t", $time);
    endtask

    task automatic wait_issue_int(input int max_cycles = 20);
        int c;
        c = 0;
        while (!exe_int_grant && c < max_cycles) begin
            @(posedge clk); #1;
            c++;
        end
        if (!exe_int_grant)
            $error("[FAIL] timeout waiting for exe_int_grant @ %0t", $time);
    endtask

    task automatic wait_issue_mul(input int max_cycles = 20);
        int c;
        c = 0;
        while (!exe_mul_grant && c < max_cycles) begin
            @(posedge clk); #1;
            c++;
        end
        if (!exe_mul_grant)
            $error("[FAIL] timeout waiting for exe_mul_grant @ %0t", $time);
    endtask

    task automatic wait_issue_div(input int max_cycles = 30);
        int c;
        c = 0;
        while (!exe_div_grant && c < max_cycles) begin
            @(posedge clk); #1;
            c++;
        end
        if (!exe_div_grant)
            $error("[FAIL] timeout waiting for exe_div_grant @ %0t", $time);
    endtask

    initial begin
        `ifdef FSDB_DUMP
            $fsdbDumpfile("issueq.fsdb");
            $fsdbDumpvars(0, ISSUEQ_tb);
            $fsdbDumpMDA();
        `else
            $dumpfile("issueq.vcd");
            $dumpvars(0, ISSUEQ_tb);
        `endif

        $display("=======================================");
        $display("  ISSUEQ + ISSUEUNIT Testbench Start");
        $display("=======================================");

        $display("\n[Test 1] Reset: queues not full, two-or-more vacant");
        reset_dut();
        check_bit("intq not full", issq_intq_full, 1'b0);
        check_bit("divq not full", issq_divq_full, 1'b0);
        check_bit("mulq not full", issq_mulq_full, 1'b0);
        check_bit("lsq not full", issq_ld_stq_full, 1'b0);
        check_bit("intq vacant", issq_intq_two_or_more_vacant, 1'b1);

        $display("\n[Test 2] INT dispatch issues through ISSUEUNIT (PRF read addresses)");
        dispatch_int(5'd1, 7'd10, 7'd11, 7'd20);
        check_bit("int ready before grant", issue_int_rdy, 1'b1);
        wait_issue_int();
        check_val("alu rs", iss_rs_phy_addr_alu, 7'd10);
        check_val("alu rt", iss_rt_phy_addr_alu, 7'd11);
        check_bit("int grant", exe_int_grant, 1'b1);
        @(posedge clk); #1;
        check_bit("int queue empty", issue_int_rdy, 1'b0);

        $display("\n[Test 3] MUL dispatch and auto-issue");
        dispatch_mul(5'd2, 7'd30, 7'd31, 7'd40);
        check_bit("mul ready", issue_mul_rdy, 1'b1);
        wait_issue_mul();
        check_val("mul rs", iss_rs_phy_addr_mul, 7'd30);
        check_val("mul rt", iss_rt_phy_addr_mul, 7'd31);

        $display("\n[Test 4] DIV has priority over INT when both ready");
        dispatch_int_this_cycle(5'd3, 7'd1, 7'd2, 7'd3);
        dispatch_div_this_cycle(5'd4, 7'd4, 7'd5, 7'd6);
        cdb_valid            = 1'b1;
        cdb_rd_phy_addr      = 7'd1;
        cdb_phy_reg_write    = 1'b1;
        #1;
        check_bit("both int and div ready", issue_int_rdy & issue_div_rdy, 1'b1);
        @(posedge clk);
        cdb_valid            = 1'b0;
        cdb_phy_reg_write    = 1'b0;
        wait_issue_div();
        check_bit("div wins first", exe_div_grant, 1'b1);
        check_bit("int not granted same cycle", exe_int_grant, 1'b0);
        wait_issue_int_no_extra_latency();

        $display("\n[Test 5] Operand wakeup via CDB at INT dispatch time");
        cdb_valid = 1'b1;
        cdb_rd_phy_addr     = 7'd50;
        cdb_phy_reg_write   = 1'b1;
        clear_dispatch();
        dis_int_issq_en       = 1'b1;
        dis_reg_write         = 1'b1;
        dis_rs_data_ready     = 1'b0;
        dis_rt_data_ready     = 1'b1;
        dis_rs_phy_addr       = 7'd50;
        dis_rt_phy_addr       = 7'd51;
        dis_new_rd_phy_addr   = 7'd52;
        dis_rob_tag           = 5'd5;
        dis_opcode            = INSTR_ADD;
        @(posedge clk); #1;
        dis_int_issq_en     = 1'b0;
        cdb_phy_reg_write   = 1'b0;
        cdb_valid           = 1'b0;
        wait_issue_int();
        check_val("wakeup rs", iss_rs_phy_addr_alu, 7'd50);
        check_val("rt already ready", iss_rt_phy_addr_alu, 7'd51);

        $display("\n[Test 6] INTQ flush removes younger entry; older survives");
        reset_dut();
        dispatch_int_this_cycle(5'd2, 7'd60, 7'd61, 7'd62);
        dispatch_int(5'd6, 7'd63, 7'd64, 7'd65);
        cdb_flush     = 1'b1;
        rob_top_ptr   = 5'd0;
        cdb_rob_depth = 5'd4;
        @(posedge clk); #1;
        cdb_flush = 1'b0;
        cdb_forwarding(7'd60);
        wait_issue_int_no_extra_latency();
        check_val("surviving entry rs", iss_rs_phy_addr_alu, 7'd60);

        $display("\n[Test 7] LW: LSQ issues to LSB when iss_lsb_ready (no ISSUEUNIT grant)");
        reset_dut();
        dispatch_lw(5'd7, 7'd70, 7'd71, 16'h0100);
        dcache_ready = 1'b1;
        repeat (24) begin
            if (iss_rs_phy_addr_ls == 7'd70)
                iss_rs_data_lsq = 64'h0000_0000_0000_2000;
            @(posedge clk); #1;
            if (iss_lsb_rdy) begin
                check_bit("LSB can accept", iss_lsb_ready, 1'b1);
                check_val("lsq->lsb rob tag", iss_lsb_rob_tag, 5'd7);
                check_val("lsq->lsb phy rd", iss_lsb_phy_addr, 7'd71);
                check_val("lsq->lsb addr", iss_lsb_addr, 32'h0000_2100);
                break;
            end
        end
        if (!iss_lsb_rdy)
            $error("[FAIL] timeout: LSQ did not issue to LSB @ %0t", $time);
        @(posedge clk); #1;
        dcache_ready = 1'b0;
        check_bit("D$ request after load enters LSB", dcache_req, 1'b1);
        @(posedge clk); #1;
        dcache_ready = 1'b1;
        dcache_rdata     = 64'hCAFEBABE_DEADBEEF;
        @(posedge clk); #1;
        //dcache_read_done = 1'b0;
        check_bit("LSB has result for ISSUEUNIT", ready_ld_buf, 1'b1);
        check_bit("ISSUEUNIT drains LSB", issue_ld_buf, 1'b1);
        @(posedge clk); #1;
        check_val("CDB load data", lsb_data, 64'hCAFEBABE_DEADBEEF);

        $display("\n[Test 8] Fill MULQ and observe full flag");
        reset_dut();
        dispatch_mul_not_rdy(5'd10, 7'd1, 7'd2, 7'd3);
        dispatch_mul_not_rdy(5'd11, 7'd4, 7'd5, 7'd6);
        dispatch_mul_not_rdy(5'd12, 7'd7, 7'd8, 7'd9);
        dispatch_mul_not_rdy(5'd13, 7'd10, 7'd11, 7'd12);
        check_bit("mulq full", issq_mulq_full, 1'b1);

        $display("\n=======================================");
        $display("  ISSUEQ Done: %0d passed, %0d failed", pass_cnt, fail_cnt);
        $display("=======================================");

        if (fail_cnt == 0) begin
            $display("[PASS] ISSUEQ_tb completed successfully");
        end else begin
            $fatal(1, "[FAIL] ISSUEQ_tb found %0d failure(s)", fail_cnt);
        end
        $finish;
    end

    initial begin
        #500_000;
        $error("TIMEOUT");
        $finish;
    end

endmodule
/* verilator lint_on WIDTH */
/* verilator lint_on BLKSEQ */
// verilog_lint: waive-stop explicit-parameter-storage-type
