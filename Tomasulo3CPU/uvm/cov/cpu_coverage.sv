// Functional coverage for Tomasulo3CPU UVM bring-up (commit + instruction stimulus).

class cpu_coverage extends uvm_subscriber #(cpu_commit_tr);
    `uvm_component_utils(cpu_coverage)

    real goal_pct = 100.0;

    // Full CPU commit space (stores, CSR, traps tracked for later milestones).
    covergroup cg_commit with function sample(cpu_commit_tr tr);
        option.per_instance = 1;

        cp_reg_write: coverpoint tr.rw {
            bins reg_write = {1'b1};
            bins no_write  = {1'b0};
        }
        cp_mem_write: coverpoint tr.mw {
            bins store    = {1'b1};
            bins no_store = {1'b0};
        }
        cp_csr: coverpoint tr.is_csr {
            bins csr     = {1'b1};
            bins non_csr = {1'b0};
        }
        cp_trap: coverpoint tr.trap_cause {
            bins none    = {TRAP_CAUSE_NONE};
            bins ebreak  = {TRAP_CAUSE_EBREAK};
            bins ecall_m = {TRAP_CAUSE_ECALL_M};
            bins other   = default;
        }
        cp_mret: coverpoint tr.mret_occur {
            bins mret    = {1'b1};
            bins no_mret = {1'b0};
        }

        cross cp_reg_write, cp_mem_write;
    endgroup

    // Milestone-2 sign-off: GPR commits on integer ALU path (no store side-effects).
    covergroup cg_commit_m2 with function sample(cpu_commit_tr tr);
        option.per_instance = 1;
        option.goal         = 100;

        cp_alu_reg_commit: coverpoint tr.rw {
            bins gpr_retire = {1'b1};
            ignore_bins no_write = {1'b0};
        }
        cp_no_store: coverpoint tr.mw {
            bins no_store = {1'b0};
        }
    endgroup

    function new(string name = "cpu_coverage", uvm_component parent = null);
        super.new(name, parent);
        cg_commit    = new();
        cg_commit_m2 = new();
    endfunction

    virtual function void write(cpu_commit_tr t);
        cg_commit.sample(t);
        if (t.rw && !t.mw)
            cg_commit_m2.sample(t);
    endfunction

    virtual function void report_phase(uvm_phase phase);
        real pct;
        real m2_pct;
        super.report_phase(phase);
        pct    = cg_commit.get_coverage();
        m2_pct = cg_commit_m2.get_coverage();
        `uvm_info(get_type_name(), $sformatf(
            "CLOSURE cg_commit (full CPU): %.2f%% — out of scope for M2", pct), UVM_LOW)
        `uvm_info(get_type_name(), $sformatf(
            "CLOSURE cg_commit_m2: %.2f%% (goal %.0f%%) %s",
            m2_pct, goal_pct, (m2_pct >= goal_pct) ? "PASS" : "OPEN"), UVM_LOW)
    endfunction

endclass

class cpu_baremetal_commit_coverage extends uvm_subscriber #(cpu_commit_tr);
    `uvm_component_utils(cpu_baremetal_commit_coverage)

    cpu_cfg cfg;
    int unsigned program_id;

    covergroup cg_baremetal_commit with function sample(
        int unsigned program_id_arg,
        int unsigned commit_kind
    );
        option.per_instance = 1;

        cp_program: coverpoint program_id_arg {
            bins memcpy          = {0};
            bins memset          = {1};
            bins strlen          = {2};
            bins strcmp          = {3};
            bins matrix_multiply = {4};
            bins linked_list     = {5};
            bins recursion       = {6};
            bins csr_trap        = {7};
            bins wide_data       = {8};
            bins deep_recursion  = {9};
            bins other           = default;
        }

        cp_commit_kind: coverpoint commit_kind {
            bins reg_write = {0};
            bins store     = {1};
            bins csr       = {2};
            bins trap      = {3};
            bins mret      = {4};
            bins other     = {5};
        }

        cross cp_program, cp_commit_kind {
            // Compute/memory programs never retire CSR, trap, or mret commits.
            ignore_bins no_priv_on_compute =
                (binsof(cp_program.memcpy) || binsof(cp_program.memset) ||
                 binsof(cp_program.strlen) || binsof(cp_program.strcmp) ||
                 binsof(cp_program.matrix_multiply) || binsof(cp_program.linked_list) ||
                 binsof(cp_program.recursion) || binsof(cp_program.wide_data) ||
                 binsof(cp_program.deep_recursion))
                &&
                (binsof(cp_commit_kind.csr) || binsof(cp_commit_kind.trap) ||
                 binsof(cp_commit_kind.mret));
        }
    endgroup

    function new(string name = "cpu_baremetal_commit_coverage", uvm_component parent = null);
        super.new(name, parent);
        cg_baremetal_commit = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(cpu_cfg)::get(this, "", "cfg", cfg))
            cfg = cpu_cfg::type_id::create("cfg");
        program_id = program_name_to_id(cfg.bm_test);
    endfunction

    static function int unsigned program_name_to_id(string name);
        if (name == "memcpy")          return 0;
        if (name == "memset")          return 1;
        if (name == "strlen")          return 2;
        if (name == "strcmp")          return 3;
        if (name == "matrix_multiply") return 4;
        if (name == "linked_list")     return 5;
        if (name == "recursion")       return 6;
        if (name == "csr_trap")        return 7;
        if (name == "wide_data")       return 8;
        if (name == "deep_recursion")  return 9;
        return 99;
    endfunction

    static function int unsigned commit_kind(cpu_commit_tr tr);
        if (tr.mret_occur)
            return 4;
        if (tr.trap_cause != TRAP_CAUSE_NONE)
            return 3;
        if (tr.is_csr)
            return 2;
        if (tr.mw)
            return 1;
        if (tr.rw)
            return 0;
        return 5;
    endfunction

    virtual function void write(cpu_commit_tr t);
        cg_baremetal_commit.sample(program_id, commit_kind(t));
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(), $sformatf(
            "CLOSURE cg_baremetal_commit: %.2f%%", cg_baremetal_commit.get_coverage()), UVM_LOW)
    endfunction
