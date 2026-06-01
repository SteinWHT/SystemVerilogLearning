class cpu_spike_commit_item extends uvm_sequence_item;
    `uvm_object_utils(cpu_spike_commit_item)

    longint unsigned            index;
    bit [63:0]                  pc;
    bit [31:0]                  instr;
    bit                         rd_write;
    bit [4:0]                   rd_addr;
    bit [63:0]                  rd_data;
    bit                         mem_write;
    bit                         mem_addr_valid;
    bit [63:0]                  mem_addr;
    bit [63:0]                  mem_data;
    cpu_spike_instr_class_e     instr_class;

    function new(string name = "cpu_spike_commit_item");
        super.new(name);
    endfunction

    function bit parse_line(string line);
        int unsigned class_i;
        int unsigned rd_w;
        int unsigned mw;
        int unsigned addr_valid;
        int          n;

        n = $sscanf(line, "%d %h %h %d %d %h %d %d %h %h %d",
            index,
            pc,
            instr,
            rd_w,
            rd_addr,
            rd_data,
            mw,
            addr_valid,
            mem_addr,
            mem_data,
            class_i
        );

        if (n != 11)
            return 1'b0;

        rd_write       = (rd_w != 0);
        mem_write      = (mw != 0);
        mem_addr_valid = (addr_valid != 0);
        instr_class    = cpu_spike_instr_class_e'(class_i);
        return 1'b1;
    endfunction

    function string instr_class_name();
        case (instr_class)
            CPU_SPIKE_CLASS_ALU:    return "ALU";
            CPU_SPIKE_CLASS_LOAD:   return "LOAD";
            CPU_SPIKE_CLASS_STORE:  return "STORE";
            CPU_SPIKE_CLASS_BRANCH: return "BRANCH";
            CPU_SPIKE_CLASS_JUMP:   return "JUMP";
            CPU_SPIKE_CLASS_MUL:    return "MUL";
            CPU_SPIKE_CLASS_DIV:    return "DIV";
            CPU_SPIKE_CLASS_WORD:   return "WORD";
            CPU_SPIKE_CLASS_SYSTEM: return "SYSTEM";
            default:                return "UNKNOWN";
        endcase
    endfunction

    virtual function string convert2string();
        return $sformatf(
            "spike[%0d] pc=0x%016h instr=0x%08h rd_w=%0b rd=x%0d rd_data=0x%016h mem_w=%0b mem_addr_valid=%0b mem_addr=0x%016h mem_data=0x%016h class=%s",
            index,
            pc,
            instr,
            rd_write,
            rd_addr,
            rd_data,
            mem_write,
            mem_addr_valid,
            mem_addr,
            mem_data,
            instr_class_name()
        );
    endfunction
endclass
