class fifo_wr_sequencer extends uvm_sequencer #(fifo_wr_item);
    `uvm_component_utils(fifo_wr_sequencer)
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass

class fifo_wr_driver extends uvm_driver #(fifo_wr_item);
    `uvm_component_utils(fifo_wr_driver)
    virtual fifo_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "Set virtual fifo_if on wr_driver via config_db")
        end
    endfunction

    task run_phase(uvm_phase phase);
        fifo_wr_item tr;
        forever begin
            seq_item_port.get_next_item(tr);
            while (!vif.wr_rst_n) @(posedge vif.wclk);
            while (vif.full) @(posedge vif.wclk);
            vif.wr_en   <= 1'b1;
            vif.wr_data <= tr.data;
            @(posedge vif.wclk);
            vif.wr_en <= 1'b0;
            seq_item_port.item_done();
        end
    endtask
endclass

class fifo_wr_monitor extends uvm_monitor;
    `uvm_component_utils(fifo_wr_monitor)
    virtual fifo_if vif;
    uvm_analysis_port #(fifo_wr_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "Set virtual fifo_if on wr_monitor via config_db")
        end
    endfunction

    task run_phase(uvm_phase phase);
        fifo_wr_item obs;
        forever @(posedge vif.wclk) begin
            if (vif.wr_rst_n && vif.wr_en && !vif.full) begin
                obs       = fifo_wr_item::type_id::create("obs");
                obs.data  = vif.wr_data;
                ap.write(obs);
            end
        end
    endtask
endclass

class fifo_wr_agent extends uvm_agent;
    `uvm_component_utils(fifo_wr_agent)
    fifo_wr_sequencer sqr;
    fifo_wr_driver    drv;
    fifo_wr_monitor   mon;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sqr = fifo_wr_sequencer::type_id::create("sqr", this);
        drv = fifo_wr_driver::type_id::create("drv", this);
        mon = fifo_wr_monitor::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
endclass
