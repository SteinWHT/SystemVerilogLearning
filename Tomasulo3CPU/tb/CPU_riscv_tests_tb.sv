/* verilator lint_off WIDTH */
// verilog_lint: waive-start explicit-parameter-storage-type
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

// Run one prebuilt riscv-tests ELF image (see arch_test/README.md).
// Plusargs:
//   +IMEM_FILE=<path>     instruction preload (hex)
//   +DMEM_FILE=<path>     data memory preload (hex)
//   +TOHOST_ADDR=0xNNN    byte address of tohost symbol
//   +TEST_NAME=<name>     printed in log
module CPU_riscv_tests_tb;
    import riscv_opcode_pkg::*;
    import riscv_funct_pkg::*;
    import riscv_types_pkg::*;

    parameter int unsigned INSTR_WIDTH             = 32;
    parameter int unsigned IMEM_DEPTH              = 64;
    parameter int unsigned IMEM_WIDTH              = 32;
    parameter int unsigned IMEM_DEPTH_WORD         = IMEM_DEPTH - 1;
    parameter int unsigned ARCH_REG_COUNT          = 32;
    parameter int unsigned ARCH_REG_WIDTH          = $clog2(ARCH_REG_COUNT);
    parameter int unsigned REG_FILE_DATA_WIDTH     = 64;
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7;
    parameter int unsigned DMEM_WIDTH              = 64;
    parameter int unsigned DMEM_DEPTH              = 64;
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
    parameter int unsigned DIV_CYCLES              = 64;
    parameter int unsigned MUL_CYCLES              = 4;
    parameter int unsigned INT_CYCLES              = 1;
    parameter int unsigned LD_ST_CYCLES            = 1;
    parameter int unsigned OPCODE_WIDTH            = 7;
    parameter int unsigned W_BYTE_NUM              = DMEM_WIDTH / 8;

    // Preload capacity for riscv-tests linked at 0x0 (must cover tohost + code)
    localparam int unsigned IMEM_WORDS = 16384;
    localparam int unsigned DMEM_QWORDS = 8192;
    localparam int unsigned MEM_ADDR_BITS = 16;

    logic clk, rst_n;

    logic                    imem_valid;
    logic [INSTR_WIDTH-1:0]  imem_data;
    logic                    imem_read_rdy;
    logic [IMEM_DEPTH-1:0]   imem_addr;

    logic                            dcache_rvalid;
    logic                            dcache_rresp_valid;
    logic [REG_FILE_DATA_WIDTH-1:0]  dcache_rdata;
    logic [DMEM_DEPTH-1:0]           dcache_raddr;
    logic                            dcache_rready;
    logic                            dcache_rresp_ready;

    logic                            dcache_wvalid;
    logic                            dcache_wresp_valid;
    logic                            dcache_write;
    logic [DMEM_WIDTH-1:0]           dcache_sw_data;
    logic [W_BYTE_NUM-1:0]           dcache_wstrb;
    logic [DMEM_DEPTH-1:0]           dcache_sw_addr;
    logic                            dcache_wready;
    logic                            dcache_wresp_ready;

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

    initial clk = 1'b0;
    always #5 clk = ~clk;

    logic [INSTR_WIDTH-1:0] imem_array [IMEM_WORDS];
    logic [REG_FILE_DATA_WIDTH-1:0] dmem_array [DMEM_QWORDS];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            imem_valid <= 1'b1;
            imem_data  <= '0;
        end else begin
            if (imem_read_rdy) begin
                imem_valid <= 1'b1;
            end else
                imem_valid <= 1'b0;

            if (imem_read_rdy && imem_valid) begin
                imem_data  <= imem_array[imem_addr[15:2]];
            end
        end
    end

    assign dcache_rvalid = rst_n;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dcache_rresp_valid <= 1'b0;
            dcache_rdata       <= '0;
        end else begin
            if (dcache_rready && dcache_rvalid) begin
                dcache_rresp_valid <= 1'b1;
                dcache_rdata       <= dmem_array[dcache_raddr[15:3]];
            end else if (dcache_rresp_valid && dcache_rresp_ready) begin
                dcache_rresp_valid <= 1'b0;
            end
        end
    end

    assign dcache_wvalid = rst_n;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dcache_wresp_valid <= 1'b0;
        end else begin
            if (dcache_wready && dcache_wvalid) begin
                logic [REG_FILE_DATA_WIDTH-1:0] temp_data;
                temp_data = dmem_array[dcache_sw_addr[15:3]];
                for (int i = 0; i < W_BYTE_NUM; i++) begin
                    if (dcache_wstrb[i]) begin
                        temp_data[i*8 +: 8] = dcache_sw_data[i*8 +: 8];
                    end
                end
                dmem_array[dcache_sw_addr[15:3]] <= temp_data;
                dcache_wresp_valid <= 1'b1;
            end else begin
                dcache_wresp_valid <= 1'b0;
            end
        end
    end

    function automatic logic [31:0] nop_instr();
        return 32'h0000_0013;
    endfunction

    task automatic reset_dut();
        rst_n = 1'b0;
        for (int i = 0; i < IMEM_WORDS; i++)
            imem_array[i] = nop_instr();
        for (int i = 0; i < DMEM_QWORDS; i++)
            dmem_array[i] = '0;
        repeat (3) @(posedge clk);
        #1;
        rst_n = 1'b1;
    endtask

    task automatic wait_cycles(input int unsigned n);
        repeat (n) @(posedge clk);
        #1;
    endtask

    function automatic logic [31:0] read_tohost_word(
        input logic [REG_FILE_DATA_WIDTH-1:0] byte_addr
    );
        logic [REG_FILE_DATA_WIDTH-1:0] qword;
        qword = dmem_array[byte_addr[15:3]];
        case (byte_addr[2:0])
            3'd0: read_tohost_word = qword[31:0];
            3'd4: read_tohost_word = qword[63:32];
            default: read_tohost_word = qword[31:0];
        endcase
    endfunction

    initial begin
