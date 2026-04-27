// template.sv — reference templates: optimized RR, fixed priority, WRR, two-level arbiter
// Each module is self-contained; pick one style and tune parameters for your bus protocol.

//-----------------------------------------------------------------------------
// 1) Round-robin via rotate + fixed priority (IP-style “masked window”)
//    - Concatenate {req, req}; take NUM_REQ bits starting at rr_ptr → RR order.
//    - First set bit in that window wins; map index back to physical master.
//    - Scales as O(N) combinational depth unless you replace first_one with a tree.
//-----------------------------------------------------------------------------

module arb_rr_masked #(
    parameter int unsigned NUM_REQ = 4
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic [NUM_REQ-1:0] req_in,
    output logic [NUM_REQ-1:0] grant_out
);

    localparam int unsigned PTR_W = (NUM_REQ > 1) ? $clog2(NUM_REQ) : 1;
    localparam bit IS_POW2        = (NUM_REQ > 1) && ((NUM_REQ & (NUM_REQ - 1)) == 1'b0);

    logic [PTR_W-1:0] rr_ptr;

    function automatic int unsigned idx_wrap(input int unsigned s);
        if (NUM_REQ <= 1)
            idx_wrap = 0;
        else if (IS_POW2)
            idx_wrap = s & (NUM_REQ - 1);
        else
            idx_wrap = s % NUM_REQ;
    endfunction

    function automatic int unsigned first_one_lsb(input logic [NUM_REQ-1:0] x);
        first_one_lsb = 0;
        for (int k = 0; k < NUM_REQ; k++) begin
            if (x[k]) begin
                first_one_lsb = k;
                return first_one_lsb;
            end
        end
    endfunction

    logic [2*NUM_REQ-1:0]          req_dup;
    logic [NUM_REQ-1:0]           req_window;
    int unsigned                  win_in_window;
    int unsigned                  win_phys;
    logic [NUM_REQ-1:0]           grant_next;

    always_comb begin
        req_dup      = {req_in, req_in};
        req_window   = req_dup[rr_ptr +: NUM_REQ];
        grant_next   = '0;
        win_phys     = 0;
        win_in_window = 0;
        if (NUM_REQ != 0 && |req_window) begin
            win_in_window = first_one_lsb(req_window);
            win_phys      = idx_wrap(rr_ptr + win_in_window);
            grant_next    = (NUM_REQ'(1'b1) << win_phys);
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rr_ptr    <= '0;
            grant_out <= '0;
        end else begin
            grant_out <= grant_next;
            if (|grant_next)
                rr_ptr <= idx_wrap(win_phys + 1);
        end
    end

endmodule


//-----------------------------------------------------------------------------
// 2) Same policy as (1), but documents where you would insert a parallel
//    priority encoder (e.g. for very wide NUM_REQ) instead of first_one_lsb().
//-----------------------------------------------------------------------------

module arb_rr_masked_parallel_hint #(
    parameter int unsigned NUM_REQ = 8
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic [NUM_REQ-1:0] req_in,
    output logic [NUM_REQ-1:0] grant_out
);
    // TODO: replace first_one_lsb() in arb_rr_masked with:
    //   - a vendor priority-encoder primitive, or
    //   - a balanced OR/AND tree (leading-one detect), or
    //   - a casez / casex one-hot decode from pre-encoded req_in.
    // Instantiate arb_rr_masked below or copy its always_comb and swap the encoder.
    arb_rr_masked #(.NUM_REQ(NUM_REQ)) u_core (
        .clk,
        .rst_n,
        .req_in,
        .grant_out
    );
endmodule


//-----------------------------------------------------------------------------
// 3) Fixed priority: lowest-index requesting master wins every cycle.
//-----------------------------------------------------------------------------

module arb_fixed_priority #(
    parameter int unsigned NUM_REQ = 4,
    parameter bit          HIGH_INDEX_FIRST = 1'b0  // 0: LSB (index 0) highest priority
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic [NUM_REQ-1:0] req_in,
    output logic [NUM_REQ-1:0] grant_out
);

    function automatic int unsigned pick_fixed(input logic [NUM_REQ-1:0] r);
        pick_fixed = 0;
        if (!HIGH_INDEX_FIRST) begin
            for (int k = 0; k < NUM_REQ; k++)
                if (r[k]) begin
                    pick_fixed = k;
                    return pick_fixed;
                end
        end else begin
            for (int k = NUM_REQ - 1; k >= 0; k--)
                if (r[k]) begin
                    pick_fixed = k;
                    return pick_fixed;
                end
        end
    endfunction

    int unsigned          win;
    logic [NUM_REQ-1:0]   grant_next;

    always_comb begin
        win = pick_fixed(req_in);
        if (|req_in)
            grant_next = (NUM_REQ'(1'b1) << win);
        else
            grant_next = '0;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            grant_out <= '0;
        else
            grant_out <= grant_next;
    end

endmodule


//-----------------------------------------------------------------------------
// 4) Weighted round-robin (deficit-style credits)
//    - Each master i has WEIGHTS[i] credits per refill epoch.
//    - Among masters with req_in[i] && credit[i] > 0, serve in RR order; burn 1 credit.
//    - When no eligible master exists and some master still requests, refill all credits.
//    - NUM_REQ is compile-time; set unused WEIGHT entries to 0 to mask ports.
//-----------------------------------------------------------------------------

