// sync fifo with depth = 2^N
module sync_fifo #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned DEPTH = 8,
    localparam int unsigned PTR_W = $clog2(DEPTH)
) (
    input logic clk,
    input logic rst_n,
    input logic clear,
    input logic [DATA_WIDTH-1:0] data_in,
    input logic write_en,
    input logic read_en,
    output logic [DATA_WIDTH-1:0] data_out,
    output logic empty,
    output logic full
);

logic [DATA_WIDTH-1:0] fifo_data [DEPTH];
logic [PTR_W:0] fifo_write_ptr;
logic [PTR_W:0] fifo_read_ptr;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fifo_write_ptr <= 0;
        fifo_read_ptr <= 0;
    end else if (clear) begin
        fifo_write_ptr <= 0;
        fifo_read_ptr <= 0;
    end else begin
        if (write_en && !full) begin
            fifo_data[fifo_write_ptr[PTR_W-1:0]] <= data_in;
            fifo_write_ptr <= fifo_write_ptr + 1;
        end
        if (read_en && !empty) begin
            fifo_read_ptr <= fifo_read_ptr + 1;
        end
    end
end

assign data_out = fifo_data[fifo_read_ptr[PTR_W-1:0]];
assign empty = (fifo_write_ptr == fifo_read_ptr);
assign full = (fifo_write_ptr[PTR_W] != fifo_read_ptr[PTR_W]) &&
              (fifo_write_ptr[PTR_W-1:0] == fifo_read_ptr[PTR_W-1:0]);
endmodule