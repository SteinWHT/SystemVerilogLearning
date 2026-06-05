// L1 D-cache drop-in for Tomasulo3CPU.
//
// This module presents the *memory side* of the Tomasulo CPU `dcache_*`
// interface, so it can replace the inline 1-cycle behavioural `dmem_array`
// read/write `always` blocks in the CPU testbenches with a real cache +
// backing SRAM.  Port names/directions mirror what `CPU.sv` drives/expects,
// so the testbench wires CPU and wrapper one-to-one by name.
//
// Handshake (standard valid/ready; the CPU is the requester):
//       - read : CPU drives dcache_rvalid (request), cache drives dcache_rready (ready)
//       - write: CPU drives dcache_wvalid (request), cache drives dcache_wready (ready)
//   These line up directly with the cache's rvalid/rready ports, so the mapping
//   to `dcache_top` is a straight pass-through.
//
// Load priority + single port: `dcache_core` serves at most one access per
// cycle and prefers loads.  The cache encodes this in its own handshake
// (wready = rready && !rvalid), so write-ready is only asserted on cycles the
// cache will actually accept the store and the CPU store buffer stays in
// lock-step.  No extra gating is needed in this wrapper.

module dcache_tomasulo_wrap #(
    parameter int unsigned CPU_ADDR_WIDTH = 64,                       // DMEM_DEPTH in CPU.sv
    parameter int unsigned DATA_WIDTH     = dcache_pkg::WORD_BITS,    // 64
    parameter int unsigned STRB_WIDTH     = dcache_pkg::STRB_WIDTH,   // 8
    parameter int unsigned MEM_IDX_BITS   = dcache_pkg::MEM_IDX_BITS  // 16
) (
    input  logic                          clk,
    input  logic                          rst_n,

    // ---- CPU load port (memory side: CPU drives request, we drive avail/resp)
    input  logic                          dcache_rvalid,       // CPU: load request
    input  logic [CPU_ADDR_WIDTH-1:0]     dcache_raddr,        // CPU: load byte addr
    input  logic                          dcache_rresp_ready,  // CPU: consumed resp
    output logic                          dcache_rready,       // to CPU: cache available
    output logic                          dcache_rresp_valid,  // to CPU: read data valid
    output logic [DATA_WIDTH-1:0]         dcache_rdata,        // to CPU: read data

    // ---- CPU store port
    input  logic                          dcache_wvalid,       // CPU: store request (SB !empty)
    input  logic                          dcache_write,        // CPU: store qualifier (unused)
    input  logic [CPU_ADDR_WIDTH-1:0]     dcache_sw_addr,      // CPU: store byte addr
    input  logic [DATA_WIDTH-1:0]         dcache_sw_data,      // CPU: store data (pre-shifted)
    input  logic [STRB_WIDTH-1:0]         dcache_wstrb,        // CPU: byte strobe
    input  logic                          dcache_wresp_ready,  // CPU: SB drain
    output logic                          dcache_wready,       // to CPU: cache available
    output logic                          dcache_wresp_valid,  // to CPU: write done

    // ---- Backing-memory preload (testbench only; clock one word at a time)
    input  logic                          mem_init_en,
    input  logic [MEM_IDX_BITS-1:0]       mem_init_idx,
    input  logic [DATA_WIDTH-1:0]         mem_init_data,

    // ---- Statistics
    output logic [31:0]                   stat_hits,
    output logic [31:0]                   stat_misses
);
    import dcache_pkg::*;

    // Cache available (combinational, from the core's single-port arbiter).
    logic        cache_rready;
    logic        cache_wready;

    logic        mem_req;
    logic        mem_we;
    mem_idx_t    mem_idx;
    cache_word_t mem_wdata;
    cache_word_t mem_rdata;
    logic        mem_ack;

    // Straight pass-through: the cache core now encodes single-port load
    // priority in its own wready (wready = rready && !rvalid), so the SB only
    // sees write-ready on cycles the cache will actually accept the store.
    assign dcache_rready = cache_rready;
    assign dcache_wready = cache_wready;

    dcache_top u_cache (
        .clk         (clk),
        .rst_n       (rst_n),

        .rvalid      (dcache_rvalid),                     // CPU request -> cache rvalid
        .rready      (cache_rready),                      // cache avail -> dcache_rready
        .raddr       (dcache_raddr[ADDR_WIDTH-1:0]),
        .rresp_valid (dcache_rresp_valid),
        .rresp_ready (dcache_rresp_ready),
        .rdata       (dcache_rdata),

        .wvalid      (dcache_wvalid),                     // CPU request -> cache wvalid
        .wready      (cache_wready),                      // cache avail -> dcache_wready
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

        .stat_hits   (stat_hits),
        .stat_misses (stat_misses)
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
        .init_en   (mem_init_en),
        .init_idx  (mem_init_idx),
        .init_data (mem_init_data)
    );

endmodule
