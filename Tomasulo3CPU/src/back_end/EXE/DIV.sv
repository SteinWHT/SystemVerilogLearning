module DIV 
import riscv_types_pkg::*;
#(
    parameter int unsigned XLEN = 64,
    parameter int unsigned OPCODE_WIDTH = 6,
    parameter int unsigned REG_FILE_DATA_WIDTH = 64,
    parameter int unsigned ROB_INDEX_WIDTH = 5,
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned DIV_CYCLES = 7
) (
    input logic clk,
    input logic rst_n,

    // PRF interface
    input logic [REG_FILE_DATA_WIDTH-1:0]           rs_data_div,
    input logic [REG_FILE_DATA_WIDTH-1:0]           rt_data_div,

    // ISSUEQ interface
    input logic [ROB_INDEX_WIDTH-1:0]               rob_tag,
    input logic [OPCODE_WIDTH-1:0]                  opcode,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]       rd_phy_addr,
    input logic [15:0]                              imm16,
    input logic                                     valid,

    // ISSUE UNIT interface
    output logic                                    div_exe_ready,

    // CDB interface
    input logic [ROB_INDEX_WIDTH-1:0]               cdb_flush,
    input logic [ROB_INDEX_WIDTH-1:0]               cdb_rob_depth,
    input logic [ROB_INDEX_WIDTH-1:0]               cdb_rob_tag,

    output logic [ROB_INDEX_WIDTH-1:0]              exe_rob_tag,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]      exe_rd_phy_addr,
    output logic [REG_FILE_DATA_WIDTH-1:0]          exe_rd_data,
    output logic                                    exe_reg_write,
    output logic                                    exe_result_valid
);

    logic start;
    logic complete;
    logic divide_by_0;
    logic [XLEN-1:0] quotient;
    logic [XLEN-1:0] remainder;
    logic busy;
    logic [XLEN-1:0] dw_divisor;

    assign dw_divisor = (valid && (rt_data_div != '0)) ?
        rt_data_div : {{(XLEN-1){1'b0}}, 1'b1};

    logic killed;
    logic                                     div_valid;
    logic [OPCODE_WIDTH-1:0]                  div_opcode;
    logic [ROB_INDEX_WIDTH-1:0]               div_rob_tag;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]       div_rd_phy_addr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy <= 1'b0;
        end else begin
            if (start) begin
                busy <= 1'b1;
            end else if (complete && busy) begin
                busy <= 1'b0;
            end
        end
    end

    always_comb begin
        killed = 1'b0;
        if (cdb_flush)
            killed = (cdb_rob_depth < (div_rob_tag - cdb_rob_tag));
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_valid       <= 1'b0;
            div_opcode      <= '0;
            div_rob_tag     <= '0;
            div_rd_phy_addr <= '0;
            exe_rd_data     <= '0;
        end else begin
            exe_rd_data         <= div_opcode == INSTR_DIV ? quotient : div_opcode == INSTR_REM ? remainder : '0;
            exe_result_valid    <= complete && div_valid && !killed;
            if (killed) begin
                div_valid       <= 1'b0;
            end else if (valid) begin
                div_valid       <= valid;
                div_opcode      <= opcode;
                div_rob_tag     <= rob_tag;
                div_rd_phy_addr <= rd_phy_addr;
            end else if (complete) begin
                div_valid       <= 1'b0;
            end
        end
    end

    assign start = valid;

    DW_div_seq #(
        .a_width     (XLEN),
        .b_width     (XLEN),
        .tc_mode     (0),        // 0 unsigned, 1 signed; check your local doc
        .num_cyc     (DIV_CYCLES),
        .rst_mode    (1),
        .input_mode  (1),
        .output_mode (1),
        .early_start (0)
    ) u_div_seq (
        .clk         (clk),
        .rst_n       (rst_n),
        .hold        (1'b0),
        .start       (start),

        .a           (rs_data_div),
        .b           (dw_divisor),

        .complete    (complete),
        .divide_by_0 (divide_by_0),
        .quotient    (quotient),
        .remainder   (remainder)
    );

    assign exe_rob_tag = div_rob_tag;
    assign exe_rd_phy_addr = div_rd_phy_addr;
    assign exe_reg_write = 1'b1;
    assign div_exe_ready    = !busy;

    // synthesis translate_off
    DIV_BUSY_ASSERT: assert property (@(posedge clk) disable iff (!rst_n)
    !(start && busy)) else $error("DIV is busy when start is asserted");
    // synthesis translate_on

endmodule
