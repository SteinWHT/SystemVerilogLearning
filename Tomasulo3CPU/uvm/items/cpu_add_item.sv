class cpu_add_item extends cpu_base_item;

    rand bit is_addw;

    constraint c_distinct_srcs {
        rs1 != rs2;
    }

    constraint c_add_instr {
        instr_format == RISCV_FMT_R;
        if (is_addw) {
            instr_name == RISCV_OP_ADDW;
        } else {
            instr_name == RISCV_OP_ADD;
        }
    }

    constraint c_add_corner_cases {
        rs1_data dist {
            64'h0000_0000_0000_0000 := 5,
            64'h0000_0000_0000_0001 := 5,
            64'hFFFF_FFFF_FFFF_FFFF := 5,
            64'h7FFF_FFFF_FFFF_FFFF := 5,
            64'h8000_0000_0000_0000 := 5,
            [64'h0000_0000_0000_0000:64'hFFFF_FFFF_FFFF_FFFF] :/ 80
        };
        rs2_data dist {
            64'h0000_0000_0000_0000 := 5,
            64'h0000_0000_0000_0001 := 5,
            64'hFFFF_FFFF_FFFF_FFFF := 5,
            64'h7FFF_FFFF_FFFF_FFFF := 5,
            64'h8000_0000_0000_0000 := 5,
            [64'h0000_0000_0000_0000:64'hFFFF_FFFF_FFFF_FFFF] :/ 80
        };
    }

    `uvm_object_utils_begin(cpu_add_item)
        `uvm_field_int(is_addw, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "cpu_add_item");
        super.new(name);
    endfunction

    virtual function void set_encoding_fields();
        funct3 = 3'b000;
        funct7 = 7'b0000000;
        if (is_addw) begin
            opcode = 7'b0111011;
        end else begin
            opcode = 7'b0110011;
        end
    endfunction

    virtual function void calculate_expected_result();
        bit [31:0] addw_result;
        bit [63:0] lhs;
        bit [63:0] rhs;

        lhs = (rs1 == 5'd0) ? 64'd0 : rs1_data;
        rhs = (rs2 == 5'd0) ? 64'd0 : rs2_data;
        if (is_addw) begin
            addw_result     = lhs[31:0] + rhs[31:0];
            expected_result = {{32{addw_result[31]}}, addw_result};
        end else begin
            expected_result = lhs + rhs;
        end
    endfunction

    virtual function string instr_name_str();
        return is_addw ? "ADDW" : "ADD";
    endfunction

endclass
