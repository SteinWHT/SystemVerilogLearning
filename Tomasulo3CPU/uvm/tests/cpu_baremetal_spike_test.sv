class cpu_baremetal_spike_test extends cpu_base_test;
    `uvm_component_utils(cpu_baremetal_spike_test)

    string       imem_file;
    string       dmem_file;
    string       meta_file;
    bit [31:0]   tohost_value;

    function new(string name = "cpu_baremetal_spike_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        cfg.is_active                 = UVM_PASSIVE;
        cfg.enable_scoreboard         = 0;
        cfg.enable_spike_scoreboard   = 1;
        cfg.enable_coverage           = 0;
        cfg.enable_baremetal_coverage = 1;
        cfg.enable_ref_model          = 0;

        if (!$value$plusargs("IMEM_FILE=%s", imem_file))
            `uvm_fatal(get_type_name(), "Missing +IMEM_FILE=<path>")
        if (!$value$plusargs("DMEM_FILE=%s", dmem_file))
            `uvm_fatal(get_type_name(), "Missing +DMEM_FILE=<path>")
        if (!$value$plusargs("SPIKE_TRACE_FILE=%s", cfg.spike_trace_file))
            `uvm_fatal(get_type_name(), "Missing +SPIKE_TRACE_FILE=<path>")

        void'($value$plusargs("BM_TEST=%s", cfg.bm_test));
        void'($value$plusargs("BM_META_FILE=%s", meta_file));
        void'($value$plusargs("DUT_TOHOST_ADDR=%h", cfg.dut_tohost_addr));
        void'($value$plusargs("SPIKE_TOHOST_ADDR=%h", cfg.spike_tohost_addr));
        void'($value$plusargs("SPIKE_BASE=%h", cfg.spike_base));
        void'($value$plusargs("MAX_CYCLES=%d", cfg.max_cycles));

        if (meta_file != "")
            parse_meta_file(meta_file);

        if (cfg.dut_tohost_addr == 64'h0)
            `uvm_fatal(get_type_name(),
                "Missing DUT tohost address; pass +DUT_TOHOST_ADDR=<hex> or BM_META_FILE with DUT_TOHOST_ADDR")

        uvm_config_db#(cpu_cfg)::set(this, "env*", "cfg", cfg);
        uvm_config_db#(int)::set(this, "env.agt", "is_active", cfg.is_active);
    endfunction

    protected function void parse_meta_file(string path);
        int fd;
        string line;
        bit [63:0] value;

        fd = $fopen(path, "r");
        if (fd == 0)
            `uvm_fatal(get_type_name(), $sformatf("Cannot open bare-metal meta file: %0s", path))

        while ($fgets(line, fd)) begin
            if ($sscanf(line, "DUT_TOHOST_ADDR=0x%h", value) == 1)
                cfg.dut_tohost_addr = value;
            else if ($sscanf(line, "SPIKE_TOHOST_ADDR=0x%h", value) == 1)
                cfg.spike_tohost_addr = value;
            else if ($sscanf(line, "SPIKE_BASE=0x%h", value) == 1)
                cfg.spike_base = value;
        end
        $fclose(fd);
    endfunction

    task preload_images();
        `uvm_info(get_type_name(), $sformatf(
            "Preloading bare-metal images: BM_TEST=%0s IMEM=%0s DMEM=%0s TRACE=%0s TOHOST=0x%0h MAX_CYCLES=%0d",
            cfg.bm_test, imem_file, dmem_file, cfg.spike_trace_file,
            cfg.dut_tohost_addr, cfg.max_cycles), UVM_LOW)

        vif.clear_memories();
        vif.load_imem_file(imem_file);
        vif.load_dmem_file(dmem_file);
    endtask

    task wait_for_reset_release();
        while (!vif.rst_n)
            @(posedge vif.clk);
        @(posedge vif.clk);
    endtask

    task poll_tohost(output bit finished, output bit passed, output int unsigned cycles);
        finished = 0;
        passed   = 0;
        cycles   = 0;

        for (cycles = 0; cycles < cfg.max_cycles; cycles++) begin
            @(posedge vif.clk);
            #1step;
            tohost_value = vif.read_dmem_word32(cfg.dut_tohost_addr[CPU_DMEM_DEPTH-1:0]);
            if (tohost_value != 32'd0) begin
                finished = 1;
                passed   = (tohost_value == 32'd1);
                return;
            end
        end
    endtask

    task run_phase(uvm_phase phase);
        bit finished;
        bit passed;
        int unsigned cycles;

        phase.raise_objection(this);

        preload_images();
        wait_for_reset_release();
        poll_tohost(finished, passed, cycles);

        if (!finished) begin
            `uvm_error(get_type_name(), $sformatf(
                "[FAIL] %0s timeout waiting for tohost after %0d cycles",
                cfg.bm_test, cfg.max_cycles))
        end else if (!passed) begin
            `uvm_error(get_type_name(), $sformatf(
                "[FAIL] %0s DUT tohost=0x%0h expected 1", cfg.bm_test, tohost_value))
        end else begin
            `uvm_info(get_type_name(), $sformatf(
                "[PASS] %0s DUT tohost=1 after %0d cycles", cfg.bm_test, cycles), UVM_LOW)
        end

        repeat (2) @(posedge vif.clk);
        phase.drop_objection(this);
    endtask
endclass
