// sync fifo with depth = 2^N
module sync_fifo #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned DEPTH = 8
) (
    input logic clk,
    input logic rst_n,
    input logic [DATA_WIDTH-1:0] data_in,
    input logic write_en,
    input logic read_en,
    output logic [DATA_WIDTH-1:0] data_out,
    output logic empty,
    output logic full
);

logic [DEPTH-1:0] [DATA_WIDTH-1:0] fifo_data;
logic [DEPTH:0] fifo_write_ptr;
logic [DEPTH:0] fifo_read_ptr;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fifo_write_ptr <= 0;
        fifo_read_ptr <= 0;
        fifo_data <= '{default: 0};
    end else begin
        if (write_en && !full) begin
            fifo_data[fifo_write_ptr] <= data_in;
            fifo_write_ptr <= fifo_write_ptr + 1;
        end
        if (read_en && !empty) begin
            data_out <= fifo_data[fifo_read_ptr];
            fifo_read_ptr <= fifo_read_ptr + 1;
        end
    end
end

assign empty = (fifo_write_ptr == fifo_read_ptr);
assign full = ((fifo_write_ptr[DEPTH] != fifo_read_ptr[DEPTH]) && (fifo_write_ptr[DEPTH-1:0] == fifo_read_ptr[DEPTH-1:0]));
endmodule