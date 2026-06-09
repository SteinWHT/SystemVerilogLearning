class cpu_base_test extends uvm_test;
    `uvm_component_utils(cpu_base_test)

    cpu_env                       env;
    cpu_cfg                       cfg;
    cpu_drv_vif_t                 vif;
    cpu_mon_vif_t                 mon_vif;
    cpu_commit_vif_t              commit_vif;
    cpu_coh_vif_t                 coh_vif;
    function new(string name = "cpu_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(cpu_drv_vif_t)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "tb_top must set virtual cpu_if.drv_mp for uvm_test_top")
        if (!uvm_config_db#(cpu_mon_vif_t)::get(this, "", "mon_vif", mon_vif))
            `uvm_fatal("NOVIF", "tb_top must set cpu_mon_vif_t for uvm_test_top")
        if (!uvm_config_db#(cpu_commit_vif_t)::get(this, "", "commit_vif", commit_vif))
            `uvm_fatal("NOVIF", "tb_top must set cpu_commit_vif_t for uvm_test_top")
        if (!uvm_config_db#(cpu_cfg)::get(this, "", "cfg", cfg)) begin
            cfg = cpu_cfg::type_id::create("cfg");
            uvm_config_db#(cpu_cfg)::set(this, "*", "cfg", cfg);
        end

        // Coherence observation is optional: only the AXI DUT publishes it.
        if (uvm_config_db#(cpu_coh_vif_t)::get(this, "", "coh_vif", coh_vif))
            uvm_config_db#(cpu_coh_vif_t)::set(this, "env*", "coh_vif", coh_vif);

        uvm_config_db#(cpu_drv_vif_t)::set(this, "env*", "vif", vif);
        uvm_config_db#(cpu_mon_vif_t)::set(this, "env.agt*", "mon_vif", mon_vif);
        uvm_config_db#(cpu_commit_vif_t)::set(this, "env.agt*", "commit_vif", commit_vif);
        uvm_config_db#(cpu_cfg)::set(this, "env*", "cfg", cfg);
        uvm_config_db#(int)::set(this, "env.agt", "is_active", cfg.is_active);

        env = cpu_env::type_id::create("env", this);
    endfunction

    // Drain ROB / pipeline after stimulus; override in derived tests as needed.
    task drain_pipeline(int unsigned cycles = 0);
        if (cycles == 0)
            cycles = cfg.drain_cycles;
        repeat (cycles) @(posedge vif.clk);
    endtask

    task run_phase(uvm_phase phase);
        // Derived tests raise/drop objections and start sequences here.
    endtask

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);

        if (vif.memory_error)
            `uvm_error(get_type_name(),
                "Memory subsystem reported a sticky protocol/error response")

        `uvm_info(get_type_name(), $sformatf(
            "D-cache statistics: hits=%0d misses=%0d backend=%s",
            vif.dcache_hits, vif.dcache_misses,
            (cfg.memory_backend == cpu_cfg::CPU_MEM_AXI) ? "AXI" : "legacy"),
            UVM_LOW)
    endfunction

endclass
