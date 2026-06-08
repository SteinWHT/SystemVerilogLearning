// Translate the I-cache's single-word req/ack backing-memory port to AXI4.
//
// The current refill engine presents one 64-bit word at a time, so each cache
// request becomes a single-beat AXI4 transaction. The AXI-facing interface is
// full AXI4 and can share the existing fabric with another master such as D-cache.

module icache_axi_master_bridge #(
    parameter int unsigned MEM_IDX_WIDTH = icache_pkg::MEM_IDX_BITS,
    parameter int unsigned ADDR_WIDTH    = axi_pkg::AXI_ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH    = axi_pkg::AXI_DATA_WIDTH,
    parameter int unsigned ID_WIDTH      = axi_pkg::AXI_ID_WIDTH,
    parameter int unsigned AXI_ID        = 1,
    parameter logic [ADDR_WIDTH-1:0] BASE_ADDR = '0
) (
    input  logic                     clk,
    input  logic                     rst_n,

    input  logic                     mem_req,
    input  logic                     mem_we,
    input  logic [MEM_IDX_WIDTH-1:0] mem_idx,
    input  logic [DATA_WIDTH-1:0]    mem_wdata,
    output logic [DATA_WIDTH-1:0]    mem_rdata,
    output logic                     mem_ack,
    output logic                     error_sticky,

    axi_if.master                    axi
);
    import axi_pkg::*;

    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;
    localparam int unsigned BYTE_LSB   = $clog2(STRB_WIDTH);
    localparam logic [2:0]  AXI_SIZE   = 3'(BYTE_LSB);

    typedef enum logic [2:0] {
        BR_IDLE,
        BR_WRITE_ADDR,
        BR_WRITE_DATA,
        BR_WRITE_RESP,
        BR_READ_ADDR,
        BR_READ_DATA,
        BR_ACK
    } bridge_state_e;

    bridge_state_e          state_q;
    logic [ADDR_WIDTH-1:0]  addr_q;
    logic [DATA_WIDTH-1:0]  wdata_q;
    logic [DATA_WIDTH-1:0]  rdata_q;

    assign mem_rdata = rdata_q;
    assign mem_ack   = (state_q == BR_ACK);

    always_comb begin
        axi.awid     = ID_WIDTH'(AXI_ID);
        axi.awaddr   = addr_q;
        axi.awlen    = 8'd0;
        axi.awsize   = AXI_SIZE;
        axi.awburst  = AXI_BURST_INCR;
        axi.awlock   = 1'b0;
        axi.awcache  = 4'b0011;
        axi.awprot   = 3'b000;
        axi.awqos    = '0;
        axi.awregion = '0;
        axi.awvalid  = (state_q == BR_WRITE_ADDR);

        axi.wdata    = wdata_q;
        axi.wstrb    = {STRB_WIDTH{1'b1}};
        axi.wlast    = 1'b1;
        axi.wvalid   = (state_q == BR_WRITE_DATA);
        axi.bready   = (state_q == BR_WRITE_RESP);

        axi.arid     = ID_WIDTH'(AXI_ID);
        axi.araddr   = addr_q;
        axi.arlen    = 8'd0;
        axi.arsize   = AXI_SIZE;
        axi.arburst  = AXI_BURST_INCR;
        axi.arlock   = 1'b0;
        axi.arcache  = 4'b0011;
        axi.arprot   = 3'b000;
        axi.arqos    = '0;
        axi.arregion = '0;
        axi.arvalid  = (state_q == BR_READ_ADDR);
        axi.rready   = (state_q == BR_READ_DATA);
    end

    initial begin
        if (DATA_WIDTH < 8 || (DATA_WIDTH % 8) != 0)
            $fatal(1, "icache_axi_master_bridge: invalid DATA_WIDTH");
        if ((1 << BYTE_LSB) != STRB_WIDTH)
            $fatal(1, "icache_axi_master_bridge: DATA_WIDTH/8 must be power of two");
        if (MEM_IDX_WIDTH + BYTE_LSB > ADDR_WIDTH)
            $fatal(1, "icache_axi_master_bridge: AXI address is too narrow");
        if (ID_WIDTH == 0)
            $fatal(1, "icache_axi_master_bridge: ID_WIDTH must be >= 1");
        if ((BASE_ADDR % STRB_WIDTH) != 0)
            $fatal(1, "icache_axi_master_bridge: BASE_ADDR must be word aligned");
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q      <= BR_IDLE;
            addr_q       <= '0;
            wdata_q      <= '0;
            rdata_q      <= '0;
            error_sticky <= 1'b0;
        end else begin
            unique case (state_q)
                BR_IDLE: begin
                    if (mem_req) begin
                        addr_q  <= BASE_ADDR + (ADDR_WIDTH'(mem_idx) << BYTE_LSB);
                        wdata_q <= mem_wdata;
                        if (mem_we)
                            state_q <= BR_WRITE_ADDR;
                        else
                            state_q <= BR_READ_ADDR;
                    end
                end

                BR_WRITE_ADDR: begin
                    if (axi.awvalid && axi.awready)
                        state_q <= BR_WRITE_DATA;
                end

                BR_WRITE_DATA: begin
                    if (axi.wvalid && axi.wready)
                        state_q <= BR_WRITE_RESP;
                end

                BR_WRITE_RESP: begin
                    if (axi.bvalid && axi.bready) begin
                        if (axi.bresp != AXI_RESP_OKAY ||
                            axi.bid != ID_WIDTH'(AXI_ID))
                            error_sticky <= 1'b1;
                        state_q <= BR_ACK;
                    end
                end

                BR_READ_ADDR: begin
                    if (axi.arvalid && axi.arready)
                        state_q <= BR_READ_DATA;
                end

                BR_READ_DATA: begin
                    if (axi.rvalid && axi.rready) begin
                        rdata_q <= axi.rdata;
                        if (axi.rresp != AXI_RESP_OKAY || !axi.rlast ||
                            axi.rid != ID_WIDTH'(AXI_ID))
                            error_sticky <= 1'b1;
                        state_q <= BR_ACK;
                    end
                end

                BR_ACK: state_q <= BR_IDLE;

                default: state_q <= BR_IDLE;
            endcase
        end
    end

endmodule
