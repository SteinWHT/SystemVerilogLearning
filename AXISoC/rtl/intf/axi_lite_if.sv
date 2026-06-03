// AXI4-Lite interface (single-beat read/write).

interface axi_lite_if #(
    parameter int unsigned ADDR_WIDTH = axi_pkg::AXI_ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH = axi_pkg::AXI_DATA_WIDTH
) (
    input logic clk,
    input logic rst_n
);
    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;
    localparam int unsigned PROT_WIDTH = 3;

    // Write address
    logic [ADDR_WIDTH-1:0]  awaddr;
    logic [PROT_WIDTH-1:0]  awprot;
    logic                   awvalid;
    logic                   awready;

    // Write data
    logic [DATA_WIDTH-1:0]  wdata;
    logic [STRB_WIDTH-1:0]  wstrb;
    logic                   wvalid;
    logic                   wready;

    // Write response
    logic [1:0]             bresp;
    logic                   bvalid;
    logic                   bready;

    // Read address
    logic [ADDR_WIDTH-1:0]  araddr;
    logic [PROT_WIDTH-1:0]  arprot;
    logic                   arvalid;
    logic                   arready;

    // Read data
    logic [DATA_WIDTH-1:0]  rdata;
    logic [1:0]             rresp;
    logic                   rvalid;
    logic                   rready;

    modport master (
        output awaddr,
        output awprot,
        output awvalid,
        input  awready,
        output wdata,
        output wstrb,
        output wvalid,
        input  wready,
        input  bresp,
        input  bvalid,
        output bready,
        output araddr,
        output arprot,
        output arvalid,
        input  arready,
        input  rdata,
        input  rresp,
        input  rvalid,
        output rready
    );

    modport slave (
        input  awaddr,
        input  awprot,
        input  awvalid,
        output awready,
        input  wdata,
        input  wstrb,
        input  wvalid,
        output wready,
        output bresp,
        output bvalid,
        input  bready,
        input  araddr,
        input  arprot,
        input  arvalid,
        output arready,
        output rdata,
        output rresp,
        output rvalid,
        input  rready
    );

    modport monitor (
        input awaddr,
        input awprot,
        input awvalid,
        input awready,
        input wdata,
        input wstrb,
        input wvalid,
        input wready,
        input bresp,
        input bvalid,
        input bready,
        input araddr,
        input arprot,
        input arvalid,
        input arready,
        input rdata,
        input rresp,
        input rvalid,
        input rready
    );

endinterface
