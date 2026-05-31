`uvm_analysis_imp_decl(_instr)
`uvm_analysis_imp_decl(_commit)

// Pending register-write expectation produced from a driven instruction item.
class cpu_expect_entry extends uvm_object;
    int unsigned          seq_id;
    bit [63:0]            imem_word_idx;
    bit [4:0]             rd;
    bit [63:0]            expected;
    riscv_instr_name_e    instr_name;
    bit                   checks_enabled;

    `uvm_object_utils_begin(cpu_expect_entry)
        `uvm_field_int(seq_id,         UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(imem_word_idx,  UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(rd,              UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(expected,        UVM_ALL_ON | UVM_HEX)
        `uvm_field_enum(riscv_instr_name_e, instr_name, UVM_ALL_ON)
        `uvm_field_int(checks_enabled, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "cpu_expect_entry");
        super.new(name);
    endfunction

    static function cpu_expect_entry from_item(cpu_base_item t);
        cpu_expect_entry e = cpu_expect_entry::type_id::create("from_item");
        e.seq_id          = t.seq_id;
        e.imem_word_idx   = t.imem_word_index();
        e.rd              = t.rd;
        e.expected        = t.expected_result;
        e.instr_name      = t.instr_name;
        e.checks_enabled  = t.checks_enabled;
        return e;
    endfunction

endclass

class cpu_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(cpu_scoreboard)

    uvm_analysis_imp_instr  #(cpu_base_item, cpu_scoreboard) imp_instr;
    uvm_analysis_imp_commit #(cpu_commit_tr, cpu_scoreboard) imp_commit;

    cpu_cfg                 cfg;

    cpu_expect_entry        exp_q[$];
    int unsigned            instr_seen;
    int unsigned            commit_seen;
    int unsigned            reg_commit_seen;
    int unsigned            mismatches;

    function new(string name = "cpu_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        imp_instr  = new("imp_instr", this);
        imp_commit = new("imp_commit", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(cpu_cfg)::get(this, "", "cfg", cfg))
            cfg = cpu_cfg::type_id::create("cfg");
    endfunction

    virtual function void write_instr(cpu_base_item t);
        cpu_expect_entry entry;
        instr_seen++;
        if (!t.checks_enabled || !t.expects_reg_write())
            return;

        entry = cpu_expect_entry::from_item(t);
        exp_q.push_back(entry);

        `uvm_info(get_type_name(),
            $sformatf("Expect seq_id=%0d pc_word=0x%0h rd=x%0d data=0x%016h depth=%0d",
                entry.seq_id, entry.imem_word_idx, entry.rd, entry.expected, exp_q.size()), UVM_HIGH)
    endfunction

    virtual function void write_commit(cpu_commit_tr t);
        cpu_expect_entry entry;
        bit              found;
        int              match_idx;
        bit [63:0]       commit_word_idx;

        commit_seen++;
        if (!t.rw)
            return;

        reg_commit_seen++;
        commit_word_idx = t.pc_word_index();

        if (exp_q.size() == 0) begin
            `uvm_error(get_type_name(),
                $sformatf("Commit rd=x%0d pc_word=0x%0h cdb=0x%016h but no pending expectation",
                    t.rd_addr, commit_word_idx, t.cdb_data))
            mismatches++;
            return;
        end

        found     = find_expect(t, commit_word_idx, match_idx);
        entry     = exp_q[match_idx];
        exp_q.delete(match_idx);

        if (!found) begin
            `uvm_warning(get_type_name(),
                $sformatf("No PC match for commit pc_word=0x%0h rd=x%0d; using entry seq_id=%0d rd=x%0d",
                    commit_word_idx, t.rd_addr, entry.seq_id, entry.rd))
        end

        if (!check_commit(entry, t))
            mismatches++;
    endfunction

    // PC-first lookup; FIFO pop when cfg.sb_match_mode == CPU_SB_MATCH_FIFO.
    protected virtual function bit find_expect(
        cpu_commit_tr t,
        input bit [63:0] commit_word_idx,
        output int     match_idx
    );
        if (cfg.sb_match_mode == CPU_SB_MATCH_FIFO) begin
            match_idx = 0;
            return 1'b1;
        end

        foreach (exp_q[i]) begin
            if (exp_q[i].imem_word_idx == commit_word_idx) begin
                match_idx = i;
                return 1'b1;
            end
        end

        match_idx = 0;
        return 1'b0;
    endfunction

    // Override or extend per instruction family (mem ops, CSR, traps, ...).
    protected virtual function bit check_commit(cpu_expect_entry exp, cpu_commit_tr act);
        if (!exp.checks_enabled)
            return 1'b1;

        if (exp.rd != act.rd_addr) begin
            `uvm_error(get_type_name(), $sformatf(
                "RD mismatch seq_id=%0d exp_rd=x%0d act_rd=x%0d pc_word=0x%0h",
                exp.seq_id, exp.rd, act.rd_addr, exp.imem_word_idx))
            return 1'b0;
        end

        if (act.cdb_data !== exp.expected) begin
            `uvm_error(get_type_name(), $sformatf(
                "Data mismatch seq_id=%0d rd=x%0d pc_word=0x%0h exp=0x%016h got=0x%016h",
                exp.seq_id, act.rd_addr, exp.imem_word_idx, exp.expected, act.cdb_data))
            return 1'b0;
        end

        `uvm_info(get_type_name(), $sformatf(
            "Match seq_id=%0d rd=x%0d pc_word=0x%0h data=0x%016h pending=%0d",
            exp.seq_id, act.rd_addr, exp.imem_word_idx, act.cdb_data, exp_q.size()), UVM_MEDIUM)
        return 1'b1;
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        if (mismatches != 0 || exp_q.size() != 0) begin
            `uvm_error(get_type_name(), $sformatf(
                "Summary mismatches=%0d leftover_expects=%0d instr_seen=%0d commit_seen=%0d reg_commits=%0d",
                mismatches, exp_q.size(), instr_seen, commit_seen, reg_commit_seen))
        end else begin
            `uvm_info(get_type_name(), $sformatf(
                "All checked commits matched (instr_seen=%0d reg_commits=%0d)",
                instr_seen, reg_commit_seen), UVM_LOW)
        end
    endfunction

endclass
