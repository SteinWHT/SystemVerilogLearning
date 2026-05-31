class cpu_add_test extends cpu_base_test;
    `uvm_component_utils(cpu_add_test)

    int unsigned num_add_instr  = 8;
    int unsigned num_addw_instr = 8;

    function new(string name = "cpu_add_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        void'(uvm_cmdline_processor::get().get_arg_value("+NUM_ADD=", num_add_instr));
        void'(uvm_cmdline_processor::get().get_arg_value("+NUM_ADDW=", num_addw_instr));
    endfunction

    task wait_for_reset_release();
        while (!vif.rst_n)
            @(posedge vif.clk);
        @(posedge vif.clk);
    endtask

    task run_add_seq(int unsigned count, bit is_addw);
        cpu_add_seq seq;
        seq = cpu_add_seq::type_id::create($sformatf("%s_seq", is_addw ? "addw" : "add"));
        if (!seq.randomize() with {
            num_instr == count;
            mix_addw  == is_addw;
        }) begin
            `uvm_fatal(get_type_name(), "cpu_add_seq randomize failed")
        end
        seq.start(env.agt.sqr);
    endtask

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        wait_for_reset_release();

        `uvm_info(get_type_name(), $sformatf(
            "Starting ADD/ADDW stimulus: num_add=%0d num_addw=%0d drain_cycles=%0d",
            num_add_instr, num_addw_instr, cfg.drain_cycles), UVM_LOW)

        run_add_seq(num_add_instr, 1'b0);
        run_add_seq(num_addw_instr, 1'b1);

        drain_pipeline();

        phase.drop_objection(this);
    endtask

endclass
