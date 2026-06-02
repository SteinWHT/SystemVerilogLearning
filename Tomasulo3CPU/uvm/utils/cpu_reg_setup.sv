// Load architectural GPR values through normal retired instructions (ADDI/LUI/LD).
class cpu_reg_setup;

    cpu_drv_vif_t                   vif;
    cpu_cfg                         cfg;
    uvm_analysis_port #(cpu_base_item) ap;
    int unsigned                    next_pc_offset;
    int unsigned                    dmem_slot;

    function new(
        cpu_drv_vif_t                   vif,
        cpu_cfg                         cfg,
        uvm_analysis_port #(cpu_base_item) ap,
        input int unsigned              next_pc_offset = 0,
        input int unsigned              dmem_slot      = 0
    );
        this.vif             = vif;
        this.cfg             = cfg;
        this.ap              = ap;
        this.next_pc_offset  = next_pc_offset;
        this.dmem_slot       = dmem_slot;
    endfunction

    function automatic bit [63:0] current_pc();
        return cfg.boot_pc + next_pc_offset;
    endfunction

    function automatic bit [4:0] pick_scratch(
        input bit [4:0] avoid0,
        input bit [4:0] avoid1 = 5'd0,
        input bit [4:0] avoid2 = 5'd0
    );
        bit [4:0] candidates[8] = '{5'd31, 5'd30, 5'd29, 5'd28, 5'd27, 5'd26, 5'd25, 5'd24};
        foreach (candidates[i]) begin
            if (candidates[i] != avoid0 && candidates[i] != avoid1 && candidates[i] != avoid2)
                return candidates[i];
        end
        return avoid0;
    endfunction

    task automatic emit_reg_write(
        input bit [4:0]  rd,
        input bit [63:0] expected,
        input bit [31:0] instr,
        input riscv_instr_name_e instr_name = RISCV_OP_ADDI
    );
        cpu_base_item setup_tr;
        bit [63:0]    pc;

        pc = current_pc();
        setup_tr = cpu_base_item::type_id::create("reg_setup");
        setup_tr.pc              = pc;
        setup_tr.rd              = rd;
        setup_tr.expected_result = expected;
        setup_tr.instr           = instr;
        setup_tr.instr_name      = instr_name;
        setup_tr.checks_enabled  = 1'b1;
        setup_tr.is_operand_setup = 1'b1;

        vif.load_instr(pc[63:0], instr);
        ap.write(setup_tr);

        next_pc_offset += 4;
        repeat (cfg.instr_gap_cycles) @(posedge vif.clk);
    endtask

    // Immediate-only path (ADDI or LUI+ADDI). Used for addresses and small operands.
    task automatic load_immediate(
        input bit [4:0]  rd,
        input bit [63:0] value,
        input bit [4:0]  avoid0,
        input bit [4:0]  avoid1 = 5'd0,
        input bit [4:0]  avoid2 = 5'd0
    );
        bit [19:0] hi20;
        bit [11:0] lo12;
        bit [4:0]  scratch;

        if (rd == 5'd0)
            return;

        scratch = pick_scratch(avoid0, avoid1, avoid2);

        if (cpu_instr_encoder::fits_addi_imm(value)) begin
            emit_reg_write(
                rd,
                value,
                cpu_instr_encoder::addi(rd, 5'd0, value[11:0])
            );
            return;
        end

        if (cpu_instr_encoder::fits_lui_addi(value)) begin
            bit [63:0] lui_result;
            cpu_instr_encoder::lui_addi_parts(value, hi20, lo12);
            lui_result = {{32{hi20[19]}}, hi20, 12'b0};
            emit_reg_write(
                rd,
                lui_result,
                cpu_instr_encoder::lui(rd, hi20),
                RISCV_OP_ADDI
            );
            emit_reg_write(
                rd,
                value,
                cpu_instr_encoder::addi(rd, rd, lo12)
            );
            return;
        end

        // Fallback: store arbitrary address/value in scratch dmem and LD.
        load_from_dmem(rd, value, scratch, avoid0, avoid1, avoid2);
    endtask

    task automatic load_from_dmem(
        input bit [4:0]  rd,
        input bit [63:0] value,
        input bit [4:0]  scratch,
        input bit [4:0]  avoid0,
        input bit [4:0]  avoid1,
        input bit [4:0]  avoid2
    );
        bit [63:0] byte_addr;
        int unsigned line_idx;
        bit [4:0]  addr_reg;

        line_idx  = cfg.setup_dmem_line + dmem_slot;
        if (line_idx >= cfg.dmem_lines) begin
            `uvm_fatal("cpu_reg_setup", $sformatf(
                "Setup DMEM pool exhausted: need line %0d but dmem_lines=%0d (setup_dmem_line=%0d). Increase dmem_lines or reduce stimulus.",
                line_idx, cfg.dmem_lines, cfg.setup_dmem_line))
        end
        byte_addr = line_idx * (cfg.dmem_width / 8);
        vif.write_dmem_line(line_idx, value);
        dmem_slot++;

        addr_reg = pick_scratch(scratch, avoid0, avoid1);
        if (addr_reg == rd || addr_reg == avoid0 || addr_reg == avoid1 || addr_reg == avoid2)
            addr_reg = pick_scratch(rd, scratch, avoid0);

        load_immediate(addr_reg, byte_addr, rd, scratch, avoid0);
        emit_reg_write(
            rd,
            value,
            cpu_instr_encoder::ld(rd, addr_reg, 12'd0),
            RISCV_OP_LD
        );
    endtask

    task automatic load_reg(
        input bit [4:0]  rd,
        input bit [63:0] value,
        input bit [4:0]  avoid0,
        input bit [4:0]  avoid1 = 5'd0,
        input bit [4:0]  avoid2 = 5'd0
    );
        bit [4:0] scratch;

        if (rd == 5'd0)
            return;

        scratch = pick_scratch(avoid0, avoid1, avoid2);

        if (cpu_instr_encoder::fits_addi_imm(value) ||
            cpu_instr_encoder::fits_lui_addi(value)) begin
            load_immediate(rd, value, avoid0, avoid1, avoid2);
            return;
        end

        load_from_dmem(rd, value, scratch, avoid0, avoid1, avoid2);
    endtask

    task automatic setup_operands(cpu_base_item tr);
        if (cfg == null || !cfg.enable_operand_setup || !tr.needs_operand_setup())
            return;

        if (tr.rs1 != 5'd0)
            load_reg(tr.rs1, tr.rs1_data, tr.rs2, tr.rd);
        if (tr.rs2 != 5'd0 && tr.rs2 != tr.rs1)
            load_reg(tr.rs2, tr.rs2_data, tr.rs1, tr.rd);
    endtask

endclass
