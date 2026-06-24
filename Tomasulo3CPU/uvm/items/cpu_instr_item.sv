// Generic, fully-resolved instruction item produced by the constrained-random
// program generator. Unlike the directed ADD/SUB items, every field is fixed
// by the generator (operands, immediate, encoding) so the IMEM image and the
// Spike golden model see identical bytes. Architectural correctness is checked
// by the Spike co-simulation scoreboard, not by a local result model.
class cpu_instr_item extends cpu_base_item;

    cpu_isa_op_e        op       = CPU_OP_NOP;
    cpu_hazard_kind_e   hazard   = CPU_HAZ_NONE;

    // Position in the generated program (instruction index, byte PC offset).
    int unsigned        prog_idx;

    // Dependency annotation for coverage (producer distance in instructions).
    int unsigned        dep_distance;

    // Full 64-bit immediate / branch offset / CSR address used for encoding.
    bit [63:0]          imm64;

    `uvm_object_utils_begin(cpu_instr_item)
        `uvm_field_enum(cpu_isa_op_e,      op,           UVM_ALL_ON)
        `uvm_field_enum(cpu_hazard_kind_e, hazard,       UVM_ALL_ON)
        `uvm_field_int(prog_idx,                         UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(dep_distance,                     UVM_ALL_ON | UVM_DEC)
    `uvm_object_utils_end

    function new(string name = "cpu_instr_item");
        super.new(name);
    endfunction

    // Build the 32-bit encoding from already-resolved fields. Called by the
    // generator after all operands/immediate are decided.
    function void finalize();
        bit [6:0] l_opcode;
        bit [2:0] l_funct3;
        bit [6:0] l_funct7;
        cpu_isa_encoder::fields_of(op, l_opcode, l_funct3, l_funct7);
        opcode       = l_opcode;
        funct3       = l_funct3;
        funct7       = l_funct7;
        instr_format = cpu_isa_encoder::format_of(op);
        imm          = imm64[31:0];
        instr        = cpu_isa_encoder::encode(op, rd, rs1, rs2, imm64);
    endfunction

    // Generic items are never set up through cpu_reg_setup.
    virtual function bit needs_operand_setup();
        return 1'b0;
    endfunction

    virtual function bit expects_reg_write();
        return cpu_isa_encoder::writes_rd(op) && (rd != 5'd0);
    endfunction

    // Overrides of the abstract base hooks: the generator fully resolves the
    // encoding, so post_randomize must not re-derive or fatal.
    virtual function void set_encoding_fields();
        // no-op: fields fixed by finalize()
    endfunction

    virtual function void calculate_expected_result();
        // no-op: golden value comes from Spike, not a local model
        expected_result = 64'h0;
    endfunction

    function void post_randomize();
        // Generic items are constructed procedurally; skip base auto-build.
    endfunction

    function string instr_name_str();
        return op.name();
    endfunction

    virtual function string convert2string();
        return $sformatf(
            "idx=%0d pc=0x%016h %s instr=0x%08h rd=x%0d rs1=x%0d rs2=x%0d imm=0x%016h haz=%s dist=%0d",
            prog_idx, pc, op.name(), instr, rd, rs1, rs2, imm64, hazard.name(), dep_distance);
    endfunction

endclass
