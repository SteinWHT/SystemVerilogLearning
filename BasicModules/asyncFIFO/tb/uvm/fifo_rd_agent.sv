class fifo_rd_sequencer extends uvm_sequencer #(fifo_rd_item);
    `uvm_component_utils(fifo_rd_sequencer)
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass

class fifo_rd_driver extends uvm_driver #(fifo_rd_item);
    `uvm_component_utils(fifo_rd_driver)
    virtual fifo_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "Set virtual fifo_if on rd_driver via config_db")
        end
    endfunction

    task run_phase(uvm_phase phase);
        fifo_rd_item tr;
        forever begin
            seq_item_port.get_next_item(tr);
            while (!vif.rd_rst_n) @(posedge vif.rclk);
            repeat (tr.idle_cycles) @(posedge vif.rclk);
            if (!vif.empty) begin
                vif.rd_en <= 1'b1;
                @(posedge vif.rclk);
                vif.rd_en <= 1'b0;
            end
            // If empty, this beat is a no-op so the sequence can finish (no deadlock).
            seq_item_port.item_done();
        end
    endtask
endclass

class fifo_rd_monitor extends uvm_monitor;
    `uvm_component_utils(fifo_rd_monitor)
    virtual fifo_if vif;
    uvm_analysis_port #(fifo_rd_obs_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "Set virtual fifo_if on rd_monitor via config_db")
        end
    endfunction

    // Match memory.sv: rd_data updates the cycle after rd_en && !empty.
    task run_phase(uvm_phase phase);
        bit rd_data_valid;
        fifo_rd_obs_item o;
        forever @(posedge vif.rclk) begin
            if (!vif.rd_rst_n) begin
                rd_data_valid = 1'b0;
            end else begin
                if (rd_data_valid) begin
                    o      = fifo_rd_obs_item::type_id::create("o");
                    o.data = vif.rd_data;
                    ap.write(o);
                end
                rd_data_valid = vif.rd_en && !vif.empty;
            end
        end
    endtask
endclass

class fifo_rd_agent extends uvm_agent;
    `uvm_component_utils(fifo_rd_agent)
    fifo_rd_sequencer sqr;
    fifo_rd_driver    drv;
    fifo_rd_monitor   mon;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sqr = fifo_rd_sequencer::type_id::create("sqr", this);
        drv = fifo_rd_driver::type_id::create("drv", this);
        mon = fifo_rd_monitor::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
endclass
