class cpu_cfg extends uvm_object;

    uvm_active_passive_enum is_active         = UVM_ACTIVE;
    bit                     enable_scoreboard = 1;
    bit                     enable_coverage   = 0;
    bit                     enable_ref_model  = 0;
    bit                     enable_operand_preload = 1;

    // Boot / memory map (match Tomasulo3CPU CPU_tb defaults)
    bit [63:0]              boot_pc           = 64'h0;
    int unsigned            imem_words        = 1024;
    int unsigned            dmem_lines        = 256;

    // Stimulus pacing
    int unsigned            instr_gap_cycles  = 0;
    int unsigned            drain_cycles      = 200;

    // Scoreboard: match commit to stimulus by PC (robust for OOO) or strict FIFO order.
    typedef enum bit { CPU_SB_MATCH_PC, CPU_SB_MATCH_FIFO } sb_match_mode_e;
    sb_match_mode_e         sb_match_mode     = CPU_SB_MATCH_PC;

    `uvm_object_utils_begin(cpu_cfg)
        `uvm_field_enum(uvm_active_passive_enum, is_active,            UVM_ALL_ON)
        `uvm_field_int(enable_scoreboard,                              UVM_ALL_ON)
        `uvm_field_int(enable_coverage,                                UVM_ALL_ON)
        `uvm_field_int(enable_ref_model,                               UVM_ALL_ON)
        `uvm_field_int(enable_operand_preload,                         UVM_ALL_ON)
        `uvm_field_int(boot_pc,                                        UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(imem_words,                                     UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(dmem_lines,                                     UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(instr_gap_cycles,                               UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(drain_cycles,                                   UVM_ALL_ON | UVM_DEC)
        `uvm_field_enum(sb_match_mode_e, sb_match_mode,                UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "cpu_cfg");
        super.new(name);
    endfunction

endclass
