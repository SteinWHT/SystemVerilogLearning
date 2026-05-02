module IMEM #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned DEPTH = 8
) (
    input logic clk,
    input logic rst_n,
    input logic [DEPTH-1:0] address,
    output logic [DATA_WIDTH-1:0] data_out
);





endmodule