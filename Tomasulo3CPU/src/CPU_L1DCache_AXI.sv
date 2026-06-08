`timescale 1ns/1ps

// Tomasulo CPU + L1 D-cache + L1 I-cache + shared AXI4 SRAM subsystem.
module CPU_L1DCache_AXI #(
    parameter int unsigned INSTR_WIDTH             = 32,
    parameter int unsigned IMEM_DEPTH              = 64,
    parameter int unsigned IMEM_WIDTH              = 128, // Default to 128 (4 instructions)
    parameter int unsigned IMEM_DEPTH_WORD         = IMEM_DEPTH - 1,
    parameter int unsigned XLEN                    = 64,
    parameter int unsigned ARCH_REG_COUNT          = 32,
    parameter int unsigned ARCH_REG_WIDTH          = $clog2(ARCH_REG_COUNT),
    parameter int unsigned REG_FILE_DATA_WIDTH     = 64,
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned DMEM_WIDTH              = 64,
    parameter int unsigned DMEM_DEPTH              = 64,
    parameter int unsigned W_BYTE_NUM              = DMEM_WIDTH / 8,
    parameter int unsigned BPB_PC_BITS             = 3,
    parameter int unsigned NUM_WAYS                = 4,
    parameter int unsigned IFQ_DEPTH               = 16,
    parameter int unsigned RAS_DEPTH               = 4,
    parameter int unsigned FRL_SIZE                = 128,
    parameter int unsigned FRL_PTR_WIDTH           = $clog2(FRL_SIZE),
    parameter int unsigned NUM_CHECKPOINT          = 8,
    parameter int unsigned ROB_DEPTH               = 16,
    parameter int unsigned ROB_INDEX_WIDTH         = $clog2(ROB_DEPTH),
    parameter int unsigned SB_DEPTH                = 4,
    parameter int unsigned SB_INDEX_WIDTH          = $clog2(SB_DEPTH),
    parameter int unsigned ISSUE_QUEUE_DEPTH       = 8,
    parameter int unsigned LSB_DEPTH               = 4,
    parameter int unsigned DIV_CYCLES              = 64,
    parameter int unsigned MUL_CYCLES              = 4,
    parameter int unsigned INT_CYCLES              = 1,
    parameter int unsigned LD_ST_CYCLES            = 1,
    parameter int unsigned OPCODE_WIDTH            = 7,
    parameter int unsigned AXI_ADDR_WIDTH          = axi_pkg::AXI_ADDR_WIDTH,
    parameter int unsigned AXI_DATA_WIDTH          = axi_pkg::AXI_DATA_WIDTH,
    parameter int unsigned AXI_ID_WIDTH            = axi_pkg::AXI_ID_WIDTH,
    parameter int unsigned AXI_SRAM_DEPTH          = dcache_pkg::MEM_DEPTH,
    parameter logic [AXI_ADDR_WIDTH-1:0] ICACHE_AXI_BASE_ADDR = '0
) (
    input  logic                            clk,
    input  logic                            rst_n,

    // Expose ports for testbench observability
    output logic [IMEM_DEPTH-1:0]           imem_addr,
    output logic                            imem_req_valid,
    output logic                            imem_req_ready,
    input  logic [IMEM_WIDTH-1:0]           imem_resp_data,
    input  logic                            imem_resp_valid,
    output logic                            imem_resp_ready,

    input  logic                            axi_mem_init_en,
    input  logic [AXI_ADDR_WIDTH-1:0]       axi_mem_init_word_idx,
    input  logic [AXI_DATA_WIDTH-1:0]       axi_mem_init_data,

    axi_if.slave                            dma_axi, // Unused internally; kept for port compatibility

    output logic [31:0]                     dcache_hits,
    output logic [31:0]                     dcache_misses,
    output logic                            dcache_axi_error,

    output logic                            dcache_rready,
    output logic                            dcache_rresp_valid,
    output logic [REG_FILE_DATA_WIDTH-1:0]  dcache_rdata,
    output logic [DMEM_DEPTH-1:0]           dcache_raddr,
    output logic                            dcache_rvalid,
    output logic                            dcache_rresp_ready,
    output logic                            dcache_wready,
    output logic                            dcache_wresp_valid,
    output logic                            dcache_write,
    output logic [DMEM_WIDTH-1:0]           dcache_sw_data,
    output logic [W_BYTE_NUM-1:0]           dcache_wstrb,
    output logic [DMEM_DEPTH-1:0]           dcache_sw_addr,
    output logic                            dcache_wvalid,
    output logic                            dcache_wresp_ready
);
    import dcache_pkg::*;

    // L1 D-Cache internal memory interfaces
    logic        mem_req;
    logic        mem_we;
    mem_idx_t    mem_idx;
    cache_word_t mem_wdata;
    cache_word_t mem_rdata;
    logic        mem_ack;
    logic        dcache_axi_error_internal;

    // L1 I-Cache internal memory interfaces
    logic        imem_mem_req;
    logic        imem_mem_we;
    icache_pkg::mem_idx_t    imem_mem_idx;
    icache_pkg::mem_word_t   imem_mem_wdata;
    icache_pkg::mem_word_t   imem_mem_rdata;
    logic        imem_mem_ack;
    logic        icache_axi_error_internal;

    // CPU instruction fetch internal interfaces
    logic [IMEM_DEPTH-1:0]   cpu_imem_addr;
    logic                            cpu_imem_req_valid;
    logic                            cpu_imem_req_ready;
    logic [IMEM_WIDTH-1:0]           cpu_imem_resp_data;
    logic                            cpu_imem_resp_valid;
    logic                            cpu_imem_resp_ready;

    // AXI busses
    axi_if #(
        .ADDR_WIDTH (AXI_ADDR_WIDTH),
        .DATA_WIDTH (AXI_DATA_WIDTH),
        .ID_WIDTH   (AXI_ID_WIDTH)
    ) cpu_axi (clk, rst_n);

    axi_if #(
        .ADDR_WIDTH (AXI_ADDR_WIDTH),
        .DATA_WIDTH (AXI_DATA_WIDTH),
        .ID_WIDTH   (AXI_ID_WIDTH)
    ) icache_axi (clk, rst_n);

    // Combine AXI errors into dcache_axi_error output
    assign dcache_axi_error = dcache_axi_error_internal || icache_axi_error_internal;

    // Drive boundary debug ports
    assign imem_addr       = cpu_imem_addr;
    assign imem_req_valid  = cpu_imem_req_valid;
    assign imem_req_ready  = cpu_imem_req_ready;
    assign imem_resp_ready = cpu_imem_resp_ready;

    initial begin
        if (DMEM_WIDTH != WORD_BITS || AXI_DATA_WIDTH != WORD_BITS)
            $fatal(1, "CPU_L1DCache_AXI: CPU, cache, and AXI data widths must match");
        if (DMEM_DEPTH < ADDR_WIDTH)
            $fatal(1, "CPU_L1DCache_AXI: CPU data address width is too narrow");
        if (IMEM_WIDTH == 0 || (IMEM_WIDTH % INSTR_WIDTH) != 0)
            $fatal(1, "CPU_L1DCache_AXI: IMEM_WIDTH must contain a whole number of instructions");
    end

    CPU #(
        .INSTR_WIDTH             (INSTR_WIDTH),
        .IMEM_DEPTH              (IMEM_DEPTH),
        .IMEM_WIDTH              (IMEM_WIDTH),
        .IMEM_DEPTH_WORD         (IMEM_DEPTH_WORD),
        .XLEN                    (XLEN),
        .ARCH_REG_COUNT          (ARCH_REG_COUNT),
        .ARCH_REG_WIDTH          (ARCH_REG_WIDTH),
        .REG_FILE_DATA_WIDTH     (REG_FILE_DATA_WIDTH),
        .PHY_REGISTER_FILE_WIDTH (PHY_REGISTER_FILE_WIDTH),
        .DMEM_WIDTH              (DMEM_WIDTH),
        .DMEM_DEPTH              (DMEM_DEPTH),
        .W_BYTE_NUM              (W_BYTE_NUM),
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
    ) u_cpu (
        .clk                (clk),
        .rst_n              (rst_n),
        .imem_addr          (cpu_imem_addr),
        .imem_req_valid     (cpu_imem_req_valid),
        .imem_req_ready     (cpu_imem_req_ready),
        .imem_resp_data     (cpu_imem_resp_data),
        .imem_resp_valid    (cpu_imem_resp_valid),
        .imem_resp_ready    (cpu_imem_resp_ready),
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

    dcache_top u_dcache (
        .clk         (clk),
        .rst_n       (rst_n),
        .rvalid      (dcache_rvalid),
        .rready      (dcache_rready),
        .raddr       (dcache_raddr[ADDR_WIDTH-1:0]),
        .rresp_valid (dcache_rresp_valid),
        .rresp_ready (dcache_rresp_ready),
        .rdata       (dcache_rdata),
        .wvalid      (dcache_wvalid),
        .wready      (dcache_wready),
        .waddr       (dcache_sw_addr[ADDR_WIDTH-1:0]),
        .wdata       (dcache_sw_data),
        .wstrb       (dcache_wstrb),
        .wresp_valid (dcache_wresp_valid),
        .wresp_ready (dcache_wresp_ready),
        .mem_req     (mem_req),
        .mem_we      (mem_we),
        .mem_idx     (mem_idx),
        .mem_wdata   (mem_wdata),
        .mem_rdata   (mem_rdata),
        .mem_ack     (mem_ack),
        .stat_hits   (dcache_hits),
        .stat_misses (dcache_misses)
    );

    dcache_axi_master_bridge #(
        .MEM_IDX_WIDTH (MEM_IDX_BITS),
        .ADDR_WIDTH    (AXI_ADDR_WIDTH),
        .DATA_WIDTH    (AXI_DATA_WIDTH),
        .ID_WIDTH      (AXI_ID_WIDTH),
        .AXI_ID        (0)
    ) u_dcache_axi_bridge (
        .clk          (clk),
        .rst_n        (rst_n),
        .mem_req      (mem_req),
        .mem_we       (mem_we),
        .mem_idx      (mem_idx),
        .mem_wdata    (mem_wdata),
        .mem_rdata    (mem_rdata),
        .mem_ack      (mem_ack),
        .error_sticky (dcache_axi_error_internal),
        .axi          (cpu_axi)
    );

    icache_top #(
        .FETCH_INSTR_NUM (IMEM_WIDTH / INSTR_WIDTH)
    ) u_icache (
        .clk             (clk),
        .rst_n           (rst_n),
        .req_valid       (cpu_imem_req_valid),
        .req_ready       (cpu_imem_req_ready),
        .req_addr        (cpu_imem_addr[31:0]),
        .resp_valid      (cpu_imem_resp_valid),
        .resp_ready      (cpu_imem_resp_ready),
        .resp_data       (cpu_imem_resp_data),
        .resp_valid_mask (),
        .inv_all         (1'b0), // Tying off fence.i hook for now
        .mem_req         (imem_mem_req),
        .mem_we          (imem_mem_we),
        .mem_idx         (imem_mem_idx),
        .mem_wdata       (imem_mem_wdata),
        .mem_rdata       (imem_mem_rdata),
        .mem_ack         (imem_mem_ack),
        .stat_hits       (),
        .stat_misses     ()
    );

    icache_axi_master_bridge #(
        .MEM_IDX_WIDTH (icache_pkg::MEM_IDX_BITS),
        .ADDR_WIDTH    (AXI_ADDR_WIDTH),
        .DATA_WIDTH    (AXI_DATA_WIDTH),
        .ID_WIDTH      (AXI_ID_WIDTH),
        .AXI_ID        (1), // Separate AXI ID
        .BASE_ADDR     (ICACHE_AXI_BASE_ADDR)
    ) u_icache_axi_bridge (
        .clk          (clk),
        .rst_n        (rst_n),
        .mem_req      (imem_mem_req),
        .mem_we       (imem_mem_we),
        .mem_idx      (imem_mem_idx),
        .mem_wdata    (imem_mem_wdata),
        .mem_rdata    (imem_mem_rdata),
        .mem_ack      (imem_mem_ack),
        .error_sticky (icache_axi_error_internal),
        .axi          (icache_axi)
    );

    axi_full_soc_top #(
        .ADDR_WIDTH (AXI_ADDR_WIDTH),
        .DATA_WIDTH (AXI_DATA_WIDTH),
        .ID_WIDTH   (AXI_ID_WIDTH),
        .SRAM_DEPTH (AXI_SRAM_DEPTH)
    ) u_mem_subsystem (
        .clk                (clk),
        .rst_n              (rst_n),
        .sram_init_en       (axi_mem_init_en),
        .sram_init_word_idx (axi_mem_init_word_idx),
        .sram_init_data     (axi_mem_init_data),
        .m0                 (cpu_axi),
        .m1                 (icache_axi) // Connect I-Cache AXI instead of DMA AXI
    );

endmodule
