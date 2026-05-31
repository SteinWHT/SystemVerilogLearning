class cpu_monitor extends uvm_monitor;
    `uvm_component_utils(cpu_monitor)

    cpu_commit_vif_t commit_vif;
    cpu_cfg          cfg;

    uvm_analysis_port #(cpu_commit_tr) ap_commit;

    function new(string name = "cpu_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap_commit = new("ap_commit", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(cpu_commit_vif_t)::get(this, "", "commit_vif", commit_vif))
            `uvm_fatal("NOVIF", "Set cpu_commit_vif_t on cpu_monitor via config_db")
        void'(uvm_config_db#(cpu_cfg)::get(this, "", "cfg", cfg));
    endfunction

    task run_phase(uvm_phase phase);
        cpu_commit_tr obs;
        forever begin
            @(posedge commit_vif.clk);
            if (!commit_vif.rst_n)
                continue;
            // Sample registered lat_* after NBA updates (rob_commit_monitor).
            #1step;
            if (!commit_vif.lat_valid)
                continue;

            obs = cpu_commit_tr::type_id::create("obs");
            obs.sample_from_commit_if(commit_vif);
            if (obs.valid) begin
                `uvm_info(get_type_name(), $sformatf("Observed commit: %s", obs.convert2string()), UVM_MEDIUM)
                ap_commit.write(obs);
            end
        end
    endtask

endclass
