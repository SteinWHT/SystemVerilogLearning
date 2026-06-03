// Full AXI4 SoC top: 2 masters, interconnect, burst-capable SRAM.

import axi_pkg::*;

module axi_full_soc_top #(
    parameter int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
    parameter int unsigned SRAM_DEPTH = 4096
) (
    input  logic clk,
    input  logic rst_n,
    axi_if.slave m0,
    axi_if.slave m1
);

    axi_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) sram_bus (clk, rst_n);

    axi_xbar_2x1 #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_xbar (
        .clk   (clk),
        .rst_n (rst_n),
        .s0    (m0),
        .s1    (m1),
        .m     (sram_bus)
    );

    axi_sram #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .SRAM_DEPTH (SRAM_DEPTH)
    ) u_sram (
        .clk   (clk),
        .rst_n (rst_n),
        .bus   (sram_bus)
    );

endmodule
