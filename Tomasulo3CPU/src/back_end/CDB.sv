// Registered CDB Fields
// Valid    RobTag  RobDepth    RdPhyAddr   Data    RW  Flush   Branch  BrOutcome   BrAddr  BrPC[4:2]   SWaddr
// 1b       5b      5b          6b          32b     1b  1b      1b      1b          32b     3b          32b


module CDB #(
    parameter int unsigned INSTR_WIDTH = 64,
    parameter int unsigned ARCH_REG_COUNT = 32,
    parameter int unsigned ARCH_REG_WIDTH = $clog2(ARCH_REG_COUNT),
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned NUM_CHECKPOINT = 8,
    parameter int unsigned CHECKPOINT_PTR_WIDTH = $clog2(NUM_CHECKPOINT)
) (
    input logic clk,
    input logic rst_n,

    // ROB interface


    // PRF interface


    // ISSUE interface


    // EXE interface


    // SAB interface


    // BPB interface


    // DISPATCH interface


    
);




endmodule