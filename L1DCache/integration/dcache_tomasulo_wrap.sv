// Phase 4 shim: maps Tomasulo CPU dcache_* ports to dcache_top + backing SRAM.
// Instantiate this in Tomasulo3CPU testbenches instead of inline dmem read/write logic.

module dcache_tomasulo_wrap #(
    parameter int unsigned ADDR_WIDTH = dcache_pkg::ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH = dcache_pkg::WORD_BITS
) (
    input  logic                          clk,
    input  logic                          rst_n,

    // Tomasulo CPU load port
    input  logic                          dcache_rvalid,
    output logic                          dcache_rready,
    input  logic [ADDR_WIDTH-1:0]         dcache_raddr,
    output logic                          dcache_rresp_valid,
    input  logic                          dcache_rresp_ready,
    output logic [DATA_WIDTH-1:0]         dcache_rdata,

    // Tomasulo CPU store port
    input  logic                          dcache_wvalid,
    output logic                          dcache_wready,
    input  logic [ADDR_WIDTH-1:0]         dcache_sw_addr,
    input  logic [DATA_WIDTH-1:0]         dcache_sw_data,
    input  logic [DATA_WIDTH/8-1:0]       dcache_wstrb,
    output logic                          dcache_wresp_valid,
    input  logic                          dcache_wresp_ready
);
    import dcache_pkg::*;

    logic        mem_req;
    logic        mem_we;
    mem_idx_t    mem_idx;
    cache_word_t mem_wdata;
    cache_word_t mem_rdata;
    logic        mem_ack;

    logic [31:0] stat_hits;
    logic [31:0] stat_misses;

    dcache_top u_cache (
        .clk           (clk),
        .rst_n         (rst_n),
        .rvalid        (dcache_rvalid),
        .rready        (dcache_rready),
        .raddr         (dcache_raddr),
        .rresp_valid   (dcache_rresp_valid),
        .rresp_ready   (dcache_rresp_ready),
        .rdata         (dcache_rdata),
        .wvalid        (dcache_wvalid),
        .wready        (dcache_wready),
        .waddr         (dcache_sw_addr),
        .wdata         (dcache_sw_data),
        .wstrb         (dcache_wstrb),
        .wresp_valid   (dcache_wresp_valid),
        .wresp_ready   (dcache_wresp_ready),
        .mem_req       (mem_req),
        .mem_we        (mem_we),
        .mem_idx       (mem_idx),
        .mem_wdata     (mem_wdata),
        .mem_rdata     (mem_rdata),
        .mem_ack       (mem_ack),
        .stat_hits     (stat_hits),
        .stat_misses   (stat_misses)
    );

    dcache_backing_mem u_mem (
        .clk       (clk),
        .rst_n     (rst_n),
        .req       (mem_req),
        .we        (mem_we),
        .idx       (mem_idx),
        .wdata     (mem_wdata),
        .rdata     (mem_rdata),
        .ack       (mem_ack),
        .init_en   (1'b0),
        .init_idx  ('0),
        .init_data ('0)
    );

endmodule
