class cpu_base_item extends uvm_sequence_item;

    // Stimulus identity (for scoreboard / debug)
    int unsigned            seq_id;
    bit [63:0]              pc;

    // Instruction identity
    rand riscv_instr_name_e   instr_name;
    rand riscv_instr_format_e instr_format;

    rand bit [4:0]  rs1;
    rand bit [4:0]  rs2;
    rand bit [4:0]  rd;

    rand bit [63:0] rs1_data;
    rand bit [63:0] rs2_data;

    bit [63:0] expected_result;
    bit        checks_enabled = 1'b1;

    bit [6:0]  opcode;
    bit [2:0]  funct3;
    bit [6:0]  funct7;
    rand bit [31:0] imm;
    bit [31:0] instr;

    constraint c_reg_range {
        rs1 inside {[5'd0:5'd31]};
        rs2 inside {[5'd0:5'd31]};
        rd  inside {[5'd0:5'd31]};
    }

    constraint c_rd_not_x0 {
        rd != 5'd0;
    }

    `uvm_object_utils_begin(cpu_base_item)
        `uvm_field_int(seq_id,            UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(pc,                UVM_ALL_ON | UVM_HEX)
        `uvm_field_enum(riscv_instr_name_e,   instr_name,       UVM_ALL_ON)
        `uvm_field_enum(riscv_instr_format_e, instr_format,     UVM_ALL_ON)
        `uvm_field_int(rs1,               UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(rs2,               UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(rd,                UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(rs1_data,          UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(rs2_data,          UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(expected_result,   UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(checks_enabled,    UVM_ALL_ON)
        `uvm_field_int(opcode,            UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(funct3,            UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(funct7,            UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(imm,               UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(instr,             UVM_ALL_ON | UVM_HEX)
    `uvm_object_utils_end

    function new(string name = "cpu_base_item");
        super.new(name);
    endfunction

    function void post_randomize();
        set_encoding_fields();
        build_instruction();
        calculate_expected_result();
    endfunction

    virtual function void set_encoding_fields();
        `uvm_fatal(get_type_name(),
            "set_encoding_fields() must be implemented in a derived item")
    endfunction

    virtual function void build_instruction();
        case (instr_format)
            RISCV_FMT_R: begin
                instr = {funct7, rs2, rs1, funct3, rd, opcode};
            end
            RISCV_FMT_I: begin
                instr = {imm[11:0], rs1, funct3, rd, opcode};
            end
            RISCV_FMT_S: begin
                instr = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
            end
            RISCV_FMT_B: begin
                instr = {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode};
            end
            RISCV_FMT_U: begin
                instr = {imm[31:12], rd, opcode};
            end
            RISCV_FMT_J: begin
                instr = {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
            end
            default: begin
                `uvm_fatal(get_type_name(), $sformatf("Unsupported format %0d", instr_format))
            end
        endcase
    endfunction

    virtual function void calculate_expected_result();
        `uvm_fatal(get_type_name(),
            "calculate_expected_result() must be implemented in a derived item")
    endfunction

    // Override in derived items when an instruction does not write a GPR.
    virtual function bit expects_reg_write();
        return 1'b1;
    endfunction

    // Override when operands must be preloaded via PRF backdoor (R-type, etc.).
    virtual function bit needs_operand_preload();
        return (instr_format == RISCV_FMT_R);
    endfunction

    // Word index into imem_array; matches cpu_if.load_instr indexing.
    virtual function bit [63:0] imem_word_index();
        return pc[63:2];
    endfunction

    virtual function string instr_name_str();
        return $sformatf("%0d", instr_name);
    endfunction

    virtual function string convert2string();
        return $sformatf(
            "seq_id=%0d pc=0x%016h %s instr=0x%08h rd=x%0d rs1=x%0d rs2=x%0d rs1_data=0x%016h rs2_data=0x%016h expected=0x%016h",
            seq_id, pc, instr_name_str(), instr, rd, rs1, rs2, rs1_data, rs2_data, expected_result
        );
    endfunction

endclass
