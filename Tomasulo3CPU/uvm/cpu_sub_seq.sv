class cpu_sub_seq extends cpu_base_seq;
    `uvm_object_utils(cpu_sub_seq)

    rand int unsigned num_instr;
    rand bit          mix_subw;

    constraint c_num {
        num_instr inside {[1:32]};
    }

    function new(string name = "cpu_sub_seq");
        super.new(name);
    endfunction

    task body();
        repeat (num_instr) begin
            cpu_sub_item tr;
            tr = cpu_sub_item::type_id::create($sformatf("sub_%0d", get_sequence_id()));
            init_item(tr);
            if (!tr.randomize() with { is_subw == local::mix_subw; })
                `uvm_fatal(get_type_name(), "cpu_sub_item randomize failed")
            start_item(tr);
            finish_item(tr);
        end
    endtask

endclass
