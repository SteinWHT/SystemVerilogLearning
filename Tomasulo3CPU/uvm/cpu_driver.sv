class cpu_driver extends uvm_driver #(cpu_base_item);
    `uvm_component_utils(cpu_driver)

    virtual cpu_if.drv_mp           vif;
    cpu_cfg                         cfg;
    cpu_reg_setup                   reg_setup;

    uvm_analysis_port #(cpu_base_item) ap_instr;

    int unsigned next_pc_offset;
    int unsigned seq_counter;

    function new(string name = "cpu_driver", uvm_component parent = null);
        super.new(name, parent);
        ap_instr = new("ap_instr", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual cpu_if.drv_mp)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Set virtual cpu_if.drv_mp on cpu_driver via config_db")
        if (!uvm_config_db#(cpu_cfg)::get(this, "", "cfg", cfg)) begin
            cfg = cpu_cfg::type_id::create("cfg");
            `uvm_info("NOCFG", "cpu_cfg not found; using defaults", UVM_LOW)
        end
    endfunction

    function void reg_setup_refresh();
        int unsigned saved_dmem_slot = 0;
        if (reg_setup != null)
            saved_dmem_slot = reg_setup.dmem_slot;
        reg_setup = new(vif, cfg, ap_instr, next_pc_offset, saved_dmem_slot);
    endfunction

    task run_phase(uvm_phase phase);
        cpu_base_item tr;
        reg_setup = new(vif, cfg, ap_instr, next_pc_offset, 0);
        forever begin
            seq_item_port.get_next_item(tr);
            drive_item(tr);
            seq_item_port.item_done();
        end
    endtask

    virtual task drive_item(cpu_base_item tr);
        // IMEM/DMEM backdoor loads are safe while rst_n=0; do not wait for reset here
        // or the CPU may execute before the full program image is written.
        if (tr.pc == '0)
            tr.pc = cfg.boot_pc + next_pc_offset;

        tr.seq_id = seq_counter++;

        `uvm_info(get_type_name(), $sformatf("Drive: %s", tr.convert2string()), UVM_MEDIUM)

        reg_setup_refresh();
        reg_setup.setup_operands(tr);
        next_pc_offset = reg_setup.next_pc_offset;

        tr.pc = cfg.boot_pc + next_pc_offset;
        vif.load_instr(tr.pc[63:0], tr.instr);
        ap_instr.write(tr);

        next_pc_offset += 4;
        repeat (cfg.instr_gap_cycles) @(posedge vif.clk);
    endtask

endclass