module arb_weighted_rr #(
    parameter int unsigned NUM_REQ = 4,
    parameter int unsigned WEIGHTS [NUM_REQ] = '{default: 1}
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic [NUM_REQ-1:0] req_in,
    output logic [NUM_REQ-1:0] grant_out
);

    localparam int unsigned PTR_W = (NUM_REQ > 1) ? $clog2(NUM_REQ) : 1;

    logic [PTR_W-1:0]             rr_ptr;
    logic [NUM_REQ-1:0]           grant_next;
    int unsigned                  win_phys;
    logic [31:0]                  credit [NUM_REQ];  // wide enough for typical weights

    function automatic int unsigned idx_mod(input int unsigned s);
        if (NUM_REQ <= 1)
            idx_mod = 0;
        else
            idx_mod = s % NUM_REQ;
    endfunction

    always_comb begin
        grant_next = '0;
        win_phys   = 0;
        if (NUM_REQ != 0) begin
            automatic logic granted;
            automatic int unsigned idx;
            granted = 1'b0;
            for (int i = 0; i < NUM_REQ; i++) begin
                idx = idx_mod(rr_ptr + i);
                if (!granted && req_in[idx] && (credit[idx] != 0)) begin
                    grant_next = (NUM_REQ'(1'b1) << idx);
                    win_phys   = idx;
                    granted    = 1'b1;
                end
            end
        end
    end

    function automatic bit any_eligible(input logic [NUM_REQ-1:0] r);
        any_eligible = 1'b0;
        for (int j = 0; j < NUM_REQ; j++)
            if (r[j] && (credit[j] != 0))
                any_eligible = 1'b1;
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rr_ptr    <= '0;
            grant_out <= '0;
            for (int j = 0; j < NUM_REQ; j++)
                credit[j] <= WEIGHTS[j];
        end else begin
            grant_out <= grant_next;
            if (|grant_next) begin
                credit[win_phys] <= credit[win_phys] - 1;
                rr_ptr <= idx_mod(win_phys + 1);
            end else if (|req_in && !any_eligible(req_in)) begin
                for (int j = 0; j < NUM_REQ; j++)
                    credit[j] <= WEIGHTS[j];
            end
        end
    end

endmodule


//-----------------------------------------------------------------------------
// 5) Two-level (hierarchical) template: G groups × M masters each — fixed
//    priority inside a group, round-robin across groups. Shows how IP blocks
//    split wide arbiters without a single N-wide priority chain.
//-----------------------------------------------------------------------------

module arb_two_level #(
    parameter int unsigned M = 4,  // masters per group
    parameter int unsigned G = 2   // number of groups (total NUM_REQ = M*G)
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic [M*G-1:0]          req_in,
    output logic [M*G-1:0]          grant_out
);

    localparam int unsigned NUM_REQ = M * G;
    localparam int unsigned PTR_GW  = (G > 1) ? $clog2(G) : 1;
    localparam bit          G_POW2  = (G > 1) && ((G & (G - 1)) == 1'b0);

    logic [PTR_GW-1:0]      rr_ptr_g;
    logic [G-1:0]           group_req;
    logic [2*G-1:0]         req_dup_g;
    logic [G-1:0]           grp_window;
    int unsigned            win_in_grp;
    int unsigned            grp_phys;
    int unsigned            m_phys;
    logic [NUM_REQ-1:0]     grant_next;

    function automatic int unsigned idx_wrap_g(input int unsigned s);
        if (G <= 1)
            idx_wrap_g = 0;
        else if (G_POW2)
            idx_wrap_g = s & (G - 1);
        else
            idx_wrap_g = s % G;
    endfunction

    function automatic int unsigned first_one_lsb_g(input logic [G-1:0] x);
        first_one_lsb_g = 0;
        for (int k = 0; k < G; k++) begin
            if (x[k]) begin
                first_one_lsb_g = k;
                return first_one_lsb_g;
            end
        end
    endfunction

    function automatic int unsigned first_one_lsb_m(input logic [M-1:0] x);
        first_one_lsb_m = 0;
        for (int k = 0; k < M; k++) begin
            if (x[k]) begin
                first_one_lsb_m = k;
                return first_one_lsb_m;
            end
        end
    endfunction

    genvar gi;
    generate
        for (gi = 0; gi < G; gi++) begin : g_or
            assign group_req[gi] = |req_in[gi*M +: M];
        end
    endgenerate

    // One cycle: RR among groups (rotate window), then fixed (LSB) priority inside the group.
    always_comb begin
        req_dup_g    = {group_req, group_req};
        grp_window   = req_dup_g[rr_ptr_g +: G];
        grant_next   = '0;
        grp_phys     = 0;
        m_phys       = 0;
        win_in_grp   = 0;
        if (NUM_REQ != 0 && |grp_window) begin
            win_in_grp = first_one_lsb_g(grp_window);
            grp_phys   = idx_wrap_g(rr_ptr_g + win_in_grp);
            m_phys     = first_one_lsb_m(req_in[grp_phys*M +: M]);
            grant_next = (NUM_REQ'(1'b1) << (grp_phys * M + m_phys));
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rr_ptr_g  <= '0;
            grant_out <= '0;
        end else begin
            grant_out <= grant_next;
            if (|grant_next)
                rr_ptr_g <= idx_wrap_g(grp_phys + 1);
        end
    end

endmodule
