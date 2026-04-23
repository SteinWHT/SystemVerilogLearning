class fifo_wr_seq extends uvm_sequence #(fifo_wr_item);
    `uvm_object_utils(fifo_wr_seq)

    function new(string name = "fifo_wr_seq");
        super.new(name);
    endfunction

    task body();
        fifo_wr_item tr;
        repeat (12) begin
            tr = fifo_wr_item::type_id::create("tr");
            start_item(tr);
            if (!tr.randomize()) begin
                `uvm_fatal("SEQ", "randomize failed")
            end
            finish_item(tr);
        end
    endtask
endclass

class fifo_rd_seq extends uvm_sequence #(fifo_rd_item);
    `uvm_object_utils(fifo_rd_seq)

    function new(string name = "fifo_rd_seq");
        super.new(name);
    endfunction

    task body();
        fifo_rd_item tr;
        // Enough read attempts to drain what the write sequence produces.
        repeat (24) begin
            tr = fifo_rd_item::type_id::create("tr");
            start_item(tr);
            if (!tr.randomize()) begin
                `uvm_fatal("SEQ", "randomize failed")
            end
            finish_item(tr);
        end
    endtask
endclass
