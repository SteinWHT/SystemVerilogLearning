// Bare-metal whole-system testbench:
// Tomasulo CPU -> L1 D-cache -> AXI4 bridge -> 2x1 AXI fabric -> AXI SRAM.
//
// The second AXI master is tied idle and is reserved for a future DMA.

/* verilator lint_off WIDTH */
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module CPU_dcache_axi_tb;
    import dcache_pkg::*;

    localparam int unsigned INSTR_WIDTH = 32;
    localparam int unsigned IMEM_DEPTH  = 64;
    localparam int unsigned DMEM_DEPTH  = 64;
    localparam int unsigned DMEM_WIDTH  = 64;
    localparam int unsigned AXI_ADDR_WIDTH = 32;
    localparam int unsigned AXI_DATA_WIDTH = 64;
    localparam int unsigned AXI_ID_WIDTH   = 4;
    localparam int unsigned IMEM_WORDS     = 16384;
    localparam int unsigned SEED_WORDS     = 16384;

    logic clk;
    logic rst_n;

    logic [IMEM_DEPTH-1:0]  imem_addr;
    logic                   imem_req_valid;
    logic                   imem_req_ready;
    logic [127:0]           imem_resp_data;
    logic                   imem_resp_valid;
    logic                   imem_resp_ready;

    logic [31:0] dcache_hits;
    logic [31:0] dcache_misses;
    logic        dcache_axi_error;

    logic                      axi_mem_init_en;
    logic [AXI_ADDR_WIDTH-1:0] axi_mem_init_word_idx;
    logic [AXI_DATA_WIDTH-1:0] axi_mem_init_data;

    logic                   dcache_rready;
    logic                   dcache_rresp_valid;
    logic [DMEM_WIDTH-1:0]  dcache_rdata;
    logic [DMEM_DEPTH-1:0]  dcache_raddr;
    logic                   dcache_rvalid;
    logic                   dcache_rresp_ready;
    logic                   dcache_wready;
    logic                   dcache_wresp_valid;
    logic                   dcache_write;
    logic [DMEM_WIDTH-1:0]  dcache_sw_data;
    logic [7:0]             dcache_wstrb;
    logic [DMEM_DEPTH-1:0]  dcache_sw_addr;
    logic                   dcache_wvalid;
    logic                   dcache_wresp_ready;

    axi_if #(
        .ADDR_WIDTH (AXI_ADDR_WIDTH),
        .DATA_WIDTH (AXI_DATA_WIDTH),
        .ID_WIDTH   (AXI_ID_WIDTH)
    ) dma_axi (clk, rst_n);

    CPU_L1DCache_AXI #(
        .INSTR_WIDTH      (INSTR_WIDTH),
        .IMEM_DEPTH       (IMEM_DEPTH),
        .DMEM_DEPTH       (DMEM_DEPTH),
        .DMEM_WIDTH       (DMEM_WIDTH),
        .ISSUE_QUEUE_DEPTH(16),
        .AXI_ADDR_WIDTH   (AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH   (AXI_DATA_WIDTH),
        .AXI_ID_WIDTH     (AXI_ID_WIDTH)
    ) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .imem_addr          (imem_addr),
        .imem_req_valid     (imem_req_valid),
        .imem_req_ready     (imem_req_ready),
        .imem_resp_data     (imem_resp_data),
        .imem_resp_valid    (imem_resp_valid),
        .imem_resp_ready    (imem_resp_ready),
        .axi_mem_init_en    (axi_mem_init_en),
        .axi_mem_init_word_idx(axi_mem_init_word_idx),
        .axi_mem_init_data  (axi_mem_init_data),
        .dma_axi            (dma_axi),
        .dcache_hits        (dcache_hits),
        .dcache_misses      (dcache_misses),
        .dcache_axi_error   (dcache_axi_error),
        .dcache_rready      (dcache_rready),
        .dcache_rresp_valid (dcache_rresp_valid),
        .dcache_rdata       (dcache_rdata),
        .dcache_raddr       (dcache_raddr),
        .dcache_rvalid      (dcache_rvalid),
        .dcache_rresp_ready (dcache_rresp_ready),
        .dcache_wready      (dcache_wready),
        .dcache_wresp_valid (dcache_wresp_valid),
        .dcache_write       (dcache_write),
        .dcache_sw_data     (dcache_sw_data),
        .dcache_wstrb       (dcache_wstrb),
        .dcache_sw_addr     (dcache_sw_addr),
        .dcache_wvalid      (dcache_wvalid),
        .dcache_wresp_ready (dcache_wresp_ready)
    );

    assign dma_axi.awid     = '0;
    assign dma_axi.awaddr   = '0;
    assign dma_axi.awlen    = '0;
    assign dma_axi.awsize   = 3'd3;
    assign dma_axi.awburst  = axi_pkg::AXI_BURST_INCR;
    assign dma_axi.awlock   = 1'b0;
    assign dma_axi.awcache  = '0;
    assign dma_axi.awprot   = '0;
    assign dma_axi.awqos    = '0;
    assign dma_axi.awregion = '0;
    assign dma_axi.awvalid  = 1'b0;
    assign dma_axi.wdata    = '0;
    assign dma_axi.wstrb    = '0;
    assign dma_axi.wlast    = 1'b0;
    assign dma_axi.wvalid   = 1'b0;
    assign dma_axi.bready   = 1'b1;
    assign dma_axi.arid     = '0;
    assign dma_axi.araddr   = '0;
    assign dma_axi.arlen    = '0;
    assign dma_axi.arsize   = 3'd3;
    assign dma_axi.arburst  = axi_pkg::AXI_BURST_INCR;
    assign dma_axi.arlock   = 1'b0;
    assign dma_axi.arcache  = '0;
    assign dma_axi.arprot   = '0;
    assign dma_axi.arqos    = '0;
    assign dma_axi.arregion = '0;
    assign dma_axi.arvalid  = 1'b0;
    assign dma_axi.rready   = 1'b1;

    initial clk = 1'b0;
    always #5 clk = ~clk;

    logic [INSTR_WIDTH-1:0] imem_array [IMEM_WORDS];
    logic [63:0]            dmem_seed [SEED_WORDS];

    // Instruction memory emulation is removed since CPU fetches directly from AXI SRAM via L1 I-Cache.
    assign imem_resp_valid = 1'b0;
    assign imem_resp_data  = '0;

    function automatic logic [63:0] peek_qword(input logic [63:0] byte_addr);
        cache_set_t  set;
        cache_tag_t  tag;
        word_sel_t   wsel;
        mem_idx_t    midx;
        cache_line_t line;
        logic        found;

        peek_qword = '0;
        set   = byte_addr[OFFSET_BITS +: INDEX_BITS];
        tag   = byte_addr[INDEX_BITS+OFFSET_BITS +: TAG_BITS];
        wsel  = byte_addr[BYTE_OFF_BITS +: WORD_SEL_BITS];
        midx  = byte_addr[BYTE_OFF_BITS +: MEM_IDX_BITS];
        found = 1'b0;
        for (int w = 0; w < NUM_WAYS; w++) begin
            if (dut.u_dcache.u_core.u_tag.valid_ram[int'(set)][w] &&
                dut.u_dcache.u_core.u_tag.tag_ram[int'(set)][w] == tag) begin
                line = dut.u_dcache.u_core.u_data.data_array[int'(set)][w];
                peek_qword = line[int'(wsel)*64 +: 64];
                found = 1'b1;
            end
        end
        if (!found)
            peek_qword = dut.u_mem_subsystem.u_sram.mem[int'(midx)];
    endfunction

    function automatic logic [31:0] read_word_at(input logic [63:0] byte_addr);
        logic [63:0] qword;
        qword = peek_qword(byte_addr);
        return byte_addr[2] ? qword[63:32] : qword[31:0];
    endfunction

    function automatic logic [31:0] nop_instr();
        return 32'h0000_0013;
    endfunction

    task automatic reset_dut(input string imem_file, input string dmem_file);
        rst_n = 1'b0;
        axi_mem_init_en       = 1'b0;
        axi_mem_init_word_idx = '0;
        axi_mem_init_data     = '0;
        for (int i = 0; i < IMEM_WORDS; i++)
            imem_array[i] = nop_instr();
        for (int i = 0; i < SEED_WORDS; i++)
            dmem_seed[i] = '0;
        $readmemh(imem_file, imem_array);
        $readmemh(dmem_file, dmem_seed);

        // Copy instructions into the data seed memory (each 64-bit word holds 2 instructions)
        // Only copy the first 128 instructions to avoid overlapping data at 0x200 (word index 64)
        for (int i = 0; i < 128; i += 2) begin
            dmem_seed[i/2][31:0]  = imem_array[i];
            dmem_seed[i/2][63:32] = imem_array[i+1];
        end

        @(negedge clk);
        for (int i = 0; i < SEED_WORDS; i++) begin
            axi_mem_init_en       = 1'b1;
            axi_mem_init_word_idx = AXI_ADDR_WIDTH'(i);
            axi_mem_init_data     = dmem_seed[i];
            @(negedge clk);
        end
        axi_mem_init_en       = 1'b0;
        axi_mem_init_word_idx = '0;
        axi_mem_init_data     = '0;
        repeat (4) @(posedge clk);
        #1;
        rst_n = 1'b1;
    endtask

    initial begin
        `ifdef FSDB_DUMP
            $fsdbDumpfile("CPU_dcache_axi.fsdb");
            $fsdbDumpvars("+all");
            $fsdbDumpvars(0, CPU_dcache_axi_tb);
            $fsdbDumpMDA();
        `endif
    end

    initial begin
        string imem_file;
        string dmem_file;
        string test_name;
        logic [63:0] tohost_addr;
        logic [31:0] host_val;
        int cycles;
        int max_cycles;
        bit finished;
        bit passed;

        if (!$value$plusargs("IMEM_FILE=%s", imem_file))
            $fatal(1, "Missing +IMEM_FILE=");
        if (!$value$plusargs("DMEM_FILE=%s", dmem_file))
            $fatal(1, "Missing +DMEM_FILE=");
        if (!$value$plusargs("TOHOST_ADDR=%h", tohost_addr))
            $fatal(1, "Missing +TOHOST_ADDR=");
        if (!$value$plusargs("TEST_NAME=%s", test_name))
            test_name = "c_suite_axi";
        if (!$value$plusargs("MAX_CYCLES=%d", max_cycles))
            max_cycles = 5_000_000;

        $display("=======================================");
        $display("  CPU + L1 D-cache + AXI4: %s", test_name);
        $display("=======================================");

        reset_dut(imem_file, dmem_file);

        finished = 1'b0;
        passed   = 1'b0;
        for (cycles = 0; cycles < max_cycles; cycles++) begin
            @(posedge clk);
            #1;
            host_val = read_word_at(tohost_addr);
            if (host_val != 32'd0) begin
                finished = 1'b1;
                passed   = (host_val == 32'd1);
                break;
            end
        end

        if (!finished) begin
            $display("  dcache: hits=%0d misses=%0d axi_error=%0b",
                     dcache_hits, dcache_misses, dcache_axi_error);
            $fatal(1, "[FAIL] %s: timeout waiting for tohost", test_name);
        end
        if (!passed)
            $fatal(1, "[FAIL] %s: tohost=0x%0h", test_name, host_val);
        if (dcache_axi_error)
            $fatal(1, "[FAIL] AXI bridge observed a protocol/error response");

        $display("[PASS] %s (%0d cycles)", test_name, cycles);
        $display("  dcache: hits=%0d misses=%0d", dcache_hits, dcache_misses);
        $finish;
    end

    initial begin
        #150_000_000;
        $fatal(1, "TIMEOUT: CPU_dcache_axi_tb");
    end

endmodule
/* verilator lint_on WIDTH */
/* verilator lint_on BLKSEQ */
