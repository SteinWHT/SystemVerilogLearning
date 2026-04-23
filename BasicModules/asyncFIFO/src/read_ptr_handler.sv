// Read-side binary/Gray pointer and empty flag.
// PTR_WIDTH = ADDR_WIDTH + 1 for RAM depth 2**ADDR_WIDTH.

module read_ptr_handler #(
    parameter int unsigned PTR_WIDTH = 9
) (
    input  logic                    rclk,
    input  logic                    rd_rst_n,
    input  logic                    rd_en,
    input  logic [PTR_WIDTH-1:0]    wr_sync_ptr_gray,
    output logic                    empty,
    output logic [PTR_WIDTH-1:0]   rd_ptr_bin,
    output logic [PTR_WIDTH-1:0]   rd_ptr_gray
);

    assign rd_ptr_gray = (rd_ptr_bin >> 1) ^ rd_ptr_bin;

    always_ff @(posedge rclk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_ptr_bin <= '0;
        end else if (rd_en && !empty) begin
            rd_ptr_bin <= rd_ptr_bin + 1'b1;
        end
    end

    assign empty = (rd_ptr_gray == wr_sync_ptr_gray);

endmodule
