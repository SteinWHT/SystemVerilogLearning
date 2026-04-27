// AXI-style weighted round-robin arbiter: valid/ready on each master and on muxed output.
// Back-to-back transfers: on m_valid && m_ready, credits/ptr update and the *next* grant
// is registered in the same cycle (no idle bubble between beats).

module axi_wrr_arbiter #(
    parameter int unsigned N     = 4,
    parameter int unsigned W     = 4,
    // Tied to N; do not set independently unless you know what you are doing.
    parameter int unsigned IDX_W = (N > 1) ? $clog2(N) : 1
) (
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic [N-1:0]            valid,
    output logic [N-1:0]            ready,

    input  logic                    m_ready,
    output logic                    m_valid,
    output logic [IDX_W-1:0]        m_sel,

    input  logic [W-1:0]            weight [N]
);

    logic [W-1:0]             credit [N];
    logic [IDX_W-1:0]         ptr;

    logic [N-1:0]             eligible;
    logic [N-1:0]             grant;

    logic [W-1:0]             credit_post [N];
    logic [IDX_W-1:0]         ptr_post;
    logic [N-1:0]             eligible_post;
    logic [N-1:0]             grant_next_idle;
    logic [N-1:0]             grant_next_xfer;

    function automatic logic [IDX_W-1:0] idx_wrap(input int unsigned s);
        if (N <= 1)
            idx_wrap = '0;
        else
            idx_wrap = IDX_W'(s % N);
    endfunction

    // -------------------------------------------------------------------------
    function automatic logic [N-1:0] pick(
        input logic [N-1:0]            req,
        input logic [IDX_W-1:0]        start
    );
        logic [N-1:0] g;
        g = '0;
        for (int i = 0; i < N; i++) begin
            automatic int unsigned idx;
            idx = (N <= 1) ? 0 : ((start + i) % N);
            if (req[idx]) begin
                g[idx] = 1'b1;
                break;
            end
        end
        return g;
    endfunction

    // Eligible = valid && credit > 0
    always_comb begin
        for (int i = 0; i < N; i++)
            eligible[i] = valid[i] && (credit[i] != '0);
    end

    // Next pick from *current* credits (starting a new beat when bus is idle).
    always_comb begin
        if (|eligible)
            grant_next_idle = pick(eligible, ptr);
        else
            grant_next_idle = pick(valid, ptr);
    end

    // Post-handshake credits / ptr (mirrors sequential update order in always_ff).
    always_comb begin
        for (int i = 0; i < N; i++)
            credit_post[i] = credit[i];
        ptr_post = ptr;

        if (|grant) begin
            if (!(|eligible)) begin
                for (int i = 0; i < N; i++)
                    credit_post[i] = weight[i];
                for (int i = 0; i < N; i++) begin
                    if (grant[i])
                        ptr_post = idx_wrap(i + 1);
                end
            end else begin
                for (int i = 0; i < N; i++) begin
                    if (grant[i]) begin
                        credit_post[i] = credit[i] - 1'b1;
                        ptr_post       = idx_wrap(i + 1);
                    end
                end
            end
        end

        for (int i = 0; i < N; i++)
            eligible_post[i] = valid[i] && (credit_post[i] != '0);

        if (|eligible_post)
            grant_next_xfer = pick(eligible_post, ptr_post);
        else
            grant_next_xfer = pick(valid, ptr_post);
    end

    // -------------------------------------------------------------------------
    // Grant register: load next winner on handshake (same cycle) or when idle.
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            grant <= '0;
        end else begin
            if (m_valid && m_ready) begin
                grant <= grant_next_xfer;
            end else if (!m_valid && |grant_next_idle) begin
                grant <= grant_next_idle;
            end
        end
    end

    // Credits and pointer (same semantics as before; aligned with grant_next_xfer).
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ptr <= '0;
            for (int i = 0; i < N; i++)
                credit[i] <= weight[i];
        end else if (m_valid && m_ready) begin
            for (int i = 0; i < N; i++)
                credit[i] <= credit_post[i];
            ptr <= ptr_post;
        end
    end

    assign m_valid = |grant;
    assign ready   = grant & {N{m_ready}};

    always_comb begin
        m_sel = '0;
        for (int i = 0; i < N; i++)
            if (grant[i])
                m_sel = IDX_W'(i);
    end

endmodule
