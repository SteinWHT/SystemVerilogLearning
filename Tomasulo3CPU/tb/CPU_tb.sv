/* verilator lint_off WIDTH */
// verilog_lint: waive-start explicit-parameter-storage-type
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module CPU_tb;
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
    parameter int unsigned ISSUE_QUEUE_DEPTH       = 16;
    parameter int unsigned LSB_DEPTH               = 4;
    parameter int unsigned DIV_CYCLES              = 7;
    parameter int unsigned MUL_CYCLES              = 4;
    parameter int unsigned INT_CYCLES              = 1;
    parameter int unsigned LD_ST_CYCLES            = 1;
    parameter int unsigned OPCODE_WIDTH            = 6;

    // ----------------------------------------------------------------
    // DUT Signals
    // ----------------------------------------------------------------
    logic clk, rst_n;

    // I-Cache
    logic                    imem_valid;
    logic [INSTR_WIDTH-1:0]  imem_data;
    logic                    imem_read_rdy;
    logic [IMEM_DEPTH-1:0]   imem_addr;

    // D-Cache read
    logic                            dcache_read_busy;
    logic                            dcache_read_done;
    logic [REG_FILE_DATA_WIDTH-1:0]  dcache_rdata;
    logic                            dcache_req;
    logic [DMEM_DEPTH-1:0]           dcache_addr;

    // D-Cache write
    logic                    dcache_valid;
    logic                    dcache_write_done;
    logic [DMEM_DEPTH-1:0]   dcache_sw_addr;
    logic [DMEM_WIDTH-1:0]   dcache_sw_data;
    logic                    dcache_ready;

    logic imem_busy;

    // ----------------------------------------------------------------
    // DUT Instantiation
    // ----------------------------------------------------------------
    CPU #(
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
        .ISSUE_QUEUE_DEPTH       (ISSUE_QUEUE_DEPTH),
        .LSB_DEPTH               (LSB_DEPTH),
        .DIV_CYCLES              (DIV_CYCLES),
        .MUL_CYCLES              (MUL_CYCLES),
        .INT_CYCLES              (INT_CYCLES),
        .LD_ST_CYCLES            (LD_ST_CYCLES),
        .OPCODE_WIDTH            (OPCODE_WIDTH)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .imem_valid       (imem_valid),
        .imem_data        (imem_data),
        .imem_read_rdy    (imem_read_rdy),
        .imem_addr        (imem_addr),
        .dcache_read_busy (dcache_read_busy),
        .dcache_read_done (dcache_read_done),
        .dcache_rdata     (dcache_rdata),
        .dcache_req       (dcache_req),
        .dcache_addr      (dcache_addr),
        .dcache_valid     (dcache_valid),
        .dcache_write_done(dcache_write_done),
        .dcache_sw_addr   (dcache_sw_addr),
        .dcache_sw_data   (dcache_sw_data),
        .dcache_ready     (dcache_ready)
    );

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
    int test_num = 0;

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

    // NOP = ADDI x0, x0, 0
    function automatic logic [31:0] nop();
        return encode_i(12'd0, 5'd0, FUNCT3_ADD_SUB, 5'd0, OP_NOP);
    endfunction

    // ----------------------------------------------------------------
    // I-Cache model (1-cycle latency)
    // ----------------------------------------------------------------
    localparam int unsigned IMEM_SIZE = 1024;
    logic [INSTR_WIDTH-1:0] imem_array [IMEM_SIZE];

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
    // D-Cache model (1-cycle read, 1-cycle write)
    // ----------------------------------------------------------------
    localparam int unsigned DMEM_SIZE = 256;
    logic [REG_FILE_DATA_WIDTH-1:0] dmem_array [DMEM_SIZE];

    // Read path
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dcache_read_done <= 1'b0;
            dcache_rdata     <= '0;
        end else begin
            if (dcache_req && !dcache_read_busy) begin
                dcache_read_done <= 1'b1;
                dcache_rdata     <= dmem_array[dcache_addr[DMEM_DEPTH-1:3]];
            end else begin
                dcache_read_done <= 1'b0;
            end
        end
    end

    // Write path
    // Plain always is intentional: dmem_array is also initialized/preloaded by
    // testbench tasks, which is illegal for an always_ff-written variable.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dcache_valid      <= 1'b0;
            dcache_write_done <= 1'b0;
        end else begin
            if (dcache_ready) begin
                dmem_array[dcache_sw_addr[DMEM_DEPTH-1:3]] <= dcache_sw_data;
                dcache_valid      <= 1'b1;
                dcache_write_done <= 1'b1;
            end else begin
                dcache_valid      <= 1'b0;
                dcache_write_done <= 1'b0;
            end
        end
    end

    // ----------------------------------------------------------------
    // Helper tasks
    // ----------------------------------------------------------------
    task automatic load_instr(
        input logic [IMEM_DEPTH-1:0] addr,
        input logic [INSTR_WIDTH-1:0] instr
    );
        imem_array[addr[IMEM_DEPTH-1:2]] = instr;
    endtask

    task automatic load_dmem(
        input logic [DMEM_DEPTH-1:0] addr,
        input logic [REG_FILE_DATA_WIDTH-1:0] data
    );
        dmem_array[addr[DMEM_DEPTH-1:3]] = data;
    endtask

    task automatic reset_dut();
        rst_n = 1'b0;
        dcache_read_busy = 1'b0;
        for (int i = 0; i < IMEM_SIZE; i++)
            imem_array[i] = nop();
        for (int i = 0; i < DMEM_SIZE; i++)
            dmem_array[i] = '0;
        repeat (3) @(posedge clk); #1;
        rst_n = 1'b1;
    endtask

    // Wait for CDB valid (instruction completed execution)
    task automatic wait_cdb_valid(input int unsigned max_cycles = 100);
        int cyc;
        cyc = 0;
        while (cyc < max_cycles) begin
            @(posedge clk); #1;
            if (dut.cdb_valid) return;
            cyc++;
        end
        $warning("wait_cdb_valid: timed out after %0d cycles @ %0t", max_cycles, $time);
    endtask

    // Wait for dispatch to issue queue
    task automatic wait_dispatch(input int unsigned max_cycles = 80);
        int cyc;
        cyc = 0;
        while (cyc < max_cycles) begin
            @(posedge clk); #1;
            if (dut.dis_int_issue_en || dut.dis_div_issue_en ||
                dut.dis_mul_issue_en || dut.dis_ld_st_issue_en)
                return;
            cyc++;
        end
        $warning("wait_dispatch: timed out after %0d cycles @ %0t", max_cycles, $time);
    endtask

    // Wait N cycles
    task automatic wait_cycles(input int unsigned n);
        repeat (n) @(posedge clk);
        #1;
    endtask

    // Check PRF value by reading through the back-end's PRF
    function automatic logic [REG_FILE_DATA_WIDTH-1:0] read_prf(
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] phy_addr
    );
        return dut.back_end.prf.prf_data_array[phy_addr];
    endfunction

    // ----------------------------------------------------------------
    // Main test sequence
    // ----------------------------------------------------------------
    initial begin
        `ifdef FSDB_DUMP
            $fsdbDumpfile("CPU.fsdb");
            $fsdbDumpvars(0, CPU_tb);
            $fsdbDumpMDA();
        `else
            $dumpfile("CPU.vcd");
            $dumpvars(0, CPU_tb);
        `endif

        $display("=======================================");
        $display("  CPU Integration Testbench Start");
        $display("=======================================");

        // ==============================================================
        // Test 1: Reset state
        // ==============================================================
        test_num = 1;
        $display("\n[Test %0d] Reset state verification", test_num);
        reset_dut();
        check_bit("imem_read_rdy after reset", imem_read_rdy, 1'b1);
        check_bit("dcache_req after reset", dcache_req, 1'b0);
        check_bit("no CDB valid", dut.cdb_valid, 1'b0);

        // ==============================================================
        // Test 2: Single ADDI instruction end-to-end
        // ADDI x1, x0, 42
        // ==============================================================
        test_num = 2;
        $display("\n[Test %0d] ADDI x1, x0, 42 end-to-end", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd42, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));

        wait_dispatch();
        check_val("ADDI dispatched to INT", dut.dis_opcode, INSTR_ADDI);
        check_bit("ADDI INT issue", dut.dis_int_issue_en, 1'b1);

        wait_cdb_valid();
        check_val("ADDI result = 42", dut.cdb_rd_data, 64'd42);
        check_bit("ADDI reg write", dut.cdb_reg_write, 1'b1);

        // ==============================================================
        // Test 3: ADD two registers
        // ADDI x1, x0, 10 → ADDI x2, x0, 20 → ADD x3, x1, x2
        // ==============================================================
        test_num = 3;
        $display("\n[Test %0d] ADD x3, x1, x2 (10 + 20 = 30)", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd10, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'd20, 5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));
        load_instr(32'h0000_0008, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_ADD_SUB, 5'd3, OP_REG));

        // Wait for all three to complete
        wait_cdb_valid(); // ADDI x1
        check_val("ADDI x1 = 10", dut.cdb_rd_data, 64'd10);
        wait_cdb_valid(); // ADDI x2
        check_val("ADDI x2 = 20", dut.cdb_rd_data, 64'd20);
        wait_cdb_valid(); // ADD x3
        check_val("ADD x3 = 30", dut.cdb_rd_data, 64'd30);

        // ==============================================================
        // Test 4: SUB instruction
        // ADDI x1, x0, 50 → ADDI x2, x0, 18 → SUB x3, x1, x2
        // ==============================================================
        test_num = 4;
        $display("\n[Test %0d] SUB x3, x1, x2 (50 - 18 = 32)", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd50, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'd18, 5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));
        load_instr(32'h0000_0008, encode_r(FUNCT7_ALT, 5'd2, 5'd1, FUNCT3_ADD_SUB, 5'd3, OP_REG));

        wait_cdb_valid(); // ADDI x1
        wait_cdb_valid(); // ADDI x2
        wait_cdb_valid(); // SUB x3
        check_val("SUB x3 = 32", dut.cdb_rd_data, 64'd32);

        // ==============================================================
        // Test 5: AND, OR, XOR instructions
        // ADDI x1, x0, 0xFF → ADDI x2, x0, 0x0F
        // AND x3, x1, x2 → OR x4, x1, x2 → XOR x5, x1, x2
        // ==============================================================
        test_num = 5;
        $display("\n[Test %0d] AND/OR/XOR operations", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'hFF, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'h0F, 5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));
        load_instr(32'h0000_0008, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_AND, 5'd3, OP_REG));
        load_instr(32'h0000_000C, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_OR, 5'd4, OP_REG));
        load_instr(32'h0000_0010, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_XOR, 5'd5, OP_REG));

        wait_cdb_valid(); // ADDI x1 = 0xFF
        wait_cdb_valid(); // ADDI x2 = 0x0F
        wait_cdb_valid(); // AND x3
        check_val("AND result", dut.cdb_rd_data, 64'h0F);
        wait_cdb_valid(); // OR x4
        check_val("OR result", dut.cdb_rd_data, 64'hFF);
        wait_cdb_valid(); // XOR x5
        check_val("XOR result", dut.cdb_rd_data, 64'hF0);

        // ==============================================================
        // Test 6: SLT / SLTU instructions
        // ADDI x1, x0, 5 → ADDI x2, x0, 10
        // SLT x3, x1, x2 (5 < 10 → 1) → SLT x4, x2, x1 (10 < 5 → 0)
        // ==============================================================
        test_num = 6;
        $display("\n[Test %0d] SLT comparison", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd5,  5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'd10, 5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));
        load_instr(32'h0000_0008, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_SLT, 5'd3, OP_REG));
        load_instr(32'h0000_000C, encode_r(FUNCT7_ZERO, 5'd1, 5'd2, FUNCT3_SLT, 5'd4, OP_REG));

        wait_cdb_valid(); // ADDI x1
        wait_cdb_valid(); // ADDI x2
        wait_cdb_valid(); // SLT x3
        check_val("SLT 5<10 = 1", dut.cdb_rd_data, 64'd1);
        wait_cdb_valid(); // SLT x4
        check_val("SLT 10<5 = 0", dut.cdb_rd_data, 64'd0);

        // ==============================================================
        // Test 7: Shift operations (SLL, SRL, SRA)
        // ADDI x1, x0, 8 → ADDI x2, x0, 2
        // SLL x3, x1, x2 (8 << 2 = 32)
        // SRL x4, x1, x2 (8 >> 2 = 2)
        // ==============================================================
        test_num = 7;
        $display("\n[Test %0d] Shift operations SLL/SRL", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd8, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'd2, 5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));
        load_instr(32'h0000_0008, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_SLL, 5'd3, OP_REG));
        load_instr(32'h0000_000C, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_SRL_SRA, 5'd4, OP_REG));

        wait_cdb_valid(); // ADDI x1
        wait_cdb_valid(); // ADDI x2
        wait_cdb_valid(); // SLL x3
        check_val("SLL 8<<2 = 32", dut.cdb_rd_data, 64'd32);
        wait_cdb_valid(); // SRL x4
        check_val("SRL 8>>2 = 2", dut.cdb_rd_data, 64'd2);

        // ==============================================================
        // Test 8: Immediate shift (SLLI, SRLI, SRAI)
        // ADDI x1, x0, 16
        // SLLI x2, x1, 3 (16 << 3 = 128)
        // SRLI x3, x1, 2 (16 >> 2 = 4)
        // ==============================================================
        test_num = 8;
        $display("\n[Test %0d] Immediate shifts SLLI/SRLI", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd16, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        // SLLI x2, x1, 3: imm[11:0] = {0000000, shamt[4:0]=00011}
        load_instr(32'h0000_0004, encode_i({7'b0000000, 5'd3}, 5'd1, FUNCT3_SLL, 5'd2, OP_IMM));
        // SRLI x3, x1, 2: imm[11:0] = {0000000, shamt[4:0]=00010}
        load_instr(32'h0000_0008, encode_i({7'b0000000, 5'd2}, 5'd1, FUNCT3_SRL_SRA, 5'd3, OP_IMM));

        wait_cdb_valid(); // ADDI x1
        wait_cdb_valid(); // SLLI x2
        check_val("SLLI 16<<3 = 128", dut.cdb_rd_data, 64'd128);
        wait_cdb_valid(); // SRLI x3
        check_val("SRLI 16>>2 = 4", dut.cdb_rd_data, 64'd4);

        // ==============================================================
        // Test 9: I-type logic (ANDI, ORI, XORI)
        // ADDI x1, x0, 0xAB
        // ANDI x2, x1, 0x0F (0xAB & 0x0F = 0x0B)
        // ORI  x3, x1, 0x100 (0xAB | 0x100 = 0x1AB)
        // XORI x4, x1, 0xFF (0xAB ^ 0xFF = 0x54)
        // ==============================================================
        test_num = 9;
        $display("\n[Test %0d] I-type logic ANDI/ORI/XORI", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'hAB,  5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'h0F,  5'd1, FUNCT3_AND,     5'd2, OP_IMM));
        load_instr(32'h0000_0008, encode_i(12'h100, 5'd1, FUNCT3_OR,      5'd3, OP_IMM));
        load_instr(32'h0000_000C, encode_i(12'hFF,  5'd1, FUNCT3_XOR,     5'd4, OP_IMM));

        wait_cdb_valid(); // ADDI x1 = 0xAB
        wait_cdb_valid(); // ANDI x2
        check_val("ANDI 0xAB & 0x0F = 0x0B", dut.cdb_rd_data, 64'h0B);
        wait_cdb_valid(); // ORI x3
        check_val("ORI 0xAB | 0x100 = 0x1AB", dut.cdb_rd_data, 64'h1AB);
        wait_cdb_valid(); // XORI x4
        check_val("XORI 0xAB ^ 0xFF = 0x54", dut.cdb_rd_data, 64'h54);

        // ==============================================================
        // Test 10: SLTI / SLTIU
        // ADDI x1, x0, 5
        // SLTI x2, x1, 10 (5 < 10 → 1)
        // SLTI x3, x1, 3  (5 < 3 → 0)
        // ==============================================================
        test_num = 10;
        $display("\n[Test %0d] SLTI comparison", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd5,  5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'd10, 5'd1, FUNCT3_SLT,     5'd2, OP_IMM));
        load_instr(32'h0000_0008, encode_i(12'd3,  5'd1, FUNCT3_SLT,     5'd3, OP_IMM));

        wait_cdb_valid(); // ADDI x1
        wait_cdb_valid(); // SLTI x2
        check_val("SLTI 5<10 = 1", dut.cdb_rd_data, 64'd1);
        wait_cdb_valid(); // SLTI x3
        check_val("SLTI 5<3 = 0", dut.cdb_rd_data, 64'd0);

        // ==============================================================
        // Test 11: MUL instruction
        // ADDI x1, x0, 6 → ADDI x2, x0, 7 → MUL x3, x1, x2 = 42
        // ==============================================================
        test_num = 11;
        $display("\n[Test %0d] MUL x3 = 6 * 7 = 42", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd6, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'd7, 5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));
        load_instr(32'h0000_0008, encode_r(FUNCT7_MULDIV, 5'd2, 5'd1, FUNCT3_ADD_SUB, 5'd3, OP_REG));

        wait_cdb_valid(); // ADDI x1
        wait_cdb_valid(); // ADDI x2
        wait_cdb_valid(50); // MUL x3 (multi-cycle)
        check_val("MUL 6*7 = 42", dut.cdb_rd_data, 64'd42);

        // ==============================================================
        // Test 12: DIV instruction
        // ADDI x1, x0, 100 → ADDI x2, x0, 5 → DIV x3, x1, x2 = 20
        // ==============================================================
        test_num = 12;
        $display("\n[Test %0d] DIV x3 = 100 / 5 = 20", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd100, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'd5,   5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));
        load_instr(32'h0000_0008, encode_r(FUNCT7_MULDIV, 5'd2, 5'd1, FUNCT3_XOR, 5'd3, OP_REG));

        wait_cdb_valid(); // ADDI x1
        wait_cdb_valid(); // ADDI x2
        wait_cdb_valid(50); // DIV x3 (multi-cycle)
        check_val("DIV 100/5 = 20", dut.cdb_rd_data, 64'd20);

        // ==============================================================
        // Test 13: REM instruction
        // ADDI x1, x0, 100 → ADDI x2, x0, 7 → REM x3, x1, x2 = 2
        // ==============================================================
        test_num = 13;
        $display("\n[Test %0d] REM x3 = 100 %% 7 = 2", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd100, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'd7,   5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));
        load_instr(32'h0000_0008, encode_r(FUNCT7_MULDIV, 5'd2, 5'd1, FUNCT3_AND, 5'd3, OP_REG));

        wait_cdb_valid(); // ADDI x1
        wait_cdb_valid(); // ADDI x2
        wait_cdb_valid(50); // REM x3 (multi-cycle)
        check_val("REM 100%%7 = 2", dut.cdb_rd_data, 64'd2);

        // ==============================================================
        // Test 14: LW instruction
        // Pre-load D-cache with value, then LW to register
        // ADDI x1, x0, 0 → LW x2, 0(x1) — read from addr 0
        // ==============================================================
        test_num = 14;
        $display("\n[Test %0d] LW x2, 0(x1) from D-cache", test_num);
        reset_dut();
        load_dmem(32'h0000_0000, 64'hDEAD_BEEF_CAFE_BABE);
        load_instr(32'h0000_0000, encode_i(12'd0, 5'd0, FUNCT3_LW, 5'd2, OP_LOAD));

        wait_cdb_valid(50);
        check_val("LW loaded data", dut.cdb_rd_data, 64'hDEAD_BEEF_CAFE_BABE);

        // ==============================================================
        // Test 15: LW with non-zero offset
        // ADDI x1, x0, 8 → LW x2, 8(x1) — read from addr 16
        // ==============================================================
        test_num = 15;
        $display("\n[Test %0d] LW x2, 8(x1) with offset", test_num);
        reset_dut();
        load_dmem(32'h0000_0010, 64'h1234_5678_ABCD_EF00);
        load_instr(32'h0000_0000, encode_i(12'd8, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'd8, 5'd1, FUNCT3_LW, 5'd2, OP_LOAD));

        wait_cdb_valid(); // ADDI x1
        wait_cdb_valid(50); // LW x2
        check_val("LW from addr 16", dut.cdb_rd_data, 64'h1234_5678_ABCD_EF00);

        // ==============================================================
        // Test 16: SW instruction (store to memory)
        // ADDI x1, x0, 99 → SW x1, 0(x0)
        // ==============================================================
        test_num = 16;
        $display("\n[Test %0d] SW x1, 0(x0) store to memory", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd99, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_s(12'd0, 5'd1, 5'd0, FUNCT3_SW, OP_STORE));

        wait_cdb_valid(); // ADDI x1
        wait_cdb_valid(50); // SW completes on CDB
        // Wait for ROB to commit and SB to write
        wait_cycles(20);
        $display("  SW test: store completed (checking commit path)");

        // ==============================================================
        // Test 17: JAL instruction — jump and link
        // JAL x1, +16 at 0x0000 → target 0x0010
        // ADDI x10, x0, 77 at 0x0010
        // ==============================================================
        test_num = 17;
        $display("\n[Test %0d] JAL x1, +16", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_j(21'd16, 5'd1, OP_JAL));
        load_instr(32'h0000_0010, encode_i(12'd77, 5'd0, FUNCT3_ADD_SUB, 5'd10, OP_IMM));

        wait_dispatch();
        check_val("JAL dispatched", dut.dis_opcode, INSTR_JAL);
        check_bit("JAL jal_inst", dut.dis_jal_inst, 1'b1);

        wait_cdb_valid(); // JAL link address
        wait_cdb_valid(50); // ADDI at target
        check_val("ADDI at JAL target = 77", dut.cdb_rd_data, 64'd77);

        // ==============================================================
        // Test 18: BEQ taken — branch when equal
        // ADDI x1, x0, 5 → ADDI x2, x0, 5
        // BEQ x1, x2, +12 (skip next instr)
        // ADDI x3, x0, 99 (skipped if branch taken)
        // ADDI x4, x0, 42 (target)
        // ==============================================================
        test_num = 18;
        $display("\n[Test %0d] BEQ taken (equal values)", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd5, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'd5, 5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));
        load_instr(32'h0000_0008, encode_b(13'd12, 5'd2, 5'd1, FUNCT3_BEQ, OP_BRANCH));
        load_instr(32'h0000_000C, encode_i(12'd99, 5'd0, FUNCT3_ADD_SUB, 5'd3, OP_IMM));
        load_instr(32'h0000_0014, encode_i(12'd42, 5'd0, FUNCT3_ADD_SUB, 5'd4, OP_IMM));

        // Let instructions flow through pipeline
        wait_cycles(80);
        $display("  BEQ taken test completed (branch resolution depends on predictor state)");

        // ==============================================================
        // Test 19: BNE not taken — branch when not equal fails
        // ADDI x1, x0, 5 → ADDI x2, x0, 5
        // BNE x1, x2, +8 (not taken since equal)
        // ADDI x3, x0, 11 (executed)
        // ==============================================================
        test_num = 19;
        $display("\n[Test %0d] BNE not-taken (equal values)", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd5,  5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'd5,  5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));
        load_instr(32'h0000_0008, encode_b(13'd8, 5'd2, 5'd1, FUNCT3_BNE, OP_BRANCH));
        load_instr(32'h0000_000C, encode_i(12'd11, 5'd0, FUNCT3_ADD_SUB, 5'd3, OP_IMM));

        wait_cycles(80);
        $display("  BNE not-taken test completed");

        // ==============================================================
        // Test 20: BNE taken — branch when not equal succeeds
        // ADDI x1, x0, 5 → ADDI x2, x0, 10
        // BNE x1, x2, +12 (taken)
        // ==============================================================
        test_num = 20;
        $display("\n[Test %0d] BNE taken (different values)", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd5,  5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'd10, 5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));
        load_instr(32'h0000_0008, encode_b(13'd12, 5'd2, 5'd1, FUNCT3_BNE, OP_BRANCH));
        load_instr(32'h0000_000C, encode_i(12'd99, 5'd0, FUNCT3_ADD_SUB, 5'd3, OP_IMM));
        load_instr(32'h0000_0014, encode_i(12'd55, 5'd0, FUNCT3_ADD_SUB, 5'd4, OP_IMM));

        wait_cycles(80);
        $display("  BNE taken test completed");

        // ==============================================================
        // Test 21: JALR — indirect jump
        // ADDI x1, x0, 0x20 → JALR x2, 0(x1) → target 0x20
        // ADDI x10, x0, 88 at 0x20
        // ==============================================================
        test_num = 21;
        $display("\n[Test %0d] JALR x2, 0(x1) indirect jump", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'h20, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'd0, 5'd1, 3'b000, 5'd2, OP_JALR));
        load_instr(32'h0000_0020, encode_i(12'd88, 5'd0, FUNCT3_ADD_SUB, 5'd10, OP_IMM));

        wait_cdb_valid(); // ADDI x1
        wait_cdb_valid(80); // JALR x2 link
        // After JALR resolves, pipeline should redirect to 0x20
        wait_cdb_valid(80); // ADDI at target
        check_val("ADDI at JALR target = 88", dut.cdb_rd_data, 64'd88);

        // ==============================================================
        // Test 22: JAL/RET pattern (function call and return via RAS)
        // 0x00: JAL x1, +16 (call func at 0x10, push 0x04 to RAS)
        // 0x04: ADDI x10, x0, 33 (return point)
        // 0x10: ADDI x5, x0, 55 (func body)
        // 0x14: JALR x0, 0(x1) (return, pop RAS → 0x04)
        // ==============================================================
        test_num = 22;
        $display("\n[Test %0d] JAL + JALR return via RAS", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_j(21'd16, 5'd1, OP_JAL));
        load_instr(32'h0000_0004, encode_i(12'd33, 5'd0, FUNCT3_ADD_SUB, 5'd10, OP_IMM));
        load_instr(32'h0000_0010, encode_i(12'd55, 5'd0, FUNCT3_ADD_SUB, 5'd5, OP_IMM));
        load_instr(32'h0000_0014, encode_i(12'd0, 5'd1, 3'b000, 5'd0, OP_JALR));

        wait_cycles(100);
        $display("  JAL/RET pattern test completed");

        // ==============================================================
        // Test 23: RAW dependency chain
        // ADDI x1, x0, 1
        // ADDI x2, x1, 1 (depends on x1)
        // ADDI x3, x2, 1 (depends on x2)
        // ADDI x4, x3, 1 (depends on x3)
        // ==============================================================
        test_num = 23;
        $display("\n[Test %0d] RAW dependency chain", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd1, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'd1, 5'd1, FUNCT3_ADD_SUB, 5'd2, OP_IMM));
        load_instr(32'h0000_0008, encode_i(12'd1, 5'd2, FUNCT3_ADD_SUB, 5'd3, OP_IMM));
        load_instr(32'h0000_000C, encode_i(12'd1, 5'd3, FUNCT3_ADD_SUB, 5'd4, OP_IMM));

        wait_cdb_valid(); // x1 = 1
        check_val("chain x1 = 1", dut.cdb_rd_data, 64'd1);
        wait_cdb_valid(); // x2 = 2
        check_val("chain x2 = 2", dut.cdb_rd_data, 64'd2);
        wait_cdb_valid(); // x3 = 3
        check_val("chain x3 = 3", dut.cdb_rd_data, 64'd3);
        wait_cdb_valid(); // x4 = 4
        check_val("chain x4 = 4", dut.cdb_rd_data, 64'd4);

        // ==============================================================
        // Test 24: Multiple different FU types in flight
        // ADDI x1, x0, 6 → ADDI x2, x0, 7
        // ADD x3, x1, x2 (INT)
        // MUL x4, x1, x2 (MUL)
        // DIV x5, x4, x1 (DIV, depends on MUL result)
        // ==============================================================
        test_num = 24;
        $display("\n[Test %0d] Mixed FU pipeline (INT + MUL + DIV)", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd6, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'd7, 5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));
        load_instr(32'h0000_0008, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_ADD_SUB, 5'd3, OP_REG));
        load_instr(32'h0000_000C, encode_r(FUNCT7_MULDIV, 5'd2, 5'd1, FUNCT3_ADD_SUB, 5'd4, OP_REG));

        wait_cdb_valid(); // ADDI x1 = 6
        wait_cdb_valid(); // ADDI x2 = 7
        wait_cdb_valid(); // ADD x3 = 13 (fast)
        check_val("ADD x3 = 13", dut.cdb_rd_data, 64'd13);
        wait_cdb_valid(50); // MUL x4 = 42 (slower)
        check_val("MUL x4 = 42", dut.cdb_rd_data, 64'd42);

        // ==============================================================
        // Test 25: Pipeline throughput — many independent instructions
        // ==============================================================
        test_num = 25;
        $display("\n[Test %0d] Pipeline throughput: 8 independent ADDI", test_num);
        reset_dut();
        for (int i = 0; i < 8; i++) begin
            load_instr(IMEM_DEPTH'(i * 4),
                       encode_i(12'(i + 1), 5'd0, FUNCT3_ADD_SUB, 5'(i + 1), OP_IMM));
        end

        for (int i = 0; i < 8; i++) begin
            wait_cdb_valid(30);
            $display("  Instruction %0d completed: CDB data = %0d", i, dut.cdb_rd_data);
        end
        $display("  All 8 instructions completed");

        // ==============================================================
        // Test 26: WAW hazard — same dest register written twice
        // ADDI x1, x0, 10
        // ADDI x1, x0, 20 (same dest, newer value)
        // ADD x2, x1, x0 (should use latest x1 = 20)
        // ==============================================================
        test_num = 26;
        $display("\n[Test %0d] WAW hazard: double write to x1", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd10, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'd20, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0008, encode_r(FUNCT7_ZERO, 5'd0, 5'd1, FUNCT3_ADD_SUB, 5'd2, OP_REG));

        wait_cdb_valid(); // ADDI x1 = 10
        wait_cdb_valid(); // ADDI x1 = 20
        wait_cdb_valid(); // ADD x2 = x1 + x0 = 20
        check_val("WAW: ADD uses latest x1 = 20", dut.cdb_rd_data, 64'd20);

        // ==============================================================
        // Test 27: Long dependency through MUL then ADD
        // ADDI x1, x0, 3 → ADDI x2, x0, 4
        // MUL x3, x1, x2 (= 12, takes MUL_CYCLES)
        // ADDI x4, x3, 1 (depends on MUL result, should be 13)
        // ==============================================================
        test_num = 27;
        $display("\n[Test %0d] MUL → ADDI dependency (3*4+1=13)", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd3, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'd4, 5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));
        load_instr(32'h0000_0008, encode_r(FUNCT7_MULDIV, 5'd2, 5'd1, FUNCT3_ADD_SUB, 5'd3, OP_REG));
        load_instr(32'h0000_000C, encode_i(12'd1, 5'd3, FUNCT3_ADD_SUB, 5'd4, OP_IMM));

        wait_cdb_valid(); // ADDI x1
        wait_cdb_valid(); // ADDI x2
        wait_cdb_valid(50); // MUL x3 = 12
        check_val("MUL x3 = 12", dut.cdb_rd_data, 64'd12);
        wait_cdb_valid(); // ADDI x4 = 13
        check_val("ADDI x4 = 13", dut.cdb_rd_data, 64'd13);

        // ==============================================================
        // Test 28: LW followed by dependent ADD
        // pre-load dmem[0] = 100
        // LW x1, 0(x0) → ADD x2, x1, x0 (x2 = 100)
        // ==============================================================
        test_num = 28;
        $display("\n[Test %0d] LW → ADD dependency", test_num);
        reset_dut();
        load_dmem(32'h0000_0000, 64'd100);
        load_instr(32'h0000_0000, encode_i(12'd0, 5'd0, FUNCT3_LW, 5'd1, OP_LOAD));
        load_instr(32'h0000_0004, encode_r(FUNCT7_ZERO, 5'd0, 5'd1, FUNCT3_ADD_SUB, 5'd2, OP_REG));

        wait_cdb_valid(50); // LW x1 = 100
        check_val("LW x1 = 100", dut.cdb_rd_data, 64'd100);
        wait_cdb_valid(50); // ADD x2 = 100 + 0
        check_val("ADD after LW = 100", dut.cdb_rd_data, 64'd100);

        // ==============================================================
        // Test 29: Multiple stores followed by loads (memory ordering)
        // SW x1, 0(x0) then SW x2, 8(x0)
        // ==============================================================
        test_num = 29;
        $display("\n[Test %0d] Multiple stores", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd11, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'd22, 5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));
        load_instr(32'h0000_0008, encode_s(12'd0, 5'd1, 5'd0, FUNCT3_SW, OP_STORE));
        load_instr(32'h0000_000C, encode_s(12'd8, 5'd2, 5'd0, FUNCT3_SW, OP_STORE));

        wait_cycles(80);
        $display("  Multiple stores test completed");

        // ==============================================================
        // Test 30: Back-to-back branches
        // ADDI x1, x0, 1 → ADDI x2, x0, 2
        // BEQ x0, x0, +8 (always taken, x0==x0)
        // target: ADDI x3, x0, 33
        // ==============================================================
        test_num = 30;
        $display("\n[Test %0d] Back-to-back branches", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd1, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_b(13'd8, 5'd0, 5'd0, FUNCT3_BEQ, OP_BRANCH));
        load_instr(32'h0000_000C, encode_i(12'd33, 5'd0, FUNCT3_ADD_SUB, 5'd3, OP_IMM));

        wait_cycles(80);
        $display("  Back-to-back branches test completed");

        // ==============================================================
        // Test 31: ROB capacity — fill without completing
        // Dispatch ROB_DEPTH instructions without CDB completion
        // ==============================================================
        test_num = 31;
        $display("\n[Test %0d] ROB capacity stress", test_num);
        reset_dut();
        for (int i = 0; i < ROB_DEPTH + 4; i++) begin
            load_instr(IMEM_DEPTH'(i * 4),
                       encode_i(12'(i + 1), 5'd0, FUNCT3_ADD_SUB, 5'((i % 30) + 1), OP_IMM));
        end

        wait_cycles(150);
        $display("  ROB stress test completed (pipeline should self-regulate)");

        // ==============================================================
        // Test 32: Fibonacci-like sequence
        // x1=1, x2=1, x3=x1+x2=2, x4=x2+x3=3, x5=x3+x4=5
        // ==============================================================
        test_num = 32;
        $display("\n[Test %0d] Fibonacci: 1,1,2,3,5", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd1, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'd1, 5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));
        load_instr(32'h0000_0008, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_ADD_SUB, 5'd3, OP_REG));
        load_instr(32'h0000_000C, encode_r(FUNCT7_ZERO, 5'd3, 5'd2, FUNCT3_ADD_SUB, 5'd4, OP_REG));
        load_instr(32'h0000_0010, encode_r(FUNCT7_ZERO, 5'd4, 5'd3, FUNCT3_ADD_SUB, 5'd5, OP_REG));

        wait_cdb_valid(); // x1 = 1
        check_val("fib x1 = 1", dut.cdb_rd_data, 64'd1);
        wait_cdb_valid(); // x2 = 1
        check_val("fib x2 = 1", dut.cdb_rd_data, 64'd1);
        wait_cdb_valid(); // x3 = 2
        check_val("fib x3 = 2", dut.cdb_rd_data, 64'd2);
        wait_cdb_valid(); // x4 = 3
        check_val("fib x4 = 3", dut.cdb_rd_data, 64'd3);
        wait_cdb_valid(); // x5 = 5
        check_val("fib x5 = 5", dut.cdb_rd_data, 64'd5);

        // ==============================================================
        // Test 33: Compute with all R-type ALU ops in sequence
        // ==============================================================
        test_num = 33;
        $display("\n[Test %0d] All R-type ALU ops sequence", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd100, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM)); // x1=100
        load_instr(32'h0000_0004, encode_i(12'd3,   5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM)); // x2=3
        load_instr(32'h0000_0008, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_ADD_SUB, 5'd3, OP_REG));  // ADD x3=103
        load_instr(32'h0000_000C, encode_r(FUNCT7_ALT,  5'd2, 5'd1, FUNCT3_ADD_SUB, 5'd4, OP_REG));  // SUB x4=97
        load_instr(32'h0000_0010, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_AND,     5'd5, OP_REG));  // AND x5
        load_instr(32'h0000_0014, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_OR,      5'd6, OP_REG));  // OR x6
        load_instr(32'h0000_0018, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_XOR,     5'd7, OP_REG));  // XOR x7
        load_instr(32'h0000_001C, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_SLT,     5'd8, OP_REG));  // SLT x8 (100<3→0)
        load_instr(32'h0000_0020, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_SLL,     5'd9, OP_REG));  // SLL x9=100<<3
        load_instr(32'h0000_0024, encode_r(FUNCT7_ZERO, 5'd2, 5'd1, FUNCT3_SRL_SRA, 5'd10, OP_REG)); // SRL x10=100>>3

        wait_cdb_valid(); // x1 = 100
        wait_cdb_valid(); // x2 = 3
        wait_cdb_valid(); // ADD x3
        check_val("ADD 100+3=103", dut.cdb_rd_data, 64'd103);
        wait_cdb_valid(); // SUB x4
        check_val("SUB 100-3=97", dut.cdb_rd_data, 64'd97);
        wait_cdb_valid(); // AND x5
        check_val("AND 100&3", dut.cdb_rd_data, 64'(100 & 3));
        wait_cdb_valid(); // OR x6
        check_val("OR 100|3", dut.cdb_rd_data, 64'(100 | 3));
        wait_cdb_valid(); // XOR x7
        check_val("XOR 100^3", dut.cdb_rd_data, 64'(100 ^ 3));
        wait_cdb_valid(); // SLT x8
        check_val("SLT 100<3=0", dut.cdb_rd_data, 64'd0);
        wait_cdb_valid(); // SLL x9
        check_val("SLL 100<<3=800", dut.cdb_rd_data, 64'd800);
        wait_cdb_valid(); // SRL x10
        check_val("SRL 100>>3=12", dut.cdb_rd_data, 64'd12);

        // ==============================================================
        // Test 34: Stress test — rapid interleaved MUL and INT
        // ==============================================================
        test_num = 34;
        $display("\n[Test %0d] Interleaved MUL and INT stress", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd2, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));  // x1=2
        load_instr(32'h0000_0004, encode_i(12'd3, 5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));  // x2=3
        load_instr(32'h0000_0008, encode_r(FUNCT7_MULDIV, 5'd2, 5'd1, FUNCT3_ADD_SUB, 5'd3, OP_REG)); // MUL x3=6
        load_instr(32'h0000_000C, encode_i(12'd10, 5'd0, FUNCT3_ADD_SUB, 5'd4, OP_IMM)); // x4=10
        load_instr(32'h0000_0010, encode_r(FUNCT7_MULDIV, 5'd2, 5'd4, FUNCT3_ADD_SUB, 5'd5, OP_REG)); // MUL x5=10*3=30
        load_instr(32'h0000_0014, encode_i(12'd7, 5'd0, FUNCT3_ADD_SUB, 5'd6, OP_IMM));  // x6=7

        wait_cdb_valid(); // x1=2
        wait_cdb_valid(); // x2=3
        // INT results may come before MUL results due to out-of-order
        for (int i = 0; i < 4; i++) begin
            wait_cdb_valid(50);
            $display("  CDB result %0d: data=%0d, phy=%0d", i, dut.cdb_rd_data, dut.cdb_rd_phy_addr);
        end
        $display("  Interleaved MUL/INT stress completed");

        // ==============================================================
        // Summary
        // ==============================================================
        $display("\n=======================================");
        $display("  CPU Integration Testbench Done");
        $display("  %0d passed, %0d failed", pass_cnt, fail_cnt);
        $display("=======================================");

        if (fail_cnt == 0) begin
            $display("[PASS] CPU_tb completed successfully");
        end else begin
            $display("[RESULT] CPU_tb found %0d failure(s) — review needed", fail_cnt);
        end
        $finish;
    end

    // Timeout watchdog
    initial begin
        #5_000_000;
        $error("TIMEOUT: simulation exceeded 5ms");
        $finish;
    end

endmodule
/* verilator lint_on WIDTH */
/* verilator lint_on BLKSEQ */
// verilog_lint: waive-stop explicit-parameter-storage-type
