module DIV 
import riscv_types_pkg::*;
#(
    parameter int unsigned XLEN = 64,
    parameter int unsigned OPCODE_WIDTH = 7,
    parameter int unsigned REG_FILE_DATA_WIDTH = 64,
    parameter int unsigned ROB_INDEX_WIDTH = 5,
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned DIV_CYCLES = 64
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
    input logic                                     valid,

    // ISSUE UNIT interface
    output logic                                    div_exe_ready,

    // CDB interface
    input logic                                     cdb_flush,
    input logic [ROB_INDEX_WIDTH-1:0]               cdb_rob_depth,

    // ROB interface
    input logic [ROB_INDEX_WIDTH-1:0]               rob_top_ptr,

    output logic [ROB_INDEX_WIDTH-1:0]              exe_rob_tag,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]      exe_rd_phy_addr,
    output logic [REG_FILE_DATA_WIDTH-1:0]          exe_rd_data,
    output logic                                    exe_reg_write,
    output logic                                    exe_result_valid
);

    logic is_unsigned_op;
    logic is_word_op;

    logic zero_divisor;
    logic killed;
    logic                                     div_valid;
    logic [OPCODE_WIDTH-1:0]                  div_opcode;
    logic [ROB_INDEX_WIDTH-1:0]               div_rob_tag;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]       div_rd_phy_addr;
    logic [XLEN-1:0]                          dw_dividend;
    logic                                     is_unsigned_lat;

    always_comb begin
        unique case (instr_e'(opcode))
            INSTR_DIVU, INSTR_REMU, INSTR_DIVUW, INSTR_REMUW: is_unsigned_op = 1'b1;
            default: is_unsigned_op = 1'b0;
        endcase
        unique case (instr_e'(opcode))
            INSTR_DIVW, INSTR_REMW, INSTR_DIVUW, INSTR_REMUW: is_word_op = 1'b1;
            default: is_word_op = 1'b0;
        endcase
    end

    // Conditioned operands: narrow for W variants, full width otherwise
    logic [XLEN-1:0] a_cond, b_cond;
    always_comb begin
        if (is_word_op && is_unsigned_op) begin
            a_cond = {{32{1'b0}}, rs_data_div[31:0]};
            b_cond = {{32{1'b0}}, rt_data_div[31:0]};
        end else if (is_word_op) begin
            a_cond = {{32{rs_data_div[31]}}, rs_data_div[31:0]};
            b_cond = {{32{rt_data_div[31]}}, rt_data_div[31:0]};
        end else begin
            a_cond = rs_data_div;
            b_cond = rt_data_div;
        end
    end

    // Safe divisor: replace zero with 1 to avoid DW_div_seq issues
    logic [XLEN-1:0] b_safe;
    assign b_safe = (valid && (b_cond != '0)) ? b_cond : {{(XLEN-1){1'b0}}, 1'b1};

    logic start_s, start_u;
    logic complete_s, complete_u, complete;
    logic [XLEN-1:0] quotient_s, remainder_s;
    logic [XLEN-1:0] quotient_u, remainder_u;
    logic busy;

    assign start_s = valid && !is_unsigned_op;
    assign start_u = valid && is_unsigned_op;
    assign complete = is_unsigned_lat ? complete_u : complete_s;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy            <= 1'b0;
            zero_divisor    <= 1'b0;
            dw_dividend     <= '0;
            is_unsigned_lat <= 1'b0;
        end else begin
            if (valid) begin
                busy            <= 1'b1;
                dw_dividend     <= a_cond;
                is_unsigned_lat <= is_unsigned_op;
                zero_divisor    <= (b_cond == '0);
            end else if (complete && busy) begin
                busy <= 1'b0;
            end
        end
    end

    always_comb begin
        killed = 1'b0;
        if (cdb_flush)
            killed = (cdb_rob_depth < (div_rob_tag - rob_top_ptr));
    end

    // Select quotient/remainder from the active divider
    logic [XLEN-1:0] quotient, remainder;
    assign quotient  = is_unsigned_lat ? quotient_u  : quotient_s;
    assign remainder = is_unsigned_lat ? remainder_u : remainder_s;

    // Result formation with divide-by-zero and W-variant sign extension
    logic [REG_FILE_DATA_WIDTH-1:0] result_next;
    logic is_rem_lat, is_word_lat;

    always_comb begin
        unique case (instr_e'(div_opcode))
            INSTR_REM, INSTR_REMU, INSTR_REMW, INSTR_REMUW: is_rem_lat = 1'b1;
            default: is_rem_lat = 1'b0;
        endcase
        unique case (instr_e'(div_opcode))
            INSTR_DIVW, INSTR_REMW, INSTR_DIVUW, INSTR_REMUW: is_word_lat = 1'b1;
            default: is_word_lat = 1'b0;
        endcase
    end

    always_comb begin
        if (zero_divisor) begin
            if (is_rem_lat)
                result_next = dw_dividend;                      // REM(x,0) = x
            else
                result_next = {REG_FILE_DATA_WIDTH{1'b1}};      // DIV(x,0) = -1
        end else begin
            result_next = is_rem_lat ? remainder : quotient;
        end
        if (is_word_lat)
            result_next = {{32{result_next[31]}}, result_next[31:0]};
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_valid       <= 1'b0;
            div_opcode      <= '0;
            div_rob_tag     <= '0;
            div_rd_phy_addr <= '0;
            exe_rd_data     <= '0;
        end else begin
            exe_rd_data         <= result_next;
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

    // Signed divider (DIV, REM, DIVW, REMW)
    DW_div_seq #(
        .a_width     (XLEN),
        .b_width     (XLEN),
        .tc_mode     (1),
        .num_cyc     (DIV_CYCLES),
        .rst_mode    (1),
        .input_mode  (1),
        .output_mode (1),
        .early_start (0)
    ) u_div_signed (
        .clk         (clk),
        .rst_n       (rst_n),
        .hold        (1'b0),
        .start       (start_s),
        .a           (a_cond),
        .b           (b_safe),
        .complete    (complete_s),
        .divide_by_0 (),
        .quotient    (quotient_s),
        .remainder   (remainder_s)
    );

    // Unsigned divider (DIVU, REMU, DIVUW, REMUW)
    DW_div_seq #(
        .a_width     (XLEN),
        .b_width     (XLEN),
        .tc_mode     (0),
        .num_cyc     (DIV_CYCLES),
        .rst_mode    (1),
        .input_mode  (1),
        .output_mode (1),
        .early_start (0)
    ) u_div_unsigned (
        .clk         (clk),
        .rst_n       (rst_n),
        .hold        (1'b0),
        .start       (start_u),
        .a           (a_cond),
        .b           (b_safe),
        .complete    (complete_u),
        .divide_by_0 (),
        .quotient    (quotient_u),
        .remainder   (remainder_u)
    );

    assign exe_rob_tag      = div_rob_tag;
    assign exe_rd_phy_addr  = div_rd_phy_addr;
    assign exe_reg_write    = 1'b1;
    assign div_exe_ready    = !busy;

    // synthesis translate_off
    DIV_BUSY_ASSERT: assert property (@(posedge clk) disable iff (!rst_n)
    !(valid && busy)) else $error("DIV is busy when start is asserted");
    // synthesis translate_on

endmodule
