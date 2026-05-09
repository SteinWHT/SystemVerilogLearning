module IMEM #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned DEPTH = 8
) (
    input logic clk,
    input logic rst_n,
    input logic read_en,
    input logic write_en,
    input logic [DATA_WIDTH-1:0] data_in,
    input logic [DEPTH-1:0] address,
    output logic [DATA_WIDTH-1:0] data_out
);
    dual_port_memory #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) imem (
        .clk(clk),
        .rst_n(rst_n),
        .data_in_a(data_in),
        .write_en_a(write_en),
        .read_en_a(read_en),
        .address_a(address),
        .data_out_a(data_out),
        
        .data_in_b(0),
        .write_en_b(0),
        .read_en_b(0),
        .address_b(0),
        .data_out_b()
    );
endmodule