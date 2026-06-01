class cpu_base_test extends uvm_test;
    `uvm_component_utils(cpu_base_test)

    cpu_env                       env;
    cpu_cfg                       cfg;
    virtual cpu_if.drv_mp         vif;
    cpu_commit_vif_t              commit_vif;
    function new(string name = "cpu_base_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual cpu_if.drv_mp)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "tb_top must set virtual cpu_if.drv_mp for uvm_test_top")
        if (!uvm_config_db#(cpu_commit_vif_t)::get(this, "", "commit_vif", commit_vif))
            `uvm_fatal("NOVIF", "tb_top must set cpu_commit_vif_t for uvm_test_top")
        if (!uvm_config_db#(cpu_cfg)::get(this, "", "cfg", cfg)) begin
            cfg = cpu_cfg::type_id::create("cfg");
            uvm_config_db#(cpu_cfg)::set(this, "*", "cfg", cfg);
        end

        uvm_config_db#(virtual cpu_if.drv_mp)::set(this, "env.agt*", "vif", vif);
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

endclass
