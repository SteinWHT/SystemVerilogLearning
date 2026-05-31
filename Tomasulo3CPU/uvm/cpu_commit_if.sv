// Passive interface for Tomasulo3CPU ROB commit bind (rob_commit_monitor).
// In tb_top, connect lat_* / mon_* to dut.front_end.rob.u_rob_commit_mon.*
interface cpu_commit_if #(
    int unsigned ROB_INDEX_WIDTH         = 4,
    int unsigned DMEM_DEPTH              = 32,
    int unsigned IMEM_DEPTH              = 64,
    int unsigned REG_FILE_DATA_WIDTH     = 64,
    int unsigned ARCH_REG_WIDTH          = 5,
    int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    int unsigned W_BYTE_NUM              = 8,
    int unsigned TRAP_CAUSE_WIDTH        = 4,
    int unsigned CSR_ADDR_WIDTH          = 12,
    int unsigned CSR_CMD_WIDTH           = 3
)(
    input logic clk,
    input logic rst_n
);
    logic                                 rob_commit;

    // Combinational commit-head view
    logic                                 mon_commit_valid;
    logic [ROB_INDEX_WIDTH-1:0]           mon_commit_rob_tag;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]   mon_curr_phy;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]   mon_prev_phy;
    logic [ARCH_REG_WIDTH-1:0]            mon_rd_arch;
    logic                                 mon_reg_write;
    logic                                 mon_mem_write;
    logic [DMEM_DEPTH-1:0]                mon_sw_addr;
    logic [W_BYTE_NUM-1:0]                mon_sw_strb;
    logic [IMEM_DEPTH-1:0]                mon_pc;
    logic [TRAP_CAUSE_WIDTH-1:0]          mon_trap_cause;
    logic                                 mon_mret;
    logic                                 mon_is_csr;
    logic [CSR_ADDR_WIDTH-1:0]            mon_csr_addr;
    logic [CSR_CMD_WIDTH-1:0]             mon_csr_cmd;
    logic [ARCH_REG_WIDTH-1:0]            mon_rs1_arch;
    logic [REG_FILE_DATA_WIDTH-1:0]       mon_cdb_data;

    // Latched one-cycle snapshot
    logic                                 lat_valid;
    logic [ROB_INDEX_WIDTH-1:0]           lat_rob_tag;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]   lat_curr_phy;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]   lat_prev_phy;
    logic [ARCH_REG_WIDTH-1:0]            lat_rd_arch;
    logic                                 lat_reg_write;
    logic                                 lat_mem_write;
    logic [DMEM_DEPTH-1:0]                lat_sw_addr;
    logic [W_BYTE_NUM-1:0]                lat_sw_strb;
    logic [IMEM_DEPTH-1:0]                lat_pc;
    logic [TRAP_CAUSE_WIDTH-1:0]          lat_trap_cause;
    logic                                 lat_mret;
    logic                                 lat_is_csr;
    logic [CSR_ADDR_WIDTH-1:0]            lat_csr_addr;
    logic [CSR_CMD_WIDTH-1:0]             lat_csr_cmd;
    logic [ARCH_REG_WIDTH-1:0]            lat_rs1_arch;
    logic [REG_FILE_DATA_WIDTH-1:0]       lat_cdb_data;
    int unsigned                          lat_commit_count;

    modport mon_mp (
        input clk,
        input rst_n,
        input rob_commit,
        input lat_valid,
        input lat_rob_tag,
        input lat_curr_phy,
        input lat_prev_phy,
        input lat_rd_arch,
        input lat_reg_write,
        input lat_mem_write,
        input lat_sw_addr,
        input lat_sw_strb,
        input lat_pc,
        input lat_trap_cause,
        input lat_mret,
        input lat_is_csr,
        input lat_csr_addr,
        input lat_csr_cmd,
        input lat_rs1_arch,
        input lat_cdb_data,
        input lat_commit_count,
        input mon_commit_valid,
        input mon_commit_rob_tag,
        input mon_curr_phy,
        input mon_prev_phy,
        input mon_rd_arch,
        input mon_reg_write,
        input mon_mem_write,
        input mon_sw_addr,
        input mon_sw_strb,
        input mon_pc,
        input mon_trap_cause,
        input mon_mret,
        input mon_is_csr,
        input mon_csr_addr,
        input mon_csr_cmd,
        input mon_rs1_arch,
        input mon_cdb_data
    );

endinterface
