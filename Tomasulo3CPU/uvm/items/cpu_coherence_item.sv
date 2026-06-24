// One FENCE.I I$/D$ coherence episode observed by cpu_coherence_monitor.
class cpu_coherence_item #(
    int unsigned PC_WIDTH = 64
) extends uvm_sequence_item;

    // Redirect target the FENCE.I committed to (committing PC + 4).
    rand bit [PC_WIDTH-1:0] fence_pc;

    // 64-bit words written back to shared memory while cleaning the D-cache.
    // A full dirty line is 8 beats, so this is a multiple of 8.
    rand int unsigned         wb_beats;

    // Cycles the D-cache clean-all engine was busy.
    rand int unsigned         clean_cycles;

    // The I-cache full invalidation was observed within the episode.
    rand bit                  inv_seen;

    // Monitor-local result: clean completed before invalidate, invalidate seen.
    rand bit                  ordering_ok;

    `uvm_object_param_utils_begin(cpu_coherence_item #(PC_WIDTH))
        `uvm_field_int(fence_pc,     UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(wb_beats,     UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(clean_cycles, UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(inv_seen,     UVM_ALL_ON)
        `uvm_field_int(ordering_ok,  UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "cpu_coherence_item");
        super.new(name);
    endfunction

    virtual function string convert2string();
        return $sformatf(
            "FENCE.I coherence: redirect_pc=0x%0h wb_beats=%0d clean_cycles=%0d inv=%0b ordering_ok=%0b",
            fence_pc, wb_beats, clean_cycles, inv_seen, ordering_ok);
    endfunction

endclass
