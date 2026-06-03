// SVA for full AXI4 — slave (DUT) response channels only.
//
// Master AW/W/AR valid-stable checks are intentionally omitted: the directed
// testbench uses a procedural BFM (tasks), not a cycle-accurate RTL master.

import axi_pkg::*;

module axi_assertions #(
    parameter int unsigned DATA_WIDTH = AXI_DATA_WIDTH
) (
    input logic clk,
    input logic rst_n,
    axi_if.monitor bus
);

    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;

    property p_bvalid_stable;
        @(posedge clk) disable iff (!rst_n)
            (bus.bvalid && !bus.bready) |=> bus.bvalid;
    endproperty
    assert property (p_bvalid_stable)
        else $error("axi_sram: BVALID dropped before BREADY");

    property p_rvalid_stable;
        @(posedge clk) disable iff (!rst_n)
            (bus.rvalid && !bus.rready) |=> bus.rvalid;
    endproperty
    assert property (p_rvalid_stable)
        else $error("axi_sram: RVALID dropped before RREADY");

    property p_wstrb_nonzero;
        @(posedge clk) disable iff (!rst_n)
            (bus.wvalid && bus.wready) |-> (|bus.wstrb);
    endproperty
    assert property (p_wstrb_nonzero)
        else $error("axi_sram: WSTRB zero on write beat");

endmodule
