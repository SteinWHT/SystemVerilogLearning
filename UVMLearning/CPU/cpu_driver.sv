class cpu_driver extends uvm_driver #(cpu_base_item);
    `uvm_component_utils(cpu_driver)

    virtual cpu_if.drv_mp           vif;
    virtual cpu_backdoor_if.drv_mp  backdoor_vif;
    cpu_cfg                         cfg;

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
        void'(uvm_config_db#(virtual cpu_backdoor_if.drv_mp)::get(this, "", "backdoor_vif", backdoor_vif));
    endfunction

    task run_phase(uvm_phase phase);
        cpu_base_item tr;
        forever begin
            seq_item_port.get_next_item(tr);
            drive_item(tr);
            seq_item_port.item_done();
        end
    endtask

    virtual task drive_item(cpu_base_item tr);
        while (!vif.rst_n)
            @(posedge vif.clk);

        if (tr.pc == '0)
            tr.pc = cfg.boot_pc + next_pc_offset;

        tr.seq_id = seq_counter++;

        `uvm_info(get_type_name(), $sformatf("Drive: %s", tr.convert2string()), UVM_MEDIUM)

        preload_operands(tr);
        vif.load_instr(tr.pc[63:0], tr.instr);

        ap_instr.write(tr);

        next_pc_offset += 4;
        repeat (cfg.instr_gap_cycles) @(posedge vif.clk);
    endtask

    virtual task preload_operands(cpu_base_item tr);
        if (cfg == null || !cfg.enable_operand_preload || !tr.needs_operand_preload())
            return;
        if (backdoor_vif == null) begin
            `uvm_warning(get_type_name(),
                "enable_operand_preload set but backdoor_vif not connected; skipping PRF preload")
            return;
        end
        // After reset RRAT maps arch[i] -> phy[i].
        backdoor_vif.write_prf(tr.rs1, tr.rs1_data);
        backdoor_vif.write_prf(tr.rs2, tr.rs2_data);
    endtask

endclass
