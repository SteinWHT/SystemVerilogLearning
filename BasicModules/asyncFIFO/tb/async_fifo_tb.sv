// Self-checking testbench for async_fifo (Questa / VCS / compatible simulators).
//
// Clock gating (power demo): free-running clocks are wclk_ungated / rclk_ungated; the DUT sees
// wclk / rclk through clock_gate_behavioral. Tie wclk_gate_en / rclk_gate_en high for normal runs.
// See docs/topic_clock_gating.md.

`timescale 1ns / 1ps

module async_fifo_tb;

    parameter int unsigned DATA_WIDTH  = 8;
    parameter int unsigned ADDR_WIDTH  = 4;  // depth = 16 (fast sim)
    parameter int unsigned DEPTH       = 1 << ADDR_WIDTH;
    parameter time         TW        = 10;  // wclk half-period (ns)
    parameter time         TR        = 13;  // rclk half-period — unrelated to wclk

    logic                    wclk_ungated;
    logic                    rclk_ungated;
    logic                    wclk;
    logic                    rclk;
    logic                    wclk_gate_en = 1'b1;
    logic                    rclk_gate_en = 1'b1;
    logic                    wr_rst_n;
    logic                    rd_rst_n;
    logic                    wr_en;
    logic [DATA_WIDTH-1:0]   wr_data;
    logic                    rd_en;
    logic [DATA_WIDTH-1:0]   rd_data;
    logic                    full;
    logic                    empty;
    logic                    almost_full;
    logic                    almost_empty;

    logic [DATA_WIDTH-1:0]   exp_queue[$];
    int unsigned             writes_ok;
    int unsigned             reads_ok;
    int unsigned             mon_errors;
    int unsigned             stim_errors;

    // rd_data is registered in memory on the cycle where rd_en && !empty;
    // compare one cycle later (rd_data_valid) so rd_data has settled.
    logic                    rd_data_valid;

    async_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) dut (
        .wclk          (wclk),
        .rclk          (rclk),
        .wr_rst_n      (wr_rst_n),
        .rd_rst_n      (rd_rst_n),
        .wr_en         (wr_en),
        .wr_data       (wr_data),
        .rd_en         (rd_en),
        .rd_data       (rd_data),
        .full          (full),
        .empty         (empty),
        .almost_full   (almost_full),
        .almost_empty  (almost_empty)
    );

    initial wclk_ungated = 1'b0;
    always #(TW) wclk_ungated = ~wclk_ungated;

    initial rclk_ungated = 1'b0;
    always #(TR) rclk_ungated = ~rclk_ungated;

    clock_gate_behavioral u_wclk_gate (
        .clk_i(wclk_ungated),
        .en_i (wclk_gate_en),
        .clk_o(wclk)
    );

    clock_gate_behavioral u_rclk_gate (
        .clk_i(rclk_ungated),
        .en_i (rclk_gate_en),
        .clk_o(rclk)
    );

    initial begin
        wr_rst_n    = 1'b0;
        rd_rst_n    = 1'b0;
        wr_en   = 1'b0;
        rd_en   = 1'b0;
        wr_data     = '0;
        stim_errors = 0;
        repeat (8) @(posedge wclk);
        repeat (8) @(posedge rclk);
        wr_rst_n = 1'b1;
        rd_rst_n = 1'b1;
        repeat (6) @(posedge wclk);
        repeat (6) @(posedge rclk);
    end

    // Record successful writes (same gating as memory / write pointer).
    always_ff @(posedge wclk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            writes_ok <= 0;
        end else if (wr_en && !full) begin
            writes_ok <= writes_ok + 1;
            exp_queue.push_back(wr_data);
        end
    end

    always_ff @(posedge rclk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rd_data_valid <= 1'b0;
        end else begin
            rd_data_valid <= rd_en && !empty;
        end
    end

    always_ff @(posedge rclk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            reads_ok   <= 0;
            mon_errors <= 0;
        end else if (rd_data_valid) begin
            reads_ok <= reads_ok + 1;
            if (exp_queue.size() == 0) begin
                $error("%t TB: read while scoreboard empty", $time);
                mon_errors <= mon_errors + 1;
            end else begin
                automatic logic [DATA_WIDTH-1:0] exp = exp_queue.pop_front();
                if (rd_data !== exp) begin
                    $error("%t TB: data mismatch exp=%h got=%h", $time, exp, rd_data);
                    mon_errors <= mon_errors + 1;
                end
            end
        end
    end

    // Stimulus
    initial begin
        wait (wr_rst_n === 1'b1 && rd_rst_n === 1'b1);
        @(posedge wclk);
        @(posedge wclk);

        // --- 1) Single word ---
        wr_data = 8'hA5;
        wr_en   = 1'b1;
        @(posedge wclk);
        wr_en = 1'b0;
        repeat (10) @(posedge rclk);
        rd_en = 1'b1;
        @(posedge rclk);
        rd_en = 1'b0;
        repeat (5) @(posedge rclk);

        // --- 2) Stream smaller than depth ---
        for (int i = 0; i < 7; i++) begin
            @(posedge wclk);
            wr_data = 8'(i + 1);
            wr_en   = 1'b1;
        end
        @(posedge wclk);
        wr_en = 1'b0;
        repeat (12) @(posedge rclk);
        repeat (7) begin
            @(posedge rclk);
            rd_en = 1'b1;
            @(posedge rclk);
            rd_en = 1'b0;
        end
        repeat (8) @(posedge rclk);

        // --- 3) Fill to full then verify no extra accepted writes ---
        begin
            int unsigned w0;
            @(posedge wclk);
            w0 = writes_ok;
            for (int j = 0; j < DEPTH + 5; j++) begin
                @(posedge wclk);
                wr_data = 8'(16 + j);
                wr_en   = 1'b1;
            end
            @(posedge wclk);
            wr_en = 1'b0;
            if ((writes_ok - w0) != DEPTH) begin
                $error(
                    "%t TB: expected %0d successful writes in fill phase, got %0d (writes_ok=%0d w0=%0d)",
                    $time, DEPTH, (writes_ok - w0), writes_ok, w0);
                stim_errors++;
            end
        end
        if (!full) begin
            $error("%t TB: expected full after %0d writes", $time, DEPTH);
            stim_errors++;
        end

        // One more write attempt while full — pointer must not advance
        begin
            int unsigned wcnt;
            @(posedge wclk);
            wcnt = writes_ok;
            wr_data = 8'hFF;
            wr_en   = 1'b1;
            @(posedge wclk);
            wr_en = 1'b0;
            if (writes_ok != wcnt) begin
                $error("%t TB: write while full should not increment count", $time);
                stim_errors++;
            end
        end

        // --- 4) Drain FIFO ---
        repeat (20) @(posedge rclk);
        while (!empty) begin
            @(posedge rclk);
            rd_en = 1'b1;
            @(posedge rclk);
            rd_en = 1'b0;
        end
        repeat (5) @(posedge rclk);
        if (exp_queue.size() != 0) begin
            $error("%t TB: scoreboard not empty after drain (left=%0d)", $time, exp_queue.size());
            stim_errors++;
        end
        if (!empty) begin
            $error("%t TB: expected empty after drain", $time);
            stim_errors++;
        end

        // --- 5) Concurrent traffic (bounded) ---
        fork
            begin
                for (int k = 0; k < 50; k++) begin
                    @(posedge wclk);
                    if (!full) begin
                        wr_data = 8'(k);
                        wr_en   = 1'b1;
                    end else begin
                        wr_en = 1'b0;
                    end
                end
                @(posedge wclk);
                wr_en = 1'b0;
            end
            begin
                for (int m = 0; m < 200; m++) begin
                    @(posedge rclk);
                    rd_en = (!empty) ? 1'b1 : 1'b0;
                end
                rd_en = 1'b0;
            end
        join
        repeat (40) @(posedge rclk);
        while (!empty) begin
            @(posedge rclk);
            rd_en = 1'b1;
            @(posedge rclk);
            rd_en = 1'b0;
        end
        rd_en = 1'b0;

        @(posedge rclk);
        if (mon_errors == 0 && stim_errors == 0 && exp_queue.size() == 0)
            $display("%t TB: PASS (writes_ok=%0d reads_ok=%0d)", $time, writes_ok, reads_ok);
        else
            $display("%t TB: FAIL mon_err=%0d stim_err=%0d sb_left=%0d", $time, mon_errors,
                     stim_errors, exp_queue.size());
        $finish;
    end

endmodule
