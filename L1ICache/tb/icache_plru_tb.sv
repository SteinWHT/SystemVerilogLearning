// Directed PLRU golden check (package model vs RTL).

`timescale 1ns / 1ps

module icache_plru_tb;

    import icache_pkg::*;

    localparam int unsigned SET0 = 8'hA5;

    logic clk;
    logic rst_n;
    cache_set_t set_idx;
    cache_way_t victim_way;
    logic       update_en;
    cache_way_t touch_way;

    int unsigned errors;

    plru_state_t golden;

    icache_plru u_plru (
        .clk        (clk),
        .rst_n      (rst_n),
        .set_idx    (set_idx),
        .victim_way (victim_way),
        .update_en  (update_en),
        .touch_way  (touch_way)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task automatic check_victim(input string label, input cache_way_t exp);
        if (victim_way !== exp) begin
            $error("[%s] victim exp=%0d got=%0d", label, exp, victim_way);
            errors++;
        end
    endtask

    task automatic touch(input cache_way_t way);
        @(posedge clk);
        update_en <= 1'b1;
        touch_way <= way;
        @(posedge clk);
        update_en <= 1'b0;
        golden    <= plru_touch(golden, way);
    endtask

    initial begin
        errors    = 0;
        set_idx   = SET0;
        update_en = 1'b0;
        touch_way = '0;

        rst_n = 1'b0;
        golden = '0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        check_victim("reset", 2'd0);

        touch(2'd3); check_victim("after 3", plru_victim(golden));
        touch(2'd1); check_victim("after 1", plru_victim(golden));
        touch(2'd0); check_victim("after 0", plru_victim(golden));
        touch(2'd2); check_victim("after 2", plru_victim(golden));
        touch(2'd3); check_victim("after 3b", plru_victim(golden));
        touch(2'd3); check_victim("after 3c", plru_victim(golden));
        touch(2'd1); check_victim("after 1b", plru_victim(golden));
        touch(2'd2); check_victim("after 2b", plru_victim(golden));
        touch(2'd0); check_victim("after 0b", plru_victim(golden));
        touch(2'd1); check_victim("after 1c", plru_victim(golden));
        touch(2'd2); check_victim("after 2c", plru_victim(golden));
        touch(2'd3); check_victim("after 3d", plru_victim(golden));
        touch(2'd0); check_victim("after 0c", plru_victim(golden));
        touch(2'd0); check_victim("after 0d", plru_victim(golden));
        touch(2'd1); check_victim("after 1d", plru_victim(golden));
        touch(2'd1); check_victim("after 1e", plru_victim(golden));

        if (errors == 0)
            $display("icache_plru_tb: PASS");
        else
            $display("icache_plru_tb: FAIL (%0d errors)", errors);

        $finish;
    end

endmodule
