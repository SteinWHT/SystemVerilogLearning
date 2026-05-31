class cpu_sequencer extends uvm_sequencer #(cpu_base_item);
    `uvm_component_utils(cpu_sequencer)

    function new(string name = "cpu_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

endclass
