module PRF #(
    parameter int unsigned REG_FILE_DATA_WIDTH = 64,
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7
) (
    input logic clk,
    input logic rst_n,

    // ROB interface
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   rt_sb_phy_addr,

    // SB interface
    output logic [REG_FILE_DATA_WIDTH-1:0]      rt_sb_data,

    // CDB interface
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   cdb_rd_phy_addr,
    input logic [REG_FILE_DATA_WIDTH-1:0]       cdb_rd_data,
    input logic                                 cdb_reg_write,

    // CSR commit write port (from ROB commit path)
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   csr_wr_phy_addr,
    input logic [REG_FILE_DATA_WIDTH-1:0]       csr_wr_data,
    input logic                                 csr_wr_en,

    // ISSUE interface
    // 7 read ports for issue
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   issue_rs_phy_addr_alu,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   issue_rt_phy_addr_alu,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   issue_rs_phy_addr_div,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   issue_rt_phy_addr_div,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   issue_rs_phy_addr_mul,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   issue_rt_phy_addr_mul,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   issue_rs_phy_addr_lsq,

    output logic [REG_FILE_DATA_WIDTH-1:0]      issue_rs_data_lsq,

    // EXE interface
    output logic [REG_FILE_DATA_WIDTH-1:0]      exe_rs_data_alu,
    output logic [REG_FILE_DATA_WIDTH-1:0]      exe_rt_data_alu,
    output logic [REG_FILE_DATA_WIDTH-1:0]      exe_rs_data_div,
    output logic [REG_FILE_DATA_WIDTH-1:0]      exe_rt_data_div,
    output logic [REG_FILE_DATA_WIDTH-1:0]      exe_rs_data_mul,
    output logic [REG_FILE_DATA_WIDTH-1:0]      exe_rt_data_mul
);

    localparam int unsigned NumPhyRegs = 1 << PHY_REGISTER_FILE_WIDTH;
    logic [REG_FILE_DATA_WIDTH-1:0] prf_data_array [NumPhyRegs];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NumPhyRegs; i++) begin
                prf_data_array[i] <= '0;
            end
        end else begin
            // CSR should have the highest priority
            if (csr_wr_en) begin
                prf_data_array[csr_wr_phy_addr] <= csr_wr_data;
            end else if (cdb_reg_write) begin
                prf_data_array[cdb_rd_phy_addr] <= cdb_rd_data;
            end
        end
    end

    // forwarding logic
    always_comb begin
        exe_rs_data_alu = ((issue_rs_phy_addr_alu == cdb_rd_phy_addr) && cdb_reg_write) ? cdb_rd_data : prf_data_array[issue_rs_phy_addr_alu];
        exe_rt_data_alu = ((issue_rt_phy_addr_alu == cdb_rd_phy_addr) && cdb_reg_write) ? cdb_rd_data : prf_data_array[issue_rt_phy_addr_alu];
        exe_rs_data_div = ((issue_rs_phy_addr_div == cdb_rd_phy_addr) && cdb_reg_write) ? cdb_rd_data : prf_data_array[issue_rs_phy_addr_div];
        exe_rt_data_div = ((issue_rt_phy_addr_div == cdb_rd_phy_addr) && cdb_reg_write) ? cdb_rd_data : prf_data_array[issue_rt_phy_addr_div];
        exe_rs_data_mul = ((issue_rs_phy_addr_mul == cdb_rd_phy_addr) && cdb_reg_write) ? cdb_rd_data : prf_data_array[issue_rs_phy_addr_mul];
        exe_rt_data_mul = ((issue_rt_phy_addr_mul == cdb_rd_phy_addr) && cdb_reg_write) ? cdb_rd_data : prf_data_array[issue_rt_phy_addr_mul];
        issue_rs_data_lsq = ((issue_rs_phy_addr_lsq == cdb_rd_phy_addr) && cdb_reg_write) ? cdb_rd_data : prf_data_array[issue_rs_phy_addr_lsq];
        rt_sb_data = ((rt_sb_phy_addr == cdb_rd_phy_addr) && cdb_reg_write) ? cdb_rd_data : prf_data_array[rt_sb_phy_addr];
    end

    // synthesis translate_off
    CSR_PRIORITY: assert property(@(posedge clk) disable iff (!rst_n)
        !(csr_wr_en && cdb_reg_write))
        else $error("cdb reg write can not be asserted when csr is being executed");
    // synthesis translate_on

endmodule
