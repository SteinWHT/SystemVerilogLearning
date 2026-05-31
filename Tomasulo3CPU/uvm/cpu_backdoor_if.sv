// HDL backdoor for PRF operand preload and future CSR/debug access.
// tb_top implements the actual writes into the DUT hierarchy.
interface cpu_backdoor_if (
    input logic clk
);

    logic                               prf_wr_pending;
    logic [6:0]                         prf_wr_addr;
    logic [63:0]                        prf_wr_data;

    task automatic write_prf(
        input bit [6:0]   phy_addr,
        input bit [63:0]  data
    );
        prf_wr_addr    = phy_addr;
        prf_wr_data    = data;
        prf_wr_pending = 1'b1;
        @(posedge clk);
        prf_wr_pending = 1'b0;
    endtask

    modport drv_mp (
        input  clk,
        import write_prf
    );

    modport tb_mp (
        input  clk,
        input  prf_wr_pending,
        input  prf_wr_addr,
        input  prf_wr_data
    );

endinterface
