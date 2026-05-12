// By default:
// PC[4:2] 3-bit LSB used for indexing into BPB
// 8 entries in BPB, each entry is 2 bits for 2-bit saturating counter
module BPB #(
    parameter int unsigned BUFFER_WIDTH = 3,
    localparam int unsigned BUFFER_SIZE = 2**BUFFER_WIDTH,
    // should be hardcoded to 2 for 2-bit saturating counter although it's now a configurable parameter
    parameter int unsigned FSM_WIDTH = 2 
) (
    input  logic clk,
    input  logic rst_n,

    // DISPATCH interface
    input  logic [BUFFER_WIDTH-1:0]     dis_bpb_branch_pc_bits,
    input  logic                        dis_bpb_branch,

    output logic                        bpb_branch_prediction,

    // CDB interface
    input  logic                        dis_cdb_upd_branch,
    input  logic [BUFFER_WIDTH-1:0]     dis_cdb_upd_branch_addr,
    // 1: taken, 0: not taken
    input  logic                        dis_cdb_branch_outcome
);

    logic [FSM_WIDTH-1:0] dis_cdb_upd_branch_outcome_reg;
    logic [FSM_WIDTH-1:0] dis_cdb_upd_branch_outcome_reg_next;

    // The BPB array: simple direct-mapped BPB with size 8x2
    // a: read-only port for DISPATCH to read the prediction
    // b: read-write port for CDB to update the BPB based on branch outcomes
    dual_port_memory #(
        .DATA_WIDTH(FSM_WIDTH),
        .DEPTH(BUFFER_SIZE),
        .READBEFOREWRITE(1)
    ) bpb_memory (
        .clk(clk),
        .rst_n(rst_n),
        .data_in_a(), // Not used
        .data_in_b(dis_cdb_upd_branch_outcome_reg_next),
        .write_en_a(1'b0),
        .write_en_b(dis_cdb_upd_branch),
        .read_en_a(dis_bpb_branch),
        .read_en_b(1'b1),
        .address_a(dis_bpb_branch_pc_bits),
        .address_b(dis_cdb_upd_branch_addr),
        .data_out_a(bpb_branch_prediction), 
        .data_out_b(dis_cdb_upd_branch_outcome_reg)  
    );
    // 2-bit prediction FSM -> FSM_WIDTH = 2
    // 00: strongly not taken
    // 01: taken
    // 10: not taken
    // 11: strongly taken

    assign dis_cdb_upd_branch_outcome_reg_next = (dis_cdb_branch_outcome) ? 
        (dis_cdb_upd_branch_outcome_reg + 1) :
        (dis_cdb_upd_branch_outcome_reg - 1);
endmodule