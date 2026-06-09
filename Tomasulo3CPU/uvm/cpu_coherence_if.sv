// Observation interface for the FENCE.I I$/D$ coherence handshake.
//
// All signals are sampled from inside CPU_L1DCache_AXI (driven by hierarchical
// continuous assigns in tb_top_axi). The interface is observation-only: the UVM
// coherence monitor reads it, and the embedded SVA enforce the industry-style
// ordering contract (clean the write-back D$ -> invalidate the I$ -> commit).

interface cpu_coherence_if #(
    parameter int unsigned IMEM_DEPTH = 64
)(
    input logic clk,
    input logic rst_n
);

    // Coherence controller handshake
    logic                    coh_start;   // FENCE.I ready to sync (from ROB)
    logic                    coh_done;    // sync complete; FENCE.I may commit

    // D-cache clean-all
    logic                    flush_req;
    logic                    flush_busy;
    logic                    flush_done;

    // I-cache invalidate
    logic                    inv_all;

    // D-cache backing-memory bus (used to count clean writeback beats)
    logic                    mem_req;
    logic                    mem_we;
    logic                    mem_ack;

    // FENCE.I commit / redirect from the ROB
    logic                    fence_commit;       // fence_i_commit_flush pulse
    logic [IMEM_DEPTH-1:0]   fence_redirect_pc;  // committing PC + 4

    // ---------------------------------------------------------------- SVA
    // The ordering contract only needs checking once a coherence episode runs;
    // when no FENCE.I executes none of these antecedents fire.

    // Invalidation must come *after* the D-cache clean has finished, so the
    // I-cache never re-reads pre-clean bytes from the shared memory.
    property p_clean_before_invalidate;
        @(posedge clk) disable iff (!rst_n)
        $rose(inv_all) |-> $past(flush_done);
    endproperty
    a_clean_before_invalidate: assert property (p_clean_before_invalidate)
        else $error("coherence: I$ invalidate asserted before D$ clean completed");

    // Invalidation stays asserted through the completion handshake so no stale
    // line can be re-fetched before the FENCE.I redirect takes effect.
    property p_inv_held_through_done;
        @(posedge clk) disable iff (!rst_n)
        coh_done |-> inv_all;
    endproperty
    a_inv_held_through_done: assert property (p_inv_held_through_done)
        else $error("coherence: inv_all dropped before coh_done");

    // A FENCE.I never commits/redirects unless the controller has reported the
    // caches synchronized (clean done + invalidate done).
    property p_commit_requires_done;
        @(posedge clk) disable iff (!rst_n)
        fence_commit |-> coh_done;
    endproperty
    a_commit_requires_done: assert property (p_commit_requires_done)
        else $error("coherence: FENCE.I committed before coherence completed");

    // A clean-all only runs as part of a coherence episode that the ROB started.
    property p_flush_needs_start;
        @(posedge clk) disable iff (!rst_n)
        $rose(flush_req) |-> coh_start;
    endproperty
    a_flush_needs_start: assert property (p_flush_needs_start)
        else $error("coherence: D$ clean started without a FENCE.I request");

    modport mon_mp (
        input clk, rst_n,
        input coh_start, coh_done,
        input flush_req, flush_busy, flush_done,
        input inv_all,
        input mem_req, mem_we, mem_ack,
        input fence_commit, fence_redirect_pc
    );

endinterface
