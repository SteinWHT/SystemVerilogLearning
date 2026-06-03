// Full AXI4 interface (supports bursts via len/size/burst and wlast/rlast).

interface axi_if #(
    parameter int unsigned ADDR_WIDTH = axi_pkg::AXI_ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH = axi_pkg::AXI_DATA_WIDTH,
    parameter int unsigned ID_WIDTH   = 0
) (
    input logic clk,
    input logic rst_n
);
    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;
    localparam int unsigned PROT_WIDTH = 3;
    localparam int unsigned LEN_WIDTH    = 8;
    localparam int unsigned SIZE_WIDTH   = 3;
    localparam int unsigned BURST_WIDTH  = 2;

    // Write address
    logic [ADDR_WIDTH-1:0]  awaddr;
    // number of beats in burst = awlen + 1
    logic [LEN_WIDTH-1:0]   awlen;
    // size of each beat in burst = 2^awsize bytes
    logic [SIZE_WIDTH-1:0]  awsize;
    // burst type: 0=FIXED, 1=INCR, 2=WRAP
    logic [BURST_WIDTH-1:0] awburst;
    // protection (not used in this design, but part of AXI4 spec)
    logic [PROT_WIDTH-1:0]  awprot;
    logic                   awvalid;
    logic                   awready;

    // Write data
    logic [DATA_WIDTH-1:0]  wdata;
    logic [STRB_WIDTH-1:0]  wstrb;
    logic                   wlast;
    logic                   wvalid;
    logic                   wready;

    // Write response
    logic [1:0]             bresp;
    logic                   bvalid;
    logic                   bready;

    // Read address
    logic [ADDR_WIDTH-1:0]  araddr;
    logic [LEN_WIDTH-1:0]   arlen;
    logic [SIZE_WIDTH-1:0]  arsize;
    logic [BURST_WIDTH-1:0] arburst;
    logic [PROT_WIDTH-1:0]  arprot;
    logic                   arvalid;
    logic                   arready;

    // Read data
    logic [DATA_WIDTH-1:0]  rdata;
    logic [1:0]             rresp;
    logic                   rlast;
    logic                   rvalid;
    logic                   rready;

    modport master (
        output awaddr,
        output awlen,
        output awsize,
        output awburst,
        output awprot,
        output awvalid,
        input  awready,
        output wdata,
        output wstrb,
        output wlast,
        output wvalid,
        input  wready,
        input  bresp,
        input  bvalid,
        output bready,
        output araddr,
        output arlen,
        output arsize,
        output arburst,
        output arprot,
        output arvalid,
        input  arready,
        input  rdata,
        input  rresp,
        input  rlast,
        input  rvalid,
        output rready
    );

    modport slave (
        input  awaddr,
        input  awlen,
        input  awsize,
        input  awburst,
        input  awprot,
        input  awvalid,
        output awready,
        input  wdata,
        input  wstrb,
        input  wlast,
        input  wvalid,
        output wready,
        output bresp,
        output bvalid,
        input  bready,
        input  araddr,
        input  arlen,
        input  arsize,
        input  arburst,
        input  arprot,
        input  arvalid,
        output arready,
        output rdata,
        output rresp,
        output rlast,
        output rvalid,
        input  rready
    );

    modport monitor (
        input awaddr,
        input awlen,
        input awsize,
        input awburst,
        input awprot,
        input awvalid,
        input awready,
        input wdata,
        input wstrb,
        input wlast,
        input wvalid,
        input wready,
        input bresp,
        input bvalid,
        input bready,
        input araddr,
        input arlen,
        input arsize,
        input arburst,
        input arprot,
        input arvalid,
        input arready,
        input rdata,
        input rresp,
        input rlast,
        input rvalid,
        input rready
    );

endinterface
