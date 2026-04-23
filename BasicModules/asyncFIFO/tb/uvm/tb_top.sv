// UVM top: generates clocks/resets, instantiates DUT + fifo_if, starts UVM.

`timescale 1ns / 1ps

module tb_top;

    import uvm_pkg::*;
    import fifo_tb_pkg::*;

    logic dut_almost_full;
    logic dut_almost_empty;

    fifo_if #(.DATA_WIDTH(8)) vif ();

    // Async clocks (same idea as your plain SV testbench).
    initial begin
        vif.wclk = 1'b0;
        forever #10 vif.wclk = ~vif.wclk;
    end
    initial begin
        vif.rclk = 1'b0;
        forever #13 vif.rclk = ~vif.rclk;
    end

    initial begin
        vif.wr_rst_n = 1'b0;
        vif.rd_rst_n = 1'b0;
        vif.wr_en  = 1'b0;
        vif.rd_en  = 1'b0;
        vif.wr_data = '0;
        repeat (16) @(posedge vif.wclk);
        repeat (16) @(posedge vif.rclk);
        vif.wr_rst_n = 1'b1;
        vif.rd_rst_n = 1'b1;
    end

    async_fifo #(
        .DATA_WIDTH (8),
        .ADDR_WIDTH (4)
    ) dut (
        .wclk   (vif.wclk),
        .rclk   (vif.rclk),
        .wr_rst_n     (vif.wr_rst_n),
        .rd_rst_n     (vif.rd_rst_n),
        .wr_en  (vif.wr_en),
        .wr_data(vif.wr_data),
        .rd_en  (vif.rd_en),
        .rd_data(vif.rd_data),
        .full         (vif.full),
        .empty        (vif.empty),
        .almost_full  (dut_almost_full),
        .almost_empty (dut_almost_empty)
    );

    initial begin
        // All UVM components under uvm_test_top can get this handle with get(..., "", "vif", vif)
        uvm_config_db#(virtual fifo_if)::set(null, "uvm_test_top", "vif", vif);
        run_test("fifo_smoke_test");
    end

endmodule
