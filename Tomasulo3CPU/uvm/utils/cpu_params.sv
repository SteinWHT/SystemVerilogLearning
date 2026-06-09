// Use typedef aliases so monitors, scoreboard, and commit items stay width-matched.

localparam int unsigned CPU_ROB_DEPTH               = 16;
localparam int unsigned CPU_ROB_INDEX_WIDTH         = $clog2(CPU_ROB_DEPTH);
localparam int unsigned CPU_INSTR_WIDTH             = 32;
localparam int unsigned CPU_IMEM_DEPTH              = 64;
localparam int unsigned CPU_IMEM_WIDTH              = 32;
localparam int unsigned CPU_DMEM_DEPTH              = 64;
localparam int unsigned CPU_DMEM_WIDTH              = 64;
localparam int unsigned CPU_REG_FILE_DATA_WIDTH     = 64;
localparam int unsigned CPU_ARCH_REG_WIDTH          = 5;
localparam int unsigned CPU_PHY_REGISTER_FILE_WIDTH = 7;
localparam int unsigned CPU_W_BYTE_NUM              = CPU_REG_FILE_DATA_WIDTH / 8;
localparam int unsigned CPU_TRAP_CAUSE_WIDTH        = 4;
localparam int unsigned CPU_CSR_ADDR_WIDTH          = 12;
localparam int unsigned CPU_CSR_CMD_WIDTH           = 3;
localparam int unsigned CPU_IMEM_WORDS              = 16384;
localparam int unsigned CPU_DMEM_LINES              = 16384;
localparam int unsigned CPU_MEM_IDX_BITS            = 16;
// Unified (von Neumann) memory: no instruction-window offset. Must match the
// AXI_IMEM_BASE_WORD used on the cpu_if instances in both tb tops so the
// virtual-interface vif typedefs stay type-compatible.
localparam int unsigned CPU_AXI_IMEM_BASE_WORD      = 0;

typedef cpu_commit_item #(
    CPU_ROB_INDEX_WIDTH,
    CPU_DMEM_DEPTH,
    CPU_IMEM_DEPTH,
    CPU_REG_FILE_DATA_WIDTH,
    CPU_ARCH_REG_WIDTH,
    CPU_PHY_REGISTER_FILE_WIDTH,
    CPU_W_BYTE_NUM,
    CPU_TRAP_CAUSE_WIDTH,
    CPU_CSR_ADDR_WIDTH,
    CPU_CSR_CMD_WIDTH
) cpu_commit_tr;

typedef virtual cpu_commit_if #(
    CPU_ROB_INDEX_WIDTH,
    CPU_DMEM_DEPTH,
    CPU_IMEM_DEPTH,
    CPU_REG_FILE_DATA_WIDTH,
    CPU_ARCH_REG_WIDTH,
    CPU_PHY_REGISTER_FILE_WIDTH,
    CPU_W_BYTE_NUM,
    CPU_TRAP_CAUSE_WIDTH,
    CPU_CSR_ADDR_WIDTH,
    CPU_CSR_CMD_WIDTH
) cpu_commit_vif_t;

typedef virtual cpu_if #(
    CPU_INSTR_WIDTH,
    CPU_IMEM_DEPTH,
    CPU_IMEM_WIDTH,
    CPU_DMEM_WIDTH,
    CPU_DMEM_DEPTH,
    CPU_W_BYTE_NUM,
    CPU_IMEM_WORDS,
    CPU_DMEM_LINES,
    CPU_MEM_IDX_BITS,
    CPU_AXI_IMEM_BASE_WORD
).mon_mp cpu_mon_vif_t;

typedef virtual cpu_if #(
    CPU_INSTR_WIDTH,
    CPU_IMEM_DEPTH,
    CPU_IMEM_WIDTH,
    CPU_DMEM_WIDTH,
    CPU_DMEM_DEPTH,
    CPU_W_BYTE_NUM,
    CPU_IMEM_WORDS,
    CPU_DMEM_LINES,
    CPU_MEM_IDX_BITS,
    CPU_AXI_IMEM_BASE_WORD
).drv_mp cpu_drv_vif_t;

// FENCE.I coherence observation (AXI DUT only).
typedef cpu_coherence_item #(CPU_IMEM_DEPTH) cpu_coherence_tr;

typedef virtual cpu_coherence_if #(
    CPU_IMEM_DEPTH
).mon_mp cpu_coh_vif_t;
