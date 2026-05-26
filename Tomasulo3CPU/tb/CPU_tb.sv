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
    parameter int unsigned IMEM_DEPTH              = 64;
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
    parameter int unsigned W_BYTE_NUM              = DMEM_WIDTH / 8;

    // ----------------------------------------------------------------
    // DUT Signals
    // ----------------------------------------------------------------
    logic clk, rst_n;

    // I-Cache
    logic                    imem_valid;
    logic [INSTR_WIDTH-1:0]  imem_data;
    logic                    imem_read_rdy;
    logic [IMEM_DEPTH-1:0]   imem_addr;

    // D-Cache read interface
    logic                            dcache_rvalid;
    logic                            dcache_rresp_valid;
    logic [REG_FILE_DATA_WIDTH-1:0]  dcache_rdata;
    logic [DMEM_DEPTH-1:0]           dcache_raddr;
    logic                            dcache_rready;
    logic                            dcache_rresp_ready;

    // D-Cache write interface
    logic                            dcache_wvalid;
    logic                            dcache_wresp_valid;
    logic                            dcache_write;
    logic [DMEM_WIDTH-1:0]           dcache_sw_data;
    logic [W_BYTE_NUM-1:0]           dcache_wstrb;
    logic [DMEM_DEPTH-1:0]           dcache_sw_addr;
    logic                            dcache_wready;
    logic                            dcache_wresp_ready;

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
        .clk               (clk),
        .rst_n             (rst_n),
        .imem_valid        (imem_valid),
        .imem_data         (imem_data),
        .imem_read_rdy     (imem_read_rdy),
        .imem_addr         (imem_addr),
        .dcache_rvalid     (dcache_rvalid),
        .dcache_rresp_valid(dcache_rresp_valid),
        .dcache_rdata      (dcache_rdata),
        .dcache_raddr      (dcache_raddr),
        .dcache_rready     (dcache_rready),
        .dcache_rresp_ready(dcache_rresp_ready),
        .dcache_wvalid     (dcache_wvalid),
        .dcache_wresp_valid(dcache_wresp_valid),
        .dcache_write      (dcache_write),
        .dcache_sw_data    (dcache_sw_data),
        .dcache_wstrb      (dcache_wstrb),
        .dcache_sw_addr    (dcache_sw_addr),
        .dcache_wready     (dcache_wready),
        .dcache_wresp_ready(dcache_wresp_ready)
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

    function automatic logic [31:0] encode_u(
        input logic [19:0] imm,
        input logic [4:0]  rd,
        input logic [6:0]  opcode
    );
        return {imm, rd, opcode};
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

    // CSR instruction: CSRRW/CSRRS/CSRRC/CSRRWI/CSRRSI/CSRRCI
    function automatic logic [31:0] encode_csr(
        input logic [11:0] csr_addr,
        input logic [4:0]  rs1_or_zimm,
        input logic [2:0]  funct3,
        input logic [4:0]  rd
    );
        return {csr_addr, rs1_or_zimm, funct3, rd, OP_SYSTEM};
    endfunction

    function automatic logic [31:0] encode_ecall();
        return {12'b0000_0000_0000, 5'd0, 3'b000, 5'd0, OP_SYSTEM};
    endfunction

    function automatic logic [31:0] encode_ebreak();
        return {12'b0000_0000_0001, 5'd0, 3'b000, 5'd0, OP_SYSTEM};
    endfunction

    function automatic logic [31:0] encode_mret();
        return {12'b0011_0000_0010, 5'd0, 3'b000, 5'd0, OP_SYSTEM};
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

    logic cdb_seen_by_rob [ROB_DEPTH];
    logic cdb_expected_by_rob [ROB_DEPTH];
    logic cdb_checked_by_rob [ROB_DEPTH];
    logic cdb_pass_by_rob [ROB_DEPTH];
    logic cdb_reg_write_by_rob [ROB_DEPTH];
    logic [REG_FILE_DATA_WIDTH-1:0] cdb_data_by_rob [ROB_DEPTH];
    logic [REG_FILE_DATA_WIDTH-1:0] cdb_expected_data_by_rob [ROB_DEPTH];

    // Read path
    assign dcache_rvalid = rst_n;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dcache_rresp_valid <= 1'b0;
            dcache_rdata       <= '0;
        end else begin
            if (dcache_rready && dcache_rvalid) begin
                dcache_rresp_valid <= 1'b1;
                dcache_rdata       <= dmem_array[dcache_raddr[DMEM_DEPTH-1:3]];
            end else if (dcache_rresp_valid && dcache_rresp_ready) begin
                dcache_rresp_valid <= 1'b0;
            end
        end
    end

    // Write path
    // Plain always is intentional: dmem_array is also initialized/preloaded by
    // testbench tasks, which is illegal for an always_ff-written variable.
    assign dcache_wvalid = rst_n;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dcache_wresp_valid <= 1'b0;
        end else begin
            if (dcache_wready && dcache_wvalid) begin
                for (int i = 0; i < W_BYTE_NUM; i++) begin
                    if (dcache_wstrb[i]) begin
                        dmem_array[dcache_sw_addr[DMEM_DEPTH-1:3]][i*8 +: 8] <= dcache_sw_data[i*8 +: 8];
                    end
                end
                dcache_wresp_valid <= 1'b1;
            end else begin
                dcache_wresp_valid <= 1'b0;
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
        for (int i = 0; i < IMEM_SIZE; i++)
            imem_array[i] = nop();
        for (int i = 0; i < DMEM_SIZE; i++)
            dmem_array[i] = '0;
        for (int i = 0; i < ROB_DEPTH; i++) begin
            cdb_seen_by_rob[i] = 1'b0;
            cdb_expected_by_rob[i] = 1'b0;
            cdb_checked_by_rob[i] = 1'b0;
            cdb_pass_by_rob[i] = 1'b0;
            cdb_reg_write_by_rob[i] = 1'b0;
            cdb_data_by_rob[i] = '0;
            cdb_expected_data_by_rob[i] = '0;
        end
        repeat (3) @(posedge clk); #1;
        rst_n = 1'b1;
    endtask

    task automatic check_cdb_pool_entry(input int unsigned rob_idx);
        if (cdb_seen_by_rob[rob_idx] &&
            cdb_expected_by_rob[rob_idx] &&
            !cdb_checked_by_rob[rob_idx]) begin
            cdb_checked_by_rob[rob_idx] = 1'b1;
            if (cdb_data_by_rob[rob_idx] !== cdb_expected_data_by_rob[rob_idx]) begin
                $error("[FAIL] CDB ROB tag %0d: got 0x%0h, want 0x%0h @ %0t",
                       rob_idx, cdb_data_by_rob[rob_idx],
                       cdb_expected_data_by_rob[rob_idx], $time);
                fail_cnt++;
            end else begin
                cdb_pass_by_rob[rob_idx] = 1'b1;
                pass_cnt++;
            end
        end
    endtask

    task automatic sample_cdb();
        if (dut.cdb_valid) begin
            cdb_seen_by_rob[int'(dut.cdb_rob_tag)] = 1'b1;
            cdb_reg_write_by_rob[int'(dut.cdb_rob_tag)] = dut.cdb_reg_write;
            cdb_data_by_rob[int'(dut.cdb_rob_tag)] = dut.cdb_rd_data;
            check_cdb_pool_entry(int'(dut.cdb_rob_tag));
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (rst_n)
            sample_cdb();
    end

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

    task automatic wait_cdb_tag(
        input logic [ROB_INDEX_WIDTH-1:0] expected_rob_tag,
        input int unsigned max_cycles = 100
    );
        int cyc;
        cyc = 0;
        while (!cdb_seen_by_rob[int'(expected_rob_tag)] && (cyc < max_cycles)) begin
            @(posedge clk); #1;
            cyc++;
        end

        if (!cdb_seen_by_rob[int'(expected_rob_tag)])
            $warning("wait_cdb_tag: ROB tag %0d timed out after %0d cycles @ %0t",
                     expected_rob_tag, max_cycles, $time);
    endtask

    task automatic check_cdb_result(
        input string tag,
        input logic [ROB_INDEX_WIDTH-1:0] expected_rob_tag,
        input logic [REG_FILE_DATA_WIDTH-1:0] expected_data,
        input int unsigned max_cycles = 100
    );
        int rob_idx;
        int cyc;
        rob_idx = int'(expected_rob_tag);
        cdb_expected_by_rob[rob_idx] = 1'b1;
        cdb_expected_data_by_rob[rob_idx] = expected_data;
        check_cdb_pool_entry(rob_idx);

        cyc = 0;
        while (!cdb_checked_by_rob[rob_idx] && (cyc < max_cycles)) begin
            @(posedge clk); #1;
            cyc++;
        end

        if (!cdb_checked_by_rob[rob_idx]) begin
            $error("[FAIL] %s: ROB tag %0d did not appear on CDB within %0d cycles @ %0t",
                   tag, expected_rob_tag, max_cycles, $time);
            fail_cnt++;
        end else if (!cdb_pass_by_rob[rob_idx]) begin
            $display("  %s failed for ROB tag %0d", tag, expected_rob_tag);
        end
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

    // Read architectural register via RRAT → PRF
    function automatic logic [REG_FILE_DATA_WIDTH-1:0] read_arch_reg(
        input logic [ARCH_REG_WIDTH-1:0] arch_addr
    );
        logic [PHY_REGISTER_FILE_WIDTH-1:0] phy;
        phy = dut.front_end.rrat.rrat_array[arch_addr];
        return dut.back_end.prf.prf_data_array[phy];
    endfunction

    // Read CSR value directly from the CSR module
    function automatic logic [REG_FILE_DATA_WIDTH-1:0] read_csr_mscratch();
        return dut.front_end.csr_unit.mscratch_q;
    endfunction
    function automatic logic [REG_FILE_DATA_WIDTH-1:0] read_csr_mtvec();
        return dut.front_end.csr_unit.mtvec_q;
    endfunction
    function automatic logic [REG_FILE_DATA_WIDTH-1:0] read_csr_mepc();
        return dut.front_end.csr_unit.mepc_q;
    endfunction
    function automatic logic [REG_FILE_DATA_WIDTH-1:0] read_csr_mcause();
        return dut.front_end.csr_unit.mcause_q;
    endfunction
    function automatic logic [REG_FILE_DATA_WIDTH-1:0] read_csr_mstatus();
        return dut.front_end.csr_unit.mstatus_q;
    endfunction

    // ----------------------------------------------------------------
    // Main test sequence
    // ----------------------------------------------------------------
    initial begin
        `ifdef FSDB_DUMP
            $fsdbDumpfile("CPU.fsdb");
            $fsdbDumpvars("+all");
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
        check_bit("dcache_rready after reset", dcache_rready, 1'b0);
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

        check_cdb_result("ADDI result = 42", 0, 64'd42);
        check_bit("ADDI reg write", cdb_reg_write_by_rob[0], 1'b1);

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
        check_cdb_result("ADDI x1 = 10", 0, 64'd10);
        check_cdb_result("ADDI x2 = 20", 1, 64'd20);
        check_cdb_result("ADD x3 = 30", 2, 64'd30);

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

        wait_cdb_tag(0); // ADDI x1
        wait_cdb_tag(1); // ADDI x2
        check_cdb_result("SUB x3 = 32", 2, 64'd32);

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

        wait_cdb_tag(0); // ADDI x1 = 0xFF
        wait_cdb_tag(1); // ADDI x2 = 0x0F
        check_cdb_result("AND result", 2, 64'h0F);
        check_cdb_result("OR result", 3, 64'hFF);
        check_cdb_result("XOR result", 4, 64'hF0);

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

        wait_cdb_tag(0); // ADDI x1
        wait_cdb_tag(1); // ADDI x2
        check_cdb_result("SLT 5<10 = 1", 2, 64'd1);
        check_cdb_result("SLT 10<5 = 0", 3, 64'd0);

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

        wait_cdb_tag(0); // ADDI x1
        wait_cdb_tag(1); // ADDI x2
        check_cdb_result("SLL 8<<2 = 32", 2, 64'd32);
        check_cdb_result("SRL 8>>2 = 2", 3, 64'd2);

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

        wait_cdb_tag(0); // ADDI x1
        check_cdb_result("SLLI 16<<3 = 128", 1, 64'd128);
        check_cdb_result("SRLI 16>>2 = 4", 2, 64'd4);

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

        wait_cdb_tag(0); // ADDI x1 = 0xAB
        check_cdb_result("ANDI 0xAB & 0x0F = 0x0B", 1, 64'h0B);
        check_cdb_result("ORI 0xAB | 0x100 = 0x1AB", 2, 64'h1AB);
        check_cdb_result("XORI 0xAB ^ 0xFF = 0x54", 3, 64'h54);

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

        wait_cdb_tag(0); // ADDI x1
        check_cdb_result("SLTI 5<10 = 1", 1, 64'd1);
        check_cdb_result("SLTI 5<3 = 0", 2, 64'd0);

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

        wait_cdb_tag(0); // ADDI x1
        wait_cdb_tag(1); // ADDI x2
        check_cdb_result("MUL 6*7 = 42", 2, 64'd42, 50);

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

        wait_cdb_tag(0); // ADDI x1
        wait_cdb_tag(1); // ADDI x2
        check_cdb_result("DIV 100/5 = 20", 2, 64'd20, 50);

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

        wait_cdb_tag(0); // ADDI x1
        wait_cdb_tag(1); // ADDI x2
        check_cdb_result("REM 100%%7 = 2", 2, 64'd2, 50);

        // ==============================================================
        // Test 14: LD instruction
        // Pre-load D-cache with value, then LD to register
        // ADDI x1, x0, 0 → LD x2, 0(x1) — read from addr 0
        // ==============================================================
        test_num = 14;
        $display("\n[Test %0d] LD x2, 0(x1) from D-cache", test_num);
        reset_dut();
        load_dmem(32'h0000_0000, 64'hDEAD_BEEF_CAFE_BABE);
        load_instr(32'h0000_0000, encode_i(12'd0, 5'd0, FUNCT3_LD, 5'd2, OP_LOAD));

        check_cdb_result("LD loaded data", 0, 64'hDEAD_BEEF_CAFE_BABE, 50);

        // ==============================================================
        // Test 15: LD with non-zero offset
        // ADDI x1, x0, 8 → LD x2, 8(x1) — read from addr 16
        // ==============================================================
        test_num = 15;
        $display("\n[Test %0d] LD x2, 8(x1) with offset", test_num);
        reset_dut();
        load_dmem(32'h0000_0010, 64'h1234_5678_ABCD_EF00);
        load_instr(32'h0000_0000, encode_i(12'd8, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'd8, 5'd1, FUNCT3_LD, 5'd2, OP_LOAD));

        wait_cdb_tag(0); // ADDI x1
        check_cdb_result("LD from addr 16", 1, 64'h1234_5678_ABCD_EF00, 50);

        // ==============================================================
        // Test 16: SD instruction (store to memory)
        // ADDI x1, x0, 99 → SD x1, 0(x0)
        // ==============================================================
        test_num = 16;
        $display("\n[Test %0d] SD x1, 0(x0) store to memory", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd99, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_s(12'd0, 5'd1, 5'd0, FUNCT3_SD, OP_STORE));

        wait_cdb_tag(0); // ADDI x1
        wait_cdb_tag(1, 50); // SD completes on CDB
        // Wait for ROB to commit and SB to write
        wait_cycles(20);
        $display("  SD test: store completed (checking commit path)");

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

        wait_cdb_tag(0); // JAL link address
        check_cdb_result("ADDI at JAL target = 77", 1, 64'd77, 50);

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

        wait_cdb_tag(0); // ADDI x1
        wait_cdb_tag(1, 80); // JALR x2 link
        // After JALR resolves, pipeline should redirect to 0x20
        check_cdb_result("ADDI at JALR target = 88", 2, 64'd88, 80);

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

        check_cdb_result("chain x1 = 1", 0, 64'd1);
        check_cdb_result("chain x2 = 2", 1, 64'd2);
        check_cdb_result("chain x3 = 3", 2, 64'd3);
        check_cdb_result("chain x4 = 4", 3, 64'd4);

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

        wait_cdb_tag(0); // ADDI x1 = 6
        wait_cdb_tag(1); // ADDI x2 = 7
        check_cdb_result("ADD x3 = 13", 2, 64'd13);
        check_cdb_result("MUL x4 = 42", 3, 64'd42, 50);

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

        wait_cdb_tag(0); // ADDI x1 = 10
        wait_cdb_tag(1); // ADDI x1 = 20
        check_cdb_result("WAW: ADD uses latest x1 = 20", 2, 64'd20);

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

        wait_cdb_tag(0); // ADDI x1
        wait_cdb_tag(1); // ADDI x2
        check_cdb_result("MUL x3 = 12", 2, 64'd12, 50);
        check_cdb_result("ADDI x4 = 13", 3, 64'd13);

        // ==============================================================
        // Test 28: LD followed by dependent ADD
        // pre-load dmem[0] = 100
        // LD x1, 0(x0) → ADD x2, x1, x0 (x2 = 100)
        // ==============================================================
        test_num = 28;
        $display("\n[Test %0d] LD → ADD dependency", test_num);
        reset_dut();
        load_dmem(32'h0000_0000, 64'd100);
        load_instr(32'h0000_0000, encode_i(12'd0, 5'd0, FUNCT3_LD, 5'd1, OP_LOAD));
        load_instr(32'h0000_0004, encode_r(FUNCT7_ZERO, 5'd0, 5'd1, FUNCT3_ADD_SUB, 5'd2, OP_REG));

        check_cdb_result("LD x1 = 100", 0, 64'd100, 50);
        check_cdb_result("ADD after LD = 100", 1, 64'd100, 50);

        // ==============================================================
        // Test 29: Multiple stores followed by loads (memory ordering)
        // SD x1, 0(x0) then SD x2, 8(x0)
        // ==============================================================
        test_num = 29;
        $display("\n[Test %0d] Multiple stores", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd11, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'd22, 5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));
        load_instr(32'h0000_0008, encode_s(12'd0, 5'd1, 5'd0, FUNCT3_SD, OP_STORE));
        load_instr(32'h0000_000C, encode_s(12'd8, 5'd2, 5'd0, FUNCT3_SD, OP_STORE));

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

        check_cdb_result("fib x1 = 1", 0, 64'd1);
        check_cdb_result("fib x2 = 1", 1, 64'd1);
        check_cdb_result("fib x3 = 2", 2, 64'd2);
        check_cdb_result("fib x4 = 3", 3, 64'd3);
        check_cdb_result("fib x5 = 5", 4, 64'd5);

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

        wait_cdb_tag(0); // x1 = 100
        wait_cdb_tag(1); // x2 = 3
        check_cdb_result("ADD 100+3=103", 2, 64'd103);
        check_cdb_result("SUB 100-3=97", 3, 64'd97);
        check_cdb_result("AND 100&3", 4, 64'(100 & 3));
        check_cdb_result("OR 100|3", 5, 64'(100 | 3));
        check_cdb_result("XOR 100^3", 6, 64'(100 ^ 3));
        check_cdb_result("SLT 100<3=0", 7, 64'd0);
        check_cdb_result("SLL 100<<3=800", 8, 64'd800);
        check_cdb_result("SRL 100>>3=12", 9, 64'd12);

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
        // Test 35: LUI U-type immediate
        // LUI x1, 0x12345 → x1 = 0x0000_0000_1234_5000
        // LUI x2, 0x80000 → x2 = 0xFFFF_FFFF_8000_0000 (RV64 sign-extended)
        // ==============================================================
        test_num = 35;
        $display("\n[Test %0d] LUI U-type immediate", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_u(20'h12345, 5'd1, OP_LUI));
        load_instr(32'h0000_0004, encode_u(20'h80000, 5'd2, OP_LUI));

        wait_dispatch();
        check_val("LUI dispatched", dut.dis_opcode, INSTR_LUI);
        check_bit("LUI INT issue", dut.dis_int_issue_en, 1'b1);

        check_cdb_result("LUI x1 = 0x12345000", 0, 64'h0000_0000_1234_5000);
        check_cdb_result("LUI x2 sign-extends bit 31", 1, 64'hFFFF_FFFF_8000_0000);

        // ==============================================================
        // Test 36: AUIPC U-type immediate plus current PC
        // AUIPC x3, 0x00010 at PC 0x00 → x3 = 0x0001_0000
        // AUIPC x4, 0x12345 at PC 0x04 → x4 = 0x1234_5004
        // AUIPC x5, 0xFFFFF at PC 0x08 → x5 = -0x1000 + 0x08
        // ==============================================================
        test_num = 36;
        $display("\n[Test %0d] AUIPC U-type immediate plus PC", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_u(20'h00010, 5'd3, OP_AUIPC));
        load_instr(32'h0000_0004, encode_u(20'h12345, 5'd4, OP_AUIPC));
        load_instr(32'h0000_0008, encode_u(20'hFFFFF, 5'd5, OP_AUIPC));

        wait_dispatch();
        check_val("AUIPC dispatched", dut.dis_opcode, INSTR_AUIPC);
        check_bit("AUIPC INT issue", dut.dis_int_issue_en, 1'b1);

        check_cdb_result("AUIPC x3 = 0x00010000 + PC0", 0, 64'h0000_0000_0001_0000);
        check_cdb_result("AUIPC x4 = 0x12345000 + PC4", 1, 64'h0000_0000_1234_5004);
        check_cdb_result("AUIPC x5 sign-extended offset + PC8", 2, 64'hFFFF_FFFF_FFFF_F008);

        // ==============================================================
        // Test 37: BLT taken — signed comparison
        // ADDI x1, x0, -1 → ADDI x2, x0, 1
        // BLT x1, x2, +16 should skip the wrong-path store
        // ==============================================================
        test_num = 37;
        $display("\n[Test %0d] BLT taken signed compare (-1 < 1)", test_num);
        reset_dut();
        load_dmem(32'h0000_0000, 64'hCAFE_BABE_0000_0000);
        load_dmem(32'h0000_0008, 64'h0);
        load_instr(32'h0000_0000, encode_i(12'hFFF, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'd1,   5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));
        load_instr(32'h0000_0008, encode_b(13'd16, 5'd2, 5'd1, FUNCT3_BLT, OP_BRANCH));
        load_instr(32'h0000_000C, encode_i(12'd99, 5'd0, FUNCT3_ADD_SUB, 5'd3, OP_IMM));
        load_instr(32'h0000_0010, encode_s(12'd0,  5'd3, 5'd0, FUNCT3_SD, OP_STORE));
        load_instr(32'h0000_0018, encode_i(12'd42, 5'd0, FUNCT3_ADD_SUB, 5'd4, OP_IMM));
        load_instr(32'h0000_001C, encode_s(12'd8,  5'd4, 5'd0, FUNCT3_SD, OP_STORE));

        wait_cycles(120);
        check_val("BLT skipped wrong-path store", dmem_array[0], 64'hCAFE_BABE_0000_0000);
        check_val("BLT reached target store", dmem_array[1], 64'd42);

        // ==============================================================
        // Test 38: BLTU taken — unsigned comparison
        // ADDI x1, x0, 1 → ADDI x2, x0, -1
        // BLTU x1, x2, +16 should skip the wrong-path store
        // ==============================================================
        test_num = 38;
        $display("\n[Test %0d] BLTU taken unsigned compare (1 < 0xffff...)", test_num);
        reset_dut();
        load_dmem(32'h0000_0010, 64'hBADC_0FFE_0000_0010);
        load_dmem(32'h0000_0018, 64'h0);
        load_instr(32'h0000_0000, encode_i(12'd1,   5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'hFFF, 5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));
        load_instr(32'h0000_0008, encode_b(13'd16, 5'd2, 5'd1, FUNCT3_BLTU, OP_BRANCH));
        load_instr(32'h0000_000C, encode_i(12'd77, 5'd0, FUNCT3_ADD_SUB, 5'd3, OP_IMM));
        load_instr(32'h0000_0010, encode_s(12'd16, 5'd3, 5'd0, FUNCT3_SD, OP_STORE));
        load_instr(32'h0000_0018, encode_i(12'd33, 5'd0, FUNCT3_ADD_SUB, 5'd4, OP_IMM));
        load_instr(32'h0000_001C, encode_s(12'd24, 5'd4, 5'd0, FUNCT3_SD, OP_STORE));

        wait_cycles(120);
        check_val("BLTU skipped wrong-path store", dmem_array[2], 64'hBADC_0FFE_0000_0010);
        check_val("BLTU reached target store", dmem_array[3], 64'd33);

        // ==============================================================
        // Test 39: SB (Store Byte) and LD (Load Doubleword)
        // Verify byte strobe positioning and dependency tracking on the same address.
        // We write 0xEF to offset 3 of address 8.
        // ADDI x1, x0, 8 (base addr)
        // ADDI x2, x0, 0xEF (data to store)
        // SB x2, 3(x1) -> writes 0xEF to address 11
        // LD x3, 0(x1) -> reads 64-bit word from address 8
        // We expect the read word to contain 0xEF at byte 3, other bytes should be 0.
        // ==============================================================
        test_num = 39;
        $display("\n[Test %0d] SB (Store Byte) at offset 3 and LD", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd8,    5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));   // x1 = 8
        load_instr(32'h0000_0004, encode_i(12'hEF,   5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));   // x2 = 0xEF
        load_instr(32'h0000_0008, encode_s(12'd3,    5'd2, 5'd1,           FUNCT3_SB, OP_STORE)); // SB x2, 3(x1) -> addr 11
        load_instr(32'h0000_000c, encode_i(12'd0,    5'd1, FUNCT3_LD,      5'd3, OP_LOAD));  // LD x3, 0(x1) -> read from addr 8

        wait_cycles(150);
        check_val("SB byte written to dmem", dmem_array[1], 64'h0000_0000_EF00_0000);
        check_cdb_result("LD x3 read back stored byte", 3, 64'h0000_0000_EF00_0000, 50);

        // ==============================================================
        // Test 40: SH (Store Halfword) and LD (Load Doubleword)
        // Verify partial-word write behavior at offset 2.
        // We write 0xFFFE to offset 2 of address 8.
        // ADDI x1, x0, 8 (base addr)
        // ADDI x2, x0, -2 (data to store, lower 16 bits = 0xFFFE)
        // SH x2, 2(x1) -> writes 0xFFFE to address 10
        // LD x3, 0(x1) -> reads 64-bit word from address 8
        // We expect the read word to contain 0xFFFE at bytes 3:2, other bytes should be 0.
        // ==============================================================
        test_num = 40;
        $display("\n[Test %0d] SH (Store Halfword) at offset 2 and LD", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd8,     5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));   // x1 = 8
        load_instr(32'h0000_0004, encode_i(12'hFFE,   5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));   // x2 = -2
        load_instr(32'h0000_0008, encode_s(12'd2,     5'd2, 5'd1,           FUNCT3_SH, OP_STORE)); // SH x2, 2(x1) -> addr 10
        load_instr(32'h0000_00c, encode_i(12'd0,     5'd1, FUNCT3_LD,      5'd3, OP_LOAD));  // LD x3, 0(x1) -> read from addr 8

        wait_cycles(150);
        check_val("SH halfword written to dmem", dmem_array[1], 64'h0000_0000_FFFE_0000);
        check_cdb_result("LD x3 read back stored halfword", 3, 64'h0000_0000_FFFE_0000, 50);

        // ==============================================================
        // Test 41: SW (Store Word) and LD (Load Doubleword)
        // Verify 32-bit store strobe behavior at offset 4.
        // We write 0x1234_5678 to offset 4 of address 8.
        // ADDI x1, x0, 8 (base addr)
        // LUI x2, 0x12345
        // ADDI x2, x2, 0x678
        // SW x2, 4(x1) -> writes 0x1234_5678 to address 12
        // LD x3, 0(x1) -> reads 64-bit word from address 8
        // We expect the read word to contain 0x1234_5678 at bytes 7:4.
        // ==============================================================
        test_num = 41;
        $display("\n[Test %0d] SW (Store Word) at offset 4 and LD", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd8,     5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));   // x1 = 8
        load_instr(32'h0000_0004, encode_u(20'h12345, 5'd2, OP_LUI));                         // x2 = 0x1234_5000
        load_instr(32'h0000_0008, encode_i(12'h678,   5'd2, FUNCT3_ADD_SUB, 5'd2, OP_IMM));   // x2 = 0x1234_5678
        load_instr(32'h0000_000C, encode_s(12'd4,     5'd2, 5'd1,           FUNCT3_SW, OP_STORE)); // SW x2, 4(x1) -> addr 12
        load_instr(32'h0000_0010, encode_i(12'd0,     5'd1, FUNCT3_LD,      5'd3, OP_LOAD));  // LD x3, 0(x1) -> read from addr 8
        
        wait_cycles(150);
        check_val("SW word written to dmem", dmem_array[1], 64'h1234_5678_0000_0000);
        check_cdb_result("LD x3 read back stored word", 4, 64'h1234_5678_0000_0000, 50);

        // ==============================================================
        // Test 42: SD (Store Doubleword) and LD (Load Doubleword)
        // Verify standard 64-bit store and load.
        // We write 0xFFFF_FFFF_ABCD_E321 to address 8.
        // ADDI x1, x0, 8 (base addr)
        // LUI x2, 0xABCDE
        // ADDI x2, x2, 0x321
        // SD x2, 0(x1) -> writes 0xFFFF_FFFF_ABCD_E321 to address 8
        // LD x3, 0(x1) -> reads 64-bit word from address 8
        // We expect the read word to contain 0xFFFF_FFFF_ABCD_E321.
        // ==============================================================
        test_num = 42;
        $display("\n[Test %0d] SD (Store Doubleword) and LD", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'd8,     5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));   // x1 = 8
        load_instr(32'h0000_0004, encode_u(20'hABCDE, 5'd2, OP_LUI));                         // x2 = 0xABCDE000 (sign-extended)
        load_instr(32'h0000_0008, encode_i(12'h321,   5'd2, FUNCT3_ADD_SUB, 5'd2, OP_IMM));   // x2 = 0xFFFF_FFFF_ABCD_E321
        load_instr(32'h0000_000C, encode_s(12'd0,     5'd2, 5'd1,           FUNCT3_SD, OP_STORE)); // SD x2, 0(x1) -> addr 8
        load_instr(32'h0000_0010, encode_i(12'd0,     5'd1, FUNCT3_LD,      5'd3, OP_LOAD));  // LD x3, 0(x1) -> read from addr 8
        
        wait_cycles(150);
        check_val("SD doubleword written to dmem", dmem_array[1], 64'hFFFF_FFFF_ABCD_E321);
        check_cdb_result("LD x3 read back stored doubleword", 4, 64'hFFFF_FFFF_ABCD_E321, 50);

        // ==============================================================
        // Test 43: LW (Load Word) at offset 0
        // Verify 32-bit load and sign-extension.
        // We preload dmem[1] (addr 8) with 64'hABCD_EF01_8765_4321.
        // ADDI x1, x0, 8 (base addr)
        // LW x3, 0(x1) -> reads 32-bit word from address 8
        // We expect the word to be sign-extended to 64'hFFFF_FFFF_8765_4321.
        // ==============================================================
        test_num = 43;
        $display("\n[Test %0d] LW (Load Word) at offset 0 with sign-extension", test_num);
        reset_dut();
        load_dmem(32'h0000_0008, 64'hABCD_EF01_8765_4321);
        load_instr(32'h0000_0000, encode_i(12'd8,     5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));   // x1 = 8
        load_instr(32'h0000_0004, encode_i(12'd0,     5'd1, FUNCT3_LW,      5'd3, OP_LOAD));  // LW x3, 0(x1) -> read from addr 8

        wait_cycles(50);
        check_cdb_result("LW x3 sign-extended word", 1, 64'hFFFF_FFFF_8765_4321, 50);

        // ==============================================================
        // Test 44: LW (Load Word) at offset 4
        // Verify 32-bit load from offset 4 and sign-extension.
        // We preload dmem[1] (addr 8) with 64'h8765_4321_ABCD_EF01.
        // ADDI x1, x0, 8 (base addr)
        // LW x3, 4(x1) -> reads 32-bit word from address 12
        // We expect the word to be sign-extended to 64'hFFFF_FFFF_8765_4321.
        // ==============================================================
        test_num = 44;
        $display("\n[Test %0d] LW (Load Word) at offset 4 with sign-extension", test_num);
        reset_dut();
        load_dmem(32'h0000_0008, 64'h8765_4321_ABCD_EF01);
        load_instr(32'h0000_0000, encode_i(12'd8,     5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));   // x1 = 8
        load_instr(32'h0000_0004, encode_i(12'd4,     5'd1, FUNCT3_LW,      5'd3, OP_LOAD));  // LW x3, 4(x1) -> read from addr 12

        wait_cycles(50);
        check_cdb_result("LW x3 sign-extended word from offset 4", 1, 64'hFFFF_FFFF_8765_4321, 50);

        // ==============================================================
        // Test 45: ADDIW (Add Word Immediate)
        // Verify 32-bit addition with immediate and sign-extension.
        // We load preloaded values from memory and perform ADDIW.
        // Preload:
        // - dmem[1] (addr 8)  = 64'h1234_5678_8000_0000
        // - dmem[2] (addr 16) = 64'h1234_5678_FFFF_FFFF
        // Instructions:
        // 0: LD x1, 8(x0)        -> x1 = 64'h1234_5678_8000_0000
        // 4: LD x4, 16(x0)       -> x4 = 64'h1234_5678_FFFF_FFFF
        // 8: ADDIW x2, x1, 3     -> x2 = 64'hFFFF_FFFF_8000_0003 (8000_0000 + 3 = 8000_0003, sign-extended)
        // C: ADDIW x3, x1, -1    -> x3 = 64'h0000_0000_7FFF_FFFF (8000_0000 - 1 = 7FFF_FFFF, sign-extended)
        // 10: ADDIW x5, x4, 1    -> x5 = 64'h0000_0000_0000_0000 (FFFF_FFFF + 1 = 0000_0000, sign-extended)
        // ==============================================================
        test_num = 45;
        $display("\n[Test %0d] ADDIW (Add Word Immediate)", test_num);
        reset_dut();
        load_dmem(32'h0000_0008, 64'h1234_5678_8000_0000);
        load_dmem(32'h0000_0010, 64'h1234_5678_FFFF_FFFF);

        load_instr(32'h0000_0000, encode_i(12'd8,     5'd0, FUNCT3_LD,      5'd1, OP_LOAD));   // LD x1, 8(x0)
        load_instr(32'h0000_0004, encode_i(12'd16,    5'd0, FUNCT3_LD,      5'd4, OP_LOAD));   // LD x4, 16(x0)
        load_instr(32'h0000_0008, encode_i(12'd3,     5'd1, FUNCT3_ADD_SUB, 5'd2, OP_IMM_32)); // ADDIW x2, x1, 3
        load_instr(32'h0000_000C, encode_i(12'hFFF,   5'd1, FUNCT3_ADD_SUB, 5'd3, OP_IMM_32)); // ADDIW x3, x1, -1 (imm = 12'hFFF)
        load_instr(32'h0000_0010, encode_i(12'd1,     5'd4, FUNCT3_ADD_SUB, 5'd5, OP_IMM_32)); // ADDIW x5, x4, 1

        wait_cycles(150);
        check_cdb_result("LD x1 loaded value", 0, 64'h1234_5678_8000_0000, 50);
        check_cdb_result("LD x4 loaded value", 1, 64'h1234_5678_FFFF_FFFF, 50);
        check_cdb_result("ADDIW x2 with positive imm and negative sign bit", 2, 64'hFFFF_FFFF_8000_0003, 50);
        check_cdb_result("ADDIW x3 with negative imm and positive sign bit", 3, 64'h0000_0000_7FFF_FFFF, 50);
        check_cdb_result("ADDIW x5 with positive imm causing overflow", 4, 64'h0000_0000_0000_0000, 50);

        // ==============================================================
        // Test 46: BGE taken — signed comparison
        // ADDI x1, x0, 5 → ADDI x2, x0, -5
        // BGE x1, x2, +16 should skip the wrong-path store
        // ==============================================================
        test_num = 46;
        $display("\n[Test %0d] BGE taken signed compare (5 >= -5)", test_num);
        reset_dut();
        load_dmem(32'h0000_0000, 64'hCAFE_BABE_0000_0000);
        load_dmem(32'h0000_0008, 64'h0);
        load_instr(32'h0000_0000, encode_i(12'd5,   5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));
        load_instr(32'h0000_0004, encode_i(12'hFFB, 5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM)); // x2 = -5
        load_instr(32'h0000_0008, encode_b(13'd16,  5'd2, 5'd1, FUNCT3_BGE, OP_BRANCH));
        load_instr(32'h0000_000C, encode_i(12'd99,  5'd0, FUNCT3_ADD_SUB, 5'd3, OP_IMM));
        load_instr(32'h0000_0010, encode_s(12'd0,   5'd3, 5'd0, FUNCT3_SD, OP_STORE));
        load_instr(32'h0000_0018, encode_i(12'd42,  5'd0, FUNCT3_ADD_SUB, 5'd4, OP_IMM));
        load_instr(32'h0000_001C, encode_s(12'd8,   5'd4, 5'd0, FUNCT3_SD, OP_STORE));

        wait_cycles(120);
        check_val("BGE skipped wrong-path store", dmem_array[0], 64'hCAFE_BABE_0000_0000);
        check_val("BGE reached target store", dmem_array[1], 64'd42);

        // ==============================================================
        // Test 47: BGEU taken — unsigned comparison
        // ADDI x1, x0, -5 → ADDI x2, x0, 5
        // BGEU x1, x2, +16 should skip the wrong-path store
        // ==============================================================
        test_num = 47;
        $display("\n[Test %0d] BGEU taken unsigned compare (0xfff... >= 5)", test_num);
        reset_dut();
        load_dmem(32'h0000_0010, 64'hBADC_0FFE_0000_0010);
        load_dmem(32'h0000_0018, 64'h0);
        load_instr(32'h0000_0000, encode_i(12'hFFB, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM)); // x1 = -5
        load_instr(32'h0000_0004, encode_i(12'd5,   5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM)); // x2 = 5
        load_instr(32'h0000_0008, encode_b(13'd16,  5'd2, 5'd1, FUNCT3_BGEU, OP_BRANCH));
        load_instr(32'h0000_000C, encode_i(12'd77,  5'd0, FUNCT3_ADD_SUB, 5'd3, OP_IMM));
        load_instr(32'h0000_0010, encode_s(12'd16,  5'd3, 5'd0, FUNCT3_SD, OP_STORE));
        load_instr(32'h0000_0018, encode_i(12'd33,  5'd0, FUNCT3_ADD_SUB, 5'd4, OP_IMM));
        load_instr(32'h0000_001C, encode_s(12'd24,  5'd4, 5'd0, FUNCT3_SD, OP_STORE));

        wait_cycles(120);
        check_val("BGEU skipped wrong-path store", dmem_array[2], 64'hBADC_0FFE_0000_0010);
        check_val("BGEU reached target store", dmem_array[3], 64'd33);

        // ==============================================================
        // Test 48: CSRRW — write mscratch, read old value to rd
        // ADDI x1, x0, 0xAB → CSRRW x2, mscratch, x1
        // rd=x2 gets old mscratch (0), mscratch becomes 0xAB
        // ==============================================================
        test_num = 48;
        $display("\n[Test %0d] CSRRW write mscratch, read old value", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'hAB, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));   // x1 = 0xAB
        load_instr(32'h0000_0004, encode_csr(12'h340, 5'd1, FUNCT3_CSRRW, 5'd2));          // CSRRW x2, mscratch, x1
        load_instr(32'h0000_0008, encode_i(12'd1, 5'd0, FUNCT3_ADD_SUB, 5'd3, OP_IMM));    // x3 = 1 (sentinel)

        wait_cycles(80);
        check_val("CSRRW old mscratch in x2", read_arch_reg(5'd2), 64'd0);
        check_val("mscratch updated", read_csr_mscratch(), 64'hAB);
        check_val("Sentinel x3", read_arch_reg(5'd3), 64'd1);

        // ==============================================================
        // Test 49: CSRRS — set bits in mtvec
        // CSRRW x0, mtvec, x0 (clear mtvec) → ADDI x1, x0, 0x100
        // CSRRW x0, mtvec, x1 (mtvec=0x100)
        // ADDI x2, x0, 0x44 → CSRRS x3, mtvec, x2
        // x3 = old mtvec (0x100), mtvec = 0x100 | 0x44 = 0x144
        // ==============================================================
        test_num = 49;
        $display("\n[Test %0d] CSRRS set bits in mtvec", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'h100, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM)); // x1 = 0x100
        load_instr(32'h0000_0004, encode_csr(12'h305, 5'd1, FUNCT3_CSRRW, 5'd0));          // CSRRW x0, mtvec, x1
        load_instr(32'h0000_0008, encode_i(12'h44, 5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));   // x2 = 0x44
        load_instr(32'h0000_000C, encode_csr(12'h305, 5'd2, FUNCT3_CSRRS, 5'd3));          // CSRRS x3, mtvec, x2
        load_instr(32'h0000_0010, encode_i(12'd1, 5'd0, FUNCT3_ADD_SUB, 5'd4, OP_IMM));    // x4 = 1 sentinel

        wait_cycles(120);
        check_val("CSRRS old mtvec in x3", read_arch_reg(5'd3), 64'h100);
        check_val("mtvec after CSRRS", read_csr_mtvec(), 64'h144);
        check_val("Sentinel x4", read_arch_reg(5'd4), 64'd1);

        // ==============================================================
        // Test 50: CSRRC — clear bits in mscratch
        // Set mscratch=0xFF, then CSRRC with mask 0x0F → 0xF0
        // ==============================================================
        test_num = 50;
        $display("\n[Test %0d] CSRRC clear bits in mscratch", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'hFF, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));  // x1 = 0xFF
        load_instr(32'h0000_0004, encode_csr(12'h340, 5'd1, FUNCT3_CSRRW, 5'd0));          // CSRRW x0, mscratch, x1
        load_instr(32'h0000_0008, encode_i(12'h0F, 5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));   // x2 = 0x0F
        load_instr(32'h0000_000C, encode_csr(12'h340, 5'd2, FUNCT3_CSRRC, 5'd3));          // CSRRC x3, mscratch, x2
        load_instr(32'h0000_0010, encode_i(12'd1, 5'd0, FUNCT3_ADD_SUB, 5'd4, OP_IMM));    // sentinel

        wait_cycles(120);
        check_val("CSRRC old mscratch in x3", read_arch_reg(5'd3), 64'hFF);
        check_val("mscratch after CSRRC", read_csr_mscratch(), 64'hF0);

        // ==============================================================
        // Test 51: CSRRWI — immediate write to mscratch
        // CSRRWI x1, mscratch, zimm=0x1F
        // ==============================================================
        test_num = 51;
        $display("\n[Test %0d] CSRRWI immediate write to mscratch", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_csr(12'h340, 5'd31, FUNCT3_CSRRWI, 5'd1));        // CSRRWI x1, mscratch, 0x1F
        load_instr(32'h0000_0004, encode_i(12'd1, 5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));    // sentinel

        wait_cycles(80);
        check_val("CSRRWI old mscratch in x1", read_arch_reg(5'd1), 64'd0);
        check_val("mscratch after CSRRWI", read_csr_mscratch(), 64'h1F);

        // ==============================================================
        // Test 52: ECALL — trap entry
        // Set mtvec=0x100, then ECALL at PC=0x08
        // Verify: PC redirects to 0x100, mepc=0x08, mcause=11
        // ==============================================================
        test_num = 52;
        $display("\n[Test %0d] ECALL trap entry", test_num);
        reset_dut();
        // Set up mtvec to point to handler at 0x100
        load_instr(32'h0000_0000, encode_i(12'h100, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM)); // x1 = 0x100
        load_instr(32'h0000_0004, encode_csr(12'h305, 5'd1, FUNCT3_CSRRW, 5'd0));          // CSRRW x0, mtvec, x1
        load_instr(32'h0000_0008, encode_ecall());                                          // ECALL at PC=0x08
        load_instr(32'h0000_000C, encode_i(12'hDE, 5'd0, FUNCT3_ADD_SUB, 5'd5, OP_IMM));   // should NOT execute
        // Handler at 0x100: ADDI x6, x0, 0x42
        load_instr(32'h0000_0100, encode_i(12'h42, 5'd0, FUNCT3_ADD_SUB, 5'd6, OP_IMM));   // handler: x6=0x42
        load_instr(32'h0000_0104, encode_i(12'd1, 5'd0, FUNCT3_ADD_SUB, 5'd7, OP_IMM));    // sentinel

        wait_cycles(150);
        check_val("mepc saved ECALL PC", read_csr_mepc(), 64'h08);
        check_val("mcause = 11 (M-mode ecall)", read_csr_mcause(), 64'd11);
        check_val("Handler executed (x6=0x42)", read_arch_reg(5'd6), 64'h42);
        check_val("Sentinel at handler (x7=1)", read_arch_reg(5'd7), 64'd1);

        // ==============================================================
        // Test 53: EBREAK — trap entry with mcause=3
        // ==============================================================
        test_num = 53;
        $display("\n[Test %0d] EBREAK trap entry", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'h200, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM)); // x1 = 0x200
        load_instr(32'h0000_0004, encode_csr(12'h305, 5'd1, FUNCT3_CSRRW, 5'd0));          // CSRRW x0, mtvec, x1
        load_instr(32'h0000_0008, encode_ebreak());                                         // EBREAK at PC=0x08
        // Handler at 0x200: ADDI x2, x0, 0x55
        load_instr(32'h0000_0200, encode_i(12'h55, 5'd0, FUNCT3_ADD_SUB, 5'd2, OP_IMM));

        wait_cycles(150);
        check_val("mepc saved EBREAK PC", read_csr_mepc(), 64'h08);
        check_val("mcause = 3 (ebreak)", read_csr_mcause(), 64'd3);
        check_val("Handler executed (x2=0x55)", read_arch_reg(5'd2), 64'h55);

        // ==============================================================
        // Test 54: MRET — return from trap
        // Set mepc=0x20 via CSRRW, then MRET → PC goes to 0x20
        // ==============================================================
        test_num = 54;
        $display("\n[Test %0d] MRET return from trap", test_num);
        reset_dut();
        load_instr(32'h0000_0000, encode_i(12'h20, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM));  // x1 = 0x20
        load_instr(32'h0000_0004, encode_csr(12'h341, 5'd1, FUNCT3_CSRRW, 5'd0));          // CSRRW x0, mepc, x1
        load_instr(32'h0000_0008, encode_mret());                                           // MRET → PC=0x20
        load_instr(32'h0000_000C, encode_i(12'hBB, 5'd0, FUNCT3_ADD_SUB, 5'd5, OP_IMM));   // should NOT execute
        // Target at 0x20: ADDI x3, x0, 0x77
        load_instr(32'h0000_0020, encode_i(12'h77, 5'd0, FUNCT3_ADD_SUB, 5'd3, OP_IMM));
        load_instr(32'h0000_0024, encode_i(12'd1, 5'd0, FUNCT3_ADD_SUB, 5'd4, OP_IMM));    // sentinel

        wait_cycles(150);
        check_val("MRET target executed (x3=0x77)", read_arch_reg(5'd3), 64'h77);
        check_val("MRET sentinel (x4=1)", read_arch_reg(5'd4), 64'd1);

        // ==============================================================
        // Test 55: ECALL + MRET round-trip
        // Set mtvec=0x100, ECALL at 0x08, handler does MRET
        // After MRET, PC returns to 0x0C (instruction after ECALL)
        // ==============================================================
        test_num = 55;
        $display("\n[Test %0d] ECALL + MRET round-trip", test_num);
        reset_dut();
        // Main code
        load_instr(32'h0000_0000, encode_i(12'h100, 5'd0, FUNCT3_ADD_SUB, 5'd1, OP_IMM)); // x1 = 0x100
        load_instr(32'h0000_0004, encode_csr(12'h305, 5'd1, FUNCT3_CSRRW, 5'd0));          // CSRRW x0, mtvec, x1
        load_instr(32'h0000_0008, encode_ecall());                                          // ECALL at PC=0x08
        // Return point at 0x0C: after MRET from handler
        load_instr(32'h0000_000C, encode_i(12'h99, 5'd0, FUNCT3_ADD_SUB, 5'd8, OP_IMM));   // x8 = 0x99
        load_instr(32'h0000_0010, encode_i(12'd1, 5'd0, FUNCT3_ADD_SUB, 5'd9, OP_IMM));    // x9 = 1 sentinel

        // Handler at 0x100: set x6=0x42, then adjust mepc to next instr and MRET
        load_instr(32'h0000_0100, encode_i(12'h42, 5'd0, FUNCT3_ADD_SUB, 5'd6, OP_IMM));   // x6 = 0x42
        // Read mepc into x10, add 4, write back (skip past ECALL)
        load_instr(32'h0000_0104, encode_csr(12'h341, 5'd0, FUNCT3_CSRRS, 5'd10));         // CSRRS x10, mepc, x0 (read mepc)
        load_instr(32'h0000_0108, encode_i(12'd4, 5'd10, FUNCT3_ADD_SUB, 5'd10, OP_IMM));  // x10 = mepc + 4
        load_instr(32'h0000_010C, encode_csr(12'h341, 5'd10, FUNCT3_CSRRW, 5'd0));         // CSRRW x0, mepc, x10
        load_instr(32'h0000_0110, encode_mret());                                           // MRET → PC=0x0C

        wait_cycles(250);
        check_val("Handler ran (x6=0x42)", read_arch_reg(5'd6), 64'h42);
        check_val("Returned from trap (x8=0x99)", read_arch_reg(5'd8), 64'h99);
        check_val("Round-trip sentinel (x9=1)", read_arch_reg(5'd9), 64'd1);

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
