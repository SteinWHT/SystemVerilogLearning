// EXE wrapper: ALU single-cycle, DIV/MUL completion and wakeup sidebands.
/* verilator lint_off WIDTH */
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module EXE_tb;
import riscv_types_pkg::*;

    parameter int unsigned XLEN                   = 64;
    parameter int unsigned OPCODE_WIDTH             = 7;
    parameter int unsigned REG_FILE_DATA_WIDTH      = 64;
    parameter int unsigned DMEM_WIDTH               = 32;
    parameter int unsigned BPB_PC_BITS                = 3;
    parameter int unsigned ROB_INDEX_WIDTH            = 4;
    parameter int unsigned PHY_REGISTER_FILE_WIDTH    = 7;
    parameter int unsigned DIV_CYCLES                 = 3;
    parameter int unsigned MUL_CYCLES                 = 2;

    logic clk;
    logic rst_n;

    logic                                 cdb_flush;
    logic [ROB_INDEX_WIDTH-1:0]           cdb_rob_depth;
    logic [ROB_INDEX_WIDTH-1:0]           cdb_rob_tag;

    logic                                 exe_valid;
    logic [ROB_INDEX_WIDTH-1:0]           exe_rob_tag;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]   exe_rd_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0]       exe_rd_data;
    logic                                 exe_reg_write;
    logic                                 exe_branch_mispredicted;
    logic                                 exe_branch;
    logic                                 exe_jr_inst;
    logic                                 exe_jr31_inst;
    logic                                 exe_jal_inst;
    logic [BPB_PC_BITS-1:0]               exe_branch_pc_bits;
    logic [DMEM_WIDTH-1:0]                exe_branch_other_addr;

    logic [ROB_INDEX_WIDTH-1:0]           iss_rob_tag;
    logic [OPCODE_WIDTH-1:0]              iss_opcode;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]   iss_rd_phy_addr;
    logic                                 iss_rw;
    logic [15:0]                          iss_imm16;
    logic [DMEM_WIDTH-1:0]                iss_branch_other_addr;
    logic                                 iss_branch_prediction;
    logic                                 iss_branch;
    logic                                 iss_jr_inst;
    logic                                 iss_jr31_inst;
    logic                                 iss_jal_inst;
    logic [BPB_PC_BITS-1:0]               iss_branch_pc_bits;

    logic                                 issue_int_en;
    logic                                 issue_div_en;
    logic                                 issue_mul_en;

    logic                                 div_unit_ready;
    logic                                 div_result_valid;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]   div_rd_phy_addr;
    logic                                 mul_result_valid;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]   mul_rd_phy_addr;

    logic [REG_FILE_DATA_WIDTH-1:0]       exe_rs_data_alu;
    logic [REG_FILE_DATA_WIDTH-1:0]       exe_rt_data_alu;
    logic [REG_FILE_DATA_WIDTH-1:0]       exe_rs_data_div;
    logic [REG_FILE_DATA_WIDTH-1:0]       exe_rt_data_div;
    logic [REG_FILE_DATA_WIDTH-1:0]       exe_rs_data_mul;
    logic [REG_FILE_DATA_WIDTH-1:0]       exe_rt_data_mul;

    EXE #(
        .XLEN(XLEN),
        .OPCODE_WIDTH(OPCODE_WIDTH),
        .REG_FILE_DATA_WIDTH(REG_FILE_DATA_WIDTH),
        .DMEM_WIDTH(DMEM_WIDTH),
        .BPB_PC_BITS(BPB_PC_BITS),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .DIV_CYCLES(DIV_CYCLES),
        .MUL_CYCLES(MUL_CYCLES)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .cdb_flush(cdb_flush),
        .cdb_rob_depth(cdb_rob_depth),
        .cdb_rob_tag(cdb_rob_tag),
        .exe_valid(exe_valid),
        .exe_rob_tag(exe_rob_tag),
        .exe_rd_phy_addr(exe_rd_phy_addr),
        .exe_rd_data(exe_rd_data),
        .exe_reg_write(exe_reg_write),
        .exe_branch_mispredicted(exe_branch_mispredicted),
        .exe_branch(exe_branch),
        .exe_jr_inst(exe_jr_inst),
        .exe_jr31_inst(exe_jr31_inst),
        .exe_jal_inst(exe_jal_inst),
        .exe_branch_pc_bits(exe_branch_pc_bits),
        .exe_branch_other_addr(exe_branch_other_addr),
        .iss_rob_tag(iss_rob_tag),
        .iss_opcode(iss_opcode),
        .iss_rd_phy_addr(iss_rd_phy_addr),
        .iss_rw(iss_rw),
        .iss_imm16(iss_imm16),
        .iss_branch_other_addr(iss_branch_other_addr),
        .iss_branch_prediction(iss_branch_prediction),
        .iss_branch(iss_branch),
        .iss_jr_inst(iss_jr_inst),
        .iss_jr31_inst(iss_jr31_inst),
        .iss_jal_inst(iss_jal_inst),
        .iss_branch_pc_bits(iss_branch_pc_bits),
        .issue_int_en(issue_int_en),
        .issue_div_en(issue_div_en),
        .issue_mul_en(issue_mul_en),
        .div_unit_ready(div_unit_ready),
        .div_result_valid(div_result_valid),
        .div_rd_phy_addr(div_rd_phy_addr),
        .mul_result_valid(mul_result_valid),
        .mul_rd_phy_addr(mul_rd_phy_addr),
        .exe_rs_data_alu(exe_rs_data_alu),
        .exe_rt_data_alu(exe_rt_data_alu),
        .exe_rs_data_div(exe_rs_data_div),
        .exe_rt_data_div(exe_rt_data_div),
        .exe_rs_data_mul(exe_rs_data_mul),
        .exe_rt_data_mul(exe_rt_data_mul)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    int pass_cnt = 0;
    int fail_cnt = 0;

    task automatic check_bit(input string tag, input logic actual, input logic expected);
        if (actual !== expected) begin
            $error("[FAIL] %s: got %0b, want %0b @ %0t", tag, actual, expected, $time);
            fail_cnt++;
        end else pass_cnt++;
    endtask

    task automatic check_val(input string tag, input logic [63:0] actual, input logic [63:0] expected);
        if (actual !== expected) begin
            $error("[FAIL] %s: got 0x%0h, want 0x%0h @ %0t", tag, actual, expected, $time);
            fail_cnt++;
        end else pass_cnt++;
    endtask

    task automatic clear_issue();
        issue_int_en = 1'b0;
        issue_div_en = 1'b0;
        issue_mul_en = 1'b0;
        iss_rob_tag  = '0;
        iss_opcode   = INSTR_NONE;
        iss_rd_phy_addr = '0;
        iss_rw       = 1'b0;
        iss_imm16    = '0;
        iss_branch_other_addr = '0;
        iss_branch_prediction = 1'b0;
        iss_branch   = 1'b0;
        iss_jr_inst  = 1'b0;
        iss_jr31_inst = 1'b0;
        iss_jal_inst = 1'b0;
        iss_branch_pc_bits = '0;
    endtask

    task automatic reset_dut();
        rst_n = 1'b0;
        cdb_flush = 1'b0;
        cdb_rob_depth = '0;
        cdb_rob_tag = '0;
        clear_issue();
        exe_rs_data_alu = '0;
        exe_rt_data_alu = '0;
        exe_rs_data_div = '0;
        exe_rt_data_div = '0;
        exe_rs_data_mul = '0;
        exe_rt_data_mul = '0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;
    endtask

    task automatic cycle();
        clear_issue();
        @(posedge clk); #1;
    endtask

    initial begin
        `ifdef FSDB_DUMP
        $fsdbDumpfile("EXE.fsdb");
        $fsdbDumpvars(0, EXE_tb);
        `endif

        reset_dut();
        check_bit("div idle after reset", div_unit_ready, 1'b1);

        $display("\n[Test 1] ALU ADD completes one cycle after issue_int_en");
        iss_rob_tag       = 4'd3;
        iss_opcode        = INSTR_ADD;
        iss_rd_phy_addr   = 7'd10;
        iss_rw            = 1'b1;
        exe_rs_data_alu   = 64'd20;
        exe_rt_data_alu   = 64'd22;
        issue_int_en      = 1'b1;
        @(posedge clk); #1;
        issue_int_en      = 1'b0;
        check_bit("exe_valid registered", exe_valid, 1'b1);
        check_val("ADD result", exe_rd_data, 64'd42);
        check_val("rob tag", exe_rob_tag, 4'd3);
        check_val("rd phy", exe_rd_phy_addr, 7'd10);
        check_bit("reg write", exe_reg_write, 1'b1);
        cycle();
        check_bit("no valid without issue", exe_valid, 1'b0);

        $display("\n[Test 2] DIV issues, blocks unit, then broadcasts result");
        iss_rob_tag     = 4'd5;
        iss_opcode      = INSTR_DIV;
        iss_rd_phy_addr = 7'd11;
        exe_rs_data_div = 64'd100;
        exe_rt_data_div = 64'd5;
        issue_div_en    = 1'b1;
        @(posedge clk); #1;
        check_bit("div busy after issue", div_unit_ready, 1'b0);
        check_bit("no CDB yet", div_result_valid, 1'b0);
        cycle();
        repeat (DIV_CYCLES - 1) cycle();
        check_bit("div result valid", div_result_valid, 1'b1);
        check_val("quotient", exe_rd_data, 64'd20);
        check_val("div rd phy wakeup", div_rd_phy_addr, 7'd11);
        cycle();
        check_bit("unit ready again", div_unit_ready, 1'b1);
        cycle();

        $display("\n[Test 3] MUL pipelined completion");
        iss_rob_tag      = 4'd7;
        iss_opcode       = INSTR_MUL;
        iss_rd_phy_addr  = 7'd12;
        exe_rs_data_mul  = 64'd6;
        exe_rt_data_mul  = 64'd7;
        issue_mul_en     = 1'b1;
        @(posedge clk); #1;
        repeat (MUL_CYCLES) cycle();
        check_bit("mul result valid", mul_result_valid, 1'b1);
        check_val("product", exe_rd_data, 64'd42);
        check_val("mul rd phy", mul_rd_phy_addr, 7'd12);
        cycle();

        $display("\n============================================");
        if (fail_cnt == 0)
            $display("EXE_tb PASSED (%0d checks)", pass_cnt);
        else
            $display("EXE_tb FAILED: %0d failures, %0d passes", fail_cnt, pass_cnt);
        $display("============================================");
        $finish;
    end
endmodule
