/* verilator lint_off WIDTH */
// verilog_lint: waive-start explicit-parameter-storage-type
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module DISPATCH_tb;
    import riscv_opcode_pkg::*;
    import riscv_funct_pkg::*;
    import riscv_types_pkg::*;

    // ----------------------------------------------------------------
    // Parameters (smaller than default for faster simulation)
    // ----------------------------------------------------------------
    parameter int unsigned XLEN                    = 64;
    parameter int unsigned INSTR_WIDTH             = 32;
    parameter int unsigned IMEM_DEPTH              = 32;
    parameter int unsigned IMEM_WIDTH              = 32;
    parameter int unsigned IMEM_WIDTH_WORD         = IMEM_DEPTH - 1;
    parameter int unsigned DMEM_DEPTH              = 64;
    parameter int unsigned DMEM_WIDTH              = 64;
    parameter int unsigned ARCH_REG_COUNT          = 32;
    parameter int unsigned ARCH_REG_WIDTH          = $clog2(ARCH_REG_COUNT);
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7;
    parameter int unsigned ROB_DEPTH               = 32;
    parameter int unsigned ROB_INDEX_WIDTH         = $clog2(ROB_DEPTH);
    parameter int unsigned BPB_PC_BITS             = 3;
    parameter int unsigned OPCODE_WIDTH            = 6;

    // ----------------------------------------------------------------
    // DUT signals
    // ----------------------------------------------------------------
    logic clk, rst_n;

    // IFQ interface
    logic [INSTR_WIDTH-1:0]             ifetch_instr_in;
    logic [IMEM_DEPTH-1:0]              ifetch_pcplus4_in;
    logic [IMEM_DEPTH-1:0]              ifetch_pc;
    logic                               ifetch_empty;
    logic                               dis_ren;
    logic                               dis_jmpbr;
    logic [IMEM_WIDTH_WORD-1:0]         dis_jmpbr_addr;
    logic                               dis_jmpbr_addr_valid;

    // BPB interface
    logic                               bpb_branch_prediction;
    logic [BPB_PC_BITS-1:0]             dis_bpb_branch_pc_bits;
    logic                               dis_bpb_branch;

    // RAS interface
    logic [IMEM_WIDTH_WORD-1:0]         ras_addr;
    logic                               dis_ras_jr31_inst;
    logic                               dis_ras_jal_inst;
    logic [IMEM_DEPTH-1:0]              dis_pc_plus4;

    // FRL interface
    logic                               dis_frl_empty;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_frl_rd_phy_addr;
    logic                               dis_frl_read;

    // CDB interface
    logic                               cdb_valid;
    logic [IMEM_WIDTH_WORD-1:0]         cdb_branch_addr;
    logic                               cdb_flush;
    logic                               cdb_jalr_resolved;

    // FRAT interface
    logic                               frat_full;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] frat_rs_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] frat_rt_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] frat_rd_phy_addr;
    logic [ARCH_REG_WIDTH-1:0]          dis_rs_arch_addr;
    logic [ARCH_REG_WIDTH-1:0]          dis_rt_arch_addr;
    logic [ARCH_REG_WIDTH-1:0]          dis_rd_arch_addr;

    // Issue Queue interface
    logic issue_intq_full, issue_divq_full, issue_mulq_full, issue_ld_stq_full;
    logic issue_intq_two_or_more_vacant, issue_divq_two_or_more_vacant;
    logic issue_mulq_two_or_more_vacant, issue_ld_stq_two_or_more_vacant;

    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rs_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rt_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_new_rd_phy_addr;
    logic [OPCODE_WIDTH-1:0]            dis_opcode;
    logic [15:0]                        dis_imm16;
    logic [IMEM_DEPTH-1:0]              dis_branch_other_addr;
    logic                               dis_branch_prediction;
    logic                               dis_branch;
    logic [BPB_PC_BITS-1:0]             dis_branch_pc_bits;
    logic                               dis_jr_inst;
    logic                               dis_jal_inst;
    logic                               dis_jr31_inst;
    logic                               dis_int_issue_en;
    logic                               dis_div_issue_en;
    logic                               dis_mul_issue_en;
    logic                               dis_ld_st_issue_en;

    // ROB interface
    logic                               rob_full;
    logic                               rob_two_or_more_vacant;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_pre_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_new_phy_addr;
    logic [ARCH_REG_WIDTH-1:0]          dis_rob_rd_arch_addr;
    logic                               dis_inst_valid;
    logic                               dis_inst_sw;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_sw_rt_phy_addr;

    // RBA interface
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rba_new_rd_phy_addr;
    logic                               dis_rba_reg_write;

    // ----------------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------------
    DISPATCH #(
        .XLEN                    (XLEN),
        .INSTR_WIDTH             (INSTR_WIDTH),
        .IMEM_DEPTH              (IMEM_DEPTH),
        .IMEM_WIDTH              (IMEM_WIDTH),
        .IMEM_WIDTH_WORD         (IMEM_WIDTH_WORD),
        .DMEM_DEPTH              (DMEM_DEPTH),
        .DMEM_WIDTH              (DMEM_WIDTH),
        .ARCH_REG_COUNT          (ARCH_REG_COUNT),
        .ARCH_REG_WIDTH          (ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH (PHY_REGISTER_FILE_WIDTH),
        .ROB_DEPTH               (ROB_DEPTH),
        .ROB_INDEX_WIDTH         (ROB_INDEX_WIDTH),
        .BPB_PC_BITS             (BPB_PC_BITS),
        .OPCODE_WIDTH            (OPCODE_WIDTH)
    ) dut (.*);

    // ----------------------------------------------------------------
    // Clock
    // ----------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ----------------------------------------------------------------
    // Score keeping
    // ----------------------------------------------------------------
    int pass_cnt = 0;
    int fail_cnt = 0;

    task automatic check_val(
        input string tag,
        input logic [63:0] actual,
        input logic [63:0] expected
    );
        if (actual !== expected) begin
            $error("[FAIL] %s: got 0x%0h, want 0x%0h @ %0t", tag, actual, expected, $time);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
    endtask

    task automatic check_bit(
        input string tag,
        input logic  actual,
        input logic  expected
    );
        if (actual !== expected) begin
            $error("[FAIL] %s: got %0b, want %0b @ %0t", tag, actual, expected, $time);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
    endtask

    // ----------------------------------------------------------------
    // Instruction encoding helpers
    // ----------------------------------------------------------------
    function automatic logic [31:0] encode_r(
        input logic [6:0] funct7,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );
        return {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] encode_i(
        input logic [11:0] imm,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3,
        input logic [4:0]  rd,
        input logic [6:0]  opcode
    );
        return {imm, rs1, funct3, rd, opcode};
    endfunction

    function automatic logic [31:0] encode_s(
        input logic [11:0] imm,
        input logic [4:0]  rs2,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3,
        input logic [6:0]  opcode
    );
        return {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
    endfunction

    function automatic logic [31:0] encode_b(
        input logic [12:0] imm,
        input logic [4:0]  rs2,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3,
        input logic [6:0]  opcode
    );
        return {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode};
    endfunction

    function automatic logic [31:0] encode_j(
        input logic [20:0] imm,
        input logic [4:0]  rd,
        input logic [6:0]  opcode
    );
        return {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
    endfunction

    // Pre-built instruction encodings
    // ADD x3, x1, x2
    logic [31:0] INSTR_ADD_X3_X1_X2;
    assign INSTR_ADD_X3_X1_X2 = encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_ADD_SUB, 5'd3, OP_REG);

    // SUB x5, x3, x4
    logic [31:0] INSTR_SUB_X5_X3_X4;
    assign INSTR_SUB_X5_X3_X4 = encode_r(FUNCT7_ALT, 5'd4, 5'd3, FUNCT3_ADD_SUB, 5'd5, OP_REG);

    // ADDI x6, x1, 100
    logic [31:0] INSTR_ADDI_X6_X1_100;
    assign INSTR_ADDI_X6_X1_100 = encode_i(12'd100, 5'd1, FUNCT3_ADD_SUB, 5'd6, OP_IMM);

    // MUL x7, x1, x2
    logic [31:0] INSTR_MUL_X7_X1_X2;
    assign INSTR_MUL_X7_X1_X2 = encode_r(FUNCT7_MULDIV, 5'd2, 5'd1, FUNCT3_ADD_SUB, 5'd7, OP_REG);

    // DIV x8, x1, x2
    logic [31:0] INSTR_DIV_X8_X1_X2;
    assign INSTR_DIV_X8_X1_X2 = encode_r(FUNCT7_MULDIV, 5'd2, 5'd1, FUNCT3_XOR, 5'd8, OP_REG);

    // LW x9, 8(x1)
    logic [31:0] INSTR_LW_X9_8_X1;
    assign INSTR_LW_X9_8_X1 = encode_i(12'd8, 5'd1, FUNCT3_LW, 5'd9, OP_LOAD);

    // SW x2, 16(x1)
    logic [31:0] INSTR_SW_X2_16_X1;
    assign INSTR_SW_X2_16_X1 = encode_s(12'd16, 5'd2, 5'd1, FUNCT3_SW, OP_STORE);

    // BEQ x1, x2, +8
    logic [31:0] INSTR_BEQ_X1_X2_8;
    assign INSTR_BEQ_X1_X2_8 = encode_b(13'd8, 5'd2, 5'd1, FUNCT3_BEQ, OP_BRANCH);

    // BNE x3, x4, +16
    logic [31:0] INSTR_BNE_X3_X4_16;
    assign INSTR_BNE_X3_X4_16 = encode_b(13'd16, 5'd4, 5'd3, FUNCT3_BNE, OP_BRANCH);

    // AND x10, x1, x2
    logic [31:0] INSTR_AND_X10_X1_X2;
    assign INSTR_AND_X10_X1_X2 = encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_AND, 5'd10, OP_REG);

    // OR x11, x1, x2
    logic [31:0] INSTR_OR_X11_X1_X2;
    assign INSTR_OR_X11_X1_X2 = encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_OR, 5'd11, OP_REG);

    // SLT x12, x1, x2
    logic [31:0] INSTR_SLT_X12_X1_X2;
    assign INSTR_SLT_X12_X1_X2 = encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_SLT, 5'd12, OP_REG);

    // JAL x1, +64
    logic [31:0] INSTR_JAL_X1_64;
    assign INSTR_JAL_X1_64 = encode_j(21'd64, 5'd1, OP_JAL);

    // JALR x0, x1, 0  (JR x1 — rd == x0, rs != x1 treated as jr_inst)
    logic [31:0] INSTR_JALR_X0_X1_0;
    assign INSTR_JALR_X0_X1_0 = encode_i(12'd0, 5'd1, 3'b000, 5'd0, OP_JALR);

    // NOP (ADDI x0, x0, 0)
    logic [31:0] INSTR_NOP;
    assign INSTR_NOP = encode_i(12'd0, 5'd0, FUNCT3_ADD_SUB, 5'd0, OP_IMM);

    // ADD x0, x1, x2 (writes to x0 — should NOT allocate physical register)
    logic [31:0] INSTR_ADD_X0_X1_X2;
    assign INSTR_ADD_X0_X1_X2 = encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_ADD_SUB, 5'd0, OP_REG);

    // JALR x5, 0(x3) — general JALR (rd!=x0, rs!=x1 → jal_inst=1, jr_inst=1)
    logic [31:0] INSTR_JALR_X5_X3_0;
    assign INSTR_JALR_X5_X3_0 = encode_i(12'd0, 5'd3, 3'b000, 5'd5, OP_JALR);

    // JALR x0, 0(x3) — JR x3 (rd=x0, rs!=x1 → jr_inst=1 only)
    logic [31:0] INSTR_JALR_X0_X3_0;
    assign INSTR_JALR_X0_X3_0 = encode_i(12'd0, 5'd3, 3'b000, 5'd0, OP_JALR);

    // ----------------------------------------------------------------
    // Helper tasks
    // ----------------------------------------------------------------
    task automatic clear_inputs();
        ifetch_instr_in     = '0;
        ifetch_pcplus4_in   = '0;
        ifetch_pc           = '0;
        ifetch_empty        = 1'b1;
        bpb_branch_prediction = 1'b0;
        ras_addr            = '0;
        dis_frl_empty       = 1'b0;
        dis_frl_rd_phy_addr = '0;
        cdb_valid           = 1'b0;
        cdb_branch_addr     = '0;
        cdb_flush           = 1'b0;
        cdb_jalr_resolved   = 1'b0;
        frat_full           = 1'b0;
        frat_rs_phy_addr    = '0;
        frat_rt_phy_addr    = '0;
        frat_rd_phy_addr    = '0;
        issue_intq_full     = 1'b0;
        issue_divq_full     = 1'b0;
        issue_mulq_full     = 1'b0;
        issue_ld_stq_full   = 1'b0;
        issue_intq_two_or_more_vacant = 1'b1;
        issue_divq_two_or_more_vacant = 1'b1;
        issue_mulq_two_or_more_vacant = 1'b1;
        issue_ld_stq_two_or_more_vacant = 1'b1;
        rob_full            = 1'b0;
        rob_two_or_more_vacant = 1'b1;
    endtask

    task automatic reset_dut();
        rst_n = 1'b0;
        clear_inputs();
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;
    endtask

    // Present an instruction to stage 1 and let it propagate to stage 2.
    // Returns after stage 2 has valid outputs (2 clock edges).
    task automatic present_instr(
        input logic [31:0] instr,
        input logic [IMEM_DEPTH-1:0] pc_val,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] frl_phy,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] frat_rs,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] frat_rt,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] frat_rd
    );
        ifetch_instr_in     = instr;
        ifetch_pc           = pc_val;
        ifetch_pcplus4_in   = pc_val + 4;
        ifetch_empty        = 1'b0;
        dis_frl_rd_phy_addr = frl_phy;
        frat_rs_phy_addr    = frat_rs;
        frat_rt_phy_addr    = frat_rt;
        frat_rd_phy_addr    = frat_rd;
        @(posedge clk); #1;
        // stage 1 captured; now advance to stage 2
        ifetch_empty = 1'b1;
        @(posedge clk); #1;
    endtask

    // Present instruction to stage 1 only (don't wait for stage 2)
    task automatic present_instr_stage1(
        input logic [31:0] instr,
        input logic [IMEM_DEPTH-1:0] pc_val,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] frl_phy,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] frat_rs,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] frat_rt,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] frat_rd
    );
        ifetch_instr_in     = instr;
        ifetch_pc           = pc_val;
        ifetch_pcplus4_in   = pc_val + 4;
        ifetch_empty        = 1'b0;
        dis_frl_rd_phy_addr = frl_phy;
        frat_rs_phy_addr    = frat_rs;
        frat_rt_phy_addr    = frat_rt;
        frat_rd_phy_addr    = frat_rd;
    endtask

    // ----------------------------------------------------------------
    // Main test
    // ----------------------------------------------------------------
    initial begin
        `ifdef FSDB_DUMP
            $fsdbDumpfile("DISPATCH.fsdb");
            $fsdbDumpvars(0, DISPATCH_tb);
        `else
            $dumpfile("DISPATCH.vcd");
            $dumpvars(0, DISPATCH_tb);
        `endif

        $display("=======================================");
        $display("  DISPATCH Testbench Start");
        $display("=======================================");

        // ==============================================================
        // Test 1: Reset state — stage2 outputs should be invalid
        // ==============================================================
        $display("\n[Test 1] Reset state");
        reset_dut();
        check_bit("dis_inst_valid after reset", dis_inst_valid, 1'b0);
        check_bit("dis_int_issue_en after reset", dis_int_issue_en, 1'b0);
        check_bit("dis_div_issue_en after reset", dis_div_issue_en, 1'b0);
        check_bit("dis_mul_issue_en after reset", dis_mul_issue_en, 1'b0);
        check_bit("dis_ld_st_issue_en after reset", dis_ld_st_issue_en, 1'b0);
        check_bit("dis_rba_reg_write after reset", dis_rba_reg_write, 1'b0);

        // ==============================================================
        // Test 2: IFQ empty — should stall (dis_ren = 0)
        // ==============================================================
        $display("\n[Test 2] IFQ empty stall");
        reset_dut();
        ifetch_empty = 1'b1;
        @(posedge clk); #1;
        check_bit("dis_ren when IFQ empty", dis_ren, 1'b0);
        check_bit("dis_inst_valid when IFQ empty", dis_inst_valid, 1'b0);

        // ==============================================================
        // Test 3: Simple ADD dispatch — R-type, routed to INT queue
        // ==============================================================
        $display("\n[Test 3] ADD x3, x1, x2 — INT issue");
        reset_dut();
        present_instr(
            .instr(INSTR_ADD_X3_X1_X2),
            .pc_val(32'h0000_0010),
            .frl_phy(7'd40),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd3)
        );
        check_bit("dis_inst_valid for ADD", dis_inst_valid, 1'b1);
        check_bit("dis_int_issue_en for ADD", dis_int_issue_en, 1'b1);
        check_bit("dis_mul_issue_en for ADD", dis_mul_issue_en, 1'b0);
        check_bit("dis_div_issue_en for ADD", dis_div_issue_en, 1'b0);
        check_bit("dis_ld_st_issue_en for ADD", dis_ld_st_issue_en, 1'b0);
        check_val("dis_opcode for ADD", dis_opcode, INSTR_ADD);
        check_val("dis_rs_phy_addr for ADD", dis_rs_phy_addr, 7'd1);
        check_val("dis_rt_phy_addr for ADD", dis_rt_phy_addr, 7'd2);
        check_val("dis_pre_phy_addr for ADD", dis_pre_phy_addr, 7'd3);
        check_val("dis_new_phy_addr for ADD", dis_new_phy_addr, 7'd40);
        check_val("dis_rob_rd_arch_addr for ADD", dis_rob_rd_arch_addr, 5'd3);
        check_bit("dis_rba_reg_write for ADD", dis_rba_reg_write, 1'b1);

        // ==============================================================
        // Test 4: SUB dispatch — also INT queue
        // ==============================================================
        $display("\n[Test 4] SUB x5, x3, x4 — INT issue");
        reset_dut();
        present_instr(
            .instr(INSTR_SUB_X5_X3_X4),
            .pc_val(32'h0000_0020),
            .frl_phy(7'd41),
            .frat_rs(7'd33),
            .frat_rt(7'd34),
            .frat_rd(7'd35)
        );
        check_bit("dis_int_issue_en for SUB", dis_int_issue_en, 1'b1);
        check_val("dis_opcode for SUB", dis_opcode, INSTR_SUB);
        check_val("dis_rs_phy_addr for SUB", dis_rs_phy_addr, 7'd33);
        check_val("dis_rt_phy_addr for SUB", dis_rt_phy_addr, 7'd34);

        // ==============================================================
        // Test 5: ADDI dispatch — I-type, INT queue
        // ==============================================================
        $display("\n[Test 5] ADDI x6, x1, 100 — INT issue");
        reset_dut();
        present_instr(
            .instr(INSTR_ADDI_X6_X1_100),
            .pc_val(32'h0000_0030),
            .frl_phy(7'd42),
            .frat_rs(7'd1),
            .frat_rt(7'd0),
            .frat_rd(7'd6)
        );
        check_bit("dis_int_issue_en for ADDI", dis_int_issue_en, 1'b1);
        check_val("dis_opcode for ADDI", dis_opcode, INSTR_ADDI);
        check_val("dis_imm16 for ADDI", dis_imm16, 16'd100);

        // ==============================================================
        // Test 6: MUL dispatch — routed to MUL queue
        // ==============================================================
        $display("\n[Test 6] MUL x7, x1, x2 — MUL issue");
        reset_dut();
        present_instr(
            .instr(INSTR_MUL_X7_X1_X2),
            .pc_val(32'h0000_0040),
            .frl_phy(7'd43),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd7)
        );
        check_bit("dis_mul_issue_en for MUL", dis_mul_issue_en, 1'b1);
        check_bit("dis_int_issue_en for MUL", dis_int_issue_en, 1'b0);
        check_val("dis_opcode for MUL", dis_opcode, INSTR_MUL);

        // ==============================================================
        // Test 7: DIV dispatch — routed to DIV queue
        // ==============================================================
        $display("\n[Test 7] DIV x8, x1, x2 — DIV issue");
        reset_dut();
        present_instr(
            .instr(INSTR_DIV_X8_X1_X2),
            .pc_val(32'h0000_0050),
            .frl_phy(7'd44),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd8)
        );
        check_bit("dis_div_issue_en for DIV", dis_div_issue_en, 1'b1);
        check_bit("dis_int_issue_en for DIV", dis_int_issue_en, 1'b0);
        check_val("dis_opcode for DIV", dis_opcode, INSTR_DIV);

        // ==============================================================
        // Test 8: LW dispatch — routed to LD/ST queue
        // ==============================================================
        $display("\n[Test 8] LW x9, 8(x1) — LD_ST issue");
        reset_dut();
        present_instr(
            .instr(INSTR_LW_X9_8_X1),
            .pc_val(32'h0000_0060),
            .frl_phy(7'd45),
            .frat_rs(7'd1),
            .frat_rt(7'd0),
            .frat_rd(7'd9)
        );
        check_bit("dis_ld_st_issue_en for LW", dis_ld_st_issue_en, 1'b1);
        check_val("dis_opcode for LW", dis_opcode, INSTR_LW);
        check_val("dis_imm16 for LW", dis_imm16, 16'd8);
        check_bit("dis_inst_sw for LW", dis_inst_sw, 1'b0);
        check_bit("dis_rba_reg_write for LW", dis_rba_reg_write, 1'b1);

        // ==============================================================
        // Test 9: SW dispatch — routed to LD/ST queue, mw set
        // ==============================================================
        $display("\n[Test 9] SW x2, 16(x1) — LD_ST issue, mem write");
        reset_dut();
        present_instr(
            .instr(INSTR_SW_X2_16_X1),
            .pc_val(32'h0000_0070),
            .frl_phy(7'd46),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd0)
        );
        check_bit("dis_ld_st_issue_en for SW", dis_ld_st_issue_en, 1'b1);
        check_val("dis_opcode for SW", dis_opcode, INSTR_SW);
        check_bit("dis_inst_sw for SW", dis_inst_sw, 1'b1);
        check_bit("dis_rba_reg_write for SW", dis_rba_reg_write, 1'b0);

        // ==============================================================
        // Test 10: BEQ dispatch, not-taken prediction — INT queue
        // ==============================================================
        $display("\n[Test 10] BEQ x1, x2, +8 — branch, predict not-taken");
        reset_dut();
        bpb_branch_prediction = 1'b0;
        present_instr(
            .instr(INSTR_BEQ_X1_X2_8),
            .pc_val(32'h0000_0100),
            .frl_phy(7'd47),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd0)
        );
        check_bit("dis_branch for BEQ", dis_branch, 1'b1);
        check_bit("dis_branch_prediction for BEQ not-taken", dis_branch_prediction, 1'b0);
        check_bit("dis_int_issue_en for BEQ", dis_int_issue_en, 1'b1);
        check_bit("dis_rba_reg_write for BEQ", dis_rba_reg_write, 1'b0);

        // ==============================================================
        // Test 11: BNE with taken prediction — redirect
        // ==============================================================
        $display("\n[Test 11] BNE x3, x4, +16 — branch, predict taken");
        reset_dut();
        bpb_branch_prediction = 1'b1;
        present_instr_stage1(
            .instr(INSTR_BNE_X3_X4_16),
            .pc_val(32'h0000_0200),
            .frl_phy(7'd48),
            .frat_rs(7'd3),
            .frat_rt(7'd4),
            .frat_rd(7'd0)
        );
        #1;
        check_bit("dis_jmpbr for BNE taken", dis_jmpbr, 1'b1);
        check_bit("dis_jmpbr_addr_valid for BNE taken", dis_jmpbr_addr_valid, 1'b1);
        check_bit("dis_bpb_branch for BNE", dis_bpb_branch, 1'b1);
        @(posedge clk); #1;
        ifetch_empty = 1'b1;
        @(posedge clk); #1;
        check_bit("dis_branch_prediction for BNE taken", dis_branch_prediction, 1'b1);

        // ==============================================================
        // Test 12: Write to x0 — should NOT set reg_write
        // ==============================================================
        $display("\n[Test 12] ADD x0, x1, x2 — no reg write for x0");
        reset_dut();
        present_instr(
            .instr(INSTR_ADD_X0_X1_X2),
            .pc_val(32'h0000_0300),
            .frl_phy(7'd50),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd0)
        );
        check_bit("dis_rba_reg_write for ADD x0", dis_rba_reg_write, 1'b0);
        check_bit("dis_frl_read should not fire for x0 dest", dis_frl_read, 1'b0);

        // ==============================================================
        // Test 13: ROB full stall
        // ==============================================================
        $display("\n[Test 13] ROB full stall");
        reset_dut();
        rob_full = 1'b1;
        present_instr_stage1(
            .instr(INSTR_ADD_X3_X1_X2),
            .pc_val(32'h0000_0400),
            .frl_phy(7'd51),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd3)
        );
        @(posedge clk); #1;
        check_bit("dis_ren when ROB full", dis_ren, 1'b0);
        @(posedge clk); #1;
        check_bit("dis_inst_valid when ROB full", dis_inst_valid, 1'b0);

        // ==============================================================
        // Test 14: FRL empty stall for reg-write instruction
        // ==============================================================
        $display("\n[Test 14] FRL empty stall");
        reset_dut();
        dis_frl_empty = 1'b1;
        present_instr_stage1(
            .instr(INSTR_ADD_X3_X1_X2),
            .pc_val(32'h0000_0500),
            .frl_phy(7'd52),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd3)
        );
        @(posedge clk); #1;
        check_bit("dis_ren when FRL empty (reg-write instr)", dis_ren, 1'b0);

        // ==============================================================
        // Test 15: FRL empty should NOT stall SW (no reg write)
        // ==============================================================
        $display("\n[Test 15] FRL empty does NOT stall SW");
        reset_dut();
        dis_frl_empty = 1'b1;
        present_instr_stage1(
            .instr(INSTR_SW_X2_16_X1),
            .pc_val(32'h0000_0600),
            .frl_phy(7'd53),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd0)
        );
        #1;
        check_bit("dis_ren when FRL empty (SW, no reg write)", dis_ren, 1'b1);

        // ==============================================================
        // Test 16: INT queue full stall
        // ==============================================================
        $display("\n[Test 16] INT queue full stall");
        reset_dut();
        issue_intq_full = 1'b1;
        present_instr_stage1(
            .instr(INSTR_ADD_X3_X1_X2),
            .pc_val(32'h0000_0700),
            .frl_phy(7'd54),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd3)
        );
        @(posedge clk); #1;
        check_bit("dis_ren when INT queue full (ADD)", dis_ren, 1'b0);

        // ==============================================================
        // Test 17: MUL queue full does NOT stall ADD
        // ==============================================================
        $display("\n[Test 17] MUL queue full does NOT stall ADD");
        reset_dut();
        issue_mulq_full = 1'b1;
        present_instr_stage1(
            .instr(INSTR_ADD_X3_X1_X2),
            .pc_val(32'h0000_0800),
            .frl_phy(7'd55),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd3)
        );
        #1;
        check_bit("dis_ren when MUL full but ADD instr", dis_ren, 1'b1);

        // ==============================================================
        // Test 18: FRAT full stall for branch
        // ==============================================================
        $display("\n[Test 18] FRAT full stall for branch");
        reset_dut();
        frat_full = 1'b1;
        present_instr_stage1(
            .instr(INSTR_BEQ_X1_X2_8),
            .pc_val(32'h0000_0900),
            .frl_phy(7'd56),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd0)
        );
        @(posedge clk); #1;
        check_bit("dis_ren when FRAT full (branch)", dis_ren, 1'b0);

        // ==============================================================
        // Test 19: FRAT full does NOT stall non-branch
        // ==============================================================
        $display("\n[Test 19] FRAT full does NOT stall ADD");
        reset_dut();
        frat_full = 1'b1;
        present_instr_stage1(
            .instr(INSTR_ADD_X3_X1_X2),
            .pc_val(32'h0000_0A00),
            .frl_phy(7'd57),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd3)
        );
        #1;
        check_bit("dis_ren when FRAT full but ADD", dis_ren, 1'b1);

        // ==============================================================
        // Test 20: CDB flush invalidates stage 2
        // ==============================================================
        $display("\n[Test 20] CDB flush invalidates pipeline");
        reset_dut();
        present_instr_stage1(
            .instr(INSTR_ADD_X3_X1_X2),
            .pc_val(32'h0000_0B00),
            .frl_phy(7'd58),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd3)
        );
        @(posedge clk); #1;
        // Instruction is now in stage 2; flush
        cdb_flush = 1'b1;
        cdb_valid = 1'b1;
        cdb_branch_addr = 31'h0000_100;
        @(posedge clk); #1;
        check_bit("dis_inst_valid after CDB flush", dis_inst_valid, 1'b0);
        cdb_flush = 1'b0;
        cdb_valid = 1'b0;

        // ==============================================================
        // Test 21: Rename forwarding — stage 2 writes same arch reg
        //          that stage 1 reads
        // ==============================================================
        $display("\n[Test 21] Rename forwarding from stage 2 to stage 1");
        reset_dut();
        // Instruction 1: ADD x3, x1, x2 (writes x3, gets phy reg 60)
        present_instr_stage1(
            .instr(INSTR_ADD_X3_X1_X2),
            .pc_val(32'h0000_0C00),
            .frl_phy(7'd60),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd3)
        );
        @(posedge clk); #1;
        // Instruction 2: SUB x5, x3, x4 (reads x3 — should be forwarded)
        // FRAT still returns old phy for x3 (say 3), but forwarding should give 60
        ifetch_instr_in     = INSTR_SUB_X5_X3_X4;
        ifetch_pc           = 32'h0000_0C04;
        ifetch_pcplus4_in   = 32'h0000_0C08;
        ifetch_empty        = 1'b0;
        dis_frl_rd_phy_addr = 7'd61;
        frat_rs_phy_addr    = 7'd3;  // old mapping of x3
        frat_rt_phy_addr    = 7'd4;
        frat_rd_phy_addr    = 7'd5;
        @(posedge clk); #1;
        // Now SUB is in stage 2; check its source registers
        ifetch_empty = 1'b1;
        @(posedge clk); #1;
        // dis_rs_phy_addr should be 60 (forwarded from ADD), not 3
        check_val("forwarded rs_phy_addr for SUB", dis_rs_phy_addr, 7'd60);
        check_val("non-forwarded rt_phy_addr for SUB", dis_rt_phy_addr, 7'd4);

        // ==============================================================
        // Test 22: ROB single-entry stall when stage 2 is valid
        // ==============================================================
        $display("\n[Test 22] ROB single-entry stall");
        reset_dut();
        rob_two_or_more_vacant = 1'b0;
        // First instruction goes to stage 2
        present_instr_stage1(
            .instr(INSTR_ADD_X3_X1_X2),
            .pc_val(32'h0000_0D00),
            .frl_phy(7'd62),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd3)
        );
        @(posedge clk); #1;
        // Stage 2 is now valid; second instruction should stall
        ifetch_instr_in = INSTR_SUB_X5_X3_X4;
        ifetch_empty = 1'b0;
        @(posedge clk); #1;
        check_bit("dis_ren when ROB has 1 entry and stage2 valid", dis_ren, 1'b0);

        // ==============================================================
        // Test 23: Back-to-back dispatch (no stall)
        // ==============================================================
        $display("\n[Test 23] Back-to-back dispatch");
        reset_dut();
        // Feed ADD then SUB without gap
        present_instr_stage1(
            .instr(INSTR_ADD_X3_X1_X2),
            .pc_val(32'h0000_1000),
            .frl_phy(7'd70),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd3)
        );
        @(posedge clk); #1;
        // ADD now in stage 2, SUB in stage 1
        present_instr_stage1(
            .instr(INSTR_SUB_X5_X3_X4),
            .pc_val(32'h0000_1004),
            .frl_phy(7'd71),
            .frat_rs(7'd33),
            .frat_rt(7'd34),
            .frat_rd(7'd35)
        );
        // Check ADD in stage 2
        check_bit("ADD fires in stage 2", dis_inst_valid, 1'b1);
        check_val("ADD opcode in stage 2", dis_opcode, INSTR_ADD);
        @(posedge clk); #1;
        // Now SUB should be in stage 2
        ifetch_empty = 1'b1;
        @(posedge clk); #1;
        check_bit("SUB fires in stage 2", dis_inst_valid, 1'b1);
        check_val("SUB opcode in stage 2", dis_opcode, INSTR_SUB);

        // ==============================================================
        // Test 24: AND, OR, SLT instructions — all INT queue
        // ==============================================================
        $display("\n[Test 24] AND, OR, SLT — INT issue");
        reset_dut();
        present_instr(
            .instr(INSTR_AND_X10_X1_X2),
            .pc_val(32'h0000_2000),
            .frl_phy(7'd72),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd10)
        );
        check_bit("AND int issue", dis_int_issue_en, 1'b1);
        check_val("AND opcode", dis_opcode, INSTR_AND);

        reset_dut();
        present_instr(
            .instr(INSTR_OR_X11_X1_X2),
            .pc_val(32'h0000_2004),
            .frl_phy(7'd73),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd11)
        );
        check_bit("OR int issue", dis_int_issue_en, 1'b1);
        check_val("OR opcode", dis_opcode, INSTR_OR);

        reset_dut();
        present_instr(
            .instr(INSTR_SLT_X12_X1_X2),
            .pc_val(32'h0000_2008),
            .frl_phy(7'd74),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd12)
        );
        check_bit("SLT int issue", dis_int_issue_en, 1'b1);
        check_val("SLT opcode", dis_opcode, INSTR_SLT);

        // ==============================================================
        // Test 25: dis_pc_plus4 passthrough
        // ==============================================================
        $display("\n[Test 25] dis_pc_plus4 passthrough");
        reset_dut();
        present_instr_stage1(
            .instr(INSTR_ADD_X3_X1_X2),
            .pc_val(32'h0000_3000),
            .frl_phy(7'd75),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd3)
        );
        #1;
        check_val("dis_pc_plus4", dis_pc_plus4, 32'h0000_3004);

        // ==============================================================
        // Test 26: BPB address bits
        // ==============================================================
        $display("\n[Test 26] BPB PC bits extraction");
        reset_dut();
        present_instr_stage1(
            .instr(INSTR_BEQ_X1_X2_8),
            .pc_val(32'h0000_001C),  // bits [4:2] = 3'b111
            .frl_phy(7'd76),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd0)
        );
        #1;
        check_val("dis_bpb_branch_pc_bits", dis_bpb_branch_pc_bits, 3'b111);

        // ==============================================================
        // Test 27: Issue queue two_or_more_vacant stall
        // ==============================================================
        $display("\n[Test 27] INT queue single-entry stall with same type in stage 2");
        reset_dut();
        issue_intq_two_or_more_vacant = 1'b0;
        // First ADD goes to stage 1 then stage 2
        present_instr_stage1(
            .instr(INSTR_ADD_X3_X1_X2),
            .pc_val(32'h0000_4000),
            .frl_phy(7'd80),
            .frat_rs(7'd1),
            .frat_rt(7'd2),
            .frat_rd(7'd3)
        );
        @(posedge clk); #1;
        // ADD is now in stage 2 (INT issue), feed another ADD to stage 1
        ifetch_instr_in = INSTR_SUB_X5_X3_X4;
        ifetch_empty = 1'b0;
        dis_frl_rd_phy_addr = 7'd81;
        @(posedge clk); #1;
        // Should stall: stage 2 has INT, stage 1 has INT, only 1 entry in INT queue
        check_bit("dis_ren stall: 1 INT entry, both stages INT", dis_ren, 1'b0);

        // ==============================================================
        // Test 28: RAS signals for JAL
        // ==============================================================
        $display("\n[Test 28] RAS jal_inst signal");
        reset_dut();
        present_instr_stage1(
            .instr(INSTR_JAL_X1_64),
            .pc_val(32'h0000_5000),
            .frl_phy(7'd82),
            .frat_rs(7'd0),
            .frat_rt(7'd0),
            .frat_rd(7'd1)
        );
        #1;
        check_bit("dis_ras_jal_inst for JAL", dis_ras_jal_inst, 1'b1);
        check_bit("dis_jmpbr for JAL", dis_jmpbr, 1'b1);
        check_bit("dis_jmpbr_addr_valid for JAL", dis_jmpbr_addr_valid, 1'b1);

        // ==============================================================
        // Test 29: RAS signals for JALR x0, x1, 0 (return)
        // ==============================================================
        $display("\n[Test 29] RAS jr31_inst signal for JALR return");
        reset_dut();
        // JALR x0, x1, 0 — rs=x1 triggers jr31_inst
        ifetch_instr_in = encode_i(12'd0, 5'd1, 3'b000, 5'd0, OP_JALR);
        ifetch_pc = 32'h0000_6000;
        ifetch_pcplus4_in = 32'h0000_6004;
        ifetch_empty = 1'b0;
        dis_frl_rd_phy_addr = 7'd83;
        frat_rs_phy_addr = 7'd1;
        frat_rt_phy_addr = 7'd0;
        frat_rd_phy_addr = 7'd0;
        ras_addr = 31'h0000_200;
        #1;
        check_bit("dis_ras_jr31_inst for JALR return", dis_ras_jr31_inst, 1'b1);
        check_bit("dis_jmpbr for JALR return", dis_jmpbr, 1'b1);
        check_bit("dis_jmpbr_addr_valid for return", dis_jmpbr_addr_valid, 1'b1);
        check_val("dis_jmpbr_addr uses RAS", dis_jmpbr_addr, 31'h0000_200);

        // ==============================================================
        // Test 30: NOP (ADDI x0, x0, 0) — should not write regs
        // ==============================================================
        $display("\n[Test 30] NOP instruction");
        reset_dut();
        present_instr(
            .instr(INSTR_NOP),
            .pc_val(32'h0000_7000),
            .frl_phy(7'd84),
            .frat_rs(7'd0),
            .frat_rt(7'd0),
            .frat_rd(7'd0)
        );
        check_bit("dis_rba_reg_write for NOP", dis_rba_reg_write, 1'b0);
        check_bit("dis_int_issue_en for NOP", dis_int_issue_en, 1'b1);

        // ==============================================================
        // Test 31: JAL x1, +64 — full stage 1 redirect + stage 2 dispatch
        // ==============================================================
        $display("\n[Test 31] JAL x1, +64 — full dispatch");
        reset_dut();
        present_instr_stage1(
            .instr(INSTR_JAL_X1_64),
            .pc_val(32'h0000_5000),
            .frl_phy(7'd85),
            .frat_rs(7'd0),
            .frat_rt(7'd0),
            .frat_rd(7'd1)
        );
        #1;
        // Stage 1: JAL triggers redirect (jal_inst && !jr_inst)
        check_bit("JAL s1: dis_ren", dis_ren, 1'b1);
        check_bit("JAL s1: dis_jmpbr", dis_jmpbr, 1'b1);
        check_bit("JAL s1: dis_jmpbr_addr_valid", dis_jmpbr_addr_valid, 1'b1);
        // JAL target = PC + imm = 0x5000 + 64 = 0x5040
        check_val("JAL s1: redirect addr", dis_jmpbr_addr, (32'h0000_5040) >> 1);
        check_bit("JAL s1: dis_ras_jal_inst", dis_ras_jal_inst, 1'b1);
        // Advance to stage 2
        @(posedge clk); #1;
        ifetch_empty = 1'b1;
        @(posedge clk); #1;
        check_bit("JAL s2: dis_inst_valid", dis_inst_valid, 1'b1);
        check_val("JAL s2: dis_opcode", dis_opcode, INSTR_JAL);
        check_bit("JAL s2: dis_jal_inst", dis_jal_inst, 1'b1);
        check_bit("JAL s2: dis_jr_inst=0", dis_jr_inst, 1'b0);
        check_bit("JAL s2: dis_rba_reg_write (rd=x1)", dis_rba_reg_write, 1'b1);
        check_val("JAL s2: dis_rob_rd_arch_addr", dis_rob_rd_arch_addr, 5'd1);
        check_bit("JAL s2: dis_int_issue_en", dis_int_issue_en, 1'b1);

        // ==============================================================
        // Test 32: JALR x5, 0(x3) — general JALR stall + cdb_jalr_resolved
        // Decoder: jal_inst=1, jr_inst=1, rw=1, rd=x5, rs=x3
        // ==============================================================
        $display("\n[Test 32] JALR x5, 0(x3) — stall + cdb_jalr_resolved");
        reset_dut();
        present_instr_stage1(
            .instr(INSTR_JALR_X5_X3_0),
            .pc_val(32'h0000_8000),
            .frl_phy(7'd86),
            .frat_rs(7'd3),
            .frat_rt(7'd0),
            .frat_rd(7'd5)
        );
        #1;
        // Cycle 0: JALR in stage 1
        // jr_two_stage_one_extra_instr=1 → stage1_valid=1 (override stall)
        check_bit("JALR c0: dis_ren (IFQ pops)", dis_ren, 1'b1);
        // No redirect yet: jr_fetch_hold=0, jr31=0, jal&&!jr=0, branch=0
        check_bit("JALR c0: dis_jmpbr=0", dis_jmpbr, 1'b0);

        @(posedge clk); #1;
        // Cycle 1: JALR moved to stage 2, jr_stall=1
        check_bit("JALR c1: dis_inst_valid", dis_inst_valid, 1'b1);
        check_val("JALR c1: dis_opcode", dis_opcode, INSTR_JALR);
        check_bit("JALR c1: dis_jr_inst", dis_jr_inst, 1'b1);
        check_bit("JALR c1: dis_jal_inst", dis_jal_inst, 1'b1);
        check_bit("JALR c1: dis_rba_reg_write (rd=x5)", dis_rba_reg_write, 1'b1);
        check_val("JALR c1: dis_rob_rd_arch_addr", dis_rob_rd_arch_addr, 5'd5);
        check_bit("JALR c1: dis_int_issue_en", dis_int_issue_en, 1'b1);
        // Fetch held by jr_stall
        check_bit("JALR c1: dis_jmpbr (fetch hold)", dis_jmpbr, 1'b1);
        check_bit("JALR c1: dis_jmpbr_addr_valid=0", dis_jmpbr_addr_valid, 1'b0);

        @(posedge clk); #1;
        // Cycle 2: stage2 now invalid (stage1_valid was 0 last cycle), stall continues
        check_bit("JALR c2: dis_inst_valid=0", dis_inst_valid, 1'b0);
        check_bit("JALR c2: dis_jmpbr (still held)", dis_jmpbr, 1'b1);

        // Assert cdb_jalr_resolved with target address
        cdb_jalr_resolved = 1'b1;
        cdb_branch_addr = 31'h0000_400;
        #1;
        check_bit("JALR resolve: dis_jmpbr_addr_valid", dis_jmpbr_addr_valid, 1'b1);
        check_val("JALR resolve: dis_jmpbr_addr", dis_jmpbr_addr, 31'h0000_400);

        @(posedge clk); #1;
        cdb_jalr_resolved = 1'b0;
        // jr_stall cleared on posedge
        check_bit("JALR post-resolve: jr_stall=0", dut.jr_stall, 1'b0);

        // ==============================================================
        // Test 33: JALR x0, 0(x3) — JR (no reg write) stall + resolve
        // Decoder: jr_inst=1, jal_inst=0, rw=0, rd=x0
        // ==============================================================
        $display("\n[Test 33] JALR x0, 0(x3) — JR, no reg write");
        reset_dut();
        present_instr_stage1(
            .instr(INSTR_JALR_X0_X3_0),
            .pc_val(32'h0000_9000),
            .frl_phy(7'd87),
            .frat_rs(7'd3),
            .frat_rt(7'd0),
            .frat_rd(7'd0)
        );
        #1;
        check_bit("JR c0: dis_ren (IFQ pops)", dis_ren, 1'b1);

        @(posedge clk); #1;
        // Stage 2: dispatches but no register write
        check_bit("JR c1: dis_inst_valid", dis_inst_valid, 1'b1);
        check_val("JR c1: dis_opcode", dis_opcode, INSTR_JALR);
        check_bit("JR c1: dis_jr_inst", dis_jr_inst, 1'b1);
        check_bit("JR c1: dis_jal_inst=0", dis_jal_inst, 1'b0);
        check_bit("JR c1: dis_rba_reg_write=0 (rd=x0)", dis_rba_reg_write, 1'b0);
        check_bit("JR c1: dis_jmpbr (fetch hold)", dis_jmpbr, 1'b1);

        // Resolve
        @(posedge clk); #1;
        cdb_jalr_resolved = 1'b1;
        cdb_branch_addr = 31'h0000_500;
        #1;
        check_bit("JR resolve: dis_jmpbr_addr_valid", dis_jmpbr_addr_valid, 1'b1);
        check_val("JR resolve: dis_jmpbr_addr", dis_jmpbr_addr, 31'h0000_500);

        @(posedge clk); #1;
        cdb_jalr_resolved = 1'b0;
        check_bit("JR post-resolve: jr_stall=0", dut.jr_stall, 1'b0);

        // ==============================================================
        // Test 34: cdb_flush also clears jr_stall
        // ==============================================================
        $display("\n[Test 34] cdb_flush clears jr_stall");
        reset_dut();
        present_instr_stage1(
            .instr(INSTR_JALR_X5_X3_0),
            .pc_val(32'h0000_A000),
            .frl_phy(7'd88),
            .frat_rs(7'd3),
            .frat_rt(7'd0),
            .frat_rd(7'd5)
        );
        @(posedge clk); #1;
        // Cycle 1: jr_stall=1, JALR in stage 2
        @(posedge clk); #1;
        // Cycle 2: confirm stall
        check_bit("pre-flush: jr_stall=1", dut.jr_stall, 1'b1);

        // Send cdb_flush (simulates branch mispredict clearing the pipeline)
        cdb_valid = 1'b1;
        cdb_flush = 1'b1;
        cdb_branch_addr = 31'h0000_100;
        @(posedge clk); #1;
        cdb_valid = 1'b0;
        cdb_flush = 1'b0;
        check_bit("post-flush: jr_stall=0", dut.jr_stall, 1'b0);

        // ==============================================================
        // Summary
        // ==============================================================
        $display("\n=======================================");
        $display("  DISPATCH Testbench Done: %0d passed, %0d failed", pass_cnt, fail_cnt);
        $display("=======================================");

        if (fail_cnt == 0) begin
            $display("[PASS] DISPATCH_tb completed successfully");
        end else begin
            $fatal(1, "[FAIL] DISPATCH_tb found %0d failure(s)", fail_cnt);
        end
        $finish;
    end

    // Timeout watchdog
    initial begin
        #500_000;
        $error("TIMEOUT");
        $finish;
    end

endmodule
/* verilator lint_on WIDTH */
/* verilator lint_on BLKSEQ */
// verilog_lint: waive-stop explicit-parameter-storage-type
