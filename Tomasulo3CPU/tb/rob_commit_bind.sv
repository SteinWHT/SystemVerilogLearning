// Simulation-only ROB commit-head observer for future UVM hookup.
// Compile this file with the DUT; bind attaches without adding RTL ports.
`timescale 1ns/1ps

module rob_commit_monitor
    import riscv_types_pkg::*;
#(
    parameter int unsigned ROB_DEPTH               = 32,
    parameter int unsigned ROB_INDEX_WIDTH         = $clog2(ROB_DEPTH),
    parameter int unsigned DMEM_WIDTH              = 64,
    parameter int unsigned DMEM_DEPTH              = 32,
    parameter int unsigned IMEM_DEPTH              = 64,
    parameter int unsigned REG_FILE_DATA_WIDTH     = 64,
    parameter int unsigned ARCH_REG_COUNT          = 32,
    parameter int unsigned ARCH_REG_WIDTH          = $clog2(ARCH_REG_COUNT),
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned W_BYTE_NUM              = DMEM_WIDTH / 8
) (
    input logic clk,
    input logic rst_n,

    // Bound from ROB internals / existing commit outputs (no RTL port changes).
    input logic                                 commit_valid,
    input logic [ROB_INDEX_WIDTH-1:0]           commit_rob_tag,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   head_curr_phy,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   head_prev_phy,
    input logic [ARCH_REG_WIDTH-1:0]            head_rd_arch,
    input logic                                 head_rw,
    input logic                                 head_mw,
    input logic [DMEM_DEPTH-1:0]                head_sw_addr,
    input logic [W_BYTE_NUM-1:0]                head_sw_strb,
    input logic [IMEM_DEPTH-1:0]                head_pc,
    input trap_cause_t                          head_trap_cause,
    input logic                                 head_mret,
    input logic                                 head_is_csr,
    input csr_addr_t                            head_csr_addr,
    input csr_cmd_e                             head_csr_cmd,
    input logic [ARCH_REG_WIDTH-1:0]            head_rs1_arch,
    input logic [REG_FILE_DATA_WIDTH-1:0]       head_cdb_data
);

    // Combinational view of the retiring ROB head (valid while commit_valid).
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
    trap_cause_t                          mon_trap_cause;
    logic                                 mon_mret;
    logic                                 mon_is_csr;
    csr_addr_t                            mon_csr_addr;
    csr_cmd_e                             mon_csr_cmd;
    logic [ARCH_REG_WIDTH-1:0]            mon_rs1_arch;
    logic [REG_FILE_DATA_WIDTH-1:0]       mon_cdb_data;

    assign mon_commit_valid = commit_valid;
    assign mon_commit_rob_tag = commit_rob_tag;
    assign mon_curr_phy       = head_curr_phy;
    assign mon_prev_phy       = head_prev_phy;
    assign mon_rd_arch        = head_rd_arch;
    assign mon_reg_write      = head_rw;
    assign mon_mem_write      = head_mw;
    assign mon_sw_addr        = head_sw_addr;
    assign mon_sw_strb        = head_sw_strb;
    assign mon_pc             = head_pc;
    assign mon_trap_cause     = head_trap_cause;
    assign mon_mret           = head_mret;
    assign mon_is_csr         = head_is_csr;
    assign mon_csr_addr       = head_csr_addr;
    assign mon_csr_cmd        = head_csr_cmd;
    assign mon_rs1_arch       = head_rs1_arch;
    assign mon_cdb_data       = head_cdb_data;

    // Latched snapshot for UVM scoreboards / callbacks (one retire per cycle).
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
    trap_cause_t                          lat_trap_cause;
    logic                                 lat_mret;
    logic                                 lat_is_csr;
    csr_addr_t                            lat_csr_addr;
    csr_cmd_e                             lat_csr_cmd;
    logic [ARCH_REG_WIDTH-1:0]            lat_rs1_arch;
    logic [REG_FILE_DATA_WIDTH-1:0]       lat_cdb_data;
    int unsigned                          lat_commit_count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lat_valid        <= 1'b0;
            lat_rob_tag      <= '0;
            lat_curr_phy     <= '0;
            lat_prev_phy     <= '0;
            lat_rd_arch      <= '0;
            lat_reg_write    <= 1'b0;
            lat_mem_write    <= 1'b0;
            lat_sw_addr      <= '0;
            lat_sw_strb      <= '0;
            lat_pc           <= '0;
            lat_trap_cause   <= TRAP_CAUSE_NONE;
            lat_mret         <= 1'b0;
            lat_is_csr       <= 1'b0;
            lat_csr_addr     <= '0;
            lat_csr_cmd      <= CSR_CMD_NONE;
            lat_rs1_arch     <= '0;
            lat_cdb_data     <= '0;
            lat_commit_count <= 0;
        end else if (commit_valid) begin
            $display("[COMMIT] pc=0x%h rd=%0d val=0x%h count=%0d", head_pc, head_rd_arch, head_cdb_data, lat_commit_count);
            lat_valid        <= 1'b1;
            lat_rob_tag      <= commit_rob_tag;
            lat_curr_phy     <= head_curr_phy;
            lat_prev_phy     <= head_prev_phy;
            lat_rd_arch      <= head_rd_arch;
            lat_reg_write    <= head_rw;
            lat_mem_write    <= head_mw;
            lat_sw_addr      <= head_sw_addr;
            lat_sw_strb      <= head_sw_strb;
            lat_pc           <= head_pc;
            lat_trap_cause   <= head_trap_cause;
            lat_mret         <= head_mret;
            lat_is_csr       <= head_is_csr;
            lat_csr_addr     <= head_csr_addr;
            lat_csr_cmd      <= head_csr_cmd;
            lat_rs1_arch     <= head_rs1_arch;
            lat_cdb_data     <= head_cdb_data;
            lat_commit_count <= lat_commit_count + 1;
        end else begin
            lat_valid <= 1'b0;
        end
    end

endmodule

bind ROB rob_commit_monitor #(
    .ROB_DEPTH              (ROB_DEPTH),
    .ROB_INDEX_WIDTH        (ROB_INDEX_WIDTH),
    .DMEM_WIDTH             (DMEM_WIDTH),
    .DMEM_DEPTH             (DMEM_DEPTH),
    .IMEM_DEPTH             (IMEM_DEPTH),
    .REG_FILE_DATA_WIDTH    (REG_FILE_DATA_WIDTH),
    .ARCH_REG_COUNT         (ARCH_REG_COUNT),
    .ARCH_REG_WIDTH         (ARCH_REG_WIDTH),
    .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
    .W_BYTE_NUM             (W_BYTE_NUM)
) u_rob_commit_mon (
    .clk              (clk),
    .rst_n            (rst_n),
    .commit_valid     (enable),
    .commit_rob_tag   (read_ptr[ROB_INDEX_WIDTH-1:0]),
    .head_curr_phy    (head.curr_phy),
    .head_prev_phy    (head.prev_phy),
    .head_rd_arch     (head.rd_addr),
    .head_rw          (head.rw),
    .head_mw          (head.opclass == ROB_STORE),
    .head_sw_addr     (head.sw_addr),
    .head_sw_strb     (head.sw_strb),
    .head_pc          (head.pc),
    .head_trap_cause  (head.trap_cause),
    .head_mret        (head_is_mret),
    .head_is_csr      (head.opclass == ROB_CSR),
    .head_csr_addr    (head.csr_addr),
    .head_csr_cmd     (head.csr_cmd),
    .head_rs1_arch    (head.rs1_arch),
    .head_cdb_data    ((head.opclass == ROB_CSR) ? csr_rdata : sim_head_cdb_data)
);
