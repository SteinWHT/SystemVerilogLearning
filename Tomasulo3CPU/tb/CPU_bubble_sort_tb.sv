/* verilator lint_off WIDTH */
// verilog_lint: waive-start explicit-parameter-storage-type
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module CPU_bubble_sort_tb;
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
    logic [W_BYTE_NUM-1:0] dmem_valid;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dcache_wresp_valid <= 1'b0;
        end else begin
            if (dcache_wready && dcache_wvalid) begin
                logic [REG_FILE_DATA_WIDTH-1:0] temp_data;
                temp_data = dmem_array[dcache_sw_addr[DMEM_DEPTH-1:3]];
                for (int i = 0; i < W_BYTE_NUM; i++) begin
                    if (dcache_wstrb[i]) begin
                        temp_data[i*8 +: 8] = dcache_sw_data[i*8 +: 8];
                    end
                end
                dmem_array[dcache_sw_addr[DMEM_DEPTH-1:3]] <= temp_data;
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

    task automatic wait_cycles(input int unsigned n);
        repeat (n) @(posedge clk);
        #1;
    endtask

    function automatic bit try_readmemh(input string path, output string final_path);
        int fd;
        fd = $fopen(path, "r");
        if (fd != 0) begin
            $fclose(fd);
            final_path = path;
            return 1'b1;
        end
        return 1'b0;
    endfunction

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
        string imem_file;
        string dmem_file;
        `ifdef FSDB_DUMP
            $fsdbDumpfile("CPU_bubble_sort.fsdb");
            $fsdbDumpvars("+all");
            $fsdbDumpvars(0, CPU_bubble_sort_tb);
            $fsdbDumpMDA();
        `else
            $dumpfile("CPU_bubble_sort.vcd");
            $dumpvars(0, CPU_bubble_sort_tb);
        `endif

        $display("=======================================");
        $display("  CPU Bubble Sort Testbench Start");
        $display("=======================================");

        test_num = 1;
        $display("\n[Test %0d] Preload and Run Bubble Sort", test_num);
        reset_dut();

        // Try to locate imem file
        if ($value$plusargs("IMEM_FILE=%s", imem_file)) begin
            $display("  Using IMEM_FILE from plusarg: %s", imem_file);
        end else if (try_readmemh("../../cprogram/bubble_sort_imem.hex", imem_file)) begin
            // Found
        end else if (try_readmemh("../cprogram/bubble_sort_imem.hex", imem_file)) begin
            // Found
        end else if (try_readmemh("cprogram/bubble_sort_imem.hex", imem_file)) begin
            // Found
        end else begin
            $error("  [ERROR] Cannot find bubble_sort_imem.hex!");
            $finish;
        end

        // Try to locate dmem file
        if ($value$plusargs("DMEM_FILE=%s", dmem_file)) begin
            $display("  Using DMEM_FILE from plusarg: %s", dmem_file);
        end else if (try_readmemh("../../cprogram/bubble_sort_dmem.hex", dmem_file)) begin
            // Found
        end else if (try_readmemh("../cprogram/bubble_sort_dmem.hex", dmem_file)) begin
            // Found
        end else if (try_readmemh("cprogram/bubble_sort_dmem.hex", dmem_file)) begin
            // Found
        end else begin
            $error("  [ERROR] Cannot find bubble_sort_dmem.hex!");
            $finish;
        end

        // Preload instruction memory and data memory
        $readmemh(imem_file, imem_array);
        $readmemh(dmem_file, dmem_array);

        $display("  Preloaded imem and dmem. Starting simulation...");

        begin
            int cycles = 0;
            bit success = 0;
            while (cycles < 15000) begin
                wait_cycles(1);
                cycles++;
                // Poll the completion flag at memory address 0x200 (index 64)
                if (dmem_array[64][31:0] == 32'd1) begin
                    $display("  Bubble sort completed in %0d cycles!", cycles);
                    success = 1;
                    break;
                end
            end

            check_bit("Bubble sort completion flag written to 0x200", success, 1'b1);

            // Verify the array is sorted [1, 2, 3, 4, 5, 6, 7, 8]
            // At index 122 (0x7A): low=1, high=2 -> 64'h00000002_00000001
            // At index 123 (0x7B): low=3, high=4 -> 64'h00000004_00000003
            // At index 124 (0x7C): low=5, high=6 -> 64'h00000006_00000005
            // At index 125 (0x7D): low=7, high=8 -> 64'h00000008_00000007
            check_val("arr[0] and arr[1]", dmem_array[122], 64'h00000002_00000001);
            check_val("arr[2] and arr[3]", dmem_array[123], 64'h00000004_00000003);
            check_val("arr[4] and arr[5]", dmem_array[124], 64'h00000006_00000005);
            check_val("arr[6] and arr[7]", dmem_array[125], 64'h00000008_00000007);
        end

        // ==============================================================
        // Summary
        // ==============================================================
        $display("\n=======================================");
        $display("  CPU Bubble Sort Testbench Done");
        $display("  %0d passed, %0d failed", pass_cnt, fail_cnt);
        $display("=======================================");

        if (fail_cnt == 0) begin
            $display("[PASS] CPU_bubble_sort_tb completed successfully");
        end else begin
            $display("[RESULT] CPU_bubble_sort_tb found %0d failure(s) — review needed", fail_cnt);
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
