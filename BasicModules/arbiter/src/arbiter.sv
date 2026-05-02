// Round-robin arbiter: one-hot grant, at most one winner per cycle.
//
// Assertion layer (below `ifndef SYNTHESIS`):
//   Extra logic — usually SystemVerilog Assertions (SVA) — that states what must
//   *always* be true (assert), what the environment may assume (assume, formal),
//   and what you want to see in tests (cover). Simulators check these on clocks;
//   formal tools prove or falsify them. They do not change synthesized hardware
//   when guarded out of synthesis; they document intent and catch bugs early.

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

`ifndef SYNTHESIS
    // --- Assertion layer (simulation / formal; not for synthesis) ---
    ap_grant_onehot0: assert property (@(posedge clk) disable iff (!rst_n)
        $onehot0(grant_out))
        else $error("arbiter: grant_out must be zero or exactly one-hot");

    ap_grant_implies_req: assert property (@(posedge clk) disable iff (!rst_n)
        ((grant_out & ~req_in) == '0))
        else $error("arbiter: no grant without a matching request");

    cp_grant_beat: cover property (@(posedge clk) disable iff (!rst_n)
        |grant_out);
`endif

endmodule
