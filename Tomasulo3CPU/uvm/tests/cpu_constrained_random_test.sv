// Constrained-random RV64IM regression with configurable hazard density,
// checked in lockstep against the Spike DPI-C golden model.
//
// Knobs (all overridable on the command line, percentages 0..100):
//   +CR_NUM_INSTR=<n>          body instruction count
//   +CR_RAW_PCT=<p>            RAW source-dependency density
//   +CR_WAW_PCT=<p>            WAW destination-reuse density
//   +CR_LOAD_USE_PCT=<p>       load-use density
//   +CR_BRANCH_CLUSTER_PCT=<p> probability of opening a branch cluster
//   +CR_BRANCH_CLUSTER_SIZE=<n>branches per cluster
//   +CR_DEP_WINDOW=<n>         producer look-back window
//   +CR_SEED=<n>              optional generator seed (srandom)
class cpu_constrained_random_test extends cpu_base_test;
    `uvm_component_utils(cpu_constrained_random_test)

    cpu_rand_program program_;
    int unsigned     gen_seed = 0;
    bit              have_seed = 0;
    bit [31:0]       tohost_value;

    function new(string name = "cpu_constrained_random_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        // Legacy DUT only: the generator places code at PC 0 and its data region
        // low in the same memory, which matches the legacy behavioural I-cache /
        // unified dmem. The AXI DUT uses a split instruction window, so this test
        // is not meaningful there (run it with UVM_DUT=legacy).
        if (cfg.memory_backend != cpu_cfg::CPU_MEM_LEGACY)
            `uvm_fatal(get_type_name(),
                "cpu_constrained_random_test supports the legacy DUT only (use UVM_DUT=legacy)")

        // Active stimulus, but lay instructions contiguously (no operand-setup
        // prologue) so the program flows as a coherent RV64IM image.
        cfg.is_active                = UVM_ACTIVE;
        cfg.enable_operand_setup     = 0;
        cfg.enable_scoreboard        = 0;
        cfg.enable_dcache_scoreboard = 0;
        cfg.enable_spike_scoreboard  = 0;
        cfg.enable_coverage          = 0;
        cfg.enable_ref_model         = 0;
        cfg.enable_spike_dpi         = 1;
        cfg.enable_hazard_coverage   = 1;
        cfg.instr_gap_cycles         = 0;
        cfg.boot_pc                  = 64'h0;

        // Hazard / program knobs.
        void'($value$plusargs("CR_NUM_INSTR=%d",           cfg.cr_num_instr));
        void'($value$plusargs("CR_RAW_PCT=%d",             cfg.cr_raw_pct));
        void'($value$plusargs("CR_WAW_PCT=%d",             cfg.cr_waw_pct));
        void'($value$plusargs("CR_LOAD_USE_PCT=%d",        cfg.cr_load_use_pct));
        void'($value$plusargs("CR_BRANCH_CLUSTER_PCT=%d",  cfg.cr_branch_cluster_pct));
        void'($value$plusargs("CR_BRANCH_CLUSTER_SIZE=%d", cfg.cr_branch_cluster_size));
        void'($value$plusargs("CR_DEP_WINDOW=%d",          cfg.cr_dep_window));
        if ($value$plusargs("CR_SEED=%d", gen_seed))
            have_seed = 1;

        uvm_config_db#(cpu_cfg)::set(this, "env*", "cfg", cfg);
        uvm_config_db#(int)::set(this, "env.agt", "is_active", cfg.is_active);
    endfunction

    function void build_program();
        program_ = cpu_rand_program::type_id::create("program");
        if (have_seed)
            program_.srandom(gen_seed);

        // Hazard knobs are driven directly from the configuration (which the
        // command-line plusargs already populated), so the generated stimulus
        // is fully reproducible for a given seed + knob set.
        program_.num_instr           = cfg.cr_num_instr;
        program_.raw_pct             = cfg.cr_raw_pct;
        program_.waw_pct             = cfg.cr_waw_pct;
        program_.load_use_pct        = cfg.cr_load_use_pct;
        program_.branch_cluster_pct  = cfg.cr_branch_cluster_pct;
        program_.branch_cluster_size = cfg.cr_branch_cluster_size;
        program_.dep_window          = cfg.cr_dep_window;
        program_.boot_pc             = cfg.boot_pc;
        program_.data_base           = cfg.cr_data_base;
        program_.data_bytes          = cfg.cr_data_bytes;
        program_.data_ptr_reg        = 5'd31;
        program_.generate_program();
    endfunction

    // Mirror the generated data region into the DUT data memory.
    task preload_dut_data();
        foreach (program_.data_init[addr])
            vif.write_dmem_line(int'(addr >> 3), program_.data_init[addr]);
    endtask

    task wait_for_reset_release();
        while (!vif.rst_n)
            @(posedge vif.clk);
        @(posedge vif.clk);
    endtask

    task poll_tohost(output bit finished, output int unsigned cycles);
        bit [63:0] addr = program_.tohost_addr();
        finished = 0;
        for (cycles = 0; cycles < cfg.max_cycles; cycles++) begin
            @(posedge vif.clk);
            #1step;
            tohost_value = vif.read_dmem_word32(addr[CPU_DMEM_DEPTH-1:0]);
            if (tohost_value != 32'd0) begin
                finished = 1;
                return;
            end
        end
    endtask

    task run_phase(uvm_phase phase);
        cpu_rand_program_seq seq;
        bit finished;
        int unsigned cycles;

        phase.raise_objection(this);

        build_program();
        `uvm_info(get_type_name(), $sformatf(
            "Generated program: %0d instructions, data_base=0x%0h tohost=0x%0h",
            program_.prog.size(), program_.data_base, program_.tohost_addr()), UVM_LOW)

        // 1) Data image into the DUT, 2) instruction image via the driver,
        // 3) the identical image into the Spike golden model.
        preload_dut_data();

        seq = cpu_rand_program_seq::type_id::create("cr_seq");
        seq.program_ = program_;

`ifdef CPU_SPIKE_DPI
        if (env.sb_dpi != null)
            env.sb_dpi.load_golden(program_);
`endif

        seq.start(env.agt.sqr);

        vif.finish_preload();
        wait_for_reset_release();

        poll_tohost(finished, cycles);
        if (!finished)
            `uvm_error(get_type_name(), $sformatf(
                "Timeout waiting for tohost after %0d cycles", cfg.max_cycles))
        else
            `uvm_info(get_type_name(), $sformatf(
                "tohost reached after %0d cycles (value=0x%0h)", cycles, tohost_value), UVM_LOW)

        drain_pipeline();
        phase.drop_objection(this);
    endtask

endclass
