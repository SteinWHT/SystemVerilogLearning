// Checks every FENCE.I coherence episode and tracks functional coverage.
//
// Invariants (per RISC-V FENCE.I semantics on a write-back D$ + read-only I$):
//   - the D-cache clean completed before the I-cache was invalidated;
//   - the I-cache invalidation was actually performed;
//   - clean writebacks happen in whole 64-byte lines (8 x 64-bit beats).
class cpu_coherence_scoreboard extends uvm_subscriber #(cpu_coherence_tr);
    `uvm_component_utils(cpu_coherence_scoreboard)

    int unsigned episodes;
    int unsigned total_wb_beats;
    int unsigned ordering_fail;

    covergroup cg_coherence with function sample(
        int unsigned wb_lines,
        bit          ordering_ok
    );
        option.per_instance = 1;

        // Number of dirty lines cleaned to memory by this FENCE.I.
        cp_wb_lines: coverpoint wb_lines {
            bins none      = {0};
            bins one_line  = {1};
            bins few_lines = {[2:8]};
            bins many      = {[9:$]};
        }

        cp_ordering: coverpoint ordering_ok {
            bins ok  = {1'b1};
            bins bad = {1'b0};
        }
    endgroup

    function new(string name = "cpu_coherence_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        cg_coherence = new();
        episodes       = 0;
        total_wb_beats = 0;
        ordering_fail  = 0;
    endfunction

    virtual function void write(cpu_coherence_tr t);
        int unsigned wb_lines;
        wb_lines = t.wb_beats / 8;

        episodes++;
        total_wb_beats += t.wb_beats;

        if (!t.ordering_ok) begin
            ordering_fail++;
            `uvm_error(get_type_name(), $sformatf(
                "FENCE.I coherence ordering violated: %s", t.convert2string()))
        end

        if (!t.inv_seen)
            `uvm_error(get_type_name(), $sformatf(
                "FENCE.I committed without an I-cache invalidation: %s",
                t.convert2string()))

        if ((t.wb_beats % 8) != 0)
            `uvm_error(get_type_name(), $sformatf(
                "D-cache clean wrote a partial line (wb_beats=%0d, not a multiple of 8): %s",
                t.wb_beats, t.convert2string()))

        cg_coherence.sample(wb_lines, t.ordering_ok);
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(), $sformatf(
            "FENCE.I coherence episodes=%0d clean_writeback_words=%0d ordering_failures=%0d coverage=%.2f%%",
            episodes, total_wb_beats, ordering_fail, cg_coherence.get_coverage()), UVM_LOW)
        if (episodes == 0)
            `uvm_info(get_type_name(),
                "No FENCE.I executed in this program (coherence path not exercised)", UVM_LOW)
    endfunction

endclass
