// Two-master AXI4 memory subsystem with a serialized, round-robin fabric.

module axi_full_soc_top #(
    parameter int unsigned ADDR_WIDTH = axi_pkg::AXI_ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH = axi_pkg::AXI_DATA_WIDTH,
    parameter int unsigned ID_WIDTH   = axi_pkg::AXI_ID_WIDTH,
    parameter int unsigned SRAM_DEPTH = 4096
) (
    input  logic clk,
    input  logic rst_n,
    input  logic                  sram_init_en,
    input  logic [ADDR_WIDTH-1:0] sram_init_word_idx,
    input  logic [DATA_WIDTH-1:0] sram_init_data,
    axi_if.slave m0,
    axi_if.slave m1
);

    axi_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) sram_bus (clk, rst_n);

    axi_xbar_2x1 u_xbar (
        .clk   (clk),
        .rst_n (rst_n),
        .s0    (m0),
        .s1    (m1),
        .m     (sram_bus)
    );

    axi_sram #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .SRAM_DEPTH (SRAM_DEPTH)
    ) u_sram (
        .clk           (clk),
        .rst_n         (rst_n),
        .init_en       (sram_init_en),
        .init_word_idx (sram_init_word_idx),
        .init_data     (sram_init_data),
        .bus           (sram_bus)
    );

endmodule
