// Virtual-interface bundle for async_fifo (all ports except clocks are in the interface).
// Clocks are generated in tb_top and driven onto this interface.

interface fifo_if #(
    parameter int unsigned DATA_WIDTH = 8
) ();
    logic wclk;
    logic rclk;
    logic wr_rst_n;
    logic rd_rst_n;
    logic wr_en;
    logic rd_en;
    logic full;
    logic empty;
    logic [DATA_WIDTH-1:0] wr_data;
    logic [DATA_WIDTH-1:0] rd_data;
endinterface
