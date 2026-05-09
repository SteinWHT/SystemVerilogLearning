// 4-way interleaved fetch queue
// 4 * 64 bit in
// 1 * 64 bit out
module IFQ #(
    parameter int unsigned INSTR_WIDTH = 64,
    parameter int unsigned DEPTH = 16,
    parameter int unsigned NUM_WAYS = 4,
    parameter int unsigned NUM_WAYS_WIDTH = $clog2(NUM_WAYS)
) (
    input  logic                        clk,
    input  logic                        rst_n,
    input  logic [INSTR_WIDTH-1:0]         instr_in [0:NUM_WAYS-1],
    input  logic                        valid_in,
    input  logic                        flush,
    input  logic [NUM_WAYS_WIDTH-1:0]   valid_out,
    output logic [INSTR_WIDTH-1:0]        instr_out,

    output logic                        full,
    output logic                        empty
);

    localparam int unsigned one_way_depth = DEPTH / NUM_WAYS;
    logic [NUM_WAYS-1:0] empty_array;
    logic [NUM_WAYS-1:0] full_array;
    logic [INSTR_WIDTH-1:0] instr_out_array [0:NUM_WAYS-1];
    genvar i;
    generate
        for(i = 0; i < NUM_WAYS; i++) begin: way_fifo_inst
            sync_fifo #(
                .DATA_WIDTH(IN_WIDTH),
                .DEPTH(one_way_depth)
            ) sync_fifo_inst (
                .clk(clk),
                .rst_n(rst_n && !flush),
                .data_in(instr_in[i]),
                .write_en(valid_in),
                .read_en(valid_out == i),
                .data_out(instr_out_array[i]),
                .empty(empty_array[i]),
                .full(full_array[i])
            );
        end
    endgenerate

    assign full = |full_array;
    assign empty = &empty_array;

    assign instr_out = instr_out_array[valid_out];

endmodule