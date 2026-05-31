class cpu_agent extends uvm_agent;
    `uvm_component_utils(cpu_agent)

    cpu_cfg       cfg;
    cpu_sequencer sqr;
    cpu_driver    drv;
    cpu_monitor   mon;

    function new(string name = "cpu_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(cpu_cfg)::get(this, "", "cfg", cfg)) begin
            cfg = cpu_cfg::type_id::create("cfg");
            cfg.is_active = get_is_active();
        end

        mon = cpu_monitor::type_id::create("mon", this);

        if (cfg.is_active == UVM_ACTIVE) begin
            sqr = cpu_sequencer::type_id::create("sqr", this);
            drv = cpu_driver::type_id::create("drv", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (cfg.is_active == UVM_ACTIVE)
            sqr.seq_item_port.connect(drv.seq_item_export);
    endfunction

endclass
