// Write transaction: one byte pushed when the driver successfully writes into the FIFO.

class fifo_wr_item extends uvm_sequence_item;
    rand bit [7:0] data;

    `uvm_object_utils_begin(fifo_wr_item)
        `uvm_field_int(data, UVM_ALL_ON)
    `uvm_object_utils_end

    constraint c_data { data dist {[8'h00:8'hFF]:/1}; }

    function new(string name = "fifo_wr_item");
        super.new(name);
    endfunction
endclass
