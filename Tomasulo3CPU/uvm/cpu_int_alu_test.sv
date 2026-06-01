// Phase-2 integer ALU regression: ADD/ADDW + SUB/SUBW with scoreboard and functional coverage.
class cpu_int_alu_test extends cpu_base_test;
    `uvm_component_utils(cpu_int_alu_test)

    int unsigned num_add_instr  = 4;
    int unsigned num_addw_instr = 4;
    int unsigned num_sub_instr  = 4;
    int unsigned num_subw_instr = 4;

    function new(string name = "cpu_int_alu_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        void'($value$plusargs("NUM_ADD=%d",  num_add_instr));
        void'($value$plusargs("NUM_ADDW=%d", num_addw_instr));
        void'($value$plusargs("NUM_SUB=%d",  num_sub_instr));
        void'($value$plusargs("NUM_SUBW=%d", num_subw_instr));

        cfg.enable_coverage = 1;
        uvm_config_db#(cpu_cfg)::set(this, "env*", "cfg", cfg);
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

    task run_sub_seq(int unsigned count, bit is_subw);
        cpu_sub_seq seq;
        seq = cpu_sub_seq::type_id::create($sformatf("%s_seq", is_subw ? "subw" : "sub"));
        if (!seq.randomize() with {
            num_instr == count;
            mix_subw  == is_subw;
        }) begin
            `uvm_fatal(get_type_name(), "cpu_sub_seq randomize failed")
        end
        seq.start(env.agt.sqr);
    endtask

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);

        `uvm_info(get_type_name(), $sformatf(
            "INT ALU regression: add=%0d addw=%0d sub=%0d subw=%0d drain=%0d cov=%0b",
            num_add_instr, num_addw_instr, num_sub_instr, num_subw_instr,
            cfg.drain_cycles, cfg.enable_coverage), UVM_LOW)

        run_add_seq(num_add_instr,  1'b0);
        run_add_seq(num_addw_instr, 1'b1);
        run_sub_seq(num_sub_instr,  1'b0);
        run_sub_seq(num_subw_instr, 1'b1);

        wait_for_reset_release();
        drain_pipeline();

        phase.drop_objection(this);
    endtask

endclass
