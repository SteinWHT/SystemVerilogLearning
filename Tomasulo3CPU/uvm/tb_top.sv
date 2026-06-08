`timescale 1ns/1ps

module tb_top;

    import uvm_pkg::*;
    import cpu_pkg::*;

    localparam int unsigned ROB_DEPTH               = 16;
    localparam int unsigned ROB_INDEX_WIDTH         = $clog2(ROB_DEPTH);
    localparam int unsigned INSTR_WIDTH             = 32;
    localparam int unsigned IMEM_DEPTH              = 64;
    localparam int unsigned IMEM_WIDTH              = 32;
    localparam int unsigned IMEM_DEPTH_WORD         = IMEM_DEPTH - 1;
    localparam int unsigned ARCH_REG_COUNT          = 32;
    localparam int unsigned ARCH_REG_WIDTH          = $clog2(ARCH_REG_COUNT);
    localparam int unsigned REG_FILE_DATA_WIDTH     = 64;
    localparam int unsigned PHY_REGISTER_FILE_WIDTH = 7;
    localparam int unsigned DMEM_WIDTH              = 64;
    localparam int unsigned DMEM_DEPTH              = 64;
    localparam int unsigned BPB_PC_BITS             = 3;
    localparam int unsigned NUM_WAYS                = 4;
    localparam int unsigned IFQ_DEPTH               = 16;
    localparam int unsigned RAS_DEPTH               = 4;
    localparam int unsigned FRL_SIZE                = 128;
    localparam int unsigned FRL_PTR_WIDTH           = $clog2(FRL_SIZE);
    localparam int unsigned NUM_CHECKPOINT          = 8;
    localparam int unsigned SB_DEPTH                = 4;
    localparam int unsigned SB_INDEX_WIDTH          = $clog2(SB_DEPTH);
    localparam int unsigned ISSUE_QUEUE_DEPTH       = 8;
    localparam int unsigned LSB_DEPTH               = 4;
    localparam int unsigned DIV_CYCLES              = 64;
    localparam int unsigned MUL_CYCLES              = 4;
    localparam int unsigned INT_CYCLES              = 1;
    localparam int unsigned LD_ST_CYCLES            = 1;
    localparam int unsigned OPCODE_WIDTH            = 7;
    localparam int unsigned W_BYTE_NUM              = DMEM_WIDTH / 8;
    localparam int unsigned IMEM_WORDS              = 16384;
    localparam int unsigned DMEM_LINES              = 16384;

    logic clk;
    logic rst_n;

    cpu_if #(
        .INSTR_WIDTH (INSTR_WIDTH),
        .IMEM_DEPTH  (IMEM_DEPTH),
        .IMEM_WIDTH  (IMEM_WIDTH),
        .DMEM_WIDTH  (DMEM_WIDTH),
        .DMEM_DEPTH  (DMEM_DEPTH),
        .W_BYTE_NUM  (W_BYTE_NUM),
        .IMEM_WORDS  (IMEM_WORDS),
        .DMEM_LINES  (DMEM_LINES)
    ) cpu_vif (
        .clk            (clk),
        .rst_n          (rst_n),
        .use_axi_memory (1'b0)
    );

    cpu_commit_if #(
        .ROB_INDEX_WIDTH         (ROB_INDEX_WIDTH),
        .DMEM_DEPTH              (DMEM_DEPTH),
        .IMEM_DEPTH              (IMEM_DEPTH),
        .REG_FILE_DATA_WIDTH     (REG_FILE_DATA_WIDTH),
        .ARCH_REG_WIDTH          (ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH (PHY_REGISTER_FILE_WIDTH),
        .W_BYTE_NUM              (W_BYTE_NUM)
    ) commit_if (
        .clk   (clk),
        .rst_n (rst_n)
    );

    CPU_L1DCache #(
        .INSTR_WIDTH             (INSTR_WIDTH),
        .IMEM_DEPTH              (IMEM_DEPTH),
        .IMEM_WIDTH              (IMEM_WIDTH),
        .IMEM_DEPTH_WORD         (IMEM_DEPTH_WORD),
        .ARCH_REG_COUNT          (ARCH_REG_COUNT),
        .ARCH_REG_WIDTH          (ARCH_REG_WIDTH),
        .REG_FILE_DATA_WIDTH     (REG_FILE_DATA_WIDTH),
        .PHY_REGISTER_FILE_WIDTH (PHY_REGISTER_FILE_WIDTH),
        .DMEM_WIDTH              (DMEM_WIDTH),
        .DMEM_DEPTH              (DMEM_DEPTH),
        .BPB_PC_BITS             (BPB_PC_BITS),
        .NUM_WAYS                (NUM_WAYS),
        .IFQ_DEPTH               (IFQ_DEPTH),
        .RAS_DEPTH               (RAS_DEPTH),
        .FRL_SIZE                (FRL_SIZE),
        .FRL_PTR_WIDTH           (FRL_PTR_WIDTH),
        .NUM_CHECKPOINT          (NUM_CHECKPOINT),
        .ROB_DEPTH               (ROB_DEPTH),
        .ROB_INDEX_WIDTH         (ROB_INDEX_WIDTH),
        .SB_DEPTH                (SB_DEPTH),
        .SB_INDEX_WIDTH          (SB_INDEX_WIDTH),
        .ISSUE_QUEUE_DEPTH       (ISSUE_QUEUE_DEPTH),
        .LSB_DEPTH               (LSB_DEPTH),
        .DIV_CYCLES              (DIV_CYCLES),
        .MUL_CYCLES              (MUL_CYCLES),
        .INT_CYCLES              (INT_CYCLES),
        .LD_ST_CYCLES            (LD_ST_CYCLES),
        .OPCODE_WIDTH            (OPCODE_WIDTH)
    ) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .imem_resp_valid    (cpu_vif.imem_resp_valid),
        .imem_resp_data     (cpu_vif.imem_resp_data),
        .imem_resp_ready    (cpu_vif.imem_resp_ready),
        .imem_req_valid     (cpu_vif.imem_req_valid),
        .imem_addr          (cpu_vif.imem_addr),
        .dcache_mem_init_en  (cpu_vif.dcache_mem_init_en),
        .dcache_mem_init_idx (cpu_vif.dcache_mem_init_idx),
        .dcache_mem_init_data(cpu_vif.dcache_mem_init_data),
        .dcache_hits         (cpu_vif.dcache_hits),
        .dcache_misses       (cpu_vif.dcache_misses),
        .dcache_rready       (cpu_vif.dcache_rready),
        .dcache_rresp_valid  (cpu_vif.dcache_rresp_valid),
        .dcache_rdata        (cpu_vif.dcache_rdata),
        .dcache_raddr        (cpu_vif.dcache_raddr),
        .dcache_rvalid       (cpu_vif.dcache_rvalid),
        .dcache_rresp_ready  (cpu_vif.dcache_rresp_ready),
        .dcache_wready       (cpu_vif.dcache_wready),
        .dcache_wresp_valid  (cpu_vif.dcache_wresp_valid),
        .dcache_write        (cpu_vif.dcache_write),
        .dcache_sw_data      (cpu_vif.dcache_sw_data),
        .dcache_wstrb        (cpu_vif.dcache_wstrb),
        .dcache_sw_addr      (cpu_vif.dcache_sw_addr),
        .dcache_wvalid       (cpu_vif.dcache_wvalid),
        .dcache_wresp_ready  (cpu_vif.dcache_wresp_ready)
    );

    assign cpu_vif.memory_error = 1'b0;

    // ----------------------------------------------------------------
    // I-cache model (1-cycle latency)
    // ----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_vif.imem_resp_valid <= 1'b1;
            cpu_vif.imem_resp_data  <= '0;
        end else begin
            if (cpu_vif.imem_req_valid) begin
                cpu_vif.imem_resp_valid <= 1'b1;
            end else begin
                cpu_vif.imem_resp_valid <= 1'b0;
            end
            if (cpu_vif.imem_req_valid && cpu_vif.imem_resp_valid) begin
                cpu_vif.imem_resp_data <= cpu_vif.imem_array[cpu_vif.imem_addr[15:2]];
            end
        end
    end

    // ----------------------------------------------------------------
    // Architectural shadow memory for UVM checking and tohost polling.
    // The real data path is CPU_L1DCache.u_dcache.
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n && cpu_vif.dcache_wvalid && cpu_vif.dcache_wready) begin
            logic [REG_FILE_DATA_WIDTH-1:0] temp_data;
            temp_data = cpu_vif.dmem_array[cpu_vif.dcache_sw_addr[15:3]];
            for (int i = 0; i < W_BYTE_NUM; i++) begin
                if (cpu_vif.dcache_wstrb[i])
                    temp_data[i*8 +: 8] = cpu_vif.dcache_sw_data[i*8 +: 8];
            end
            cpu_vif.dmem_array[cpu_vif.dcache_sw_addr[15:3]] = temp_data;
        end
    end

    // ----------------------------------------------------------------
    // ROB commit observer (explicit instance — bind + vopt often drops u_rob_commit_mon)
    // ----------------------------------------------------------------
    rob_commit_monitor #(
        .ROB_DEPTH              (ROB_DEPTH),
        .ROB_INDEX_WIDTH        (ROB_INDEX_WIDTH),
        .DMEM_WIDTH             (DMEM_WIDTH),
        .DMEM_DEPTH             (DMEM_DEPTH),
        .IMEM_DEPTH             (IMEM_DEPTH),
        .REG_FILE_DATA_WIDTH    (REG_FILE_DATA_WIDTH),
        .ARCH_REG_COUNT         (ARCH_REG_COUNT),
        .ARCH_REG_WIDTH         (ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .W_BYTE_NUM             (W_BYTE_NUM)
    ) u_rob_commit_mon (
        .clk              (clk),
        .rst_n            (rst_n),
        .commit_valid     (dut.u_cpu.front_end.rob.enable),
        .commit_rob_tag   (dut.u_cpu.front_end.rob.read_ptr[ROB_INDEX_WIDTH-1:0]),
        .head_curr_phy    (dut.u_cpu.front_end.rob.head.curr_phy),
        .head_prev_phy    (dut.u_cpu.front_end.rob.head.prev_phy),
        .head_rd_arch     (dut.u_cpu.front_end.rob.head.rd_addr),
        .head_rw          (dut.u_cpu.front_end.rob.head.rw),
        .head_mw          (dut.u_cpu.front_end.rob.head.opclass ==
                           riscv_types_pkg::ROB_STORE),
        .head_sw_addr     (dut.u_cpu.front_end.rob.head.sw_addr),
        .head_sw_strb     (dut.u_cpu.front_end.rob.head.sw_strb),
        .head_pc          (dut.u_cpu.front_end.rob.head.pc),
        .head_trap_cause  (dut.u_cpu.front_end.rob.head.trap_cause),
        .head_mret        (dut.u_cpu.front_end.rob.head_is_mret),
        .head_is_csr      (dut.u_cpu.front_end.rob.head.opclass ==
                           riscv_types_pkg::ROB_CSR),
        .head_csr_addr    (dut.u_cpu.front_end.rob.head.csr_addr),
        .head_csr_cmd     (dut.u_cpu.front_end.rob.head.csr_cmd),
        .head_rs1_arch    (dut.u_cpu.front_end.rob.head.rs1_arch),
        .head_cdb_data    ((dut.u_cpu.front_end.rob.head.opclass ==
                            riscv_types_pkg::ROB_CSR) ?
                           dut.u_cpu.front_end.rob.csr_rdata :
                           dut.u_cpu.front_end.rob.sim_head_cdb_data)
    );

    assign commit_if.rob_commit           = dut.u_cpu.front_end.rob.rob_commit;
    assign commit_if.mon_commit_valid     = u_rob_commit_mon.mon_commit_valid;
    assign commit_if.mon_commit_rob_tag   = u_rob_commit_mon.mon_commit_rob_tag;
    assign commit_if.mon_curr_phy         = u_rob_commit_mon.mon_curr_phy;
    assign commit_if.mon_prev_phy         = u_rob_commit_mon.mon_prev_phy;
    assign commit_if.mon_rd_arch          = u_rob_commit_mon.mon_rd_arch;
    assign commit_if.mon_reg_write        = u_rob_commit_mon.mon_reg_write;
    assign commit_if.mon_mem_write        = u_rob_commit_mon.mon_mem_write;
    assign commit_if.mon_sw_addr          = u_rob_commit_mon.mon_sw_addr;
    assign commit_if.mon_sw_strb          = u_rob_commit_mon.mon_sw_strb;
    assign commit_if.mon_pc               = u_rob_commit_mon.mon_pc;
    assign commit_if.mon_trap_cause       = u_rob_commit_mon.mon_trap_cause;
    assign commit_if.mon_mret             = u_rob_commit_mon.mon_mret;
    assign commit_if.mon_is_csr           = u_rob_commit_mon.mon_is_csr;
    assign commit_if.mon_csr_addr         = u_rob_commit_mon.mon_csr_addr;
    assign commit_if.mon_csr_cmd          = u_rob_commit_mon.mon_csr_cmd;
    assign commit_if.mon_rs1_arch         = u_rob_commit_mon.mon_rs1_arch;
    assign commit_if.mon_cdb_data         = u_rob_commit_mon.mon_cdb_data;
    assign commit_if.lat_valid            = u_rob_commit_mon.lat_valid;
    assign commit_if.lat_rob_tag          = u_rob_commit_mon.lat_rob_tag;
    assign commit_if.lat_curr_phy         = u_rob_commit_mon.lat_curr_phy;
    assign commit_if.lat_prev_phy         = u_rob_commit_mon.lat_prev_phy;
    assign commit_if.lat_rd_arch          = u_rob_commit_mon.lat_rd_arch;
    assign commit_if.lat_reg_write        = u_rob_commit_mon.lat_reg_write;
    assign commit_if.lat_mem_write        = u_rob_commit_mon.lat_mem_write;
    assign commit_if.lat_sw_addr          = u_rob_commit_mon.lat_sw_addr;
    assign commit_if.lat_sw_strb          = u_rob_commit_mon.lat_sw_strb;
    assign commit_if.lat_pc               = u_rob_commit_mon.lat_pc;
    assign commit_if.lat_trap_cause       = u_rob_commit_mon.lat_trap_cause;
    assign commit_if.lat_mret             = u_rob_commit_mon.lat_mret;
    assign commit_if.lat_is_csr           = u_rob_commit_mon.lat_is_csr;
    assign commit_if.lat_csr_addr         = u_rob_commit_mon.lat_csr_addr;
    assign commit_if.lat_csr_cmd          = u_rob_commit_mon.lat_csr_cmd;
    assign commit_if.lat_rs1_arch         = u_rob_commit_mon.lat_rs1_arch;
    assign commit_if.lat_cdb_data         = u_rob_commit_mon.lat_cdb_data;
    assign commit_if.lat_commit_count     = u_rob_commit_mon.lat_commit_count;

    // ----------------------------------------------------------------
    // Clock / reset / memory init
    // ----------------------------------------------------------------
    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        int unsigned reset_hold_cycles;
        rst_n = 1'b0;
        reset_hold_cycles = 3;
        void'($value$plusargs("RESET_HOLD_CYCLES=%d", reset_hold_cycles));
        wait (cpu_vif.preload_complete === 1'b1);
        repeat (reset_hold_cycles) @(posedge clk);
        rst_n = 1'b1;
    end

    // ----------------------------------------------------------------
    // UVM
    // ----------------------------------------------------------------
    initial begin
        cpu_cfg cfg;
        cfg = cpu_cfg::type_id::create("cfg");
        cfg.imem_words = IMEM_WORDS;
        cfg.dmem_lines = DMEM_LINES;
        cfg.memory_backend = cpu_cfg::CPU_MEM_LEGACY;

        uvm_config_db#(cpu_drv_vif_t)::set(null, "uvm_test_top", "vif", cpu_vif);
        uvm_config_db#(cpu_mon_vif_t)::set(null, "uvm_test_top", "mon_vif", cpu_vif);
        uvm_config_db#(cpu_commit_vif_t)::set(null, "uvm_test_top", "commit_vif", commit_if);
        uvm_config_db#(cpu_cfg)::set(null, "uvm_test_top", "cfg", cfg);

        begin
            automatic string test_name = "cpu_int_alu_test";
            void'($value$plusargs("UVM_TESTNAME=%s", test_name));
            run_test(test_name);
        end
    end

endmodule