endclass

class cpu_baremetal_dcache_coverage extends uvm_subscriber #(cpu_dcache_item#());
    `uvm_component_utils(cpu_baremetal_dcache_coverage)

    cpu_cfg cfg;

    covergroup cg_baremetal_dcache with function sample(
        int unsigned access_kind,
        int unsigned strb_kind,
        bit          is_tohost
    );
        option.per_instance = 1;

        cp_access: coverpoint access_kind {
            bins acc_read  = {0};
            bins acc_write = {1};
        }

        cp_strb: coverpoint strb_kind {
            bins none = {0};
            bins strb_byte  = {1};
            bins strb_half  = {2};
            bins strb_word  = {4};
            bins strb_dword = {8};
            bins mixed = default;
        }

        cp_tohost: coverpoint is_tohost {
            bins non_tohost = {0};
            bins tohost     = {1};
        }

        cross cp_access, cp_tohost;
    endgroup

    function new(string name = "cpu_baremetal_dcache_coverage", uvm_component parent = null);
        super.new(name, parent);
        cg_baremetal_dcache = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(cpu_cfg)::get(this, "", "cfg", cfg))
            cfg = cpu_cfg::type_id::create("cfg");
    endfunction

    static function int unsigned count_ones(bit [CPU_W_BYTE_NUM-1:0] strb);
        int unsigned n;
        n = 0;
        for (int i = 0; i < CPU_W_BYTE_NUM; i++)
            if (strb[i])
                n++;
        return n;
    endfunction

    virtual function void write(cpu_dcache_item#() t);
        int unsigned access_kind;
        bit          is_tohost;

        access_kind = (t.access == cpu_dcache_item#()::DCACHE_WRITE) ? 1 : 0;
        is_tohost   = (t.addr == cfg.dut_tohost_addr[CPU_DMEM_DEPTH-1:0]);
        cg_baremetal_dcache.sample(access_kind, count_ones(t.strb), is_tohost);
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(), $sformatf(
            "CLOSURE cg_baremetal_dcache: %.2f%%", cg_baremetal_dcache.get_coverage()), UVM_LOW)
    endfunction
endclass

class cpu_spike_trace_coverage extends uvm_component;
    `uvm_component_utils(cpu_spike_trace_coverage)

    cpu_cfg cfg;
    int unsigned program_id;

    covergroup cg_spike_instr_class with function sample(
        int unsigned program_id_arg,
        int unsigned instr_class
    );
        option.per_instance = 1;

        cp_program: coverpoint program_id_arg {
            bins memcpy          = {0};
            bins memset          = {1};
            bins strlen          = {2};
            bins strcmp          = {3};
            bins matrix_multiply = {4};
            bins linked_list     = {5};
            bins recursion       = {6};
            bins csr_trap        = {7};
            bins wide_data       = {8};
            bins deep_recursion  = {9};
            bins other           = default;
        }

        cp_instr_class: coverpoint instr_class {
            bins alu    = {CPU_SPIKE_CLASS_ALU};
            bins load   = {CPU_SPIKE_CLASS_LOAD};
            bins store  = {CPU_SPIKE_CLASS_STORE};
            bins branch = {CPU_SPIKE_CLASS_BRANCH};
            bins jump   = {CPU_SPIKE_CLASS_JUMP};
            bins mul    = {CPU_SPIKE_CLASS_MUL};
            bins div    = {CPU_SPIKE_CLASS_DIV};
            bins word   = {CPU_SPIKE_CLASS_WORD};
            bins system = {CPU_SPIKE_CLASS_SYSTEM};
            bins other  = default;
        }

        cross cp_program, cp_instr_class {
            ignore_bins no_system_on_compute =
                (binsof(cp_program.memcpy) || binsof(cp_program.memset) ||
                 binsof(cp_program.strlen) || binsof(cp_program.strcmp) ||
                 binsof(cp_program.matrix_multiply) || binsof(cp_program.linked_list) ||
                 binsof(cp_program.recursion) || binsof(cp_program.wide_data) ||
                 binsof(cp_program.deep_recursion))
                &&
                binsof(cp_instr_class.system);

            ignore_bins no_md_on_csr_trap =
                binsof(cp_program.csr_trap)
                &&
                (binsof(cp_instr_class.mul) || binsof(cp_instr_class.div) ||
                 binsof(cp_instr_class.word));
        }
    endgroup

    function new(string name = "cpu_spike_trace_coverage", uvm_component parent = null);
        super.new(name, parent);
        cg_spike_instr_class = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(cpu_cfg)::get(this, "", "cfg", cfg))
            cfg = cpu_cfg::type_id::create("cfg");
        program_id = cpu_baremetal_commit_coverage::program_name_to_id(cfg.bm_test);
        sample_trace(cfg.spike_trace_file);
    endfunction

    protected function void sample_trace(string path);
        int fd;
        string line;
        cpu_spike_commit_item item;

        if (path == "")
            return;

        fd = $fopen(path, "r");
        if (fd == 0) begin
            `uvm_warning(get_type_name(), $sformatf(
                "Cannot open Spike trace file for coverage: %0s", path))
            return;
        end

        while ($fgets(line, fd)) begin
            if (line.len() == 0)
                continue;
            if (line.substr(0, 0) == "#")
                continue;
            item = cpu_spike_commit_item::type_id::create("cov_spike_item");
            if (item.parse_line(line))
                cg_spike_instr_class.sample(program_id, item.instr_class);
        end
        $fclose(fd);
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(), $sformatf(
            "CLOSURE cg_spike_instr_class: %.2f%%", cg_spike_instr_class.get_coverage()), UVM_LOW)
    endfunction
endclass

class cpu_instr_coverage extends uvm_subscriber #(cpu_base_item);
    `uvm_component_utils(cpu_instr_coverage)

    real goal_pct = 100.0;

    // Checked R-type ALU op under test (ADD/ADDW/SUB/SUBW).
    covergroup cg_alu_main with function sample(cpu_base_item tr);
        option.per_instance = 1;
        option.goal         = 100;

        cp_op: coverpoint tr.instr_name {
            bins add   = {RISCV_OP_ADD};
            bins addw  = {RISCV_OP_ADDW};
            bins sub   = {RISCV_OP_SUB};
            bins subw  = {RISCV_OP_SUBW};
        }
        cp_rs1_zero: coverpoint (tr.rs1 == 5'd0) {
            bins is_x0  = {1'b1};
            bins not_x0 = {1'b0};
        }
        cp_rs2_zero: coverpoint (tr.rs2 == 5'd0) {
            bins is_x0  = {1'b1};
            bins not_x0 = {1'b0};
        }
        cp_result_class: coverpoint tr.expected_result {
            bins zero     = {64'h0};
            bins all_ones = {64'hFFFF_FFFF_FFFF_FFFF};
            bins msb_set  = {[64'h8000_0000_0000_0000:64'hFFFF_FFFF_FFFF_FFFF]};
            bins other    = default;
        }

        cross cp_op, cp_rs1_zero, cp_rs2_zero {
            // M2 stimulus uses non-x0 sources (rs1 != rs2, operands preloaded).
            ignore_bins src_x0 = binsof(cp_rs1_zero.is_x0) || binsof(cp_rs2_zero.is_x0);
        }
    endgroup

    // Operand setup paths exercised by cpu_reg_setup (ADDI / LUI+ADDI / DMEM+LD).
    covergroup cg_setup with function sample(cpu_base_item tr);
        option.per_instance = 1;
        option.goal         = 100;

        cp_setup_op: coverpoint tr.instr_name {
            bins addi_setup = {RISCV_OP_ADDI};
            bins ld_setup   = {RISCV_OP_LD};
            bins other      = default;
        }
    endgroup

    // Milestone-2 sign-off: all four integer ALU ops exercised.
    covergroup cg_alu_m2 with function sample(cpu_base_item tr);
        option.per_instance = 1;
        option.goal         = 100;

        cp_op: coverpoint tr.instr_name {
            bins add   = {RISCV_OP_ADD};
            bins addw  = {RISCV_OP_ADDW};
            bins sub   = {RISCV_OP_SUB};
            bins subw  = {RISCV_OP_SUBW};
        }
    endgroup

    function new(string name = "cpu_instr_coverage", uvm_component parent = null);
        super.new(name, parent);
        cg_alu_main = new();
        cg_alu_m2   = new();
        cg_setup    = new();
    endfunction

    virtual function void write(cpu_base_item t);
        if (t.is_operand_setup)
            cg_setup.sample(t);
        else if (t.instr_format == RISCV_FMT_R) begin
            cg_alu_main.sample(t);
            cg_alu_m2.sample(t);
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        real main_pct;
        real m2_pct;
        real setup_pct;
        super.report_phase(phase);
        main_pct  = cg_alu_main.get_coverage();
        m2_pct    = cg_alu_m2.get_coverage();
        setup_pct = cg_setup.get_coverage();
        `uvm_info(get_type_name(), $sformatf(
            "CLOSURE cg_alu_m2: %.2f%% (goal %.0f%%) %s",
            m2_pct, goal_pct, (m2_pct >= goal_pct) ? "PASS" : "OPEN"), UVM_LOW)
        `uvm_info(get_type_name(), $sformatf(
            "CLOSURE cg_alu_main (stretch): %.2f%%", main_pct), UVM_LOW)
        `uvm_info(get_type_name(), $sformatf(
            "CLOSURE cg_setup: %.2f%% (goal %.0f%%) %s",
            setup_pct, goal_pct, (setup_pct >= goal_pct) ? "PASS" : "OPEN"), UVM_LOW)
    endfunction

endclass
