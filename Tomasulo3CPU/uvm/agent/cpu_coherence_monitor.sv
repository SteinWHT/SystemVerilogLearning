// Observes the FENCE.I coherence handshake and publishes one
// cpu_coherence_item per episode (D$ clean -> I$ invalidate -> commit).
class cpu_coherence_monitor extends uvm_monitor;
    `uvm_component_utils(cpu_coherence_monitor)

    cpu_coh_vif_t                              vif;
    uvm_analysis_port #(cpu_coherence_tr)      ap_coh;

    function new(string name = "cpu_coherence_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap_coh = new("ap_coh", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(cpu_coh_vif_t)::get(this, "", "coh_vif", vif))
            `uvm_fatal("NOVIF", "Set cpu_coh_vif_t on cpu_coherence_monitor via config_db")
    endfunction

    task run_phase(uvm_phase phase);
        cpu_coherence_tr tr;

        // Per-episode accumulators.
        int unsigned wb_beats;
        int unsigned clean_cycles;
        bit          flush_done_seen;
        bit          inv_seen;
        bit          ordering_err;

        // Edge-detection state.
        bit          coh_start_prev;
        bit          coh_done_prev;
        bit          inv_prev;

        wb_beats = 0; clean_cycles = 0; flush_done_seen = 0;
        inv_seen = 0; ordering_err = 0;
        coh_start_prev = 0; coh_done_prev = 0; inv_prev = 0;

        forever begin
            @(posedge vif.clk);
            if (!vif.rst_n) begin
                wb_beats = 0; clean_cycles = 0; flush_done_seen = 0;
                inv_seen = 0; ordering_err = 0;
                coh_start_prev = 0; coh_done_prev = 0; inv_prev = 0;
                continue;
            end

            // New episode begins: reset accumulators.
            if (vif.coh_start && !coh_start_prev) begin
                wb_beats = 0; clean_cycles = 0; flush_done_seen = 0;
                inv_seen = 0; ordering_err = 0;
            end

            // Count clean-all writeback beats and duration.
            if (vif.flush_busy) begin
                clean_cycles++;
                if (vif.mem_req && vif.mem_we && vif.mem_ack)
                    wb_beats++;
            end
            if (vif.flush_done)
                flush_done_seen = 1;

            // I-cache invalidation must follow a completed clean.
            if (vif.inv_all && !inv_prev) begin
                inv_seen = 1;
                if (!flush_done_seen)
                    ordering_err = 1;
            end

            // Episode completes at coh_done: publish the observed transaction.
            if (vif.coh_done && !coh_done_prev) begin
                tr = cpu_coherence_tr::type_id::create("coh_episode");
                tr.fence_pc     = vif.fence_redirect_pc;
                tr.wb_beats     = wb_beats;
                tr.clean_cycles = clean_cycles;
                tr.inv_seen     = inv_seen;
                tr.ordering_ok  = inv_seen && flush_done_seen && !ordering_err;
                `uvm_info(get_type_name(), tr.convert2string(), UVM_MEDIUM)
                ap_coh.write(tr);
            end

            coh_start_prev = vif.coh_start;
            coh_done_prev  = vif.coh_done;
            inv_prev       = vif.inv_all;
        end
    endtask
endclass
