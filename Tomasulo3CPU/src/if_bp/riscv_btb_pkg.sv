`timescale 1ns/1ps

package riscv_btb_pkg;

  typedef enum logic [2:0] {
    BTB_NONE   = 3'd0,
    // BEQ/BNE/BLT/BGE/BLTU/BGEU and compressed C.BEQZ/C.BNEZ
    BTB_COND   = 3'd1,
    // JAL or C.J
    BTB_JUMP   = 3'd2,
    // JAL x1/x5, target is direct immediate
    BTB_CALL   = 3'd3,
    // JALR indirect jump, not call/return
    BTB_IND    = 3'd4,
    // JALR call, usually rd = x1/x5
    BTB_ICALL  = 3'd5,
    // JALR return, usually rs1 = x1/x5 and rd = x0
    BTB_RET    = 3'd6
  } btb_br_type_e;


  typedef enum logic [1:0] {
    BIM_STRONGLY_NT = 2'b00,
    BIM_WEAKLY_NT   = 2'b01,
    BIM_WEAKLY_T    = 2'b10,
    BIM_STRONGLY_T  = 2'b11
  } bim_ctr_e;


  typedef enum logic [2:0] {
    RAS_OP_NONE      = 3'd0,
    RAS_OP_PUSH      = 3'd1,
    RAS_OP_POP       = 3'd2,
    RAS_OP_POP_PUSH  = 3'd3
  } ras_op_e;

endpackage
