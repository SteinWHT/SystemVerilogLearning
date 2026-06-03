// System test: 2 masters through interconnect to shared SRAM.

// `timescale: see tb/timescale.v

import axi_pkg::*;

module axi_lite_sys_tb;

    localparam int unsigned DATA_WIDTH = 64;
    localparam int unsigned SRAM_DEPTH = 512;
    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;
    localparam int unsigned NUM_RANDOM = 100;

    logic clk;
    logic rst_n;

    axi_lite_if #(.DATA_WIDTH(DATA_WIDTH)) m0_bus (clk, rst_n);
    axi_lite_if #(.DATA_WIDTH(DATA_WIDTH)) m1_bus (clk, rst_n);

    axi_soc_top #(
        .DATA_WIDTH (DATA_WIDTH),
        .SRAM_DEPTH (SRAM_DEPTH)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .m0    (m0_bus),
        .m1    (m1_bus)
    );

    axi_master_bfm #(.DATA_WIDTH(DATA_WIDTH)) bfm0 (.clk(clk), .rst_n(rst_n), .bus(m0_bus));
    axi_master_bfm #(.DATA_WIDTH(DATA_WIDTH)) bfm1 (.clk(clk), .rst_n(rst_n), .bus(m1_bus));

    logic [63:0] shadow_mem [0:SRAM_DEPTH-1];
    int unsigned pass_cnt;
    int unsigned fail_cnt;

    function automatic int unsigned addr_idx(input logic [63:0] addr);
        return addr_to_idx(addr[31:0], DATA_WIDTH);
    endfunction

    task automatic shadow_write(
        input logic [63:0] addr,
        input logic [63:0] data,
        input logic [7:0]  strb
    );
        int unsigned idx;
        idx = addr_idx(addr);
        for (int i = 0; i < STRB_WIDTH; i++)
            if (strb[i])
                shadow_mem[idx][8*i +: 8] = data[8*i +: 8];
    endtask

    function automatic logic [63:0] shadow_read(input logic [63:0] addr);
        return shadow_mem[addr_idx(addr)];
    endfunction

    task automatic check_name(input string name, input bit ok);
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
        foreach (shadow_mem[i])
            shadow_mem[i] = '0;

        clk   = 1'b0;
        rst_n = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        logic [63:0] rd;
        logic [63:0] wr;
        bit          ok0, ok1, ok;

        @(posedge clk);
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        bfm0.wait_reset_release();
        bfm1.wait_reset_release();
        bfm0.drive_idle();
        bfm1.drive_idle();

        // Master 0 only
        wr = 64'hA5A5_0000_0000_0001;
        bfm0.write(64'h000, wr, {STRB_WIDTH{1'b1}}, ok0);
        shadow_write(64'h000, wr, {STRB_WIDTH{1'b1}});
        bfm0.read(64'h000, rd, ok0);
        check_name("m0_solo", ok0 && (rd == wr));

        // Master 1 only
        wr = 64'h5A5A_0000_0000_0002;
        bfm1.write(64'h010, wr, {STRB_WIDTH{1'b1}}, ok1);
        shadow_write(64'h010, wr, {STRB_WIDTH{1'b1}});
        bfm1.read(64'h010, rd, ok1);
        check_name("m1_solo", ok1 && (rd == wr));

        // Alternating masters (sequential — interconnect is single-flight)
        for (int i = 0; i < 20; i++) begin
            wr = 64'h3000 + i;
            bfm0.write(64'h100 + (i * 8), wr, {STRB_WIDTH{1'b1}}, ok0);
            shadow_write(64'h100 + (i * 8), wr, {STRB_WIDTH{1'b1}});
            wr = 64'h4000 + i;
            bfm1.write(64'h200 + (i * 8), wr, {STRB_WIDTH{1'b1}}, ok1);
            shadow_write(64'h200 + (i * 8), wr, {STRB_WIDTH{1'b1}});
            if (!ok0 || !ok1)
                check_name($sformatf("alt_%0d", i), 1'b0);
        end
        check_name("alt_writes", 1'b1);

        // Verify shadow
        for (int i = 0; i < 20; i++) begin
            bfm0.read(64'h100 + (i * 8), rd, ok0);
            check_name($sformatf("verify_m0_%0d", i),
                ok0 && (rd == shadow_read(64'h100 + (i * 8))));
            bfm1.read(64'h200 + (i * 8), rd, ok1);
            check_name($sformatf("verify_m1_%0d", i),
                ok1 && (rd == shadow_read(64'h200 + (i * 8))));
        end

        // Random single-master traffic
        for (int i = 0; i < NUM_RANDOM; i++) begin
            int unsigned idx;
            logic [63:0] addr;
            idx  = $urandom_range(0, SRAM_DEPTH - 4);
            addr = idx * 8;
            wr   = {$urandom, $urandom};
            if ($urandom_range(0, 1) == 0) begin
                bfm0.write_read_check(addr, wr, {STRB_WIDTH{1'b1}}, ok);
                if (ok) shadow_write(addr, wr, {STRB_WIDTH{1'b1}});
            end else begin
                bfm1.write_read_check(addr, wr, {STRB_WIDTH{1'b1}}, ok);
                if (ok) shadow_write(addr, wr, {STRB_WIDTH{1'b1}});
            end
            if (!ok)
                check_name($sformatf("random_%0d", i), 1'b0);
        end
        check_name("random_traffic", 1'b1);

        repeat (16) @(posedge clk);
        $display("SUMMARY pass=%0d fail=%0d", pass_cnt, fail_cnt);
        if (fail_cnt != 0)
            $fatal(1, "axi_lite_sys_tb failed");
        $finish;
    end

endmodule
