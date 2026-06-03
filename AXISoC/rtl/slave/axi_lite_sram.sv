// AXI4-Lite SRAM slave: byte-addressable memory with wstrb partial writes.

import axi_pkg::*;

module axi_lite_sram #(
    parameter int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
    parameter int unsigned SRAM_DEPTH = 4096
) (
    input  logic clk,
    input  logic rst_n,
    axi_lite_if.slave bus
);

    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;
    localparam int unsigned ADDR_LSB   = byte_lsb(DATA_WIDTH);
    localparam int unsigned IDX_WIDTH  = (SRAM_DEPTH <= 1) ? 1 : $clog2(SRAM_DEPTH);

    logic [DATA_WIDTH-1:0] mem [SRAM_DEPTH];

    logic                  pending_aw;
    logic                  pending_w;
    logic [ADDR_WIDTH-1:0] wr_addr;
    logic [DATA_WIDTH-1:0] wr_data;
    logic [STRB_WIDTH-1:0] wr_strb;

    logic                  pending_ar;
    logic [ADDR_WIDTH-1:0] rd_addr;

    logic                  bvalid_r;
    logic [1:0]            bresp_r;

    logic                  rvalid_r;
    logic [DATA_WIDTH-1:0] rdata_r;
    logic [1:0]            rresp_r;

    assign bus.awready = !pending_aw && !(bvalid_r && !bus.bready);
    assign bus.wready  = !pending_w && !(bvalid_r && !bus.bready);
    assign bus.arready = !pending_ar && !rvalid_r;

    assign bus.bvalid  = bvalid_r;
    assign bus.bresp   = bresp_r;

    assign bus.rvalid  = rvalid_r;
    assign bus.rdata   = rdata_r;
    assign bus.rresp   = rresp_r;

    function automatic int unsigned addr_idx(input logic [ADDR_WIDTH-1:0] addr);
        return addr_to_idx(addr, DATA_WIDTH);
    endfunction

    function automatic axi_resp_e check_addr(input logic [ADDR_WIDTH-1:0] addr);
        if (!addr_aligned(addr, DATA_WIDTH))
            return AXI_RESP_SLVERR;
        if (!addr_in_range(addr, DATA_WIDTH, SRAM_DEPTH))
            return AXI_RESP_DECERR;
        return AXI_RESP_OKAY;
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        int unsigned idx;
        axi_resp_e   resp;

        if (!rst_n) begin
            pending_aw <= 1'b0;
            pending_w  <= 1'b0;
            pending_ar <= 1'b0;
            bvalid_r   <= 1'b0;
            bresp_r    <= AXI_RESP_OKAY;
            rvalid_r   <= 1'b0;
            rdata_r    <= '0;
            rresp_r    <= AXI_RESP_OKAY;
            for (int i = 0; i < SRAM_DEPTH; i++)
                mem[i] <= '0;
        end else begin
            if (bvalid_r && bus.bready)
                bvalid_r <= 1'b0;

            if (rvalid_r && bus.rready)
                rvalid_r <= 1'b0;

            if (bus.awvalid && bus.awready) begin
                pending_aw <= 1'b1;
                wr_addr    <= bus.awaddr;
            end

            if (bus.wvalid && bus.wready) begin
                pending_w  <= 1'b1;
                wr_data    <= bus.wdata;
                wr_strb    <= bus.wstrb;
            end

            if (pending_aw && pending_w && !bvalid_r) begin
                resp = check_addr(wr_addr);
                if (resp == AXI_RESP_OKAY) begin
                    idx = addr_idx(wr_addr);
                    for (int i = 0; i < STRB_WIDTH; i++) begin
                        if (wr_strb[i])
                            mem[idx][8*i +: 8] <= wr_data[8*i +: 8];
                    end
                end
                bresp_r  <= resp;
                bvalid_r <= 1'b1;
                pending_aw <= 1'b0;
                pending_w  <= 1'b0;
            end

            if (bus.arvalid && bus.arready) begin
                pending_ar <= 1'b1;
                rd_addr    <= bus.araddr;
            end

            if (pending_ar && !rvalid_r) begin
                resp = check_addr(rd_addr);
                if (resp == AXI_RESP_OKAY)
                    rdata_r <= mem[addr_idx(rd_addr)];
                else
                    rdata_r <= '0;
                rresp_r    <= resp;
                rvalid_r   <= 1'b1;
                pending_ar <= 1'b0;
            end
        end
    end

endmodule
