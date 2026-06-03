// Protocol assertions for AXI4-Lite — slave response channels only (see axi_assertions.sv).

import axi_pkg::*;

module axi_lite_assertions #(
    parameter int unsigned DATA_WIDTH = AXI_DATA_WIDTH
) (
    input logic clk,
    input logic rst_n,
    axi_lite_if.monitor bus
);

    property p_bvalid_stable;
        @(posedge clk) disable iff (!rst_n)
            (bus.bvalid && !bus.bready) |=> bus.bvalid;
    endproperty
    assert property (p_bvalid_stable)
        else $error("axi_lite_sram: BVALID dropped before BREADY");

    property p_rvalid_stable;
        @(posedge clk) disable iff (!rst_n)
            (bus.rvalid && !bus.rready) |=> bus.rvalid;
    endproperty
    assert property (p_rvalid_stable)
        else $error("axi_lite_sram: RVALID dropped before RREADY");

    property p_wstrb_nonzero_on_write;
        @(posedge clk) disable iff (!rst_n)
            (bus.wvalid && bus.wready) |-> (|bus.wstrb);
    endproperty
    assert property (p_wstrb_nonzero_on_write)
        else $error("axi_lite_sram: WSTRB must be non-zero on write beat");

endmodule
