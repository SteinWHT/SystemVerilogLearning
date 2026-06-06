interface axi_if #(
    parameter int unsigned ADDR_WIDTH = axi_pkg::AXI_ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH = axi_pkg::AXI_DATA_WIDTH,
    parameter int unsigned ID_WIDTH   = axi_pkg::AXI_ID_WIDTH
) (
    input logic clk,
    input logic rst_n
);
    localparam int unsigned STRB_WIDTH   = DATA_WIDTH / 8;
    localparam int unsigned PROT_WIDTH   = 3;
    localparam int unsigned CACHE_WIDTH  = 4;
    localparam int unsigned QOS_WIDTH    = 4;
    localparam int unsigned REGION_WIDTH = 4;
    localparam int unsigned LEN_WIDTH    = 8;
    localparam int unsigned SIZE_WIDTH   = 3;
    localparam int unsigned BURST_WIDTH  = 2;

    // Write address
    logic [ID_WIDTH-1:0]    awid;
    logic [ADDR_WIDTH-1:0]  awaddr;
    // number of beats in burst = awlen + 1
    logic [LEN_WIDTH-1:0]   awlen;
    // size of each beat in burst = 2^awsize bytes
    logic [SIZE_WIDTH-1:0]  awsize;
    // burst type: 0=FIXED, 1=INCR, 2=WRAP
    logic [BURST_WIDTH-1:0] awburst;
    // exclusive access request; this SRAM does not grant exclusivity
    logic                   awlock;
    // memory/cache attributes; forwarded by the interconnect
    logic [CACHE_WIDTH-1:0] awcache;
    // protection attributes; forwarded by the interconnect
    logic [PROT_WIDTH-1:0]  awprot;
    // quality-of-service and region hints; no scheduling effect in this design
    logic [QOS_WIDTH-1:0]   awqos;
    logic [REGION_WIDTH-1:0] awregion;
    logic                   awvalid;
    logic                   awready;

    // Write data
    logic [DATA_WIDTH-1:0]  wdata;
    logic [STRB_WIDTH-1:0]  wstrb;
    logic                   wlast;
    logic                   wvalid;
    logic                   wready;

    // Write response
    logic [ID_WIDTH-1:0]    bid;
    logic [1:0]             bresp;
    logic                   bvalid;
    logic                   bready;

    // Read address
    logic [ID_WIDTH-1:0]    arid;
    logic [ADDR_WIDTH-1:0]  araddr;
    logic [LEN_WIDTH-1:0]   arlen;
    logic [SIZE_WIDTH-1:0]  arsize;
    logic [BURST_WIDTH-1:0] arburst;
    logic                   arlock;
    logic [CACHE_WIDTH-1:0] arcache;
    logic [PROT_WIDTH-1:0]  arprot;
    logic [QOS_WIDTH-1:0]   arqos;
    logic [REGION_WIDTH-1:0]arregion;
    logic                   arvalid;
    logic                   arready;

    // Read data
    logic [ID_WIDTH-1:0]    rid;
    logic [DATA_WIDTH-1:0]  rdata;
    logic [1:0]             rresp;
    logic                   rlast;
    logic                   rvalid;
    logic                   rready;

    modport master (
        output awid,
        output awaddr,
        output awlen,
        output awsize,
        output awburst,
        output awlock,
        output awcache,
        output awprot,
        output awqos,
        output awregion,
        output awvalid,
        input  awready,
        output wdata,
        output wstrb,
        output wlast,
        output wvalid,
        input  wready,
        input  bid,
        input  bresp,
        input  bvalid,
        output bready,
        output arid,
        output araddr,
        output arlen,
        output arsize,
        output arburst,
        output arlock,
        output arcache,
        output arprot,
        output arqos,
        output arregion,
        output arvalid,
        input  arready,
        input  rid,
        input  rdata,
        input  rresp,
        input  rlast,
        input  rvalid,
        output rready
    );

    modport slave (
        input  awid,
        input  awaddr,
        input  awlen,
        input  awsize,
        input  awburst,
        input  awlock,
        input  awcache,
        input  awprot,
        input  awqos,
        input  awregion,
        input  awvalid,
        output awready,
        input  wdata,
        input  wstrb,
        input  wlast,
        input  wvalid,
        output wready,
        output bid,
        output bresp,
        output bvalid,
        input  bready,
        input  arid,
        input  araddr,
        input  arlen,
        input  arsize,
        input  arburst,
        input  arlock,
        input  arcache,
        input  arprot,
        input  arqos,
        input  arregion,
        input  arvalid,
        output arready,
        output rid,
        output rdata,
        output rresp,
        output rlast,
        output rvalid,
        input  rready
    );

    modport monitor (
        input awid,
        input awaddr,
        input awlen,
        input awsize,
        input awburst,
        input awlock,
        input awcache,
        input awprot,
        input awqos,
        input awregion,
        input awvalid,
        input awready,
        input wdata,
        input wstrb,
        input wlast,
        input wvalid,
        input wready,
        input bid,
        input bresp,
        input bvalid,
        input bready,
        input arid,
        input araddr,
        input arlen,
        input arsize,
        input arburst,
        input arlock,
        input arcache,
        input arprot,
        input arqos,
        input arregion,
        input arvalid,
        input arready,
        input rid,
        input rdata,
        input rresp,
        input rlast,
        input rvalid,
        input rready
    );

endinterface
