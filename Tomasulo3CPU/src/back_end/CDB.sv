// Registered CDB Fields
// Valid    RobTag  RobDepth    RdPhyAddr   Data    RW  Flush   Branch  BrOutcome   BrAddr  BrPC[4:2]   SWaddr
// 1b       5b      5b          6b          64b     1b  1b      1b      1b          32b     3b          32b


module CDB #(
    parameter int unsigned REG_FILE_DATA_WIDTH = 64,
    parameter int unsigned IMEM_DEPTH = 64,
    parameter int unsigned DMEM_WIDTH = 64,
    parameter int unsigned DMEM_DEPTH = 32,
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned ROB_INDEX_WIDTH = 5,
    parameter int unsigned ROB_DEPTH = 32,
    parameter int unsigned BPB_PC_BITS = 3,
    parameter int unsigned W_BYTE_NUM = DMEM_WIDTH / 8
) (
    input logic clk,
    input logic rst_n,

    // ROB interface
    input logic [ROB_INDEX_WIDTH-1:0]           rob_top_ptr,

    output logic                                cdb_valid,
    output logic [ROB_INDEX_WIDTH-1:0]          cdb_rob_tag,
    output logic [DMEM_DEPTH-1:0]               cdb_sw_addr,
    output logic [W_BYTE_NUM-1:0]               cdb_sw_strb,
    output logic                                cdb_flush,

    // PRF interface
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  cdb_rd_phy_addr,
    output logic [REG_FILE_DATA_WIDTH-1:0]      cdb_rd_data,
    output logic                                cdb_reg_write,

    // RBA interface
    //input logic [PHY_REGISTER_FILE_WIDTH-1:0]   cdb_rd_phy_addr,
    //input logic                                 cdb_reg_write,

    // ISSUEQ interface
    // output logic                                cdb_flush,
    output logic [ROB_INDEX_WIDTH-1:0]          cdb_rob_depth,
    //output logic [PHY_REGISTER_FILE_WIDTH-1:0]  cdb_rd_phy_addr,
    // output logic                               cdb_reg_write,

    // EXE interface
    input logic                                 exe_valid,
    input logic [ROB_INDEX_WIDTH-1:0]           exe_rob_tag,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   exe_rd_phy_addr,
    input logic [REG_FILE_DATA_WIDTH-1:0]       exe_rd_data,
    input logic                                 exe_reg_write,
    input logic                                 exe_branch_mispredicted,
    input logic                                 exe_branch,
    input logic                                 exe_jr_inst,
    input logic                                 exe_jr31_inst,
    input logic                                 exe_jal_inst,
    input logic [BPB_PC_BITS-1:0]               exe_branch_pc_bits,
    input logic [IMEM_DEPTH-1:0]                exe_branch_other_addr,

    // LSB interface
    input logic [ROB_INDEX_WIDTH-1:0]           lsb_rob_tag,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   lsb_rd_phy_addr,
    input logic [REG_FILE_DATA_WIDTH-1:0]       lsb_data,
    input logic                                 lsb_rw,
    input logic [DMEM_DEPTH-1:0]                lsb_sw_addr,
    input logic [W_BYTE_NUM-1:0]                lsb_sw_strb,
    input logic                                 lsb_ready,

    //output  logic                             cdb_flush,
    //output  logic [ROB_INDEX_WIDTH-1:0]       cdb_rob_depth,

    //output logic [ROB_INDEX_WIDTH-1:0]               cdb_rob_depth,
    //output logic [PHY_REGISTER_FILE_WIDTH-1:0]       cdb_rd_phy_addr,
    //output logic                                     cdb_phy_reg_write,
    //output logic [REG_FILE_DATA_WIDTH-1:0]           cdb_rd_data,
    //output logic                                     cdb_reg_write,

    // BPB interface
    output  logic                               cdb_upd_branch,
    output  logic [BPB_PC_BITS-1:0]             cdb_upd_branch_addr,
    output  logic                               cdb_branch_outcome,

    // DISPATCH interface
    //output  logic                                    cdb_valid,
    output  logic [IMEM_DEPTH-1:0]              cdb_branch_addr
    //output  logic                                    cdb_flush,
);
    logic valid;
    typedef struct packed {
        logic [ROB_INDEX_WIDTH-1:0] rob_tag;
        logic [DMEM_DEPTH-1:0] addr;
        logic [REG_FILE_DATA_WIDTH-1:0] data;
        logic rw;
        logic flush;
        logic branch;
        logic [BPB_PC_BITS-1:0] branch_pc;
        logic [IMEM_DEPTH-1:0] branch_addr;
        logic [DMEM_DEPTH-1:0] sw_addr;
        logic [W_BYTE_NUM-1:0] sw_strb;
    } cdb_entry_t;

    cdb_entry_t cdb_entry;

    logic flush;
    logic [IMEM_DEPTH-1:0] branch_other_addr;
    always_comb begin
        flush = 1'b0;
        branch_other_addr = '0;
        if (((exe_branch || exe_jr31_inst) && exe_branch_mispredicted) || exe_jr_inst) begin
            flush = 1'b1;
            branch_other_addr = exe_branch_other_addr;
        end
    end

    always_comb begin
        if (exe_valid) begin
            valid = 1'b1;
            cdb_entry = '{
                rob_tag: exe_rob_tag,
                addr: exe_rd_phy_addr,
                data: exe_rd_data,
                rw: exe_reg_write,
                flush: flush,
                branch: exe_branch,
                branch_pc: exe_branch_pc_bits,
                branch_addr: branch_other_addr,
                sw_addr: '0,
                sw_strb: '0
            };
        end else if (lsb_ready) begin
            valid = 1'b1;
            cdb_entry = '{
                rob_tag: lsb_rob_tag,
                addr: lsb_rd_phy_addr,
                data: lsb_data,
                rw: lsb_rw,
                flush: 1'b0,
                branch: 1'b0,
                branch_pc: '0,
                branch_addr: '0,
                sw_addr: lsb_sw_addr,
                sw_strb: lsb_sw_strb
            };
        end else begin
            valid = 1'b0;
            cdb_entry = '{
                rob_tag: '0,
                addr: '0,
                data: '0,
                rw: 1'b0,
                flush: 1'b0,
                branch: 1'b0,
                branch_pc: '0,
                branch_addr: '0,
                sw_addr: '0,
                sw_strb: '0
            };
        end
    end

    assign cdb_valid = valid;
    assign cdb_rob_tag = cdb_entry.rob_tag;
    assign cdb_rd_phy_addr = cdb_entry.addr;
    assign cdb_rd_data = cdb_entry.data;
    assign cdb_reg_write = cdb_entry.rw;
    assign cdb_flush = cdb_entry.flush;
    assign cdb_branch_addr = cdb_entry.branch_addr;
    assign cdb_sw_addr = cdb_entry.sw_addr;
    assign cdb_sw_strb = cdb_entry.sw_strb;

    assign cdb_rob_depth = cdb_rob_tag - rob_top_ptr;
    assign cdb_upd_branch = cdb_entry.branch;
    assign cdb_upd_branch_addr = cdb_entry.branch_pc;
    assign cdb_branch_outcome = !cdb_entry.flush;

    // synthesis translate_off
    CDB_VALID_ASSERT: assert property (@(posedge clk) disable iff (!rst_n)
    !(exe_valid && lsb_ready)) else $error("CDB: EXE and LSB are both valid at the same time");
    // synthesis translate_on
endmodule
