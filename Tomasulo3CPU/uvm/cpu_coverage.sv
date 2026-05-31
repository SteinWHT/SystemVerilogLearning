class cpu_coverage extends uvm_subscriber #(cpu_commit_tr);
    `uvm_component_utils(cpu_coverage)

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

    function new(string name = "cpu_coverage", uvm_component parent = null);
        super.new(name, parent);
        cg_commit = new();
    endfunction

    virtual function void write(cpu_commit_tr t);
        cg_commit.sample(t);
    endfunction

endclass

// Instruction-side coverage (ADD/ADDW mix, register operands) — extend for new op families.
class cpu_instr_coverage extends uvm_subscriber #(cpu_base_item);
    `uvm_component_utils(cpu_instr_coverage)

    covergroup cg_instr with function sample(cpu_base_item tr);
        option.per_instance = 1;

        cp_op: coverpoint tr.instr_name {
            bins add   = {RISCV_OP_ADD};
            bins addw  = {RISCV_OP_ADDW};
            bins other = default;
        }
        cp_rd: coverpoint tr.rd {
            bins gpr[] = {[5'd1:5'd31]};
        }
        cp_rs1_zero: coverpoint (tr.rs1 == 5'd0) {
            bins is_x0  = {1'b1};
            bins not_x0 = {1'b0};
        }
        cp_rs2_zero: coverpoint (tr.rs2 == 5'd0) {
            bins is_x0  = {1'b1};
            bins not_x0 = {1'b0};
        }

        cross cp_op, cp_rs1_zero, cp_rs2_zero;
    endgroup

    function new(string name = "cpu_instr_coverage", uvm_component parent = null);
        super.new(name, parent);
        cg_instr = new();
    endfunction

    virtual function void write(cpu_base_item t);
        cg_instr.sample(t);
    endfunction

endclass
