// CPU-side and backing-memory bundles for L1 D-cache (integration-friendly).

interface dcache_cpu_if #(
    parameter int unsigned ADDR_WIDTH = dcache_pkg::ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH = dcache_pkg::WORD_BITS
) (
    input logic clk,
    input logic rst_n
);
    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;

    // Load port
    logic                   rvalid;
    logic                   rready;
    logic [ADDR_WIDTH-1:0]  raddr;
    logic                   rresp_valid;
    logic                   rresp_ready;
    logic [DATA_WIDTH-1:0]  rdata;

    // Store port
    logic                   wvalid;
    logic                   wready;
    logic [ADDR_WIDTH-1:0]  waddr;
    logic [DATA_WIDTH-1:0]  wdata;
    logic [STRB_WIDTH-1:0]  wstrb;
    logic                   wresp_valid;
    logic                   wresp_ready;

    modport cpu (
        output rvalid,
        input  rready,
        output raddr,
        input  rresp_valid,
        output rresp_ready,
        input  rdata,
        output wvalid,
        input  wready,
        output waddr,
        output wdata,
        output wstrb,
        input  wresp_valid,
        output wresp_ready
    );

    modport cache (
        input  rvalid,
        output rready,
        input  raddr,
        output rresp_valid,
        input  rresp_ready,
        output rdata,
        input  wvalid,
        output wready,
        input  waddr,
        input  wdata,
        input  wstrb,
        output wresp_valid,
        input  wresp_ready
    );
endinterface

interface dcache_mem_if #(
    parameter int unsigned ADDR_WIDTH = dcache_pkg::ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH = dcache_pkg::WORD_BITS,
    parameter int unsigned IDX_WIDTH  = dcache_pkg::MEM_IDX_BITS
) (
    input logic clk,
    input logic rst_n
);
    logic                   req;
    logic                   we;
    logic [IDX_WIDTH-1:0]   idx;
    logic [DATA_WIDTH-1:0]  wdata;
    logic [DATA_WIDTH-1:0]  rdata;
    logic                   ack;

    modport cache (
        output req,
        output we,
        output idx,
        output wdata,
        input  rdata,
        input  ack
    );

    modport memory (
        input  req,
        input  we,
        input  idx,
        input  wdata,
        output rdata,
        output ack
    );
endinterface
