// Memory transaction item for future load/store scoreboard / dcache monitor agent.
class cpu_dcache_item #(
    int unsigned DMEM_WIDTH = CPU_REG_FILE_DATA_WIDTH,
    int unsigned DMEM_DEPTH = CPU_DMEM_DEPTH
) extends uvm_sequence_item;

    typedef enum bit [1:0] { DCACHE_READ, DCACHE_WRITE } access_e;
    typedef enum bit       { DCACHE_REQUEST, DCACHE_RESPONSE } event_e;

    rand access_e              access;
    rand event_e               event_kind;
    rand bit [DMEM_WIDTH-1:0]  data;
    rand bit [DMEM_DEPTH-1:0]  addr;
    rand bit [CPU_W_BYTE_NUM-1:0] strb;

    `uvm_object_param_utils_begin(cpu_dcache_item #(DMEM_WIDTH, DMEM_DEPTH))
        `uvm_field_enum(access_e, access, UVM_ALL_ON)
        `uvm_field_enum(event_e, event_kind, UVM_ALL_ON)
        `uvm_field_int(data, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(addr, UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(strb, UVM_ALL_ON | UVM_HEX)
    `uvm_object_utils_end

    function new(string name = "cpu_dcache_item");
        super.new(name);
    endfunction

    virtual function string convert2string();
        return $sformatf("%s %s data=0x%016h addr=0x%0h strb=0x%0h",
            access.name(), event_kind.name(), data, addr, strb);
    endfunction

endclass
