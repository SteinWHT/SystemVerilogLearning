module dcache_axi_bridge_tb;
    import axi_pkg::*;

    localparam int unsigned ADDR_WIDTH = 32;
    localparam int unsigned DATA_WIDTH = 64;
    localparam int unsigned ID_WIDTH   = 4;
    localparam int unsigned IDX_WIDTH  = 16;
    localparam int unsigned SRAM_DEPTH = 8192;

    logic clk;
    logic rst_n;

    logic                 mem_req;
    logic                 mem_we;
    logic [IDX_WIDTH-1:0] mem_idx;
    logic [DATA_WIDTH-1:0] mem_wdata;
    logic [DATA_WIDTH-1:0] mem_rdata;
    logic                 mem_ack;
    logic                 bridge_error;

    axi_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
             .ID_WIDTH(ID_WIDTH)) cache_axi (clk, rst_n);
    axi_if #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
             .ID_WIDTH(ID_WIDTH)) dma_axi (clk, rst_n);

    dcache_axi_master_bridge #(
        .MEM_IDX_WIDTH (IDX_WIDTH),
        .ADDR_WIDTH    (ADDR_WIDTH),
        .DATA_WIDTH    (DATA_WIDTH),
        .ID_WIDTH      (ID_WIDTH),
        .AXI_ID        (2)
    ) u_bridge (
        .clk          (clk),
        .rst_n        (rst_n),
        .mem_req      (mem_req),
        .mem_we       (mem_we),
        .mem_idx      (mem_idx),
        .mem_wdata    (mem_wdata),
        .mem_rdata    (mem_rdata),
        .mem_ack      (mem_ack),
        .error_sticky (bridge_error),
        .axi          (cache_axi)
    );

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
        .m0                 (cache_axi),
        .m1                 (dma_axi)
    );

    axi_burst_master_bfm #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .DEFAULT_ID (9)
    ) dma_bfm (
        .clk   (clk),
        .rst_n (rst_n),
        .bus   (dma_axi)
    );

    axi_assertions #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) u_cache_axi_assert (
        .clk   (clk),
        .rst_n (rst_n),
        .bus   (cache_axi)
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

    task automatic cache_mem_write(
        input logic [IDX_WIDTH-1:0]  idx,
        input logic [DATA_WIDTH-1:0] data,
        output bit                   ok
    );
        ok = 1'b0;
        @(negedge clk);
        mem_idx   = idx;
        mem_wdata = data;
        mem_we    = 1'b1;
        mem_req   = 1'b1;
        for (int cycles = 0; cycles < 200; cycles++) begin
            @(negedge clk);
            if (mem_ack) begin
                mem_req = 1'b0;
                mem_we  = 1'b0;
                ok      = 1'b1;
                return;
            end
        end
        mem_req = 1'b0;
        mem_we  = 1'b0;
    endtask

    task automatic cache_mem_read(
        input  logic [IDX_WIDTH-1:0]  idx,
        output logic [DATA_WIDTH-1:0] data,
        output bit                    ok
    );
        data = '0;
        ok   = 1'b0;
        @(negedge clk);
        mem_idx = idx;
        mem_we  = 1'b0;
        mem_req = 1'b1;
        for (int cycles = 0; cycles < 200; cycles++) begin
            @(negedge clk);
            if (mem_ack) begin
                data    = mem_rdata;
                mem_req = 1'b0;
                ok      = 1'b1;
                return;
            end
        end
        mem_req = 1'b0;
    endtask

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        logic [DATA_WIDTH-1:0] data;
        logic [DATA_WIDTH-1:0] dma_wr[];
        logic [DATA_WIDTH-1:0] dma_rd[];
        bit ok;
        bit dma_ok;
        bit cache_ok;

        pass_cnt  = 0;
        fail_cnt  = 0;
        rst_n     = 1'b0;
        mem_req   = 1'b0;
        mem_we    = 1'b0;
        mem_idx   = '0;
        mem_wdata = '0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        dma_bfm.wait_reset_release();
        dma_bfm.drive_idle();

        cache_mem_write(16'h0020, 64'h1122_3344_5566_7788, ok);
        check("cache_port_single_write", ok && !bridge_error);
        cache_mem_read(16'h0020, data, ok);
        check("cache_port_single_read",
              ok && data == 64'h1122_3344_5566_7788 && !bridge_error);

        dma_wr = new[8];
        foreach (dma_wr[i])
            dma_wr[i] = 64'hD000_0000_0000_0000 + 64'(i);
        dma_bfm.write_burst(32'h0800, 8'd7, AXI_BURST_INCR, dma_wr, dma_ok);
        check("dma_burst_preload", dma_ok);

        cache_mem_read(16'h0103, data, ok);
        check("cache_reads_dma_written_memory",
              ok && data == dma_wr[3] && !bridge_error);

        dma_wr = new[8];
        foreach (dma_wr[i])
            dma_wr[i] = 64'hE000_0000_0000_0000 + 64'(i);
        fork
            cache_mem_write(16'h0040, 64'hCAFE_BABE_DEAD_BEEF, cache_ok);
            dma_bfm.write_burst(32'h1000, 8'd7, AXI_BURST_INCR,
                                dma_wr, dma_ok);
        join
        check("cache_dma_contention_completes",
              cache_ok && dma_ok && !bridge_error);

        cache_mem_read(16'h0040, data, ok);
        check("cache_data_after_contention",
              ok && data == 64'hCAFE_BABE_DEAD_BEEF);
        dma_bfm.read_burst(32'h1000, 8'd7, AXI_BURST_INCR, dma_rd, dma_ok);
        foreach (dma_wr[i])
            dma_ok = dma_ok && dma_rd[i] == dma_wr[i];
        check("dma_data_after_contention", dma_ok);

        repeat (5) @(posedge clk);
        $display("SUMMARY pass=%0d fail=%0d", pass_cnt, fail_cnt);
        if (fail_cnt != 0)
            $fatal(1, "dcache_axi_bridge_tb failed");
        $finish;
    end

endmodule
