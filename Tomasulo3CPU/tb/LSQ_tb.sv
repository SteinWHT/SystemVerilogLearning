// Disable width mismatch warnings from some simulators on unsized task arguments.
/* verilator lint_off WIDTH */
// verilog_lint: waive-start explicit-parameter-storage-type
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module LSQ_tb;

    parameter int unsigned LSQ_DEPTH               = 4;
    parameter int unsigned LSQ_INDEX_WIDTH         = $clog2(LSQ_DEPTH);
    parameter int unsigned SAB_DEPTH               = 8;
    parameter int unsigned SAB_INDEX_WIDTH         = $clog2(SAB_DEPTH);
    parameter int unsigned DMEM_WIDTH              = 64;
    parameter int unsigned DMEM_DEPTH              = 32;
    parameter int unsigned ROB_DEPTH               = 16;
    parameter int unsigned ROB_INDEX_WIDTH         = $clog2(ROB_DEPTH);
    parameter int unsigned ARCH_REG_WIDTH          = 5;
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7;
    parameter int unsigned REG_FILE_DATA_WIDTH     = 64;
    parameter int unsigned OPCODE_WIDTH            = 2;
    parameter int unsigned SB_DEPTH                = 4;
    parameter int unsigned SB_INDEX_WIDTH          = $clog2(SB_DEPTH);
    parameter int unsigned OPCODE_NONE             = 2'd0;
    parameter int unsigned OPCODE_LOAD             = 2'd1;
    parameter int unsigned OPCODE_STORE            = 2'd2;

    logic clk;
    logic rst_n;

    // SB interface
    logic [SB_INDEX_WIDTH-1:0]            sb_flush_sw_tag;
    logic                                 sb_flush_sw;
    logic [SB_INDEX_WIDTH-1:0]            sb_entry_sw_tag;
    logic [DMEM_DEPTH-1:0]                sb_entry_sw_addr;

    // ROB interface
    logic [ROB_INDEX_WIDTH-1:0]           rob_tag;
    logic [ROB_INDEX_WIDTH-1:0]           rob_top_ptr;
    logic                                 rob_commit_mem_write;

    // Dispatch interface
    logic                                 dis_rs_data_ready;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]   dis_rs_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]   dis_new_rd_phy_addr;
    logic [ROB_INDEX_WIDTH-1:0]           dis_rob_tag;
    logic [OPCODE_WIDTH-1:0]              dis_opcode;
    logic                                 dis_ld_st_issue_en;
    logic [15:0]                          dis_imm16;

    // Queue status
    logic                                 lsq_ld_st_full;
    logic                                 lsq_ld_st_two_or_more_vacant;

    // D-Cache interface
    logic                                 dcache_read_busy;

    // CDB interface
    logic                                 cdb_flush;
    logic [ROB_INDEX_WIDTH-1:0]           cdb_rob_depth;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]   cdb_rd_phy_addr;
    logic                                 cdb_phy_reg_write;
    logic                                 cdb_valid;

    // PRF interface
    logic [REG_FILE_DATA_WIDTH-1:0]       iss_rs_data_lsq;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]   iss_rs_phy_addr_ls;

    // LSB interface
    logic                                 lsb_rdy;
    logic [OPCODE_WIDTH-1:0]              iss_lsq_opcode;
    logic [ROB_INDEX_WIDTH-1:0]           iss_lsq_rob_tag;
    logic [DMEM_DEPTH-1:0]                iss_lsq_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]   iss_lsq_phy_addr;
    logic                                 iss_lsq_rdy;

    LSQ #(
        .LSQ_DEPTH              (LSQ_DEPTH),
        .LSQ_INDEX_WIDTH        (LSQ_INDEX_WIDTH),
        .SAB_DEPTH              (SAB_DEPTH),
        .SAB_INDEX_WIDTH        (SAB_INDEX_WIDTH),
        .DMEM_WIDTH             (DMEM_WIDTH),
        .DMEM_DEPTH             (DMEM_DEPTH),
        .ROB_DEPTH              (ROB_DEPTH),
        .ROB_INDEX_WIDTH        (ROB_INDEX_WIDTH),
        .ARCH_REG_WIDTH         (ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .REG_FILE_DATA_WIDTH    (REG_FILE_DATA_WIDTH),
        .OPCODE_WIDTH           (OPCODE_WIDTH),
        .SB_DEPTH               (SB_DEPTH),
        .SB_INDEX_WIDTH         (SB_INDEX_WIDTH),
        .OPCODE_LOAD            (OPCODE_LOAD),
        .OPCODE_STORE           (OPCODE_STORE)
    ) dut (
        .clk                            (clk),
        .rst_n                          (rst_n),
        .sb_flush_sw_tag                (sb_flush_sw_tag),
        .sb_flush_sw                    (sb_flush_sw),
        .sb_entry_sw_tag                (sb_entry_sw_tag),
        .sb_entry_sw_addr               (sb_entry_sw_addr),
        .rob_tag                        (rob_tag),
        .rob_top_ptr                    (rob_top_ptr),
        .rob_commit_mem_write           (rob_commit_mem_write),
        .dis_rs_data_ready              (dis_rs_data_ready),
        .dis_rs_phy_addr                (dis_rs_phy_addr),
        .dis_new_rd_phy_addr            (dis_new_rd_phy_addr),
        .dis_rob_tag                    (dis_rob_tag),
        .dis_opcode                     (dis_opcode),
        .dis_ld_st_issue_en             (dis_ld_st_issue_en),
        .dis_imm16                      (dis_imm16),
        .lsq_ld_st_full                 (lsq_ld_st_full),
        .lsq_ld_st_two_or_more_vacant   (lsq_ld_st_two_or_more_vacant),
        .dcache_read_busy               (dcache_read_busy),
        .cdb_flush                      (cdb_flush),
        .cdb_rob_depth                  (cdb_rob_depth),
        .cdb_rd_phy_addr                (cdb_rd_phy_addr),
        .cdb_phy_reg_write              (cdb_phy_reg_write),
        .cdb_valid                      (cdb_valid),
        .iss_rs_data_lsq                (iss_rs_data_lsq),
        .iss_rs_phy_addr_ls             (iss_rs_phy_addr_ls),
        .lsb_rdy                        (lsb_rdy),
        .iss_lsq_opcode                 (iss_lsq_opcode),
        .iss_lsq_rob_tag                (iss_lsq_rob_tag),
        .iss_lsq_addr                   (iss_lsq_addr),
        .iss_lsq_phy_addr               (iss_lsq_phy_addr),
        .iss_lsq_rdy                    (iss_lsq_rdy)
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
        sb_flush_sw_tag      = '0;
        sb_flush_sw          = 1'b0;
        sb_entry_sw_tag      = '0;
        sb_entry_sw_addr     = '0;
        rob_tag              = '0;
        rob_top_ptr          = '0;
        rob_commit_mem_write = 1'b0;
        dis_rs_data_ready    = 1'b0;
        dis_rs_phy_addr      = '0;
        dis_new_rd_phy_addr  = '0;
        dis_rob_tag          = '0;
        dis_opcode           = '0;
        dis_ld_st_issue_en   = 1'b0;
        dis_imm16            = '0;
        dcache_read_busy     = 1'b0;
        cdb_flush            = 1'b0;
        cdb_rob_depth        = '0;
        cdb_rd_phy_addr      = '0;
        cdb_phy_reg_write    = 1'b0;
        cdb_valid            = 1'b0;
        iss_rs_data_lsq      = '0;
        lsb_rdy              = 1'b1;
    endtask

    task automatic reset_dut();
        rst_n = 1'b0;
        clear_inputs();
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;
    endtask

    task automatic drive_dispatch(
        input logic [ROB_INDEX_WIDTH-1:0]         rob_tag_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs_i,
        input logic                               rs_ready_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd_i,
        input logic [OPCODE_WIDTH-1:0]            opcode_i,
        input logic [15:0]                        imm_i
    );
        dis_rob_tag         = rob_tag_i;
        dis_rs_phy_addr     = rs_i;
        dis_rs_data_ready   = rs_ready_i;
        dis_new_rd_phy_addr = rd_i;
        dis_opcode          = opcode_i;
        dis_imm16           = imm_i;
        dis_ld_st_issue_en  = 1'b1;
    endtask

    task automatic dispatch_entry(
        input logic [ROB_INDEX_WIDTH-1:0]         rob_tag_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs_i,
        input logic                               rs_ready_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd_i,
        input logic [OPCODE_WIDTH-1:0]            opcode_i,
        input logic [15:0]                        imm_i
    );
        drive_dispatch(rob_tag_i, rs_i, rs_ready_i, rd_i, opcode_i, imm_i);
        #1;
        check_bit("dispatch does not assert LSB valid", iss_lsq_rdy, 1'b0);
        @(posedge clk); #1;
        dis_ld_st_issue_en = 1'b0;
    endtask

    task automatic dispatch_entry_while_lsb_busy(
        input logic [ROB_INDEX_WIDTH-1:0]         rob_tag_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs_i,
        input logic                               rs_ready_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd_i,
        input logic [OPCODE_WIDTH-1:0]            opcode_i,
        input logic [15:0]                        imm_i
    );
        drive_dispatch(rob_tag_i, rs_i, rs_ready_i, rd_i, opcode_i, imm_i);
        @(posedge clk); #1;
        dis_ld_st_issue_en = 1'b0;
    endtask

    task automatic calculate_addr(
        input string                               tag,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs_i,
        input logic [REG_FILE_DATA_WIDTH-1:0]     base_i
    );
        check_val({tag, " PRF rs address"}, iss_rs_phy_addr_ls, rs_i);
        iss_rs_data_lsq = base_i;
        @(posedge clk); #1;
    endtask

    task automatic expect_idle_outputs(input string tag);
        check_bit({tag, " iss_lsq_rdy"}, iss_lsq_rdy, 1'b0);
        check_val({tag, " opcode"}, iss_lsq_opcode, '0);
        check_val({tag, " rob tag"}, iss_lsq_rob_tag, '0);
        check_val({tag, " addr"}, iss_lsq_addr, '0);
        check_val({tag, " phy addr"}, iss_lsq_phy_addr, '0);
    endtask

    task automatic grant_issue_and_check(
        input string                               tag,
        input logic [ROB_INDEX_WIDTH-1:0]         rob_tag_i,
        input logic [OPCODE_WIDTH-1:0]            opcode_i,
        input logic [DMEM_DEPTH-1:0]              addr_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] phy_addr_i
    );
        // LSQ issues when lsb_rdy is set; no ISSUEUNIT grant on the LSQ side.
        drive_dispatch('0, '0, 1'b0, '0, OPCODE_LOAD, 16'h0);
        #1;
        check_bit({tag, " iss_lsq_rdy"}, iss_lsq_rdy, 1'b1);
        check_val({tag, " rob tag"}, iss_lsq_rob_tag, rob_tag_i);
        check_val({tag, " opcode"}, iss_lsq_opcode, opcode_i);
        check_val({tag, " addr"}, iss_lsq_addr, addr_i);
        check_val({tag, " phy addr"}, iss_lsq_phy_addr, phy_addr_i);
        @(posedge clk); #1;
        dis_ld_st_issue_en = 1'b0;
    endtask

    task automatic accept_ready_and_check(
        input string                               tag,
        input logic [ROB_INDEX_WIDTH-1:0]         rob_tag_i,
        input logic [OPCODE_WIDTH-1:0]            opcode_i,
        input logic [DMEM_DEPTH-1:0]              addr_i,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] phy_addr_i
    );
        #1;
        check_bit({tag, " iss_lsq_rdy"}, iss_lsq_rdy, 1'b1);
        check_val({tag, " rob tag"}, iss_lsq_rob_tag, rob_tag_i);
        check_val({tag, " opcode"}, iss_lsq_opcode, opcode_i);
        check_val({tag, " addr"}, iss_lsq_addr, addr_i);
        check_val({tag, " phy addr"}, iss_lsq_phy_addr, phy_addr_i);
        @(posedge clk); #1;
    endtask

    initial begin
        `ifdef FSDB_DUMP
            $fsdbDumpfile("lsq.fsdb");
            $fsdbDumpvars(0, LSQ_tb);
            $fsdbDumpMDA();
        `else
            $dumpfile("lsq.vcd");
            $dumpvars(0, LSQ_tb);
        `endif

        $display("=======================================");
        $display("  LSQ Testbench Start");
        $display("=======================================");

        $display("\n[Test 1] Reset leaves LSQ/SAB empty and output-idle");
        reset_dut();
        expect_idle_outputs("reset");
        check_bit("not full after reset", lsq_ld_st_full, 1'b0);
        check_bit("two or more vacant after reset", lsq_ld_st_two_or_more_vacant, 1'b1);

        $display("\n[Test 2] Ready load calculates address through PRF and issues to LSB");
        reset_dut();
        dispatch_entry(4'd2, 7'd10, 1'b1, 7'd40, OPCODE_LOAD, 16'd8);
        calculate_addr("load addr calc", 7'd10, 64'd100);
        grant_issue_and_check("load issue", 4'd2, OPCODE_LOAD, 32'd108, 7'd40);

        $display("\n[Test 3] Store calculates address and issues to LSB/SAB");
        reset_dut();
        dispatch_entry(4'd3, 7'd11, 1'b1, 7'd0, OPCODE_STORE, 16'd12);
        calculate_addr("store addr calc", 7'd11, 64'd200);
        grant_issue_and_check("store issue", 4'd3, OPCODE_STORE, 32'd212, 7'd0);

        $display("\n[Test 4] CDB wakeup allows a waiting load to calculate its address");
        reset_dut();
        dispatch_entry(4'd4, 7'd21, 1'b0, 7'd41, OPCODE_LOAD, 16'd4);
        expect_idle_outputs("load waits for base operand");
        cdb_rd_phy_addr   = 7'd21;
        cdb_phy_reg_write = 1'b1;
        cdb_valid         = 1'b1;
        calculate_addr("cdb wake addr calc", 7'd21, 64'd300);
        cdb_phy_reg_write = 1'b0;
        cdb_valid         = 1'b0;
        grant_issue_and_check("cdb-woken load issue", 4'd4, OPCODE_LOAD, 32'd304, 7'd41);

        $display("\n[Test 5] D-cache busy blocks a ready load");
        reset_dut();
        dispatch_entry(4'd5, 7'd22, 1'b1, 7'd42, OPCODE_LOAD, 16'd16);
        calculate_addr("busy load addr calc", 7'd22, 64'd400);
        dcache_read_busy = 1'b1;
        drive_dispatch('0, '0, 1'b0, '0, OPCODE_LOAD, 16'h0);
        #1;
        check_bit("busy dcache blocks load issue", iss_lsq_rdy, 1'b0);
        @(posedge clk); #1;
        dis_ld_st_issue_en       = 1'b0;
        dcache_read_busy = 1'b0;
        grant_issue_and_check("load issues after dcache frees", 4'd5, OPCODE_LOAD, 32'd416, 7'd42);

        $display("\n[Test 6] Younger store waits while older load address is unknown");
        reset_dut();
        dispatch_entry(4'd2, 7'd30, 1'b0, 7'd50, OPCODE_LOAD, 16'd20);
        dispatch_entry(4'd3, 7'd31, 1'b1, 7'd0,  OPCODE_STORE, 16'd20);
        calculate_addr("younger store addr calc", 7'd31, 64'd500);
        drive_dispatch('0, '0, 1'b0, '0, OPCODE_LOAD, 16'h0);
        #1;
        check_bit("store blocked by older unknown load address", iss_lsq_rdy, 1'b0);
        @(posedge clk); #1;
        dis_ld_st_issue_en = 1'b0;

        cdb_rd_phy_addr   = 7'd30;
        cdb_phy_reg_write = 1'b1;
        cdb_valid         = 1'b1;
        calculate_addr("older load addr calc", 7'd30, 64'd500);
        cdb_phy_reg_write = 1'b0;
        cdb_valid         = 1'b0;
        grant_issue_and_check("older load issues after address known", 4'd2, OPCODE_LOAD, 32'd520, 7'd50);

        $display("\n[Test 7] Full and two-or-more-vacant flags track dispatch occupancy");
        reset_dut();
        dispatch_entry(4'd8,  7'd1, 1'b0, 7'd60, OPCODE_LOAD,  16'd1);
        dispatch_entry(4'd9,  7'd2, 1'b0, 7'd61, OPCODE_STORE, 16'd2);
        check_bit("two entries vacant after two dispatches", lsq_ld_st_two_or_more_vacant, 1'b1);
        dispatch_entry(4'd10, 7'd3, 1'b0, 7'd62, OPCODE_LOAD,  16'd3);
        check_bit("only one entry vacant after three dispatches", lsq_ld_st_two_or_more_vacant, 1'b0);
        dispatch_entry(4'd11, 7'd4, 1'b0, 7'd63, OPCODE_STORE, 16'd4);
        check_bit("full after four dispatches", lsq_ld_st_full, 1'b1);
        check_bit("not two-or-more-vacant when full", lsq_ld_st_two_or_more_vacant, 1'b0);

        $display("\n[Test 8] Flush suppresses dispatch and removes younger entries");
        reset_dut();
        lsb_rdy = 1'b0;
        dispatch_entry(4'd2, 7'd71, 1'b1, 7'd72, OPCODE_LOAD,  16'd4);
        calculate_addr("flush older addr calc", 7'd71, 64'd1000);
        dispatch_entry_while_lsb_busy(4'd6, 7'd73, 1'b1, 7'd74, OPCODE_LOAD,  16'd8);
        calculate_addr("flush younger addr calc", 7'd73, 64'd1000);

        cdb_flush     = 1'b1;
        cdb_rob_depth = 4'd3;
        drive_dispatch(4'd7, 7'd75, 1'b1, 7'd76, OPCODE_LOAD, 16'd12);
        #1;
        check_bit("flush suppresses LSB valid", iss_lsq_rdy, 1'b0);
        @(posedge clk); #1;
        cdb_flush  = 1'b0;
        dis_ld_st_issue_en = 1'b0;

        lsb_rdy = 1'b1;
        accept_ready_and_check("flush keeps older entry", 4'd2, OPCODE_LOAD, 32'd1004, 7'd72);
        expect_idle_outputs("flushed younger and suppressed dispatch");

        $display("\n=======================================");
        $display("  LSQ Testbench Done: %0d passed, %0d failed", pass_cnt, fail_cnt);
        $display("=======================================");

        if (fail_cnt == 0) begin
            $display("[PASS] LSQ_tb completed successfully");
        end else begin
            $fatal(1, "[FAIL] LSQ_tb found %0d failure(s)", fail_cnt);
        end
        $finish;
    end

    initial begin
        #100_000;
        $error("TIMEOUT");
        $finish;
    end

endmodule
/* verilator lint_on WIDTH */
/* verilator lint_on BLKSEQ */
// verilog_lint: waive-stop explicit-parameter-storage-type