`ifdef FSDB_DUMP
        $fsdbDumpfile("CPU_riscv_tests.fsdb");
        $fsdbDumpvars("+all");
        $fsdbDumpvars(0, CPU_riscv_tests_tb);
        $fsdbDumpMDA();
`endif
    end

    initial begin
        string imem_file;
        string dmem_file;
        string test_name;
        logic [63:0] tohost_addr;
        int cycles;
        logic [31:0] host_val;
        bit finished;
        bit passed;

        if (!$value$plusargs("IMEM_FILE=%s", imem_file)) begin
            $error("Missing +IMEM_FILE=");
            $finish;
        end
        if (!$value$plusargs("DMEM_FILE=%s", dmem_file)) begin
            $error("Missing +DMEM_FILE=");
            $finish;
        end
        if (!$value$plusargs("TOHOST_ADDR=%h", tohost_addr)) begin
            $error("Missing +TOHOST_ADDR=");
            $finish;
        end
        if (!$value$plusargs("TEST_NAME=%s", test_name))
            test_name = "riscv_test";

        $display("=======================================");
        $display("  riscv-tests: %s", test_name);
        $display("  IMEM=%s", imem_file);
        $display("  DMEM=%s", dmem_file);
        $display("  tohost=0x%0h", tohost_addr);
        $display("=======================================");

        reset_dut();
        $readmemh(imem_file, imem_array);
        $readmemh(dmem_file, dmem_array);

        finished = 0;
        passed   = 0;
        for (cycles = 0; cycles < 500000; cycles++) begin
            wait_cycles(1);
            host_val = read_tohost_word(tohost_addr);
            if (host_val != 32'd0) begin
                finished = 1;
                if (host_val == 32'd1)
                    passed = 1;
                break;
            end
        end

        if (!finished) begin
            $error("[FAIL] %s: timeout waiting for tohost write", test_name);
        end else if (passed) begin
            $display("[PASS] riscv_test PASS: %s (%0d cycles, tohost=1)", test_name, cycles);
        end else begin
            $error("[FAIL] %s: tohost=0x%0h (expected 1 for pass)", test_name, host_val);
        end

        $finish;
    end

    initial begin
        #50_000_000;
        $error("TIMEOUT: simulation exceeded 50ms");
        $finish;
    end

endmodule
/* verilator lint_on WIDTH */
/* verilator lint_on BLKSEQ */
// verilog_lint: waive-stop explicit-parameter-storage-type
