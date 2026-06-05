// Bare-metal C testbench for Tomasulo3CPU with a real L1 D-cache.
//
// This is the cache-integrated twin of CPU_c_suite_tb.sv: instead of the inline
// 1-cycle behavioural dmem read/write `always` blocks, the CPU data-memory port
// is driven by the L1 D-cache from ../L1DCache (dcache_tomasulo_wrap = dcache_top
// + dcache_backing_mem).  The instruction port keeps its behavioural model
// (the I-cache is a separate project).
//
// Run identically to CPU_c_suite (same +IMEM_FILE / +DMEM_FILE / +TOHOST_ADDR /
// +TEST_NAME plusargs and the same imem.hex / dmem.hex artifacts):
//
//   make sim PROJECT=CPU_dcache_c USE_DCACHE=1 \
//     PLUSARGS="+IMEM_FILE=... +DMEM_FILE=... +TOHOST_ADDR=1008 +TEST_NAME=strlen"
//
// Because the cache is write-back, a committed store to `tohost` lives in a
// dirty cache line and may never reach the backing SRAM.  The pass/fail poll
// therefore reads `tohost` through a cache-aware backdoor (peek_qword): resident
// (possibly dirty) line first, backing memory otherwise.

/* verilator lint_off WIDTH */
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module CPU_dcache_c_tb;
    import riscv_opcode_pkg::*;
    import riscv_funct_pkg::*;
    import riscv_types_pkg::*;
    import dcache_pkg::*;

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

    localparam int unsigned IMEM_WORDS  = 16384;
    // Backing-memory words to preload from dmem.hex (covers IMEM+DMEM image).
    localparam int unsigned SEED_WORDS  = 16384;

    logic clk, rst_n;

    // ---- Instruction port (behavioural, unchanged) ----
    logic                    imem_resp_valid;
    logic                    imem_resp_ready;
    logic [INSTR_WIDTH-1:0]  imem_resp_data;
    logic                    imem_req_valid;
    logic [IMEM_DEPTH-1:0]   imem_addr;

    // ---- Data port (CPU <-> L1 D-cache wrapper) ----
    logic                            dcache_rready;       // cache avail   (to CPU)
    logic                            dcache_rresp_valid;  // read resp     (to CPU)
    logic [REG_FILE_DATA_WIDTH-1:0]  dcache_rdata;        // read data     (to CPU)
    logic [DMEM_DEPTH-1:0]           dcache_raddr;        // load addr     (from CPU)
    logic                            dcache_rvalid;       // load request  (from CPU)
    logic                            dcache_rresp_ready;  // resp consumed (from CPU)

    logic                            dcache_wready;       // cache avail   (to CPU)
    logic                            dcache_wresp_valid;  // write resp    (to CPU)
    logic                            dcache_write;        // store qual    (from CPU)
    logic [DMEM_WIDTH-1:0]           dcache_sw_data;      // store data    (from CPU)
    logic [W_BYTE_NUM-1:0]           dcache_wstrb;        // byte strobe   (from CPU)
    logic [DMEM_DEPTH-1:0]           dcache_sw_addr;      // store addr    (from CPU)
    logic                            dcache_wvalid;       // store request (from CPU)
    logic                            dcache_wresp_ready;  // SB drain      (from CPU)

    logic [31:0] dcache_hits;
    logic [31:0] dcache_misses;

    // ---------------------------------------------------------------- DUT
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
        .imem_resp_valid        (imem_resp_valid),
        .imem_resp_data         (imem_resp_data),
        .imem_resp_ready        (imem_resp_ready),
        .imem_req_valid     (imem_req_valid),
        .imem_addr         (imem_addr),
        .dcache_rready     (dcache_rready),
        .dcache_rresp_valid(dcache_rresp_valid),
        .dcache_rdata      (dcache_rdata),
        .dcache_raddr      (dcache_raddr),
        .dcache_rvalid     (dcache_rvalid),
        .dcache_rresp_ready(dcache_rresp_ready),
        .dcache_wready     (dcache_wready),
        .dcache_wresp_valid(dcache_wresp_valid),
        .dcache_write      (dcache_write),
        .dcache_sw_data    (dcache_sw_data),
        .dcache_wstrb      (dcache_wstrb),
        .dcache_sw_addr    (dcache_sw_addr),
        .dcache_wvalid     (dcache_wvalid),
        .dcache_wresp_ready(dcache_wresp_ready)
    );

    // ---------------------------------------------------------------- L1 D-cache
    // Port names mirror the CPU's memory-side expectation, so CPU and wrapper
    // connect 1:1 by name (wrapper input == CPU output and vice versa).
    logic            mem_init_en;
    mem_idx_t        mem_init_idx;
    logic [63:0]     mem_init_data;

    dcache_tomasulo_wrap #(
        .CPU_ADDR_WIDTH (DMEM_DEPTH)
    ) u_dwrap (
        .clk                (clk),
        .rst_n              (rst_n),
        .dcache_rvalid      (dcache_rvalid),
        .dcache_raddr       (dcache_raddr),
        .dcache_rresp_ready (dcache_rresp_ready),
        .dcache_rready      (dcache_rready),
        .dcache_rresp_valid (dcache_rresp_valid),
        .dcache_rdata       (dcache_rdata),
        .dcache_wvalid      (dcache_wvalid),
        .dcache_write       (dcache_write),
        .dcache_sw_addr     (dcache_sw_addr),
        .dcache_sw_data     (dcache_sw_data),
        .dcache_wstrb       (dcache_wstrb),
        .dcache_wresp_ready (dcache_wresp_ready),
        .dcache_wready      (dcache_wready),
        .dcache_wresp_valid (dcache_wresp_valid),
        .mem_init_en        (mem_init_en),
        .mem_init_idx       (mem_init_idx),
        .mem_init_data      (mem_init_data),
        .stat_hits          (dcache_hits),
        .stat_misses        (dcache_misses)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // ---------------------------------------------------------------- IMEM model
    logic [INSTR_WIDTH-1:0] imem_array [IMEM_WORDS];
    logic [63:0]            dmem_seed  [SEED_WORDS];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            imem_resp_valid <= 1'b1;
            imem_resp_data  <= '0;
        end else begin
            if (imem_req_valid)
                imem_resp_valid <= 1'b1;
            else
                imem_resp_valid <= 1'b0;
            if (imem_req_valid && imem_resp_valid)
                imem_resp_data <= imem_array[imem_addr[15:2]];
        end
    end

    // ---------------------------------------------------------------- backdoor
    // Current architectural value of a 64-bit word: resident (possibly dirty)
    // cache line wins, otherwise the backing SRAM.
    function automatic logic [63:0] peek_qword(input logic [63:0] byte_addr);
        cache_set_t  set;
        cache_tag_t  tag;
        word_sel_t   wsel;
        mem_idx_t    midx;
        cache_line_t line;
        logic        found;
        peek_qword = '0;
        set  = byte_addr[OFFSET_BITS +: INDEX_BITS];
        tag  = byte_addr[INDEX_BITS+OFFSET_BITS +: TAG_BITS];
        wsel = byte_addr[BYTE_OFF_BITS +: WORD_SEL_BITS];
        midx = byte_addr[BYTE_OFF_BITS +: MEM_IDX_BITS];
        found = 1'b0;
        for (int w = 0; w < NUM_WAYS; w++) begin
            if (u_dwrap.u_cache.u_core.u_tag.valid_ram[int'(set)][w] &&
                (u_dwrap.u_cache.u_core.u_tag.tag_ram[int'(set)][w] == tag)) begin
                line = u_dwrap.u_cache.u_core.u_data.data_array[int'(set)][w];
                peek_qword = line[int'(wsel)*64 +: 64];
                found = 1'b1;
            end
        end
        if (!found)
            peek_qword = u_dwrap.u_mem.mem[int'(midx)];
    endfunction

    function automatic logic [31:0] read_word_at(input logic [63:0] byte_addr);
        logic [63:0] qword;
        qword = peek_qword(byte_addr);
        case (byte_addr[2:0])
            3'd0: read_word_at = qword[31:0];
            3'd4: read_word_at = qword[63:32];
            default: read_word_at = qword[31:0];
        endcase
    endfunction

    function automatic logic [31:0] nop_instr();
        return 32'h0000_0013;
    endfunction

    task automatic wait_cycles(input int unsigned n);
        repeat (n) @(posedge clk);
        #1;
    endtask

    // Preload the backing SRAM through the dedicated init port (single driver,
    // VCS-safe).  Streams one word per clock while the CPU/cache are in reset.
    task automatic preload_backing(input string dmem_file);
        for (int i = 0; i < SEED_WORDS; i++)
            dmem_seed[i] = '0;
        $readmemh(dmem_file, dmem_seed);
        @(negedge clk);
        for (int i = 0; i < SEED_WORDS; i++) begin
            mem_init_en   = 1'b1;
            mem_init_idx  = mem_idx_t'(i);
            mem_init_data = dmem_seed[i];
            @(negedge clk);
        end
        mem_init_en   = 1'b0;
        mem_init_idx  = '0;
        mem_init_data = '0;
    endtask

    task automatic reset_dut(input string imem_file, input string dmem_file);
        rst_n        = 1'b0;
        mem_init_en  = 1'b0;
        mem_init_idx = '0;
        mem_init_data= '0;
        for (int i = 0; i < IMEM_WORDS; i++)
            imem_array[i] = nop_instr();
        $readmemh(imem_file, imem_array);
        // Stream the data image into the backing SRAM (CPU stays in reset).
        preload_backing(dmem_file);
        repeat (4) @(posedge clk);
        #1;
        rst_n = 1'b1;
    endtask

    // ---------------------------------------------------------------- dump
    initial begin
        `ifdef FSDB_DUMP
            $fsdbDumpfile("CPU_dcache_c.fsdb");
            $fsdbDumpvars("+all");
            $fsdbDumpvars(0, CPU_dcache_c_tb);
            $fsdbDumpMDA();
        `endif
    end

    // ---------------------------------------------------------------- main
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
            test_name = "c_suite_test";

        $display("=======================================");
        $display("  c-suite (L1 D-cache): %s", test_name);
        $display("  IMEM=%s", imem_file);
        $display("  DMEM=%s", dmem_file);
        $display("  tohost=0x%0h", tohost_addr);
        $display("=======================================");

        reset_dut(imem_file, dmem_file);

        finished = 0;
        passed   = 0;
        for (cycles = 0; cycles < 1000000; cycles++) begin
            wait_cycles(1);
            host_val = read_word_at(tohost_addr);
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
            $display("[PASS] c_suite PASS: %s (%0d cycles, tohost=1)", test_name, cycles);
        end else begin
            $error("[FAIL] %s: tohost=0x%0h (expected 1 for pass)", test_name, host_val);
        end
        $display("  dcache: hits=%0d misses=%0d", dcache_hits, dcache_misses);
        $finish;
    end

    initial begin
        #100_000_000;
        $error("TIMEOUT: simulation exceeded 200ms");
        $finish;
    end
endmodule
/* verilator lint_on WIDTH */
/* verilator lint_on BLKSEQ */
