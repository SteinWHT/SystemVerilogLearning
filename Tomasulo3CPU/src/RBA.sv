module RBA #(
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned PHY_REG_COUNT = 1 << PHY_REGISTER_FILE_WIDTH,
    parameter int unsigned ARCH_REG_COUNT = 32
) (
    input logic clk,
    input logic rst_n,

    // DISPATCH interface
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   dis_rs_phy_addr,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   dis_rt_phy_addr,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   dis_new_rd_phy_addr,
    input logic                                 dis_reg_write,

    output logic                                rs_data_ready,
    output logic                                rt_data_ready,

    // CDB interface
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   rd_phy_addr,
    input logic                                 cdb_reg_write
);
    // 2 read ports for dispatch
    // and 2 write ports: 1 for dispatch and new rd phy register rdy should be cleared
    // and 1 write port for CDB to set rdy to 1
    logic prf_rdy_array [PHY_REG_COUNT];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < PHY_REG_COUNT; i++) begin
                prf_rdy_array[i] <= (i < ARCH_REG_COUNT) ? 1'b1 : 1'b0;
            end
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
