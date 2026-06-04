// L1 D-cache top: CPU word ports + 64-bit memory bus + hit/miss statistics.

module dcache_top (
    input  logic                       clk,
    input  logic                       rst_n,

    // CPU load port (64-bit word)
    input  logic                       rvalid,
    output logic                       rready,
    input  dcache_pkg::cache_addr_t    raddr,
    output logic                       rresp_valid,
    input  logic                       rresp_ready,
    output dcache_pkg::cache_word_t    rdata,

    // CPU store port
    input  logic                       wvalid,
    output logic                       wready,
    input  dcache_pkg::cache_addr_t    waddr,
    input  dcache_pkg::cache_word_t    wdata,
    input  dcache_pkg::cache_strb_t    wstrb,
    output logic                       wresp_valid,
    input  logic                       wresp_ready,

    // 64-bit memory bus
    output logic                       mem_req,
    output logic                       mem_we,
    output dcache_pkg::mem_idx_t       mem_idx,
    output dcache_pkg::cache_word_t    mem_wdata,
    input  dcache_pkg::cache_word_t    mem_rdata,
    input  logic                       mem_ack,

    output logic [31:0]                stat_hits,
    output logic [31:0]                stat_misses
);

    dcache_core u_core (
        .clk         (clk),
        .rst_n       (rst_n),
        .rvalid      (rvalid),
        .rready      (rready),
        .raddr       (raddr),
        .rresp_valid (rresp_valid),
        .rresp_ready (rresp_ready),
        .rdata       (rdata),
        .wvalid      (wvalid),
        .wready      (wready),
        .waddr       (waddr),
        .wdata       (wdata),
        .wstrb       (wstrb),
        .wresp_valid (wresp_valid),
        .wresp_ready (wresp_ready),
        .mem_req     (mem_req),
        .mem_we      (mem_we),
        .mem_idx     (mem_idx),
        .mem_wdata   (mem_wdata),
        .mem_rdata   (mem_rdata),
        .mem_ack     (mem_ack),
        .stat_hits   (stat_hits),
        .stat_misses (stat_misses)
    );

endmodule
