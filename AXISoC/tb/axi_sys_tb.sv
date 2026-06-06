module axi_sys_tb;

    import axi_pkg::*;

    localparam int unsigned ADDR_WIDTH = 32;
    localparam int unsigned DATA_WIDTH = 64;
    localparam int unsigned ID_WIDTH   = 4;
    localparam int unsigned SRAM_DEPTH = 2048;

    logic clk;
    logic rst_n;

    axi_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
             .ID_WIDTH(ID_WIDTH)) m0_bus (clk, rst_n);
    axi_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
             .ID_WIDTH(ID_WIDTH)) m1_bus (clk, rst_n);

    axi_full_soc_top #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .SRAM_DEPTH (SRAM_DEPTH)
    ) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .sram_init_en       (1'b0),
        .sram_init_word_idx ('0),
        .sram_init_data     ('0),
        .m0                 (m0_bus),
        .m1                 (m1_bus)
    );

    axi_burst_master_bfm #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .DEFAULT_ID(1)
    ) bfm0 (
        .clk(clk), .rst_n(rst_n), .bus(m0_bus)
    );

    axi_burst_master_bfm #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .DEFAULT_ID(9)
    ) bfm1 (
        .clk(clk), .rst_n(rst_n), .bus(m1_bus)
    );

    axi_assertions #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
                     .ID_WIDTH(ID_WIDTH)) u_m0_assert (
        .clk(clk), .rst_n(rst_n), .bus(m0_bus)
    );
    axi_assertions #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
                     .ID_WIDTH(ID_WIDTH)) u_m1_assert (
        .clk(clk), .rst_n(rst_n), .bus(m1_bus)
    );
    int unsigned pass_cnt;
    int unsigned fail_cnt;

    task automatic check(input string name, input bit passed);
        if (passed) begin
            pass_cnt++;
            $display("[PASS] %s", name);
        end else begin
            fail_cnt++;
            $display("[FAIL] %s", name);
        end
    endtask

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        logic [DATA_WIDTH-1:0] wr0[];
        logic [DATA_WIDTH-1:0] wr1[];
        logic [DATA_WIDTH-1:0] rd0[];
        logic [DATA_WIDTH-1:0] rd1[];
        bit ok0;
        bit ok1;

        pass_cnt = 0;
        fail_cnt = 0;
        rst_n    = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        bfm0.wait_reset_release();
        bfm1.wait_reset_release();
        bfm0.drive_idle();
        bfm1.drive_idle();

        wr0 = new[8];
        wr1 = new[8];
        foreach (wr0[i]) begin
            wr0[i] = 64'h1000 + 64'(i);
            wr1[i] = 64'h2000 + 64'(i);
        end
        fork
            bfm0.write_burst(32'h0000, 8'd7, AXI_BURST_INCR, wr0, ok0);
            bfm1.write_burst(32'h0100, 8'd7, AXI_BURST_INCR, wr1, ok1);
        join
        check("concurrent_master_writes", ok0 && ok1);

        fork
            bfm0.read_burst(32'h0000, 8'd7, AXI_BURST_INCR, rd0, ok0);
            bfm1.read_burst(32'h0100, 8'd7, AXI_BURST_INCR, rd1, ok1);
        join
        foreach (wr0[i]) begin
            ok0 = ok0 && rd0[i] == wr0[i];
            ok1 = ok1 && rd1[i] == wr1[i];
        end
        check("concurrent_master_reads_with_ids", ok0 && ok1);

        wr0 = new[4];
        foreach (wr0[i])
            wr0[i] = 64'h3000 + 64'(i);
        fork
            bfm0.write_burst(32'h0200, 8'd3, AXI_BURST_INCR, wr0, ok0);
            bfm0.read_burst(32'h0000, 8'd3, AXI_BURST_INCR, rd0, ok1);
        join
        foreach (rd0[i])
            ok1 = ok1 && rd0[i] == (64'h1000 + 64'(i));
        check("same_master_simultaneous_aw_ar", ok0 && ok1);

        fork
            begin
                for (int i = 0; i < 16; i++) begin
                    wr0 = new[1];
                    wr0[0] = 64'h4000 + 64'(i);
                    bfm0.write_burst(32'h0400 + 32'(i * 8), 8'd0,
                                     AXI_BURST_INCR, wr0, ok0);
                    if (!ok0)
                        break;
                end
            end
            begin
                for (int i = 0; i < 16; i++) begin
                    wr1 = new[1];
                    wr1[0] = 64'h5000 + 64'(i);
                    bfm1.write_burst(32'h0600 + 32'(i * 8), 8'd0,
                                     AXI_BURST_INCR, wr1, ok1);
                    if (!ok1)
                        break;
                end
            end
        join
        check("round_robin_contention_no_starvation", ok0 && ok1);

        bfm0.read_burst(32'h0478, 8'd0, AXI_BURST_INCR, rd0, ok0);
        bfm1.read_burst(32'h0678, 8'd0, AXI_BURST_INCR, rd1, ok1);
        check("contention_data_integrity",
              ok0 && ok1 && rd0[0] == 64'h400f && rd1[0] == 64'h500f);

        repeat (5) @(posedge clk);
        $display("SUMMARY pass=%0d fail=%0d", pass_cnt, fail_cnt);
        if (fail_cnt != 0)
            $fatal(1, "axi_sys_tb failed");
        $finish;
    end

endmodule
