`timescale 1ns/1ps

// FENCE.I cache-coherence controller.
//
// RISC-V leaves I$/D$ coherence to software: a hart must execute FENCE.I to
// make prior data stores visible to its own instruction fetch. This block
// implements the hardware side of that contract for a split L1 with a
// write-back D-cache and a read-only I-cache that share one backing memory.
//
// When the ROB signals that a completed FENCE.I sits at the commit head with
// the store buffer drained (coh_start), the controller performs, in order:
//
//   1. D-cache CLEAN  : write every dirty D$ line back to the shared memory so
//                       the new bytes are globally visible (dcache_flush_req
//                       held until dcache_flush_done).
//   2. I-cache INVALIDATE : drop all I$ lines (icache_inv_all). Held asserted
//                       through commit so no stale line can be re-fetched
//                       before the redirect takes effect.
//   3. coh_done       : release the ROB so FENCE.I commits and fetch is
//                       redirected to PC+4, now refilling from clean memory.
//
// The clean-before-invalidate order guarantees that any line speculatively
// refilled into the I$ during the clean is wiped before the redirected
// re-fetch observes the freshly cleaned memory.
module cache_coherence_ctrl (
    input  logic clk,
    input  logic rst_n,

    // From the core: a FENCE.I is ready to synchronize the caches.
    input  logic coh_start,

    // D-cache clean-all handshake.
    output logic dcache_flush_req,
    input  logic dcache_flush_done,

    // I-cache full invalidation.
    output logic icache_inv_all,

    // To the core: caches are synchronized; FENCE.I may commit.
    output logic coh_done
);

    typedef enum logic [1:0] {
        S_IDLE  = 2'd0,
        S_FLUSH = 2'd1,   // cleaning the D-cache
        S_INV   = 2'd2,   // invalidating the I-cache
        S_DONE  = 2'd3    // releasing the FENCE.I commit
    } state_e;

    state_e state_q;

    assign dcache_flush_req = (state_q == S_FLUSH);
    assign icache_inv_all   = (state_q == S_INV) || (state_q == S_DONE);
    assign coh_done         = (state_q == S_DONE);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= S_IDLE;
        end else begin
            unique case (state_q)
                S_IDLE:  if (coh_start)         state_q <= S_FLUSH;
                // Abort safely if the request disappears (should not happen for
                // the oldest in-flight instruction, but keeps the FSM live).
                S_FLUSH: if (!coh_start)         state_q <= S_IDLE;
                         else if (dcache_flush_done) state_q <= S_INV;
                S_INV:   if (!coh_start)         state_q <= S_IDLE;
                         else                    state_q <= S_DONE;
                // Hold invalidation + coh_done until the FENCE.I actually
                // commits (coh_start deasserts as the head advances).
                S_DONE:  if (!coh_start)         state_q <= S_IDLE;
                default:                         state_q <= S_IDLE;
            endcase
        end
    end

endmodule
