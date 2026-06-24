package cpu_pkg;
    import uvm_pkg::*;
    import riscv_types_pkg::*;
    import riscv_opcode_pkg::*;
    import riscv_funct_pkg::*;
`ifdef CPU_SPIKE_DPI
    import cpu_spike_dpi_pkg::*;
`endif

    `include "uvm_macros.svh"

    `include "utils/cpu_types.sv"
    `include "utils/cpu_isa_encoder.sv"

    `include "items/cpu_base_item.sv"
    `include "items/cpu_commit_item.sv"
    `include "items/cpu_add_item.sv"
    `include "items/cpu_sub_item.sv"
    `include "items/cpu_instr_item.sv"
    `include "items/cpu_spike_commit_item.sv"
    `include "items/cpu_coherence_item.sv"

    `include "utils/cpu_params.sv"
    `include "items/cpu_dcache_item.sv"
    `include "env/cpu_cfg.sv"
    `include "utils/cpu_instr_encoder.sv"
    `include "utils/cpu_reg_setup.sv"

    // Constrained-random program generator (depends on cpu_instr_item).
    `include "seq/cpu_rand_program.sv"

    `include "scoreboard/cpu_scoreboard.sv"
    `include "scoreboard/cpu_dcache_scoreboard.sv"
    `include "scoreboard/cpu_spike_scoreboard.sv"
`ifdef CPU_SPIKE_DPI
    `include "scoreboard/cpu_spike_dpi_scoreboard.sv"
`endif
    `include "scoreboard/cpu_coherence_scoreboard.sv"
    `include "ref/cpu_ref_model.sv"
    `include "agent/cpu_driver.sv"
    `include "agent/cpu_monitor.sv"
    `include "agent/cpu_dcache_monitor.sv"
    `include "agent/cpu_coherence_monitor.sv"
    `include "agent/cpu_sequencer.sv"
    `include "agent/cpu_agent.sv"
    `include "cov/cpu_coverage.sv"
    `include "cov/cpu_hazard_coverage.sv"
    `include "env/cpu_env.sv"

    `include "seq/cpu_base_seq.sv"
    `include "seq/cpu_add_seq.sv"
    `include "seq/cpu_sub_seq.sv"
    `include "seq/cpu_rand_program_seq.sv"

    `include "tests/cpu_base_test.sv"
    `include "tests/cpu_add_test.sv"
    `include "tests/cpu_int_alu_test.sv"
    `include "tests/cpu_baremetal_spike_test.sv"
    `include "tests/cpu_constrained_random_test.sv"

endpackage
