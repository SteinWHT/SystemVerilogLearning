// Load/Store buffer: D$, LSQ handshake, CDB issue, flush compaction.
/* verilator lint_off WIDTH */
// verilog_lint: waive-start explicit-parameter-storage-type
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module LSB_tb;
import riscv_types_pkg::*;
    parameter int unsigned LSB_DEPTH               = 4;
    parameter int unsigned DMEM_DEPTH              = 32;
    parameter int unsigned DMEM_WIDTH              = 64;
    parameter int unsigned ROB_DEPTH               = 16;
    localparam  int unsigned ROB_INDEX_WIDTH       = $clog2(ROB_DEPTH);
    parameter int unsigned ARCH_REG_WIDTH          = 5;
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7;
    parameter int unsigned REG_FILE_DATA_WIDTH     = 64;
    parameter int unsigned OPCODE_WIDTH            = 6;

    logic clk;
    logic rst_n;

    logic                               dcache_read_done;
    logic [DMEM_WIDTH-1:0]              dcache_data;
    logic                               dcache_ready;
    logic [DMEM_DEPTH-1:0]              dcache_addr;

    logic [OPCODE_WIDTH-1:0]      iss_lsb_opcode;
    logic [ROB_INDEX_WIDTH-1:0]         iss_lsb_rob_tag;
    logic [DMEM_DEPTH-1:0]              iss_lsb_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_lsb_phy_addr;
    logic                               iss_lsb_rdy;
    logic                               iss_lsb_ready;

    logic                               issue_ld_buf;
    logic                               ready_ld_buf;

    logic                               cdb_flush;
    logic [ROB_INDEX_WIDTH-1:0]         cdb_rob_depth;
    logic [ROB_INDEX_WIDTH-1:0]         lsb_rob_tag;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] lsb_rd_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0]     lsb_data;
    logic                               lsb_rw;
    logic [DMEM_DEPTH-1:0]              lsb_sw_addr;
    logic                               lsb_ready;

    logic [ROB_INDEX_WIDTH-1:0]         rob_top_ptr;

    LSB #(
        .LSB_DEPTH               (LSB_DEPTH),
        .DMEM_DEPTH              (DMEM_DEPTH),
        .DMEM_WIDTH              (DMEM_WIDTH),
        .ROB_DEPTH               (ROB_DEPTH),
        .ARCH_REG_WIDTH          (ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH (PHY_REGISTER_FILE_WIDTH),
        .REG_FILE_DATA_WIDTH     (REG_FILE_DATA_WIDTH),
        .OPCODE_WIDTH            (OPCODE_WIDTH)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .dcache_read_done (dcache_read_done),
        .dcache_data      (dcache_data),
        .dcache_ready     (dcache_ready),
        .dcache_addr      (dcache_addr),
        .iss_lsb_opcode   (iss_lsb_opcode),
        .iss_lsb_rob_tag  (iss_lsb_rob_tag),
        .iss_lsb_addr     (iss_lsb_addr),
        .iss_lsb_phy_addr (iss_lsb_phy_addr),
        .iss_lsb_rdy      (iss_lsb_rdy),
        .iss_lsb_ready    (iss_lsb_ready),
        .issue_ld_buf     (issue_ld_buf),
        .ready_ld_buf     (ready_ld_buf),
        .cdb_flush        (cdb_flush),
        .cdb_rob_depth    (cdb_rob_depth),
        .lsb_rob_tag      (lsb_rob_tag),
        .lsb_rd_phy_addr  (lsb_rd_phy_addr),
        .lsb_data         (lsb_data),
        .lsb_rw           (lsb_rw),
        .lsb_sw_addr      (lsb_sw_addr),
        .lsb_ready        (lsb_ready),
        .rob_top_ptr      (rob_top_ptr)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    int pass_cnt = 0;
    int fail_cnt = 0;

    task automatic check_bit(
        input string tag,
        input logic  actual,
        input logic  expected
    );
        if (actual !== expected) begin
            $error("[FAIL] %s: got %0b, want %0b @ %0t",
                   tag, actual, expected, $time);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
    endtask

    task automatic check_val(
        input string       tag,
        input logic [63:0] actual,
        input logic [63:0] expected
    );
        if (actual !== expected) begin
            $error("[FAIL] %s: got 0x%0h, want 0x%0h @ %0t",
                   tag, actual, expected, $time);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
    endtask

    task automatic clear_inputs();
        dcache_read_done = 1'b0;
        dcache_data      = '0;
        iss_lsb_opcode   = INSTR_LW;
        iss_lsb_rob_tag  = '0;
        iss_lsb_addr     = '0;
        iss_lsb_phy_addr = '0;
        iss_lsb_rdy      = 1'b0;
        issue_ld_buf     = 1'b0;
        cdb_flush        = 1'b0;
        cdb_rob_depth    = '0;
        rob_top_ptr      = '0;
    endtask

    task automatic reset_dut();
        rst_n = 1'b0;
        clear_inputs();
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;
    endtask

    task automatic accept_load(
        input logic [ROB_INDEX_WIDTH-1:0]         rob_tag_i,
        input logic [DMEM_DEPTH-1:0]              addr_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] phy_i
    );
        iss_lsb_opcode   = INSTR_LW;
        iss_lsb_rob_tag  = rob_tag_i;
        iss_lsb_addr     = addr_i;
        iss_lsb_phy_addr = phy_i;
        iss_lsb_rdy      = 1'b1;
        @(posedge clk); #1;
        iss_lsb_rdy = 1'b0;
    endtask

    task automatic accept_store(
        input logic [ROB_INDEX_WIDTH-1:0]         rob_tag_i,
        input logic [DMEM_DEPTH-1:0]              addr_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] phy_i
    );
        iss_lsb_opcode   = INSTR_SW;
        iss_lsb_rob_tag  = rob_tag_i;
        iss_lsb_addr     = addr_i;
        iss_lsb_phy_addr = phy_i;
        iss_lsb_rdy      = 1'b1;
        @(posedge clk); #1;
        iss_lsb_rdy = 1'b0;
    endtask

    task automatic dcache_respond(input logic [REG_FILE_DATA_WIDTH-1:0] data_i);
        dcache_read_done = 1'b1;
        dcache_data      = data_i;
        @(posedge clk); #1;
        dcache_read_done = 1'b0;
    endtask

    task automatic issue_head_to_cdb();
        issue_ld_buf = 1'b1;
        @(posedge clk); #1;
        issue_ld_buf = 1'b0;
    endtask

    initial begin
        `ifdef FSDB_DUMP
            $fsdbDumpfile("lsb.fsdb");
            $fsdbDumpvars(0, LSB_tb);
        `else
            $dumpfile("lsb.vcd");
            $dumpvars(0, LSB_tb);
        `endif

        $display("=======================================");
        $display("  LSB Testbench Start");
        $display("=======================================");

        $display("\n[Test 1] Reset: empty, accepts new entry, no D$ request");
        reset_dut();
        check_bit("iss_lsb_ready after reset", iss_lsb_ready, 1'b1);
        check_bit("ready_ld_buf deasserted", ready_ld_buf, 1'b0);
        check_bit("no dcache req", dcache_ready, 1'b0);

        $display("\n[Test 2] Load: D$ request, fill, CDB issue");
        accept_load(5'd1, 32'h1000, 7'd3);
        check_bit("load blocks new accept", iss_lsb_ready, 1'b0);
        check_bit("dcache request active", dcache_ready, 1'b1);
        check_val("dcache addr", dcache_addr, 32'h1000);
        dcache_respond(64'h1234_5678_9abc_def0);
        check_bit("entry ready after load", ready_ld_buf, 1'b1);
        check_bit("can accept again", iss_lsb_ready, 1'b1);
        issue_head_to_cdb();
        check_bit("lsb_ready pulse", lsb_ready, 1'b1);
        check_val("load data", lsb_data, 64'h1234_5678_9abc_def0);
        check_val("load rob tag", lsb_rob_tag, 5'd1);
        check_val("load phy rd", lsb_rd_phy_addr, 7'd3);
        check_bit("load rw flag", lsb_rw, 1'b1);
        @(posedge clk); #1;
        check_bit("lsb_ready clears", lsb_ready, 1'b0);
        check_bit("buffer empty", ready_ld_buf, 1'b0);

        $display("\n[Test 3] Store: no D$, direct to buffer and CDB");
        reset_dut();
        accept_store(5'd2, 32'h2000, 7'd5);
        check_bit("store does not request D$", dcache_ready, 1'b0);
        check_bit("store ready immediately", ready_ld_buf, 1'b1);
        issue_head_to_cdb();
        check_bit("store lsb_ready", lsb_ready, 1'b1);
        check_val("store rob tag", lsb_rob_tag, 5'd2);
        check_val("store sw addr", lsb_sw_addr, 32'h2000);
        check_bit("store rw=0", lsb_rw, 1'b0);

        $display("\n[Test 4] In-order loads and stores");
        reset_dut();
        accept_load(5'd3, 32'h3000, 7'd10);
        dcache_respond(64'h1111);
        accept_store(5'd4, 32'h3004, 7'd11);
        check_bit("two entries ready", ready_ld_buf, 1'b1);
        issue_head_to_cdb();
        check_val("first load tag", lsb_rob_tag, 5'd3);
        check_val("first load data", lsb_data, 64'h1111);
        issue_head_to_cdb();
        check_val("store tag", lsb_rob_tag, 5'd4);
        check_bit("store rw", lsb_rw, 1'b0);

        $display("\n[Test 5] Fill buffer (depth=%0d)", LSB_DEPTH);
        reset_dut();
        accept_store(5'd10, 32'h4000, 7'd1);
        accept_store(5'd11, 32'h4004, 7'd2);
        accept_store(5'd12, 32'h4008, 7'd3);
        accept_load(5'd14, 32'h5000, 7'd5);
        accept_store(5'd13, 32'h400c, 7'd4);
        check_bit("full: no iss_lsb_ready", iss_lsb_ready, 1'b0);
        check_bit("load while full still blocks accept", iss_lsb_ready, 1'b0);
        issue_head_to_cdb();
        issue_head_to_cdb();
        issue_head_to_cdb();
        issue_head_to_cdb();
        check_bit("space after draining stores", ready_ld_buf, 1'b0);
        dcache_respond(64'hDEAD);
        check_bit("load completed in lw_slot path", ready_ld_buf, 1'b1);

        $display("\n[Test 6] Back-to-back loads reuse lw_slot");
        reset_dut();
        accept_load(5'd20, 32'h6000, 7'd8);
        dcache_respond(64'hAAAA);
        issue_head_to_cdb();
        accept_load(5'd21, 32'h6008, 7'd9);
        dcache_respond(64'hBBBB);
        issue_head_to_cdb();
        check_val("second load data", lsb_data, 64'hBBBB);

        $display("\n[Test 7] Flush removes younger ROB entries");
        reset_dut();
        rob_top_ptr = 5'd0;
        accept_store(5'd2, 32'h7000, 7'd20);
        accept_store(5'd6, 32'h7004, 7'd21);
        accept_store(5'd9, 32'h7008, 7'd22);
        cdb_flush     = 1'b1;
        cdb_rob_depth = 5'd7;
        @(posedge clk); #1;
        cdb_flush = 1'b0;
        #1;
        check_bit("ready after flush", ready_ld_buf, 1'b1);
        issue_head_to_cdb();
        check_val("oldest surviving tag", lsb_rob_tag, 5'd2);
        issue_head_to_cdb();
        check_val("next surviving tag", lsb_rob_tag, 5'd6);
        check_bit("no third entry", ready_ld_buf, 1'b0);

        $display("\n[Test 8] Flush during outstanding D$ load drops lw_slot");
        reset_dut();
        rob_top_ptr = 5'd0;
        accept_load(5'd15, 32'h8000, 7'd30);
        check_bit("D$ pending", dcache_ready, 1'b1);
        cdb_flush     = 1'b1;
        cdb_rob_depth = 5'd0;
        @(posedge clk); #1;
        cdb_flush = 1'b0;
        check_bit("no D$ after flush kill", dcache_ready, 1'b0);
        #1;
        check_bit("accept again", iss_lsb_ready, 1'b1);
        dcache_read_done = 1'b1;
        dcache_data      = 64'hBAD0;
        @(posedge clk); #1;
        dcache_read_done = 1'b0;
        check_bit("stale D$ resp ignored (no ready)", ready_ld_buf, 1'b0);

        $display("\n[Test 9] iss_lsb_ready low during flush");
        reset_dut();
        accept_store(5'd1, 32'h9000, 7'd1);
        cdb_flush = 1'b1;
        #1;
        check_bit("no accept during flush", iss_lsb_ready, 1'b0);
        @(posedge clk); #1;
        cdb_flush = 1'b0;

        $display("\n[Test 10] Deferred lw_slot when buffer full at D$ return");
        reset_dut();
        accept_store(5'd30, 32'ha000, 7'd1);
        accept_store(5'd31, 32'ha004, 7'd2);
        accept_store(5'd32, 32'ha008, 7'd3);
        accept_load(5'd34, 32'hb000, 7'd5);
        check_bit("still full buffer", iss_lsb_ready, 1'b0);
        issue_head_to_cdb();
        issue_head_to_cdb();
        issue_head_to_cdb();
        check_bit("load invisible before dcache response", ready_ld_buf, 1'b0);
        dcache_respond(64'hCAFE);
        check_bit("load visible after space", ready_ld_buf, 1'b1);
        issue_head_to_cdb();
        check_val("deferred load data", lsb_data, 64'hCAFE);

        $display("\n=======================================");
        $display("  LSB Done: %0d passed, %0d failed", pass_cnt, fail_cnt);
        $display("=======================================");

        if (fail_cnt == 0) begin
            $display("[PASS] LSB_tb completed successfully");
        end else begin
            $fatal(1, "[FAIL] LSB_tb found %0d failure(s)", fail_cnt);
        end
        $finish;
    end

    initial begin
        #500_000;
        $error("TIMEOUT");
        $finish;
    end

endmodule
/* verilator lint_on WIDTH */
/* verilator lint_on BLKSEQ */
// verilog_lint: waive-stop explicit-parameter-storage-type
