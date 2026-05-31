class cpu_add_seq extends cpu_base_seq;
    `uvm_object_utils(cpu_add_seq)

    rand int unsigned num_instr;
    rand bit          mix_addw;

    constraint c_num {
        num_instr inside {[1:32]};
    }

    function new(string name = "cpu_add_seq");
        super.new(name);
    endfunction

    task body();
        repeat (num_instr) begin
            cpu_add_item tr;
            tr = cpu_add_item::type_id::create($sformatf("add_%0d", get_sequence_id()));
            init_item(tr);
            if (!tr.randomize() with { is_addw == local::mix_addw; })
                `uvm_fatal(get_type_name(), "cpu_add_item randomize failed")
            start_item(tr);
            finish_item(tr);
        end
    endtask

endclass
