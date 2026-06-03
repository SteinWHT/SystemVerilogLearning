// 2-master / 1-slave AXI4-Lite interconnect with round-robin single-flight arbitration.

import axi_pkg::*;

module axi_lite_xbar_2x1 #(
    parameter int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH = AXI_DATA_WIDTH
) (
    input  logic clk,
    input  logic rst_n,
    axi_lite_if.slave  s0,
    axi_lite_if.slave  s1,
    axi_lite_if.master m
);

    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;

    logic        locked;
    logic        owner;
    logic        txn_write;
    logic        rr_ptr;

    logic        s0_req;
    logic        s1_req;
    logic        pick_s0;
    logic        pick_s1;
    logic        grant_s0;
    logic        grant_s1;

    logic        wr_active;
    logic        rd_active;
    logic        wr_done;
    logic        rd_done;

    assign s0_req = s0.awvalid || s0.wvalid || s0.arvalid;
    assign s1_req = s1.awvalid || s1.wvalid || s1.arvalid;

    always_comb begin
        pick_s0 = 1'b0;
        pick_s1 = 1'b0;
        if (!locked) begin
            if (s0_req && !s1_req)
                pick_s0 = 1'b1;
            else if (s1_req && !s0_req)
                pick_s1 = 1'b1;
            else if (s0_req && s1_req) begin
                if (rr_ptr == 1'b0)
                    pick_s0 = 1'b1;
                else
                    pick_s1 = 1'b1;
            end
        end
    end

    assign grant_s0 = locked ? !owner : pick_s0;
    assign grant_s1 = locked ?  owner : pick_s1;

    assign wr_active = locked && txn_write;
    assign rd_active = locked && !txn_write;
    assign wr_done   = wr_active && m.bvalid && m.bready;
    assign rd_done   = rd_active && m.rvalid && m.rready;

    // Downstream master port (toward SRAM slave).
    assign m.awaddr  = grant_s1 ? s1.awaddr  : s0.awaddr;
    assign m.awprot  = grant_s1 ? s1.awprot  : s0.awprot;
    assign m.awvalid = (grant_s0 && s0.awvalid) || (grant_s1 && s1.awvalid);

    assign m.wdata   = grant_s1 ? s1.wdata   : s0.wdata;
    assign m.wstrb   = grant_s1 ? s1.wstrb   : s0.wstrb;
    assign m.wvalid  = (grant_s0 && s0.wvalid) || (grant_s1 && s1.wvalid);

    assign m.bready  = (grant_s0 && s0.bready) || (grant_s1 && s1.bready);

    assign m.araddr  = grant_s1 ? s1.araddr  : s0.araddr;
    assign m.arprot  = grant_s1 ? s1.arprot  : s0.arprot;
    assign m.arvalid = (grant_s0 && s0.arvalid) || (grant_s1 && s1.arvalid);

    assign m.rready  = (grant_s0 && s0.rready) || (grant_s1 && s1.rready);

    // Upstream ready / response routing.
    assign s0.awready = grant_s0 && m.awready;
    assign s0.wready  = grant_s0 && m.wready;
    assign s0.arready = grant_s0 && m.arready;

    assign s1.awready = grant_s1 && m.awready;
    assign s1.wready  = grant_s1 && m.wready;
    assign s1.arready = grant_s1 && m.arready;

    assign s0.bvalid = grant_s0 && m.bvalid;
    assign s0.bresp  = m.bresp;
    assign s1.bvalid = grant_s1 && m.bvalid;
    assign s1.bresp  = m.bresp;

    assign s0.rvalid = grant_s0 && m.rvalid;
    assign s0.rdata  = m.rdata;
    assign s0.rresp  = m.rresp;
    assign s1.rvalid = grant_s1 && m.rvalid;
    assign s1.rdata  = m.rdata;
    assign s1.rresp  = m.rresp;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            locked     <= 1'b0;
            owner      <= 1'b0;
            txn_write  <= 1'b0;
            rr_ptr     <= 1'b0;
        end else begin
            if (wr_done || rd_done) begin
                locked    <= 1'b0;
                rr_ptr    <= owner;
            end else if (!locked && (pick_s0 || pick_s1)) begin
                locked    <= 1'b1;
                owner     <= pick_s1;
                txn_write <= (pick_s1 && (s1.awvalid || s1.wvalid)) ||
                             (pick_s0 && (s0.awvalid || s0.wvalid));
            end
        end
    end

endmodule
