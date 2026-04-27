// Round-robin arbiter: one-hot grant, at most one winner per cycle.

module arbiter #(
    parameter int unsigned NUM_REQ = 4
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic [NUM_REQ-1:0]      req_in,
    output logic [NUM_REQ-1:0]      grant_out
);

    // avoid a zero-width pointer when NUM_REQ==1.
    localparam int unsigned PTR_W = (NUM_REQ > 1) ? $clog2(NUM_REQ) : 1;

    logic [PTR_W-1:0] rr_ptr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rr_ptr    <= '0;
            grant_out <= '0;
        end else begin
            automatic logic        granted;
            automatic int unsigned idx;

            granted = 1'b0;
            grant_out <= '0;

            for (int i = 0; i < NUM_REQ; i++) begin
                idx = (rr_ptr + i) % NUM_REQ;
                if (!granted && req_in[idx]) begin
                    grant_out <= (NUM_REQ'(1'b1) << idx);
                    rr_ptr    <= ((idx + 1) % NUM_REQ);
                    granted   = 1'b1;
                end
            end
        end
    end

endmodule
