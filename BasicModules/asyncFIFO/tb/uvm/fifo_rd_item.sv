// Read-transaction request: how many idle rclk cycles before attempting one read pulse.

class fifo_rd_item extends uvm_sequence_item;
    rand int unsigned idle_cycles;

    `uvm_object_utils_begin(fifo_rd_item)
        `uvm_field_int(idle_cycles, UVM_ALL_ON)
    `uvm_object_utils_end

    constraint c_idle { idle_cycles inside {[0:5]}; }

    function new(string name = "fifo_rd_item");
        super.new(name);
    endfunction
endclass

// What the read monitor sends to the scoreboard (observed data beat).

class fifo_rd_obs_item extends uvm_sequence_item;
    bit [7:0] data;

    `uvm_object_utils_begin(fifo_rd_obs_item)
        `uvm_field_int(data, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "fifo_rd_obs_item");
        super.new(name);
    endfunction
endclass
