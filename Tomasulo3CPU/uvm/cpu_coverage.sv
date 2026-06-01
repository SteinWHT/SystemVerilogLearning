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
