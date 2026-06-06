class cpu_cfg extends uvm_object;

    typedef enum bit { CPU_MEM_LEGACY, CPU_MEM_AXI } memory_backend_e;

    uvm_active_passive_enum is_active         = UVM_ACTIVE;
    memory_backend_e        memory_backend    = CPU_MEM_LEGACY;
    bit                     enable_scoreboard = 1;
    bit                     enable_dcache_scoreboard = 1;
    bit                     enable_spike_scoreboard = 0;
    bit                     enable_coverage   = 0;
    bit                     enable_baremetal_coverage = 0;
    bit                     enable_ref_model  = 0;
    bit                     enable_operand_setup   = 1;
    real                    coverage_goal_pct = 100.0;

    // Scratch dmem lines for LD-based register setup (full 64-bit operands).
    // Pool is [setup_dmem_line, setup_dmem_line + slots). Default uses all of dmem_lines.
    int unsigned            setup_dmem_line        = 0;
    int unsigned            dmem_width             = 64;

    // Boot / memory map (match Tomasulo3CPU CPU_tb defaults)
    bit [63:0]              boot_pc           = 64'h0;
    int unsigned            imem_words        = 1024;
    int unsigned            dmem_lines        = 256;

    function int unsigned setup_dmem_slots();
        if (setup_dmem_line >= dmem_lines)
            return 0;
        return dmem_lines - setup_dmem_line;
    endfunction

    // Stimulus pacing
    int unsigned            instr_gap_cycles  = 0;
    int unsigned            drain_cycles      = 200;

    // Bare-metal / Spike-golden flow.
    string                  bm_test           = "unknown";
    string                  spike_trace_file  = "";
    bit [63:0]              dut_tohost_addr   = 64'h0;
    bit [63:0]              spike_tohost_addr = 64'h0;
    bit [63:0]              spike_base        = 64'h8000_0000;
    int unsigned            max_cycles        = 500000;

    // Scoreboard: match commit to stimulus by PC (robust for OOO) or strict FIFO order.
    typedef enum bit { CPU_SB_MATCH_PC, CPU_SB_MATCH_FIFO } sb_match_mode_e;
    sb_match_mode_e         sb_match_mode     = CPU_SB_MATCH_PC;

    `uvm_object_utils_begin(cpu_cfg)
        `uvm_field_enum(uvm_active_passive_enum, is_active,            UVM_ALL_ON)
        `uvm_field_enum(memory_backend_e, memory_backend,              UVM_ALL_ON)
        `uvm_field_int(enable_scoreboard,                              UVM_ALL_ON)
        `uvm_field_int(enable_dcache_scoreboard,                       UVM_ALL_ON)
        `uvm_field_int(enable_spike_scoreboard,                        UVM_ALL_ON)
        `uvm_field_int(enable_coverage,                                UVM_ALL_ON)
        `uvm_field_int(enable_baremetal_coverage,                      UVM_ALL_ON)
        `uvm_field_int(enable_ref_model,                               UVM_ALL_ON)
        `uvm_field_int(enable_operand_setup,                           UVM_ALL_ON)
        `uvm_field_real(coverage_goal_pct,                             UVM_ALL_ON)
        `uvm_field_int(setup_dmem_line,                                UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(dmem_width,                                     UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(boot_pc,                                        UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(imem_words,                                     UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(dmem_lines,                                     UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(instr_gap_cycles,                               UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(drain_cycles,                                   UVM_ALL_ON | UVM_DEC)
        `uvm_field_string(bm_test,                                     UVM_ALL_ON)
        `uvm_field_string(spike_trace_file,                            UVM_ALL_ON)
        `uvm_field_int(dut_tohost_addr,                                UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(spike_tohost_addr,                              UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(spike_base,                                     UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(max_cycles,                                     UVM_ALL_ON | UVM_DEC)
        `uvm_field_enum(sb_match_mode_e, sb_match_mode,                UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "cpu_cfg");
        super.new(name);
    endfunction

endclass
