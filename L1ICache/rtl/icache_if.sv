// CPU-side and backing-memory bundles for L1 I-cache (integration-friendly).
//
// The CPU fetch port matches Tomasulo3CPU IFQ naming (imem_*).  Wider fetch
// (IMEM_WIDTH > 32) can be added later by extending FETCH_WIDTH in icache_pkg.

interface icache_cpu_if #(
    parameter int unsigned ADDR_WIDTH  = icache_pkg::ADDR_WIDTH,
    parameter int unsigned FETCH_WIDTH = icache_pkg::FETCH_WIDTH
) (
    input logic clk,
    input logic rst_n
);
    // Fetch request (IFQ -> I-cache)
    logic                   req_valid;
    logic                   req_ready;
    logic [ADDR_WIDTH-1:0]  req_addr;

    // Fetch response (I-cache -> IFQ)
    logic                   resp_valid;
    logic                   resp_ready;
    logic [FETCH_WIDTH-1:0] resp_data;

    modport cpu (
        output req_valid,
        input  req_ready,
        output req_addr,
        input  resp_valid,
        output resp_ready,
        input  resp_data
    );

    modport cache (
        input  req_valid,
        output req_ready,
        input  req_addr,
        output resp_valid,
        input  resp_ready,
        output resp_data
    );
endinterface

interface icache_mem_if #(
    parameter int unsigned DATA_WIDTH = icache_pkg::MEM_WORD_BITS,
    parameter int unsigned IDX_WIDTH  = icache_pkg::MEM_IDX_BITS
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
