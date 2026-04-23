// Write-side binary/Gray pointer and full flag.
// PTR_WIDTH must be ADDR_WIDTH + 1 where ADDR_WIDTH is the RAM address width
// (depth = 2**ADDR_WIDTH). Gray is PTR_WIDTH bits wide.

module write_ptr_handler #(
    parameter int unsigned PTR_WIDTH = 9
) (
    input  logic                    wclk,
    input  logic                    wr_rst_n,
    input  logic                    wr_en,
    input  logic [PTR_WIDTH-1:0]    rd_sync_ptr_gray,
    output logic                    full,
    output logic [PTR_WIDTH-1:0]   wr_ptr_bin,
    output logic [PTR_WIDTH-1:0]   wr_ptr_gray
);

    assign wr_ptr_gray = (wr_ptr_bin >> 1) ^ wr_ptr_bin;

    always_ff @(posedge wclk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wr_ptr_bin <= '0;
        end else if (wr_en && !full) begin
            wr_ptr_bin <= wr_ptr_bin + 1'b1;
        end
    end

    assign full = (wr_ptr_gray == {~rd_sync_ptr_gray[PTR_WIDTH-1:PTR_WIDTH-2],
                                    rd_sync_ptr_gray[PTR_WIDTH-3:0]});

endmodule
