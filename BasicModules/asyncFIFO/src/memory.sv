module memory #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned ADDR_WIDTH = 8
) (
    input  logic                    wclk,
    input  logic                    rclk,
    input  logic                    wr_rst_n,
    input  logic                    rd_rst_n,

    output logic [DATA_WIDTH-1:0]   rd_data,
    input  logic [ADDR_WIDTH-1:0]   rd_addr,
    input  logic                    rd_en,

    input  logic [DATA_WIDTH-1:0]   wr_data,
    input  logic [ADDR_WIDTH-1:0]   wr_addr,
    input  logic                    wr_en,

    input  logic                    full,
    input  logic                    empty
);

    localparam int unsigned DEPTH = 1 << ADDR_WIDTH;

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge wclk) begin
        if (wr_rst_n && wr_en && !full) begin
            mem[wr_addr] <= wr_data;
        end
    end

    always_ff @(posedge rclk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_data <= '0;
        end else if (rd_en && !empty) begin
            rd_data <= mem[rd_addr];
        end
    end

endmodule
