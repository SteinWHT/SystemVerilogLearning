`timescale 1ns/1ps
module CPU #(
    parameter int unsigned INSTR_WIDTH             = 32,
    parameter int unsigned PC_WIDTH                = 64,  // PC / instruction-address width
    parameter int unsigned IMEM_WIDTH              = 32,  // fetch width; invariant: == INSTR_WIDTH
    parameter int unsigned PC_WORD_WIDTH           = PC_WIDTH - 1,  // word-aligned PC (drops LSB)

    // invariant: XLEN == REG_FILE_DATA_WIDTH == DMEM_WIDTH (all 64-bit data path)
    parameter int unsigned XLEN                    = 64,
    parameter int unsigned ARCH_REG_COUNT          = 32,
    parameter int unsigned ARCH_REG_WIDTH          = $clog2(ARCH_REG_COUNT),
    parameter int unsigned REG_FILE_DATA_WIDTH     = 64,

    parameter int unsigned PHY_REG_IDX_WIDTH       = 7,   // physical-register index width

    parameter int unsigned DMEM_WIDTH              = 64,
    parameter int unsigned DMEM_ADDR_WIDTH         = 32,  // data-memory byte-address width
    parameter int unsigned W_BYTE_NUM              = DMEM_WIDTH / 8,

    parameter int unsigned BPB_PC_BITS             = 3,

    parameter int unsigned NUM_WAYS                = 4,
    parameter int unsigned IFQ_DEPTH               = 16,

    parameter int unsigned RAS_DEPTH               = 4,

    parameter int unsigned FRL_DEPTH                = 128,
    parameter int unsigned FRL_PTR_WIDTH           = $clog2(FRL_DEPTH),

    parameter int unsigned NUM_CHECKPOINT          = 8,

    parameter int unsigned ROB_DEPTH               = 16,
    parameter int unsigned ROB_INDEX_WIDTH         = $clog2(ROB_DEPTH),

    parameter int unsigned SB_DEPTH                = 4,
    parameter int unsigned SB_INDEX_WIDTH          = $clog2(SB_DEPTH),

    parameter int unsigned ISSUE_QUEUE_DEPTH       = 8,
    parameter int unsigned LSB_DEPTH               = 4,

    parameter int unsigned DIV_CYCLES              = 64,
    parameter int unsigned MUL_CYCLES              = 4,
    parameter int unsigned INT_CYCLES              = 1,
    parameter int unsigned LD_ST_CYCLES            = 1,

    parameter int unsigned OPCODE_WIDTH            = 7,

    // Enable FENCE.I-driven I$/D$ coherence handshake (see fence_i_coh_* ports).
    parameter bit FENCE_I_COHERENCE                = 1'b0
) (
    input  logic clk,
    input  logic rst_n,

    // I-Cache interface (valid/ready handshake)
    output logic [PC_WIDTH-1:0]             imem_addr,
    output logic                            imem_req_valid,
    input  logic                            imem_req_ready,
    input  logic [IMEM_WIDTH-1:0]           imem_resp_data,
    input  logic                            imem_resp_valid,
    output logic                            imem_resp_ready,

    // Cache-coherence handshake
    output logic                            fence_i_coh_start,
    input  logic                            fence_i_coh_done,

    // D-Cache read interface
    input  logic                            dcache_rready,
    input  logic                            dcache_rresp_valid,
    input  logic [REG_FILE_DATA_WIDTH-1:0]  dcache_rdata,

    output logic [DMEM_ADDR_WIDTH-1:0]      dcache_raddr,
    output logic                            dcache_rvalid,
    output logic                            dcache_rresp_ready,

    // D-Cache write interface
    input  logic                            dcache_wready,
    input  logic                            dcache_wresp_valid,

    output logic                            dcache_write,
    output logic [DMEM_WIDTH-1:0]           dcache_sw_data,
    output logic [W_BYTE_NUM-1:0]           dcache_wstrb,
    output logic [DMEM_ADDR_WIDTH-1:0]      dcache_sw_addr,
    output logic                            dcache_wvalid,
    output logic                            dcache_wresp_ready
);

    // ----------------------------------------------------------------
    // Front-end ↔ Back-end internal wires
    // ----------------------------------------------------------------

    // Dispatch channel (front-end DISPATCH → back-end issue queues)
    dispatch_if #(
        .PHY_REG_IDX_WIDTH (PHY_REG_IDX_WIDTH),
        .XLEN              (XLEN),
        .PC_WIDTH          (PC_WIDTH),
        .OPCODE_WIDTH      (OPCODE_WIDTH),
        .BPB_PC_BITS       (BPB_PC_BITS)
    ) dispatch_bus ();

    // Common data bus (back-end → front-end broadcast)
    cdb_if #(
        .PHY_REG_IDX_WIDTH   (PHY_REG_IDX_WIDTH),
        .ROB_INDEX_WIDTH     (ROB_INDEX_WIDTH),
        .REG_FILE_DATA_WIDTH (REG_FILE_DATA_WIDTH),
        .DMEM_ADDR_WIDTH     (DMEM_ADDR_WIDTH),
        .W_BYTE_NUM          (W_BYTE_NUM),
        .PC_WIDTH            (PC_WIDTH),
        .BPB_PC_BITS         (BPB_PC_BITS)
    ) cdb_bus ();

    // Issue-queue occupancy/back-pressure (back-end → front-end DISPATCH)
    issq_status_if issq_bus ();

    // ROB sideband (front-end ROB → back-end)
    rob_sideband_if #(
        .ROB_INDEX_WIDTH   (ROB_INDEX_WIDTH),
        .PHY_REG_IDX_WIDTH (PHY_REG_IDX_WIDTH)
    ) rob_sb_bus ();

    // Store-buffer allocation (front-end SB → back-end LSQ addr buffer)
    sb_alloc_if #(
        .SB_INDEX_WIDTH  (SB_INDEX_WIDTH),
        .ROB_INDEX_WIDTH (ROB_INDEX_WIDTH)
    ) sb_bus ();

    // Store-source / CSR rs1 PRF read (front sends phys addr, back returns data)
    logic [PHY_REG_IDX_WIDTH-1:0]        st_src_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0]      st_src_data;

    // CSR write-back to PRF (front-end → back-end)
    logic [PHY_REG_IDX_WIDTH-1:0]  csr_wr_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0]      csr_wr_data;
    logic                                csr_wr_en;

    // LSB sideband (back-end outputs, partially used)
    logic [ROB_INDEX_WIDTH-1:0]          lsb_rob_tag;
    logic [PHY_REG_IDX_WIDTH-1:0]  lsb_rd_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0]      lsb_data;
    logic                                lsb_rw;
    logic [DMEM_ADDR_WIDTH-1:0]               lsb_sw_addr;
    logic                                lsb_result_valid;

    // ----------------------------------------------------------------
    // Front-End
    // ----------------------------------------------------------------
    CPU_FRONT_END #(
        .INSTR_WIDTH             (INSTR_WIDTH),
        .PC_WIDTH                (PC_WIDTH),
        .IMEM_WIDTH              (IMEM_WIDTH),
        .PC_WORD_WIDTH           (PC_WORD_WIDTH),
        .ARCH_REG_COUNT          (ARCH_REG_COUNT),
        .ARCH_REG_WIDTH          (ARCH_REG_WIDTH),
        .REG_FILE_DATA_WIDTH     (REG_FILE_DATA_WIDTH),
        .PHY_REG_IDX_WIDTH       (PHY_REG_IDX_WIDTH),
        .DMEM_WIDTH              (DMEM_WIDTH),
        .DMEM_ADDR_WIDTH         (DMEM_ADDR_WIDTH),
        .BPB_PC_BITS             (BPB_PC_BITS),
        .NUM_WAYS                (NUM_WAYS),
        .IFQ_DEPTH               (IFQ_DEPTH),
        .RAS_DEPTH               (RAS_DEPTH),
        .FRL_DEPTH               (FRL_DEPTH),
        .FRL_PTR_WIDTH           (FRL_PTR_WIDTH),
        .NUM_CHECKPOINT          (NUM_CHECKPOINT),
        .ROB_DEPTH               (ROB_DEPTH),
        .ROB_INDEX_WIDTH         (ROB_INDEX_WIDTH),
        .SB_DEPTH                (SB_DEPTH),
        .SB_INDEX_WIDTH          (SB_INDEX_WIDTH),
        .OPCODE_WIDTH            (OPCODE_WIDTH),
        .FENCE_I_COHERENCE       (FENCE_I_COHERENCE)
    ) front_end (
        .clk                             (clk),
        .rst_n                           (rst_n),

        // Cache coherence handshake
        .fence_i_coh_start               (fence_i_coh_start),
        .fence_i_coh_done                (fence_i_coh_done),

        // I-Cache
        .imem_addr                       (imem_addr),
        .imem_req_valid                  (imem_req_valid),
        .imem_req_ready                  (imem_req_ready),
        .imem_resp_data                  (imem_resp_data),
        .imem_resp_valid                 (imem_resp_valid),
        .imem_resp_ready                 (imem_resp_ready),

        // D-Cache store port (SB → D-Cache)
        .dcache_st_ready                 (dcache_wready),
        .dcache_st_resp_valid            (dcache_wresp_valid),
        .dcache_sw_addr                  (dcache_sw_addr),
        .dcache_sw_data                  (dcache_sw_data),
        .dcache_sw_strb                  (dcache_wstrb),
        .dcache_st_valid                 (dcache_wvalid),
        .dcache_st_resp_ready            (dcache_wresp_ready),

        // Front-end ↔ back-end channels (interfaces)
        .dispatch_bus                    (dispatch_bus.producer),
        .cdb_bus                         (cdb_bus.consumer),
        .issq_bus                        (issq_bus.consumer),
        .rob_sb_bus                      (rob_sb_bus.producer),
        .sb_bus                          (sb_bus.producer),

        // Store-source / CSR rs1 PRF read
        .st_src_phy_addr                 (st_src_phy_addr),
        .st_src_data                     (st_src_data),

        // CSR write-back to PRF
        .csr_wr_phy_addr                 (csr_wr_phy_addr),
        .csr_wr_data                     (csr_wr_data),
        .csr_wr_en                       (csr_wr_en)
    );

    // ----------------------------------------------------------------
    // Back-End
    // ----------------------------------------------------------------
    CPU_BACK_END #(
        .XLEN                    (REG_FILE_DATA_WIDTH),
        .INSTR_WIDTH             (INSTR_WIDTH),
        .ARCH_REG_COUNT          (ARCH_REG_COUNT),
        .ARCH_REG_WIDTH          (ARCH_REG_WIDTH),
        .PHY_REG_IDX_WIDTH       (PHY_REG_IDX_WIDTH),
        .REG_FILE_DATA_WIDTH     (REG_FILE_DATA_WIDTH),
        .DMEM_WIDTH              (DMEM_WIDTH),
        .DMEM_ADDR_WIDTH         (DMEM_ADDR_WIDTH),
        .PC_WIDTH                (PC_WIDTH),
        .ROB_DEPTH               (ROB_DEPTH),
        .ROB_INDEX_WIDTH         (ROB_INDEX_WIDTH),
        .ISSUE_QUEUE_DEPTH       (ISSUE_QUEUE_DEPTH),
        .SB_DEPTH                (SB_DEPTH),
        .LSB_DEPTH               (LSB_DEPTH),
        .BPB_PC_BITS             (BPB_PC_BITS),
        .DIV_CYCLES              (DIV_CYCLES),
        .MUL_CYCLES              (MUL_CYCLES),
        .INT_CYCLES              (INT_CYCLES),
        .LD_ST_CYCLES            (LD_ST_CYCLES),
        .OPCODE_WIDTH            (OPCODE_WIDTH)
    ) back_end (
        .clk                             (clk),
        .rst_n                           (rst_n),

        // Front-end ↔ back-end channels (interfaces)
        .dispatch_bus                    (dispatch_bus.consumer),
        .cdb_bus                         (cdb_bus.producer),
        .issq_bus                        (issq_bus.producer),
        .rob_sb_bus                      (rob_sb_bus.consumer),
        .sb_bus                          (sb_bus.consumer),

        // Store-source / CSR rs1 PRF read
        .st_src_phy_addr                 (st_src_phy_addr),
        .st_src_data                     (st_src_data),

        // CSR write-back to PRF
        .csr_wr_phy_addr                 (csr_wr_phy_addr),
        .csr_wr_data                     (csr_wr_data),
        .csr_wr_en                       (csr_wr_en),

        // D-Cache load port
        .dcache_ld_ready                 (dcache_rready),
        .dcache_ld_resp_valid            (dcache_rresp_valid),
        .dcache_ld_rdata                 (dcache_rdata),
        .dcache_ld_addr                  (dcache_raddr),
        .dcache_ld_valid                 (dcache_rvalid),
        .dcache_ld_resp_ready            (dcache_rresp_ready),

        // LSB sideband
        .lsb_rob_tag                     (lsb_rob_tag),
        .lsb_rd_phy_addr                 (lsb_rd_phy_addr),
        .lsb_data                        (lsb_data),
        .lsb_rw                          (lsb_rw),
        .lsb_sw_addr                     (lsb_sw_addr),
        .lsb_result_valid                (lsb_result_valid)
    );

    // synthesis translate_off
    assign front_end.rob.sim_cdb_rd_data = cdb_bus.rd_data;
    // synthesis translate_on

endmodule
