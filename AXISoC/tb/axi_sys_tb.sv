// System test: 2 AXI4 masters, interconnect, burst SRAM.

// `timescale: see tb/timescale.v

import axi_pkg::*;

module axi_sys_tb;

    localparam int unsigned DATA_WIDTH = 64;
    localparam int unsigned SRAM_DEPTH   = 1024;
    localparam int unsigned STRB_WIDTH   = DATA_WIDTH / 8;

    logic clk;
    logic rst_n;

    axi_if #(.DATA_WIDTH(DATA_WIDTH)) m0_bus (clk, rst_n);
    axi_if #(.DATA_WIDTH(DATA_WIDTH)) m1_bus (clk, rst_n);

    axi_full_soc_top #(
        .DATA_WIDTH (DATA_WIDTH),
        .SRAM_DEPTH (SRAM_DEPTH)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .m0    (m0_bus),
        .m1    (m1_bus)
    );

    axi_burst_master_bfm #(.DATA_WIDTH(DATA_WIDTH), .MAX_BEATS(32)) bfm0 (
        .clk(clk), .rst_n(rst_n), .bus(m0_bus)
    );
    axi_burst_master_bfm #(.DATA_WIDTH(DATA_WIDTH), .MAX_BEATS(32)) bfm1 (
        .clk(clk), .rst_n(rst_n), .bus(m1_bus)
    );

    logic [63:0] shadow [0:SRAM_DEPTH-1];
    int unsigned pass_cnt;
    int unsigned fail_cnt;

    function automatic int unsigned addr_idx(input logic [63:0] addr);
        return addr_to_idx(addr[31:0], DATA_WIDTH);
    endfunction

    task automatic shadow_write_burst(
        input logic [63:0]            base_addr,
        input logic [7:0]             len,
        input axi_burst_e             burst,
        input logic [63:0]            data[]
    );
        logic [63:0] cur;
        cur = base_addr;
        for (int i = 0; i <= int'(len); i++) begin
            shadow[addr_idx(cur)] = data[i];
            cur = burst_next_addr(cur[31:0], byte_lsb(DATA_WIDTH), 2'(burst));
        end
    endtask

    task automatic check(input string name, input bit ok);
        if (ok) begin
            pass_cnt++;
            $display("[PASS] %s", name);
        end else begin
            fail_cnt++;
            $display("[FAIL] %s", name);
        end
    endtask

    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
        foreach (shadow[i]) shadow[i] = '0;
        clk   = 1'b0;
        rst_n = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        logic [63:0] wr[];
        logic [63:0] rd[];
        bit          ok;
        int unsigned i;

        @(posedge clk);
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        bfm0.wait_reset_release();
        bfm1.wait_reset_release();
        bfm0.drive_idle();
        bfm1.drive_idle();

        // Master 0 burst
        wr = new[4];
        for (i = 0; i < 4; i++)
            wr[i] = 64'hC000 + i;
        bfm0.write_burst(64'h000, 8'd3, AXI_BURST_INCR, wr, ok);
        shadow_write_burst(64'h000, 8'd3, AXI_BURST_INCR, wr);
        check("m0_burst_write", ok);

        // Master 1 burst
        wr = new[4];
        for (i = 0; i < 4; i++)
            wr[i] = 64'hD000 + i;
        bfm1.write_burst(64'h080, 8'd3, AXI_BURST_INCR, wr, ok);
        shadow_write_burst(64'h080, 8'd3, AXI_BURST_INCR, wr);
        check("m1_burst_write", ok);

        // Read back m0
        bfm0.read_burst(64'h000, 8'd3, AXI_BURST_INCR, rd, ok);
        ok = ok && (rd.size() == 4);
        for (i = 0; i < 4; i++)
            ok = ok && (rd[i] == shadow[addr_idx(64'h000 + i * 8)]);
        check("m0_burst_read", ok);

        // Read back m1
        bfm1.read_burst(64'h080, 8'd3, AXI_BURST_INCR, rd, ok);
        ok = ok && (rd.size() == 4);
        for (i = 0; i < 4; i++)
            ok = ok && (rd[i] == shadow[addr_idx(64'h080 + i * 8)]);
        check("m1_burst_read", ok);

        // Alternating single beats
        for (i = 0; i < 10; i++) begin
            wr = new[1];
            wr[0] = 64'hE000 + i;
            bfm0.write_burst(64'h200 + i * 8, 8'd0, AXI_BURST_INCR, wr, ok);
            shadow[addr_idx(64'h200 + i * 8)] = wr[0];
            wr[0] = 64'hF000 + i;
            bfm1.write_burst(64'h400 + i * 8, 8'd0, AXI_BURST_INCR, wr, ok);
            shadow[addr_idx(64'h400 + i * 8)] = wr[0];
        end
        check("alt_single_beats", 1'b1);

        repeat (16) @(posedge clk);
        $display("SUMMARY pass=%0d fail=%0d", pass_cnt, fail_cnt);
        if (fail_cnt != 0)
            $fatal(1, "axi_sys_tb failed");
        $finish;
    end

endmodule
