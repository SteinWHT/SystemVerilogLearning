// Base sequence for instruction stimulus.
// Protocol fields (seq_id, pc) are assigned by cpu_driver at drive time.
virtual class cpu_base_seq extends uvm_sequence #(cpu_base_item);

    function new(string name = "cpu_base_seq");
        super.new(name);
    endfunction

    // Leave pc at 0 so the driver assigns boot_pc + sequential offset.
    protected function void init_item(cpu_base_item tr);
        tr.pc            = '0;
        tr.seq_id        = '0;
        tr.checks_enabled = 1'b1;
    endfunction

endclass
