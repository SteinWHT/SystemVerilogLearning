// Use typedef aliases so monitors, scoreboard, and commit items stay width-matched.

localparam int unsigned CPU_ROB_DEPTH               = 16;
localparam int unsigned CPU_ROB_INDEX_WIDTH         = $clog2(CPU_ROB_DEPTH);
localparam int unsigned CPU_IMEM_DEPTH              = 64;
localparam int unsigned CPU_DMEM_DEPTH              = 32;
localparam int unsigned CPU_REG_FILE_DATA_WIDTH     = 64;
localparam int unsigned CPU_ARCH_REG_WIDTH          = 5;
localparam int unsigned CPU_PHY_REGISTER_FILE_WIDTH = 7;
localparam int unsigned CPU_W_BYTE_NUM              = CPU_REG_FILE_DATA_WIDTH / 8;
localparam int unsigned CPU_TRAP_CAUSE_WIDTH        = 4;
localparam int unsigned CPU_CSR_ADDR_WIDTH          = 12;
localparam int unsigned CPU_CSR_CMD_WIDTH           = 3;

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
