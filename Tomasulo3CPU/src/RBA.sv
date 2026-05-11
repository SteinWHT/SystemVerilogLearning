module RBA #(
    parameter int unsigned ARCH_REG_COUNT = 32,
    localparam int unsigned ARCH_REG_WIDTH = $clog2(ARCH_REG_COUNT),
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned ROB_DEPTH = 16,
    localparam int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH),
    parameter int unsigned SB_DEPTH = 4,
    localparam int unsigned SB_INDEX_WIDTH = $clog2(SB_DEPTH)
) (
    input logic clk,
    input logic rst_n,

    // DISPATCH interface
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rs_phy_addr,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rt_phy_addr,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_new_rd_phy_addr,
    input logic dis_reg_write,

    output logic rs_data_ready,
    output logic rt_data_ready,

    // CDB interface
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd_phy_addr,
    input logic cdb_reg_write
);
    // 2 read ports for dispatch 
    // and 2 write ports: 1 for dispatch and new rd phy register rdy should be cleared
    // and 1 write port for CDB to set rdy to 1
    logic [PHY_REGISTER_FILE_WIDTH-1:0] prf_rdy_array;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prf_rdy_array <= '0;
        end else begin
            if (dis_reg_write) begin
                prf_rdy_array[dis_new_rd_phy_addr] <= 1'b0;
            end

            if (cdb_reg_write) begin
                prf_rdy_array[rd_phy_addr] <= 1'b1;
            end
        end
    end

    assign rs_data_ready = prf_rdy_array[dis_rs_phy_addr];
    assign rt_data_ready = prf_rdy_array[dis_rt_phy_addr];
    
endmodule 