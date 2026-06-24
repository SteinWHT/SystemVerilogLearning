// Functional coverage for the constrained-random program: instruction-opcode
// coverage across the supported RV64IM subset, instruction-class mix, and the
// hazard scenarios the generator is built to stress (RAW / WAW / load-use /
// branch clusters), including producer-distance buckets.
class cpu_hazard_coverage extends uvm_subscriber #(cpu_base_item);
    `uvm_component_utils(cpu_hazard_coverage)

    cpu_instr_item cur;

    // ------------------------------------------------------------------
    // Opcode coverage over the generated subset. Ops the default generator
    // does not emit (privileged / JALR / AUIPC / NOP) are ignored so closure
    // reflects the active stimulus; enabling the matching knobs extends it.
    // ------------------------------------------------------------------
    covergroup cg_op with function sample(cpu_instr_item t);
        option.per_instance = 1;
        cp_op: coverpoint t.op {
            ignore_bins not_generated = {
                CPU_OP_JALR, CPU_OP_AUIPC, CPU_OP_NOP,
                CPU_OP_CSRRW, CPU_OP_CSRRS, CPU_OP_CSRRC,
                CPU_OP_CSRRWI, CPU_OP_CSRRSI, CPU_OP_CSRRCI,
                CPU_OP_ECALL, CPU_OP_EBREAK, CPU_OP_MRET
            };
        }
    endgroup

    covergroup cg_class with function sample(cpu_instr_item t);
        option.per_instance = 1;
        cp_class: coverpoint cpu_isa_encoder::class_of(t.op) {
            bins alu    = {CPU_SPIKE_CLASS_ALU};
            bins word   = {CPU_SPIKE_CLASS_WORD};
            bins mul    = {CPU_SPIKE_CLASS_MUL};
            bins div    = {CPU_SPIKE_CLASS_DIV};
            bins load   = {CPU_SPIKE_CLASS_LOAD};
            bins store  = {CPU_SPIKE_CLASS_STORE};
            bins branch = {CPU_SPIKE_CLASS_BRANCH};
            bins jump   = {CPU_SPIKE_CLASS_JUMP};
            bins system = {CPU_SPIKE_CLASS_SYSTEM};
        }
    endgroup

    // Hazard scenario coverage + producer distance.
    covergroup cg_hazard with function sample(cpu_instr_item t);
        option.per_instance = 1;
        cp_hazard: coverpoint t.hazard {
            bins none      = {CPU_HAZ_NONE};
            bins raw       = {CPU_HAZ_RAW};
            bins waw       = {CPU_HAZ_WAW};
            bins load_use  = {CPU_HAZ_LOAD_USE};
            bins branch    = {CPU_HAZ_BRANCH};
        }
        cp_dist: coverpoint t.dep_distance {
            bins d0       = {0};
            bins d1       = {1};
            bins d2_4     = {[2:4]};
            bins d5_8     = {[5:8]};
            bins d9_up    = {[9:$]};
        }
        // Dependency type by distance (RAW chains at various depths).
        cross cp_hazard, cp_dist {
            ignore_bins none_has_dist =
                binsof(cp_hazard.none) && !binsof(cp_dist.d0);
            ignore_bins waw_loaduse_far =
                (binsof(cp_hazard.load_use)) && !binsof(cp_dist.d1);
        }
    endgroup

    function new(string name = "cpu_hazard_coverage", uvm_component parent = null);
        super.new(name, parent);
        cg_op     = new();
        cg_class  = new();
        cg_hazard = new();
    endfunction

    virtual function void write(cpu_base_item t);
        if (!$cast(cur, t))
            return; // only generic generator items carry op/hazard metadata
        cg_op.sample(cur);
        cg_class.sample(cur);
        cg_hazard.sample(cur);
    endfunction

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info(get_type_name(), $sformatf(
            "CLOSURE cg_op=%.2f%% cg_class=%.2f%% cg_hazard=%.2f%%",
            cg_op.get_coverage(), cg_class.get_coverage(),
            cg_hazard.get_coverage()), UVM_LOW)
    endfunction

endclass
