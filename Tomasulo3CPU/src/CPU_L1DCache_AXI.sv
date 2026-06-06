`timescale 1ns/1ps

// Tomasulo CPU + L1 D-cache + shared AXI4 SRAM subsystem.
//
// dma_axi is the second upstream master slot. It can be tied idle today and
// connected to a DMA AXI master later without changing the CPU/cache path.
module CPU_L1DCache_AXI #(
    parameter int unsigned INSTR_WIDTH             = 32,
    parameter int unsigned IMEM_DEPTH              = 64,
    parameter int unsigned IMEM_WIDTH              = 32,
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
    parameter int unsigned AXI_SRAM_DEPTH          = dcache_pkg::MEM_DEPTH
) (
    input  logic                            clk,
    input  logic                            rst_n,

    output logic [IMEM_DEPTH-1:0]           imem_addr,
    output logic                            imem_req_valid,
    input  logic [INSTR_WIDTH-1:0]          imem_resp_data,
    input  logic                            imem_resp_valid,
    output logic                            imem_resp_ready,

    input  logic                            axi_mem_init_en,
    input  logic [AXI_ADDR_WIDTH-1:0]       axi_mem_init_word_idx,
    input  logic [AXI_DATA_WIDTH-1:0]       axi_mem_init_data,

    axi_if.slave                            dma_axi,

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

    logic        mem_req;
    logic        mem_we;
    mem_idx_t    mem_idx;
    cache_word_t mem_wdata;
    cache_word_t mem_rdata;
    logic        mem_ack;

    axi_if #(
        .ADDR_WIDTH (AXI_ADDR_WIDTH),
        .DATA_WIDTH (AXI_DATA_WIDTH),
        .ID_WIDTH   (AXI_ID_WIDTH)
    ) cpu_axi (clk, rst_n);

    initial begin
        if (DMEM_WIDTH != WORD_BITS || AXI_DATA_WIDTH != WORD_BITS)
            $fatal(1, "CPU_L1DCache_AXI: CPU, cache, and AXI data widths must match");
        if (DMEM_DEPTH < ADDR_WIDTH)
            $fatal(1, "CPU_L1DCache_AXI: CPU data address width is too narrow");
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
        .imem_addr          (imem_addr),
        .imem_req_valid     (imem_req_valid),
        .imem_resp_data     (imem_resp_data),
        .imem_resp_valid    (imem_resp_valid),
        .imem_resp_ready    (imem_resp_ready),
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
        .error_sticky (dcache_axi_error),
        .axi          (cpu_axi)
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
        .m1                 (dma_axi)
    );

endmodule
