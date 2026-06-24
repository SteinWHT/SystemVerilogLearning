// Online (DPI-C) Spike lockstep scoreboard.
//
// Preloads the Spike golden model with the *same* instruction + data image that
// is driven into the DUT, then steps Spike once per retired DUT commit and
// compares architectural effects (PC, integer rd write + value, store + addr).
// Tomasulo commits in program order from the ROB head, matching Spike's retire
// order, so a strict lockstep comparison is valid.
`uvm_analysis_imp_decl(_dpi_commit)

class cpu_spike_dpi_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(cpu_spike_dpi_scoreboard)

    uvm_analysis_imp_dpi_commit #(cpu_commit_tr, cpu_spike_dpi_scoreboard) imp_commit;

    cpu_cfg          cfg;
    cpu_rand_program program_;

    bit              ready;
    bit              done;          // tohost store observed -> stop comparing
    bit [63:0]       tohost_addr;

    int unsigned     commit_seen;
    int unsigned     compared;
    int unsigned     mismatches;

    function new(string name = "cpu_spike_dpi_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        imp_commit = new("imp_commit", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(cpu_cfg)::get(this, "", "cfg", cfg))
            cfg = cpu_cfg::type_id::create("cfg");
        // Optional handle injection through the config DB (test may also call
        // load_golden() directly).
        void'(uvm_config_db#(cpu_rand_program)::get(this, "", "program", program_));
    endfunction

    // ------------------------------------------------------------------
    // Build the golden image. Call from the test after generating the program
    // and before releasing reset, so Spike is ready before commits flow.
    // ------------------------------------------------------------------
    function void load_golden(cpu_rand_program prog = null);
        if (prog != null)
            program_ = prog;
        if (program_ == null)
            `uvm_fatal(get_type_name(), "load_golden called with no program")

        tohost_addr = program_.tohost_addr();

        spike_cosim_init(cfg.spike_isa, cfg.spike_priv,
                         longint'(cfg.spike_mem_base),
                         longint'(cfg.spike_mem_size),
                         longint'(program_.boot_pc));

        // Instruction image (4-byte words at contiguous PCs).
        foreach (program_.prog[i]) begin
            cpu_instr_item it = program_.prog[i];
            spike_cosim_write_u32(longint'(it.pc), int'(it.instr));
        end

        // Data region preload (8-byte aligned words).
        foreach (program_.data_init[addr])
            spike_cosim_write_word(longint'(addr), longint'(program_.data_init[addr]));

        ready = 1'b1;
        `uvm_info(get_type_name(), $sformatf(
            "Spike golden loaded: %0d instrs, %0d data words, tohost=0x%0h",
            program_.prog.size(), program_.data_init.num(), tohost_addr), UVM_LOW)
    endfunction

    // ------------------------------------------------------------------
    // Per-commit lockstep comparison.
    // ------------------------------------------------------------------
    virtual function void write_dpi_commit(cpu_commit_tr act);
        bit [63:0] exp_pc;
        int        exp_rd;
        bit [63:0] exp_wdata;
        bit        exp_store;
        bit [63:0] exp_store_addr;
        bit        act_rw_eff;
        bit        exp_rw_eff;

        commit_seen++;

        if (!ready) begin
            `uvm_warning(get_type_name(),
                "Commit observed before Spike golden was loaded; ignoring")
            return;
        end
        if (done)
            return; // post-tohost (self-loop) commits are not checked

        if (spike_cosim_step() == 0) begin
            `uvm_error(get_type_name(), "Spike model failed to step")
            mismatches++;
            return;
        end

        exp_pc         = spike_cosim_last_pc();
        exp_rd         = spike_cosim_last_rd();
        exp_wdata      = spike_cosim_last_wdata();
        exp_store      = (spike_cosim_last_store() != 0);
        exp_store_addr = spike_cosim_last_store_addr();

        exp_rw_eff = (exp_rd > 0);
        act_rw_eff = act.rw && (act.rd_addr != 5'd0);

        // PC
        if (act.pc !== exp_pc[CPU_IMEM_DEPTH-1:0]) begin
            `uvm_error(get_type_name(), $sformatf(
                "PC mismatch idx=%0d exp_pc=0x%0h act_pc=0x%0h (insn=0x%08h) act=%s",
                compared, exp_pc, act.pc, spike_cosim_last_insn(), act.convert2string()))
            mismatches++;
        end

        // Register write
        if (act_rw_eff !== exp_rw_eff) begin
            `uvm_error(get_type_name(), $sformatf(
                "Reg-write mismatch idx=%0d exp_rw=%0b act_rw=%0b exp_rd=%0d act=%s",
                compared, exp_rw_eff, act_rw_eff, exp_rd, act.convert2string()))
            mismatches++;
        end else if (act_rw_eff && exp_rw_eff) begin
            if (act.rd_addr !== exp_rd[CPU_ARCH_REG_WIDTH-1:0]) begin
                `uvm_error(get_type_name(), $sformatf(
                    "RD index mismatch idx=%0d exp_rd=x%0d act_rd=x%0d act=%s",
                    compared, exp_rd, act.rd_addr, act.convert2string()))
                mismatches++;
            end
            if (act.cdb_data !== exp_wdata) begin
                `uvm_error(get_type_name(), $sformatf(
                    "Writeback mismatch idx=%0d rd=x%0d exp=0x%016h act=0x%016h act=%s",
                    compared, exp_rd, exp_wdata, act.cdb_data, act.convert2string()))
                mismatches++;
            end
        end

        // Store
        if (act.mw !== exp_store) begin
            `uvm_error(get_type_name(), $sformatf(
                "Store-commit mismatch idx=%0d exp_mw=%0b act_mw=%0b act=%s",
                compared, exp_store, act.mw, act.convert2string()))
            mismatches++;
        end else if (act.mw && exp_store) begin
            if (act.sw_addr !== exp_store_addr[CPU_DMEM_DEPTH-1:0]) begin
                `uvm_error(get_type_name(), $sformatf(
                    "Store-addr mismatch idx=%0d exp_addr=0x%0h act_addr=0x%0h act=%s",
                    compared, exp_store_addr, act.sw_addr, act.convert2string()))
                mismatches++;
            end
            if (exp_store_addr === tohost_addr) begin
                done = 1'b1;
                `uvm_info(get_type_name(), $sformatf(
                    "tohost store reached at idx=%0d (compared=%0d mism=%0d)",
                    compared, compared, mismatches), UVM_LOW)
            end
        end

        compared++;
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        if (!ready) begin
            `uvm_warning(get_type_name(), "Spike golden was never loaded")
            return;
        end
        if (mismatches != 0) begin
            `uvm_error(get_type_name(), $sformatf(
                "Spike DPI scoreboard FAILED: mismatches=%0d compared=%0d commit_seen=%0d",
                mismatches, compared, commit_seen))
        end else if (!done) begin
            `uvm_error(get_type_name(), $sformatf(
                "Spike DPI scoreboard did not observe tohost store (compared=%0d commit_seen=%0d)",
                compared, commit_seen))
        end else begin
            `uvm_info(get_type_name(), $sformatf(
                "Spike DPI scoreboard PASSED: lockstep-matched %0d commits", compared), UVM_LOW)
        end
        spike_cosim_final();
    endfunction

endclass
