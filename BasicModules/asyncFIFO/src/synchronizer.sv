module synchronizer #(
    parameter int unsigned WIDTH = 8
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic [WIDTH-1:0]        async_in,
    output logic [WIDTH-1:0]        sync_out
);

    logic [WIDTH-1:0] sync_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_reg <= '0;
            sync_out <= '0;
        end else begin
            sync_reg <= async_in;
            sync_out <= sync_reg;
        end
    end
endmodule