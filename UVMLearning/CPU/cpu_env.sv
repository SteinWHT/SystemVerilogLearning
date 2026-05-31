class cpu_env extends uvm_env;
    `uvm_component_utils(cpu_env)

    cpu_cfg             cfg;
    cpu_agent           agt;
    cpu_scoreboard      sb;
    cpu_add_ref_model   rm;
    cpu_coverage        cov_commit;
    cpu_instr_coverage  cov_instr;

    function new(string name = "cpu_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(cpu_cfg)::get(this, "", "cfg", cfg)) begin
            cfg = cpu_cfg::type_id::create("cfg");
            `uvm_info(get_type_name(), "No cpu_cfg in config_db; using defaults", UVM_LOW)
        end
        uvm_config_db#(cpu_cfg)::set(this, "*", "cfg", cfg);

        agt = cpu_agent::type_id::create("agt", this);

        if (cfg.enable_scoreboard)
            sb = cpu_scoreboard::type_id::create("sb", this);

        if (cfg.enable_ref_model)
            rm = cpu_add_ref_model::type_id::create("rm", this);

        if (cfg.enable_coverage) begin
            cov_commit = cpu_coverage::type_id::create("cov_commit", this);
            cov_instr  = cpu_instr_coverage::type_id::create("cov_instr", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        if (cfg.enable_scoreboard) begin
            agt.mon.ap_commit.connect(sb.imp_commit);
            if (cfg.is_active == UVM_ACTIVE)
                agt.drv.ap_instr.connect(sb.imp_instr);
        end

        if (cfg.enable_ref_model && cfg.is_active == UVM_ACTIVE)
            agt.drv.ap_instr.connect(rm.imp_instr);

        if (cfg.enable_coverage) begin
            agt.mon.ap_commit.connect(cov_commit.analysis_export);
            if (cfg.is_active == UVM_ACTIVE)
                agt.drv.ap_instr.connect(cov_instr.analysis_export);
        end
    endfunction

endclass
