// arbiter_template.v — structural template for a parameterized round-robin arbiter
// Fill in TODOs; match port names to your testbench.

module arbiter_template #(
    parameter NUM_REQ = 4  // TODO: document minimum (e.g. >= 2); $clog2(1) is a special case
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire [NUM_REQ-1:0]       req_in,
    output reg  [NUM_REQ-1:0]       grant_out
);

    // Next search starts after last granted index.
    reg [$clog2(NUM_REQ)-1:0] rr_ptr;

    integer i;
    integer idx;
    integer winner;  // -1 = no request this cycle; else index of granted master

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rr_ptr    <= { $clog2(NUM_REQ) {1'b0} };
            grant_out <= { NUM_REQ {1'b0} };
        end else begin
            winner = -1;
            for (i = 0; i < NUM_REQ; i = i + 1) begin
                idx = (rr_ptr + i) % NUM_REQ;
                if (winner < 0 && req_in[idx])
                    winner = idx;
            end

            if (winner >= 0) begin
                // One-hot grant: TODO replace with your preferred encoding
                grant_out <= ({ { (NUM_REQ-1) {1'b0} }, 1'b1 } << winner);
                rr_ptr    <= (winner + 1) % NUM_REQ;
            end else begin
                grant_out <= { NUM_REQ {1'b0} };
                // rr_ptr unchanged — TODO or advance on idle if your spec says so
            end
        end
    end

endmodule
