`uvm_analysis_imp_decl(_spike_commit)

class cpu_spike_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(cpu_spike_scoreboard)

    uvm_analysis_imp_spike_commit #(cpu_commit_tr, cpu_spike_scoreboard) imp_commit;

    cpu_cfg                 cfg;
    cpu_spike_commit_item   exp_q[$];
    int unsigned            commit_seen;
    int unsigned            compared;
    int unsigned            mismatches;
    bit                     saw_tohost_store;

    function new(string name = "cpu_spike_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        imp_commit = new("imp_commit", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(cpu_cfg)::get(this, "", "cfg", cfg))
            cfg = cpu_cfg::type_id::create("cfg");
        load_trace(cfg.spike_trace_file);
    endfunction

    protected function void load_trace(string path);
        int fd;
        string line;
        int unsigned line_no;
        cpu_spike_commit_item item;

        if (path == "")
            `uvm_fatal(get_type_name(), "Missing +SPIKE_TRACE_FILE for Spike scoreboard")

        fd = $fopen(path, "r");
        if (fd == 0)
            `uvm_fatal(get_type_name(), $sformatf("Cannot open Spike trace file: %0s", path))

        while ($fgets(line, fd)) begin
            line_no++;
            if (line.len() == 0)
                continue;
            if (line.substr(0, 0) == "#")
                continue;

            item = cpu_spike_commit_item::type_id::create($sformatf("spike_exp_%0d", exp_q.size()));
            if (!item.parse_line(line)) begin
                `uvm_warning(get_type_name(),
                    $sformatf("Ignoring malformed Spike trace line %0d: %0s", line_no, line))
                continue;
            end
            exp_q.push_back(item);
        end
        $fclose(fd);

        if (exp_q.size() == 0)
            `uvm_fatal(get_type_name(), $sformatf("Spike trace has no commit entries: %0s", path))

        `uvm_info(get_type_name(),
            $sformatf("Loaded %0d Spike expected commits from %0s", exp_q.size(), path), UVM_LOW)
    endfunction

    virtual function void write_spike_commit(cpu_commit_tr act);
        cpu_spike_commit_item exp;
        bit act_rw_eff;
        bit exp_rw_eff;

        commit_seen++;

        if (saw_tohost_store && (compared >= exp_q.size()))
            return;

        if (compared >= exp_q.size()) begin
            `uvm_error(get_type_name(),
                $sformatf("Extra DUT commit after Spike trace end: idx=%0d %0s",
                    compared, act.convert2string()))
            mismatches++;
            return;
        end

        exp = exp_q[compared];
        act_rw_eff = act.rw && (act.rd_addr != 5'd0);
        exp_rw_eff = exp.rd_write && (exp.rd_addr != 5'd0);

        if (act.pc !== exp.pc[CPU_IMEM_DEPTH-1:0]) begin
            `uvm_error(get_type_name(), $sformatf(
                "PC mismatch idx=%0d exp_pc=0x%0h act_pc=0x%0h exp=%0s act=%0s",
                compared, exp.pc, act.pc, exp.convert2string(), act.convert2string()))
            mismatches++;
        end

        if (act_rw_eff !== exp_rw_eff) begin
            `uvm_error(get_type_name(), $sformatf(
                "Reg-write mismatch idx=%0d exp_rw=%0b act_rw=%0b exp=%0s act=%0s",
                compared, exp_rw_eff, act_rw_eff, exp.convert2string(), act.convert2string()))
            mismatches++;
        end

        if (act_rw_eff && exp_rw_eff) begin
            if (act.rd_addr !== exp.rd_addr) begin
                `uvm_error(get_type_name(), $sformatf(
                    "RD mismatch idx=%0d exp_rd=x%0d act_rd=x%0d exp=%0s act=%0s",
                    compared, exp.rd_addr, act.rd_addr, exp.convert2string(), act.convert2string()))
                mismatches++;
            end
            if (act.cdb_data !== exp.rd_data) begin
                logic [63:0] diff = exp.rd_data - act.cdb_data;
                if (diff == cfg.spike_base && act.cdb_data <= 64'h10000) begin
                    // Include the one-past-end initial stack pointer at 0x10000.
                end else begin
                    `uvm_error(get_type_name(), $sformatf(
                        "Writeback mismatch idx=%0d rd=x%0d exp=0x%016h act=0x%016h exp_item=%0s act=%0s",
                        compared, act.rd_addr, exp.rd_data, act.cdb_data,
                        exp.convert2string(), act.convert2string()))
                    mismatches++;
                end
            end
        end

        if (act.mw !== exp.mem_write) begin
            `uvm_error(get_type_name(), $sformatf(
                "Store commit mismatch idx=%0d exp_mw=%0b act_mw=%0b exp=%0s act=%0s",
                compared, exp.mem_write, act.mw, exp.convert2string(), act.convert2string()))
            mismatches++;
        end

        if (act.mw && exp.mem_addr_valid &&
            (act.sw_addr !== exp.mem_addr[CPU_DMEM_DEPTH-1:0])) begin
            `uvm_error(get_type_name(), $sformatf(
                "Store address mismatch idx=%0d exp_addr=0x%0h act_addr=0x%0h exp=%0s act=%0s",
                compared, exp.mem_addr, act.sw_addr, exp.convert2string(), act.convert2string()))
            mismatches++;
        end

        if (exp.mem_write && exp.mem_addr_valid &&
            (exp.mem_addr == cfg.dut_tohost_addr))
            saw_tohost_store = 1'b1;

        compared++;
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        if (mismatches != 0) begin
            `uvm_error(get_type_name(), $sformatf(
                "Spike scoreboard failed: mismatches=%0d compared=%0d expected=%0d",
                mismatches, compared, exp_q.size()))
        end else if (compared != exp_q.size()) begin
            `uvm_error(get_type_name(), $sformatf(
                "Spike scoreboard ended early: compared=%0d expected=%0d",
                compared, exp_q.size()))
        end else if (!saw_tohost_store) begin
            `uvm_error(get_type_name(), $sformatf(
                "Spike scoreboard did not observe expected tohost store at 0x%0h (compared=%0d expected=%0d)",
                cfg.dut_tohost_addr, compared, exp_q.size()))
        end else begin
            `uvm_info(get_type_name(), $sformatf(
                "Spike scoreboard matched %0d commits for %0s", compared, cfg.bm_test), UVM_LOW)
        end
    endfunction
endclass
