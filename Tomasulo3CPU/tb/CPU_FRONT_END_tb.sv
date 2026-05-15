/* verilator lint_off WIDTH */
// verilog_lint: waive-start explicit-parameter-storage-type
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module CPU_FRONT_END_tb;
    import riscv_opcode_pkg::*;
    import riscv_funct_pkg::*;
    import riscv_types_pkg::*;

    // ----------------------------------------------------------------
    // Parameters
    // ----------------------------------------------------------------
    parameter int unsigned INSTR_WIDTH             = 32;
    parameter int unsigned IMEM_DEPTH              = 32;
    parameter int unsigned IMEM_WIDTH              = 32;
    parameter int unsigned IMEM_DEPTH_WORD         = IMEM_DEPTH - 1;
    parameter int unsigned ARCH_REG_COUNT          = 32;
    parameter int unsigned ARCH_REG_WIDTH          = $clog2(ARCH_REG_COUNT);
    parameter int unsigned REG_FILE_DATA_WIDTH     = 64;
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7;
    parameter int unsigned DMEM_WIDTH              = 64;
    parameter int unsigned DMEM_DEPTH              = 32;
    parameter int unsigned BPB_PC_BITS             = 3;
    parameter int unsigned NUM_WAYS                = 4;
    parameter int unsigned IFQ_DEPTH               = 16;
    parameter int unsigned RAS_DEPTH               = 4;
    parameter int unsigned FRL_SIZE                = 128;
    parameter int unsigned FRL_PTR_WIDTH           = $clog2(FRL_SIZE);
    parameter int unsigned NUM_CHECKPOINT          = 8;
    parameter int unsigned ROB_DEPTH               = 16;
    parameter int unsigned ROB_INDEX_WIDTH         = $clog2(ROB_DEPTH);
    parameter int unsigned SB_DEPTH                = 4;
    parameter int unsigned SB_INDEX_WIDTH          = $clog2(SB_DEPTH);
    parameter int unsigned OPCODE_WIDTH            = 6;

    // ----------------------------------------------------------------
    // DUT Signals
    // ----------------------------------------------------------------
    logic clk, rst_n;

    // I-CACHE interface
    logic                    imem_valid;
    logic [INSTR_WIDTH-1:0]  imem_data;
    logic                    imem_read_rdy;
    logic [IMEM_DEPTH-1:0]   imem_addr;

    // D-CACHE interface
    logic dcache_valid;
    logic dcache_write_done;
    logic [DMEM_DEPTH-1:0] dcache_sw_addr;
    logic [DMEM_WIDTH-1:0] dcache_sw_data;
    logic dcache_ready;

    // Issue Queue interface
    logic issue_intq_full, issue_divq_full, issue_mulq_full, issue_ld_stq_full;
    logic issue_intq_two_or_more_vacant, issue_divq_two_or_more_vacant;
    logic issue_mulq_two_or_more_vacant, issue_ld_stq_two_or_more_vacant;

    logic dis_rs_data_ready, dis_rt_data_ready;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rs_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rt_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_new_rd_phy_addr;
    logic dis_reg_write;
    logic [15:0] dis_imm16;
    logic [DMEM_WIDTH-1:0] dis_branch_other_addr;
    logic dis_branch_prediction;
    logic dis_branch;
    logic [BPB_PC_BITS-1:0] dis_branch_pc_bits;
    logic dis_jr_inst, dis_jal_inst, dis_jr31_inst;
    logic [OPCODE_WIDTH-1:0] dis_opcode;
    logic dis_int_issue_en, dis_div_issue_en, dis_mul_issue_en, dis_ld_st_issue_en;

    // CDB interface
    logic cdb_valid;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] cdb_rd_phy_addr;
    logic cdb_reg_write;
    logic [ROB_INDEX_WIDTH-1:0] cdb_rob_tag;
    logic [DMEM_DEPTH-1:0] cdb_sw_addr;
    logic [DMEM_WIDTH-1:0] cdb_sw_data;
    logic [IMEM_DEPTH-1:0] cdb_branch_addr;
    logic [BPB_PC_BITS-1:0] cdb_br_updt_addr;
    logic cdb_branch;
    logic cdb_branch_mispredict;
    logic cdb_flush;
    logic cdb_jalr_resolved;

    // SB interface
    logic [SB_INDEX_WIDTH-1:0] sb_flush_sw_tag;
    logic sb_flush_sw;
    logic [SB_INDEX_WIDTH-1:0] sb_entry_sw_tag;
    logic [DMEM_DEPTH-1:0] sb_entry_sw_addr;

    // ----------------------------------------------------------------
    // DUT
    // ----------------------------------------------------------------
    CPU_FRONT_END #(
        .INSTR_WIDTH             (INSTR_WIDTH),
        .IMEM_DEPTH              (IMEM_DEPTH),
        .IMEM_WIDTH              (IMEM_WIDTH),
        .IMEM_DEPTH_WORD         (IMEM_DEPTH_WORD),
        .ARCH_REG_COUNT          (ARCH_REG_COUNT),
        .ARCH_REG_WIDTH          (ARCH_REG_WIDTH),
        .REG_FILE_DATA_WIDTH     (REG_FILE_DATA_WIDTH),
        .PHY_REGISTER_FILE_WIDTH (PHY_REGISTER_FILE_WIDTH),
        .DMEM_WIDTH              (DMEM_WIDTH),
        .DMEM_DEPTH              (DMEM_DEPTH),
        .BPB_PC_BITS             (BPB_PC_BITS),
        .NUM_WAYS                (NUM_WAYS),
        .IFQ_DEPTH               (IFQ_DEPTH),
        .RAS_DEPTH               (RAS_DEPTH),
        .FRL_SIZE                (FRL_SIZE),
        .FRL_PTR_WIDTH           (FRL_PTR_WIDTH),
        .NUM_CHECKPOINT          (NUM_CHECKPOINT),
        .ROB_DEPTH               (ROB_DEPTH),
        .ROB_INDEX_WIDTH         (ROB_INDEX_WIDTH),
        .SB_DEPTH                (SB_DEPTH),
        .SB_INDEX_WIDTH          (SB_INDEX_WIDTH),
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
        input logic actual,
        input logic expected
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

    // ----------------------------------------------------------------
    // Simple instruction memory model
    // ----------------------------------------------------------------
    localparam int unsigned IMEM_SIZE = 256;
    logic [INSTR_WIDTH-1:0] imem_array [IMEM_SIZE];
    logic [IMEM_DEPTH-1:0]  imem_addr_latched;

    // 1-cycle latency I-cache model
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            imem_valid <= 1'b0;
            imem_data  <= '0;
        end else begin
            if (imem_read_rdy) begin
                imem_valid <= 1'b1;
                imem_data  <= imem_array[imem_addr[IMEM_DEPTH-1:2]];
            end else begin
                imem_valid <= 1'b0;
            end
        end
    end

    // ----------------------------------------------------------------
    // Helper tasks
    // ----------------------------------------------------------------
    task automatic clear_all_inputs();
        //imem_valid              = 1'b0;
        //imem_data               = '0;
        dcache_valid            = 1'b0;
        dcache_write_done       = 1'b0;
        issue_intq_full         = 1'b0;
        issue_divq_full         = 1'b0;
        issue_mulq_full         = 1'b0;
        issue_ld_stq_full       = 1'b0;
        issue_intq_two_or_more_vacant   = 1'b1;
        issue_divq_two_or_more_vacant   = 1'b1;
        issue_mulq_two_or_more_vacant   = 1'b1;
        issue_ld_stq_two_or_more_vacant = 1'b1;
        cdb_valid               = 1'b0;
        cdb_rd_phy_addr         = '0;
        cdb_reg_write           = 1'b0;
        cdb_rob_tag             = '0;
        cdb_sw_addr             = '0;
        cdb_sw_data             = '0;
        cdb_branch_addr         = '0;
        cdb_br_updt_addr        = '0;
        cdb_branch              = 1'b0;
        cdb_branch_mispredict   = 1'b0;
        cdb_flush               = 1'b0;
        cdb_jalr_resolved       = 1'b0;
    endtask

    task automatic reset_dut();
        rst_n = 1'b0;
        clear_all_inputs();
        for (int i = 0; i < IMEM_SIZE; i++) begin
            imem_array[i] = encode_i(12'd0, 5'd0, FUNCT3_ADD_SUB, 5'd0, OP_IMM); // NOP
        end
        repeat (3) @(negedge clk);#1;
        rst_n = 1'b1;
    endtask

    // Load instruction into the simulated I-mem at word-aligned address
    task automatic load_instr(
        input logic [IMEM_DEPTH-1:0] addr,
        input logic [INSTR_WIDTH-1:0] instr
    );
        imem_array[addr[IMEM_DEPTH-1:2]] = instr;
    endtask

    // Wait for a dispatch to fire (dis_int/div/mul/ld_st_issue_en goes high)
    // Returns the opcode that was dispatched
    task automatic wait_for_dispatch(
        output logic [OPCODE_WIDTH-1:0] opcode_out,
        input int unsigned max_cycles = 50
    );
        int cyc;
        cyc = 0;
        opcode_out = '0;
        while (cyc < max_cycles) begin
            @(posedge clk); #1;
            if (dis_int_issue_en || dis_div_issue_en || dis_mul_issue_en || dis_ld_st_issue_en) begin
                opcode_out = dis_opcode;
                return;
            end
            cyc++;
        end
        $warning("wait_for_dispatch: timed out after %0d cycles @ %0t", max_cycles, $time);
    endtask

    // Complete an instruction via CDB
    task automatic cdb_complete(
        input logic [ROB_INDEX_WIDTH-1:0] rob_tag,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd_phy,
        input logic reg_wr
    );
        cdb_valid       = 1'b1;
        cdb_rob_tag     = rob_tag;
        cdb_rd_phy_addr = rd_phy;
        cdb_reg_write   = reg_wr;
        cdb_branch      = 1'b0;
        cdb_branch_mispredict = 1'b0;
        cdb_flush       = 1'b0;
        @(posedge clk); #1;
        cdb_valid       = 1'b0;
        cdb_reg_write   = 1'b0;
    endtask

    // ----------------------------------------------------------------
    // Main test sequence
    // ----------------------------------------------------------------
    logic [OPCODE_WIDTH-1:0] dispatched_opcode;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] phy_regs [3];
    initial begin
        int dispatch_count;
        `ifdef FSDB_DUMP
            $fsdbDumpfile("CPU_FRONT_END.fsdb");
            $fsdbDumpvars(0, CPU_FRONT_END_tb);
        `else
            $dumpfile("CPU_FRONT_END.vcd");
            $dumpvars(0, CPU_FRONT_END_tb);
        `endif

        $display("=======================================");
        $display("  CPU_FRONT_END Testbench Start");
        $display("=======================================");

        // ==============================================================
        // Test 1: Reset — no dispatch activity
        // ==============================================================
        $display("\n[Test 1] Reset state");
        reset_dut();
        check_bit("dis_int_issue_en after reset", dis_int_issue_en, 1'b0);
        check_bit("dis_div_issue_en after reset", dis_div_issue_en, 1'b0);
        check_bit("dis_mul_issue_en after reset", dis_mul_issue_en, 1'b0);
        check_bit("dis_ld_st_issue_en after reset", dis_ld_st_issue_en, 1'b0);
        check_bit("imem_read_rdy after reset", imem_read_rdy, 1'b1);

        // ==============================================================
        // Test 2: Single ADD instruction end-to-end
        // IFQ fetches -> DISPATCH decodes -> issues to INT queue
        // ==============================================================
        $display("\n[Test 2] Single ADD instruction fetch-decode-dispatch");
        reset_dut();
        // ADD x3, x1, x2
        load_instr(32'h0000_0000, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_ADD_SUB, 5'd3, OP_REG));
        wait_for_dispatch(dispatched_opcode, 30);
        check_val("ADD dispatched opcode", dispatched_opcode, INSTR_ADD);
        check_bit("dis_int_issue_en for ADD", dis_int_issue_en, 1'b1);
        check_bit("dis_reg_write for ADD", dis_reg_write, 1'b1);
        check_val("dis_rob_rd_arch_addr for ADD x3", dut.dis_rob_rd_arch_addr, 5'd3);

        // ==============================================================
        // Test 3: Sequence of different instruction types
        // ADD, MUL, LW — dispatched to INT, MUL, LD_ST queues
        // ==============================================================
        $display("\n[Test 3] Sequence: ADD, MUL, LW");
        reset_dut();
        load_instr(32'h0000_0000, encode_r(FUNCT7_ZERO,   5'd2, 5'd1, FUNCT3_ADD_SUB, 5'd3, OP_REG));   // ADD x3,x1,x2
        load_instr(32'h0000_0004, encode_r(FUNCT7_MULDIV, 5'd4, 5'd3, FUNCT3_ADD_SUB, 5'd5, OP_REG));   // MUL x5,x3,x4
        load_instr(32'h0000_0008, encode_i(12'd8,         5'd1, FUNCT3_LW,             5'd6, OP_LOAD));   // LW  x6,8(x1)

        wait_for_dispatch(dispatched_opcode, 30);
        check_val("1st dispatch = ADD", dispatched_opcode, INSTR_ADD);
        check_bit("ADD -> INT queue", dis_int_issue_en, 1'b1);

        wait_for_dispatch(dispatched_opcode, 30);
        check_val("2nd dispatch = MUL", dispatched_opcode, INSTR_MUL);
        check_bit("MUL -> MUL queue", dis_mul_issue_en, 1'b1);

        wait_for_dispatch(dispatched_opcode, 30);
        check_val("3rd dispatch = LW", dispatched_opcode, INSTR_LW);
        check_bit("LW -> LD_ST queue", dis_ld_st_issue_en, 1'b1);

        // ==============================================================
        // Test 4: SW instruction dispatches with mem_write set
        // ==============================================================
        $display("\n[Test 4] SW instruction");
        reset_dut();
        load_instr(32'h0000_0000, encode_s(12'd16, 5'd2, 5'd1, FUNCT3_SW, OP_STORE)); // SW x2, 16(x1)

        wait_for_dispatch(dispatched_opcode, 30);
        check_val("SW dispatched", dispatched_opcode, INSTR_SW);
        check_bit("SW -> LD_ST queue", dis_ld_st_issue_en, 1'b1);
        check_bit("SW dis_reg_write=0", dis_reg_write, 1'b0);

        // ==============================================================
        // Test 5: Branch instruction (BEQ) dispatch
        // ==============================================================
        $display("\n[Test 5] BEQ instruction dispatch");
        reset_dut();
        load_instr(32'h0000_0000, encode_b(13'd8, 5'd2, 5'd1, FUNCT3_BEQ, OP_BRANCH)); // BEQ x1,x2,+8

        wait_for_dispatch(dispatched_opcode, 30);
        check_val("BEQ dispatched", dispatched_opcode, INSTR_BEQ);
        check_bit("BEQ -> INT queue", dis_int_issue_en, 1'b1);
        check_bit("BEQ dis_branch", dis_branch, 1'b1);
        check_bit("BEQ dis_reg_write=0", dis_reg_write, 1'b0);

        // ==============================================================
        // Test 6: Issue queue full stalls dispatch
        // ==============================================================
        $display("\n[Test 6] INT queue full stalls ADD");
        reset_dut();
        load_instr(32'h0000_0000, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_ADD_SUB, 5'd3, OP_REG));
        issue_intq_full = 1'b1;

        // Wait several cycles — dispatch should NOT fire
        repeat (15) @(posedge clk);
        #1;
        check_bit("ADD NOT dispatched when INT full", dis_int_issue_en, 1'b0);

        // Release the stall
        issue_intq_full = 1'b0;
        wait_for_dispatch(dispatched_opcode, 30);
        check_val("ADD dispatched after INT queue freed", dispatched_opcode, INSTR_ADD);

        // ==============================================================
        // Test 7: Complete instruction via CDB, verify ROB commit
        // ==============================================================
        $display("\n[Test 7] CDB completion and ROB commit");
        reset_dut();
        load_instr(32'h0000_0000, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_ADD_SUB, 5'd3, OP_REG));

        wait_for_dispatch(dispatched_opcode, 30);
        check_val("ADD dispatched", dispatched_opcode, INSTR_ADD);

        // Complete instruction at ROB tag 0
        cdb_complete(
            .rob_tag(ROB_INDEX_WIDTH'(0)),
            .rd_phy(dis_new_rd_phy_addr),
            .reg_wr(1'b1)
        );

        // Wait a cycle for ROB to commit
        @(posedge clk); #1;
        // ROB should have committed — check rob_commit via internal signal
        // We can indirectly check: after commit, ROB should not be full and
        // should have freed resources
        check_bit("ROB not full after commit", dut.rob_full, 1'b0);

        // ==============================================================
        // Test 8: Multiple instructions fill and drain the pipeline
        // ==============================================================
        $display("\n[Test 8] Multiple instructions pipeline throughput");
        reset_dut();
        // Load 6 instructions
        load_instr(32'h0000_0000, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_ADD_SUB, 5'd3, OP_REG));   // ADD
        load_instr(32'h0000_0004, encode_r(FUNCT7_ALT,  5'd4, 5'd3, FUNCT3_ADD_SUB, 5'd5, OP_REG));   // SUB
        load_instr(32'h0000_0008, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_AND,     5'd6, OP_REG));   // AND
        load_instr(32'h0000_000C, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_OR,      5'd7, OP_REG));   // OR
        load_instr(32'h0000_0010, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_SLT,     5'd8, OP_REG));   // SLT
        load_instr(32'h0000_0014, encode_i(12'd42,      5'd1, FUNCT3_ADD_SUB,        5'd9, OP_IMM));   // ADDI

        // Dispatch all 6
        for (int i = 0; i < 6; i++) begin
            wait_for_dispatch(dispatched_opcode, 30);
            $display("  Instruction %0d dispatched: opcode=%0d", i, dispatched_opcode);
            // Complete immediately via CDB so ROB doesn't fill
            cdb_complete(
                .rob_tag(ROB_INDEX_WIDTH'(i)),
                .rd_phy(dis_new_rd_phy_addr),
                .reg_wr(1'b1)
            );
        end
        $display("  All 6 instructions dispatched and completed");

        // ==============================================================
        // Test 9: DIV instruction routed correctly
        // ==============================================================
        $display("\n[Test 9] DIV instruction routing");
        reset_dut();
        load_instr(32'h0000_0000, encode_r(FUNCT7_MULDIV, 5'd2, 5'd1, FUNCT3_XOR, 5'd8, OP_REG)); // DIV

        wait_for_dispatch(dispatched_opcode, 30);
        check_val("DIV dispatched", dispatched_opcode, INSTR_DIV);
        check_bit("DIV -> DIV queue", dis_div_issue_en, 1'b1);
        check_bit("DIV not INT queue", dis_int_issue_en, 1'b0);

        // ==============================================================
        // Test 10: BNE instruction dispatch
        // ==============================================================
        $display("\n[Test 10] BNE instruction dispatch");
        reset_dut();
        load_instr(32'h0000_0000, encode_b(13'd16, 5'd4, 5'd3, FUNCT3_BNE, OP_BRANCH)); // BNE x3,x4,+16

        wait_for_dispatch(dispatched_opcode, 30);
        check_val("BNE dispatched", dispatched_opcode, INSTR_BNE);
        check_bit("BNE -> INT queue", dis_int_issue_en, 1'b1);
        check_bit("BNE dis_branch", dis_branch, 1'b1);

        // ==============================================================
        // Test 11: CDB flush clears the pipeline
        // ==============================================================
        $display("\n[Test 11] CDB flush clears pipeline");
        reset_dut();
        load_instr(32'h0000_0000, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_ADD_SUB, 5'd3, OP_REG));
        load_instr(32'h0000_0004, encode_r(FUNCT7_ALT,  5'd4, 5'd3, FUNCT3_ADD_SUB, 5'd5, OP_REG));
        // Also load instructions at the redirect target
        load_instr(32'h0000_0100, encode_i(12'd7, 5'd0, FUNCT3_ADD_SUB, 5'd10, OP_IMM)); // ADDI x10,x0,7

        // Let first ADD dispatch
        wait_for_dispatch(dispatched_opcode, 30);
        check_val("pre-flush ADD dispatched", dispatched_opcode, INSTR_ADD);

        // Flush pipeline: redirect to address 0x100
        cdb_flush = 1'b1;
        cdb_valid = 1'b1;
        cdb_branch_addr = 32'h0000_0100;
        @(posedge clk);
        cdb_flush = 1'b0;
        cdb_valid = 1'b0;

        // After flush, the pipeline should eventually dispatch from 0x100
        wait_for_dispatch(dispatched_opcode, 50);
        check_val("post-flush ADDI dispatched", dispatched_opcode, INSTR_ADDI);

        // ==============================================================
        // Test 12: Verify FRL allocates distinct physical registers
        // ==============================================================
        $display("\n[Test 12] FRL allocates unique physical registers");
        reset_dut();
        load_instr(32'h0000_0000, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_ADD_SUB, 5'd3, OP_REG));
        load_instr(32'h0000_0004, encode_r(FUNCT7_ALT,  5'd4, 5'd3, FUNCT3_ADD_SUB, 5'd5, OP_REG));
        load_instr(32'h0000_0008, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_AND,     5'd6, OP_REG));

        for (int i = 0; i < 3; i++) begin
            wait_for_dispatch(dispatched_opcode, 30);
            phy_regs[i] = dis_new_rd_phy_addr;
            // cdb_complete(
            //     .rob_tag(ROB_INDEX_WIDTH'(i)),
            //     .rd_phy(dis_new_rd_phy_addr),
            //     .reg_wr(1'b1)
            // );
        end

        // All three should be distinct
        if (phy_regs[0] != phy_regs[1] && phy_regs[1] != phy_regs[2] && phy_regs[0] != phy_regs[2]) begin
            $display("  FRL allocated 3 distinct registers: %0d, %0d, %0d", phy_regs[0], phy_regs[1], phy_regs[2]);
            pass_cnt++;
        end else begin
            $error("[FAIL] FRL allocated duplicate registers: %0d, %0d, %0d", phy_regs[0], phy_regs[1], phy_regs[2]);
            fail_cnt++;
        end

        // ==============================================================
        // Test 13: Mixed instruction types dispatched to correct queues
        // ==============================================================
        $display("\n[Test 13] Mixed instruction routing: ADD, MUL, DIV, SW, LW");
        reset_dut();
        load_instr(32'h0000_0000, encode_r(FUNCT7_ZERO,   5'd2, 5'd1, FUNCT3_ADD_SUB, 5'd3,  OP_REG));   // ADD -> INT
        load_instr(32'h0000_0004, encode_r(FUNCT7_MULDIV, 5'd4, 5'd3, FUNCT3_ADD_SUB, 5'd5,  OP_REG));   // MUL -> MUL
        load_instr(32'h0000_0008, encode_r(FUNCT7_MULDIV, 5'd2, 5'd1, FUNCT3_XOR,     5'd8,  OP_REG));   // DIV -> DIV
        load_instr(32'h0000_000C, encode_s(12'd16,        5'd2, 5'd1, FUNCT3_SW,              OP_STORE)); // SW  -> LD_ST
        load_instr(32'h0000_0010, encode_i(12'd8,         5'd1, FUNCT3_LW,             5'd9,  OP_LOAD));  // LW  -> LD_ST

        // ADD -> INT
        wait_for_dispatch(dispatched_opcode, 30);
        check_bit("ADD->INT", dis_int_issue_en, 1'b1);
        //cdb_complete(ROB_INDEX_WIDTH'(0), dis_new_rd_phy_addr, 1'b1);

        // MUL -> MUL
        wait_for_dispatch(dispatched_opcode, 30);
        check_bit("MUL->MUL", dis_mul_issue_en, 1'b1);
        //cdb_complete(ROB_INDEX_WIDTH'(1), dis_new_rd_phy_addr, 1'b1);

        // DIV -> DIV
        wait_for_dispatch(dispatched_opcode, 30);
        check_bit("DIV->DIV", dis_div_issue_en, 1'b1);
        //cdb_complete(ROB_INDEX_WIDTH'(2), dis_new_rd_phy_addr, 1'b1);

        // SW -> LD_ST
        wait_for_dispatch(dispatched_opcode, 30);
        check_bit("SW->LD_ST", dis_ld_st_issue_en, 1'b1);
        //cdb_complete(ROB_INDEX_WIDTH'(3), '0, 1'b0);

        // LW -> LD_ST
        wait_for_dispatch(dispatched_opcode, 30);
        check_bit("LW->LD_ST", dis_ld_st_issue_en, 1'b1);
        //cdb_complete(ROB_INDEX_WIDTH'(4), dis_new_rd_phy_addr, 1'b1);

        // ==============================================================
        // Test 14: ROB fills up and stalls dispatch
        // ==============================================================
        $display("\n[Test 14] ROB full stalls dispatch");
        reset_dut();
        // Fill ROB with instructions (don't complete any via CDB)
        for (int i = 0; i < ROB_DEPTH + 4; i++) begin
            load_instr(IMEM_DEPTH'(i * 4),
                       encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_ADD_SUB, 5'd3, OP_REG));
        end

        dispatch_count = 0;
        for (int cyc = 0; cyc < 100; cyc++) begin
            @(posedge clk); #1;
            if (dis_int_issue_en) dispatch_count++;
        end
        $display("  Dispatched %0d instructions before ROB presumably filled", dispatch_count);
        // Should dispatch at most ROB_DEPTH instructions
        if (dispatch_count <= ROB_DEPTH) begin
            pass_cnt++;
        end else begin
            $error("[FAIL] Dispatched %0d > ROB_DEPTH=%0d without CDB completions",
                   dispatch_count, ROB_DEPTH);
            fail_cnt++;
        end

        // ==============================================================
        // Test 15: ADDI instruction carries immediate correctly
        // ==============================================================
        $display("\n[Test 15] ADDI immediate propagation");
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd1234, 5'd1, FUNCT3_ADD_SUB, 5'd6, OP_IMM));

        wait_for_dispatch(dispatched_opcode, 30);
        check_val("ADDI opcode", dispatched_opcode, INSTR_ADDI);
        check_val("ADDI imm16", dis_imm16, 16'd1234);

        // ==============================================================
        // Summary
        // ==============================================================
        $display("\n=======================================");
        $display("  CPU_FRONT_END Testbench Done: %0d passed, %0d failed", pass_cnt, fail_cnt);
        $display("=======================================");

        if (fail_cnt == 0) begin
            $display("[PASS] CPU_FRONT_END_tb completed successfully");
        end else begin
            $fatal(1, "[FAIL] CPU_FRONT_END_tb found %0d failure(s)", fail_cnt);
        end
        $finish;
    end

    // Timeout watchdog
    initial begin
        #1_000_000;
        $error("TIMEOUT");
        $finish;
    end

endmodule
/* verilator lint_on WIDTH */
/* verilator lint_on BLKSEQ */
// verilog_lint: waive-stop explicit-parameter-storage-type
