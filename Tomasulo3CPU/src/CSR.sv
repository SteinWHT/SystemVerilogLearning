// Machine-mode CSR file for the current single-hart RV64 core.
//
// This block is intentionally small: it implements the CSRs needed for
// CSR read/modify/write instructions plus minimal ECALL/EBREAK/MRET trap
// handling. It is meant to be called from the in-order retirement side of
// the CPU so traps remain precise.
module CSR
    import riscv_types_pkg::*;
#(
    parameter int unsigned REG_FILE_WIDTH = 64,
    parameter int unsigned CSR_ADDR_WIDTH = 12
) (
    input  logic                           clk,
    input  logic                           rst_n,

    // CSR instruction interface.
    // csr_rdata is the old CSR value and should be written to rd by CSRxx.
    input  logic                           csr_valid,
    input  csr_cmd_e                       csr_cmd,
    input  logic [CSR_ADDR_WIDTH-1:0]      csr_addr,
    input  logic [REG_FILE_WIDTH-1:0]      csr_rs1_data,
    input  logic                           csr_rs1_is_x0,
    input  logic [4:0]                     csr_zimm,

    output logic [REG_FILE_WIDTH-1:0]      csr_rdata,
    output logic                           csr_result_valid,
    output logic                           csr_illegal_access,

    // Trap/return interface.
    // ECALL and EBREAK are synchronous traps; current_pc is written to mepc.
    input  logic                           ecall_valid,
    input  logic                           ebreak_valid,
    input  logic                           mret_valid,
    input  logic [REG_FILE_WIDTH-1:0]      current_pc,
    input  logic [REG_FILE_WIDTH-1:0]      trap_value,

    output logic                           redirect_valid,
    output logic [REG_FILE_WIDTH-1:0]      redirect_pc,

    // Debug/observation outputs. These are also convenient when wiring tests.
    output logic [REG_FILE_WIDTH-1:0]      mstatus,
    output logic [REG_FILE_WIDTH-1:0]      mtvec,
    output logic [REG_FILE_WIDTH-1:0]      mscratch,
    output logic [REG_FILE_WIDTH-1:0]      mepc,
    output logic [REG_FILE_WIDTH-1:0]      mcause,
    output logic [REG_FILE_WIDTH-1:0]      mtval
);

    // Machine exception causes used by the minimal trap path.
    localparam logic [REG_FILE_WIDTH-1:0] MCAUSE_EBREAK = REG_FILE_WIDTH'(3);
    localparam logic [REG_FILE_WIDTH-1:0] MCAUSE_ECALL_MMODE = REG_FILE_WIDTH'(11);

    // mstatus bits modeled by this CPU. The rest are kept zero for now.
    localparam int unsigned MSTATUS_MIE_BIT  = 3;
    localparam int unsigned MSTATUS_MPIE_BIT = 7;
    localparam int unsigned MSTATUS_MPP_LSB  = 11;
    localparam int unsigned MSTATUS_MPP_MSB  = 12;
    localparam logic [1:0]  PRIV_M           = 2'b11;
    localparam logic [1:0]  PRIV_U           = 2'b00;

    logic [REG_FILE_WIDTH-1:0] mstatus_q, mtvec_q, mscratch_q;
    logic [REG_FILE_WIDTH-1:0] mepc_q, mcause_q, mtval_q;

    logic [REG_FILE_WIDTH-1:0] csr_operand;
    logic [REG_FILE_WIDTH-1:0] csr_next_data;
    logic                      csr_supported;
    logic                      csr_write_enable;
    logic                      trap_enter;

    assign mstatus = mstatus_q;
    assign mtvec = mtvec_q;
    assign mscratch = mscratch_q;
    assign mepc = mepc_q;
    assign mcause = mcause_q;
    assign mtval = mtval_q;

    assign trap_enter = ecall_valid || ebreak_valid;

    // Synchronous traps jump to the BASE part of mtvec. ECALL/EBREAK are not
    // interrupts, so vectored mode still uses BASE rather than BASE+4*cause.
    assign redirect_valid = trap_enter || mret_valid;
    assign redirect_pc = trap_enter ? {mtvec_q[REG_FILE_WIDTH-1:2], 2'b00} :
                         mret_valid ? {mepc_q[REG_FILE_WIDTH-1:2], 2'b00} :
                         '0;

    assign csr_result_valid = csr_valid && !csr_illegal_access;
    assign csr_illegal_access = csr_valid && !csr_supported;

    // Immediate CSR instructions use the zero-extended zimm field instead of
    // rs1 data. The decoder already separates the command type for us.
    always_comb begin
        unique case (csr_cmd)
            CSR_CMD_RWI, CSR_CMD_RSI, CSR_CMD_RCI: csr_operand = REG_FILE_WIDTH'(csr_zimm);
            default:                               csr_operand = csr_rs1_data;
        endcase
    end

    always_comb begin
        csr_supported = 1'b1;
        csr_rdata = '0;

        unique case (CSR_ADDR_WIDTH'(csr_addr))
            CSR_ADDR_MSTATUS:  csr_rdata = mstatus_q;
            CSR_ADDR_MTVEC:    csr_rdata = mtvec_q;
            CSR_ADDR_MSCRATCH: csr_rdata = mscratch_q;
            CSR_ADDR_MEPC:     csr_rdata = mepc_q;
            CSR_ADDR_MCAUSE:   csr_rdata = mcause_q;
            CSR_ADDR_MTVAL:    csr_rdata = mtval_q;
            default: begin
                csr_supported = 1'b0;
                csr_rdata = '0;
            end
        endcase
    end

    // CSRRS/CSRRC do not write when rs1 is x0; CSRRSI/CSRRCI do not write
    // when zimm is zero. CSRRW/CSRRWI always write.
    always_comb begin
        csr_write_enable = 1'b0;

        if (csr_valid && !csr_illegal_access) begin
            unique case (csr_cmd)
                CSR_CMD_RW, CSR_CMD_RWI: csr_write_enable = 1'b1;
                CSR_CMD_RS, CSR_CMD_RC:  csr_write_enable = !csr_rs1_is_x0;
                CSR_CMD_RSI, CSR_CMD_RCI: csr_write_enable = (csr_zimm != '0);
                default:                 csr_write_enable = 1'b0;
            endcase
        end
    end

    always_comb begin
        csr_next_data = csr_rdata;

        unique case (csr_cmd)
            CSR_CMD_RW, CSR_CMD_RWI:  csr_next_data = csr_operand;
            CSR_CMD_RS, CSR_CMD_RSI:  csr_next_data = csr_rdata | csr_operand;
            CSR_CMD_RC, CSR_CMD_RCI:  csr_next_data = csr_rdata & ~csr_operand;
            default:                  csr_next_data = csr_rdata;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus_q  <= '0;
            mtvec_q    <= '0;
            mscratch_q <= '0;
            mepc_q     <= '0;
            mcause_q   <= '0;
            mtval_q    <= '0;
        end else begin
            if (csr_write_enable) begin
                unique case (CSR_ADDR_WIDTH'(csr_addr))
                    CSR_ADDR_MSTATUS:  mstatus_q  <= mask_mstatus(csr_next_data);
                    CSR_ADDR_MTVEC:    mtvec_q    <= csr_next_data;
                    CSR_ADDR_MSCRATCH: mscratch_q <= csr_next_data;
                    CSR_ADDR_MEPC:     mepc_q     <= {csr_next_data[REG_FILE_WIDTH-1:2], 2'b00};
                    CSR_ADDR_MCAUSE:   mcause_q   <= csr_next_data;
                    CSR_ADDR_MTVAL:    mtval_q    <= csr_next_data;
                    default: begin
                    end
                endcase
            end

            if (trap_enter) begin
                // Save the interrupted instruction and cause. The pipeline
                // should redirect using redirect_pc in the same cycle.
                mepc_q <= {current_pc[REG_FILE_WIDTH-1:2], 2'b00};
                mcause_q <= ebreak_valid ? MCAUSE_EBREAK : MCAUSE_ECALL_MMODE;
                mtval_q <= trap_value;

                mstatus_q[MSTATUS_MPIE_BIT] <= mstatus_q[MSTATUS_MIE_BIT];
                mstatus_q[MSTATUS_MIE_BIT] <= 1'b0;
                mstatus_q[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] <= PRIV_M;
            end else if (mret_valid) begin
                // Return from trap: restore interrupt enable and clear MPP.
                mstatus_q[MSTATUS_MIE_BIT] <= mstatus_q[MSTATUS_MPIE_BIT];
                mstatus_q[MSTATUS_MPIE_BIT] <= 1'b1;
                mstatus_q[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] <= PRIV_U;
            end
        end
    end

    function automatic logic [REG_FILE_WIDTH-1:0] mask_mstatus(
        input logic [REG_FILE_WIDTH-1:0] value
    );
        mask_mstatus = '0;
        mask_mstatus[MSTATUS_MIE_BIT] = value[MSTATUS_MIE_BIT];
        mask_mstatus[MSTATUS_MPIE_BIT] = value[MSTATUS_MPIE_BIT];
        mask_mstatus[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] =
                value[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB];
    endfunction

endmodule

