// Constrained-random RV64IM + Zicsr program generator.
//
// Produces a self-contained instruction stream with *configurable hazard
// density*: RAW / WAW dependency chains, load-use pairs, and branch clusters.
// Hazards arise from register/memory reuse across a shared architectural
// state, so the program is generated procedurally (riscv-dv style) rather than
// with whole-program declarative constraints.
//
// Control flow is forward-only by construction (branches and jumps target
// instructions ahead of themselves), which guarantees termination: execution
// always drains into the tohost epilogue. Memory traffic is confined to a data
// region placed above the code, so the stream is never self-modifying and the
// DUT (Harvard legacy memories) and Spike (unified memory) stay in agreement.
class cpu_rand_program extends uvm_object;

    // ------------------------------------------------------------------
    // Knobs (populated from cpu_cfg by the sequence; randomizable directly).
    // ------------------------------------------------------------------
    rand int unsigned num_instr;          // body instruction count
    rand int unsigned raw_pct;            // % of source operands forced RAW
    rand int unsigned waw_pct;            // % of writers that re-target a recent rd
    rand int unsigned load_use_pct;       // % chance a load is immediately consumed
    rand int unsigned branch_cluster_pct; // % chance to open a branch cluster
    rand int unsigned branch_cluster_size;// branches per cluster
    rand int unsigned dep_window;         // look-back window for producers

    // Instruction-class mix weights (relative).
    int unsigned w_alu_r  = 24;
    int unsigned w_alu_w  = 8;
    int unsigned w_mul    = 5;
    int unsigned w_div    = 4;
    int unsigned w_alu_i  = 20;
    int unsigned w_alu_iw = 6;
    int unsigned w_load   = 12;
    int unsigned w_store  = 9;
    int unsigned w_branch = 6;
    int unsigned w_jal    = 2;

    // Optional / privileged op enables (off by default; they perturb control
    // flow or require a trap handler that this CPU-only env does not model).
    bit enable_jalr   = 0;
    bit enable_csr    = 0;
    bit enable_system = 0;

    // Memory map.
    bit [63:0] data_base   = 64'h0000_8000; // byte addr of data region (> code)
    int unsigned data_bytes = 512;           // size of the data region
    bit [63:0] tohost_off  = 64'h0000_0000;  // tohost within the data region
    bit [4:0]  data_ptr_reg = 5'd31;         // reserved base pointer register
    int unsigned seed_regs  = 12;            // GPRs initialised in the prologue

    bit [63:0] boot_pc = 64'h0;

    constraint c_knob_ranges {
        num_instr           inside {[16:4096]};
        raw_pct             inside {[0:100]};
        waw_pct             inside {[0:100]};
        load_use_pct        inside {[0:100]};
        branch_cluster_pct  inside {[0:100]};
        branch_cluster_size inside {[2:8]};
        dep_window          inside {[1:16]};
    }

    constraint c_knob_defaults {
        soft num_instr           == 200;
        soft raw_pct             == 40;
        soft waw_pct             == 20;
        soft load_use_pct        == 30;
        soft branch_cluster_pct  == 15;
        soft branch_cluster_size == 3;
        soft dep_window          == 6;
    }

    // ------------------------------------------------------------------
    // Outputs
    // ------------------------------------------------------------------
    cpu_instr_item    prog[$];                // ordered instruction stream
    bit [63:0]        data_init[bit [63:0]];  // 8B-aligned data-region preload

    // ------------------------------------------------------------------
    // Internal generation state
    // ------------------------------------------------------------------
    protected bit [63:0] gpr[32];             // shadow value model (for seeds)
    protected bit        gpr_known[32];       // has a defined value been written
    protected int        producers[$];        // recency list of written regs
    protected int        last_load_rd;        // rd of most recent load (-1 none)
    protected int        cur_idx;             // running instruction index

    `uvm_object_utils(cpu_rand_program)

    function new(string name = "cpu_rand_program");
        super.new(name);
    endfunction

    // ==================================================================
    // Public entry point
    // ==================================================================
    function void generate_program();
        prog.delete();
        data_init.delete();
        producers.delete();
        last_load_rd = -1;
        cur_idx      = 0;
        foreach (gpr[i]) begin
            gpr[i]       = 64'h0;
            gpr_known[i] = (i == 0); // x0 is always a known zero
        end

        init_data_region();
        emit_prologue();
        emit_body();
        emit_epilogue();
    endfunction

    // Byte PC for an instruction index.
    function bit [63:0] pc_of(int idx);
        return boot_pc + (idx * 4);
    endfunction

    function int body_start();
        return prologue_len();
    endfunction

    // ==================================================================
    // Data region
    // ==================================================================
    protected function void init_data_region();
        bit [63:0] addr;
        for (int unsigned b = 0; b < data_bytes; b += 8) begin
            addr            = data_base + b;
            data_init[addr] = {$urandom(), $urandom()};
        end
        // tohost cell starts at zero; the epilogue store sets it.
        data_init[data_base + tohost_off] = 64'h0;
    endfunction

    // ==================================================================
    // Prologue: establish the data pointer and seed operand registers.
    // ==================================================================
    protected function int prologue_len();
        // data_ptr: LUI + ADDI (2). Each seeded reg: LUI + ADDI (2).
        return 2 + (seed_regs * 2);
    endfunction

    protected function void emit_prologue();
        bit [4:0] r;
        bit [63:0] val;

        // data_ptr_reg = data_base
        load_imm32(data_ptr_reg, data_base);

        // Seed a spread of registers with diverse 32-bit signed values.
        for (int unsigned i = 0; i < seed_regs; i++) begin
            r = pick_seed_reg(i);
            if (r == 5'd0 || r == data_ptr_reg) continue;
            val = seed_value(i);
            load_imm32(r, val);
            note_producer(int'(r));
            gpr[r]       = val;
            gpr_known[r] = 1'b1;
        end
    endfunction

    // Pick a register to seed (spread across the file, skipping the pointer).
    protected function bit [4:0] pick_seed_reg(int unsigned i);
        bit [4:0] r = 5'((i % 30) + 1); // x1..x30
        if (r == data_ptr_reg) r = 5'd1;
        return r;
    endfunction

    protected function bit [63:0] seed_value(int unsigned i);
        case (i % 6)
            0: return 64'h0;
            1: return 64'h1;
            2: return 64'hFFFF_FFFF_FFFF_FFFF;
            3: return {{32{1'b0}}, 32'h7FFF_FFFF};
            4: return {{32{1'b1}}, 32'h8000_0000};
            default: return {{32{1'b0}}, $urandom()};
        endcase
    endfunction

    // Materialise a 32-bit signed value via LUI + ADDI (two committed insns).
    protected function void load_imm32(bit [4:0] rd, bit [63:0] value);
        bit [19:0] hi20;
        bit [11:0] lo12;
        bit [31:0] v = value[31:0];
        hi20 = (v + 32'h800) >> 12;
        lo12 = v - (hi20 << 12);
        // U-type immediate occupies instr[31:12]; pass the value (hi20<<12) so
        // the encoder slices imm[31:12] back out as hi20.
        push(make(CPU_OP_LUI,  rd, 5'd0, 5'd0, {{32{hi20[19]}}, hi20, 12'b0}, CPU_HAZ_NONE, 0));
        push(make(CPU_OP_ADDI, rd, rd,   5'd0, {{52{lo12[11]}}, lo12}, CPU_HAZ_NONE, 0));
    endfunction

    // ==================================================================
    // Body
    // ==================================================================
    protected function void emit_body();
        int unsigned remaining;
        remaining = num_instr;
        while (remaining > 0) begin
            if (in_cluster_window(remaining) && roll(branch_cluster_pct)) begin
                int unsigned n = (branch_cluster_size < remaining) ?
                                 branch_cluster_size : remaining;
                for (int unsigned k = 0; k < n; k++) begin
                    emit_branch(CPU_HAZ_BRANCH);
                    remaining--;
                end
            end else begin
                emit_one();
                remaining--;
            end
        end
    endfunction

    // Reserve room so a cluster (and the epilogue) still fit forward targets.
    protected function bit in_cluster_window(int unsigned remaining);
        return (remaining > branch_cluster_size + 2);
    endfunction

    protected function void emit_one();
        cpu_isa_op_e op;
        op = pick_op();
        case (cpu_isa_encoder::class_of(op))
            CPU_SPIKE_CLASS_LOAD:   emit_load(op);
            CPU_SPIKE_CLASS_STORE:  emit_store(op);
            CPU_SPIKE_CLASS_BRANCH: emit_branch(CPU_HAZ_NONE);
            CPU_SPIKE_CLASS_JUMP:   emit_jump(op);
            default:                emit_alu(op);
        endcase
    endfunction

    // ---- ALU / shift / imm / mul / div ----
    protected function void emit_alu(cpu_isa_op_e op);
        bit [4:0] rd, rs1, rs2;
        bit [63:0] imm;
        cpu_hazard_kind_e haz = CPU_HAZ_NONE;
        int _dist = 0;

        rd = pick_rd(haz);
        if (cpu_isa_encoder::reads_rs1(op))
            rs1 = pick_src(haz, _dist);
        else
            rs1 = 5'd0;
        if (cpu_isa_encoder::reads_rs2(op))
            rs2 = pick_src(haz, _dist);
        else
            rs2 = 5'd0;

        imm = alu_imm(op);
        push(make(op, rd, rs1, rs2, imm, haz, _dist));
        note_producer(int'(rd));
    endfunction

    protected function bit [63:0] alu_imm(cpu_isa_op_e op);
        case (op)
            CPU_OP_SLLI, CPU_OP_SRLI, CPU_OP_SRAI:
                return {58'd0, 6'($urandom_range(0, 63))};
            CPU_OP_SLLIW, CPU_OP_SRLIW, CPU_OP_SRAIW:
                return {59'd0, 5'($urandom_range(0, 31))};
            CPU_OP_LUI, CPU_OP_AUIPC: begin
                bit [19:0] u = $urandom();
                return {{32{u[19]}}, u, 12'b0};
            end
            default: begin
                bit [11:0] s = $urandom();
                return {{52{s[11]}}, s};
            end
        endcase
    endfunction

    // ---- Load ----
    protected function void emit_load(cpu_isa_op_e op);
        bit [4:0] rd;
        bit [63:0] off;
        cpu_hazard_kind_e haz = CPU_HAZ_NONE;
        int _dist = 0;

        rd  = pick_rd(haz);
        off = mem_offset(cpu_isa_encoder::mem_bytes(op));
        push(make(op, rd, data_ptr_reg, 5'd0, off, haz, _dist));
        note_producer(int'(rd));
        last_load_rd = int'(rd);
    endfunction

    // ---- Store ----
    protected function void emit_store(cpu_isa_op_e op);
        bit [4:0] rs2;
        bit [63:0] off;
        cpu_hazard_kind_e haz = CPU_HAZ_NONE;
        int _dist = 0;

        rs2 = pick_src(haz, _dist); // data value
        off = mem_offset(cpu_isa_encoder::mem_bytes(op));
        push(make(op, 5'd0, data_ptr_reg, rs2, off, haz, _dist));
        last_load_rd = -1;
    endfunction

    // Aligned byte offset within the data region (excluding the tohost cell).
    protected function bit [63:0] mem_offset(int unsigned nbytes);
        int unsigned slots;
        int unsigned slot;
        int unsigned off;
        if (nbytes == 0) nbytes = 8;
        slots = data_bytes / nbytes;
        if (slots <= 1) return 64'h8; // skip tohost at offset 0
        slot  = $urandom_range(1, slots - 1); // slot 0 reserved for tohost
        off   = slot * nbytes;
        return {32'd0, 32'(off)};
    endfunction

    // ---- Branch (forward target) ----
    protected function void emit_branch(cpu_hazard_kind_e cluster_haz);
        cpu_isa_op_e ops[6] = '{CPU_OP_BEQ, CPU_OP_BNE, CPU_OP_BLT,
                                CPU_OP_BGE, CPU_OP_BLTU, CPU_OP_BGEU};
        cpu_isa_op_e op = ops[$urandom_range(0, 5)];
        bit [4:0] rs1, rs2;
        int target;
        bit [63:0] off;
        cpu_hazard_kind_e haz = (cluster_haz == CPU_HAZ_BRANCH) ?
                                CPU_HAZ_BRANCH : CPU_HAZ_NONE;
        int _dist = 0;

        rs1 = pick_src(haz, _dist);
        rs2 = pick_src(haz, _dist);
        target = forward_target();
        off    = signed_pc_delta(target);
        push(make(op, 5'd0, rs1, rs2, off, haz, _dist));
    endfunction

    // ---- Jump (JAL forward, optional JALR) ----
    protected function void emit_jump(cpu_isa_op_e op);
        bit [4:0] rd;
        int target;
        bit [63:0] off;
        cpu_hazard_kind_e haz = CPU_HAZ_NONE;
        int _dist = 0;

        rd     = pick_rd(haz);
        target = forward_target();
        off    = signed_pc_delta(target);
        push(make(CPU_OP_JAL, rd, 5'd0, 5'd0, off, haz, _dist));
        note_producer(int'(rd));
    endfunction

    // Last valid instruction index in the fully-generated program (the
    // self-loop JAL of the epilogue). Forward targets are clamped to this so a
    // taken branch/jump can never run off the end into NOP land.
    protected function int last_index();
        return prologue_len() + int'(num_instr) + 3 - 1;
    endfunction

    // A forward instruction index strictly ahead of the current one, clamped
    // to remain inside the program.
    protected function int forward_target();
        int span = $urandom_range(1, 4);
        int t    = cur_idx + span;
        if (t > last_index()) t = last_index();
        if (t <= cur_idx)     t = cur_idx + 1;
        return t;
    endfunction

    // Signed PC delta (bytes) from current index to a target index.
    protected function bit [63:0] signed_pc_delta(int target);
        int delta = (target - cur_idx) * 4;
        return {{32{delta[31]}}, delta};
    endfunction

    // ==================================================================
    // Epilogue: signal completion via a tohost store, then spin.
    // ==================================================================
    protected function void emit_epilogue();
        bit [4:0] one_reg = 5'd1;
        // x1 = 1
        push(make(CPU_OP_ADDI, one_reg, 5'd0, 5'd0, 64'h1, CPU_HAZ_NONE, 0));
        // SD x1, tohost_off(data_ptr)
        push(make(CPU_OP_SD, 5'd0, data_ptr_reg, one_reg,
                  {32'd0, 32'(tohost_off)}, CPU_HAZ_NONE, 0));
        // self loop: JAL x0, 0
        push(make(CPU_OP_JAL, 5'd0, 5'd0, 5'd0, 64'h0, CPU_HAZ_NONE, 0));
    endfunction

    function bit [63:0] tohost_addr();
        return data_base + tohost_off;
    endfunction

    // ==================================================================
    // Item construction
    // ==================================================================
    protected function cpu_instr_item make(
        cpu_isa_op_e op, bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2,
        bit [63:0] imm, cpu_hazard_kind_e haz, int _dist
    );
        cpu_instr_item it;
        it = cpu_instr_item::type_id::create($sformatf("instr_%0d", cur_idx));
        it.op           = op;
        it.rd           = rd;
        it.rs1          = rs1;
        it.rs2          = rs2;
        it.imm64        = imm;
        it.hazard       = haz;
        it.dep_distance = _dist;
        it.prog_idx     = cur_idx;
        it.pc           = pc_of(cur_idx);
        it.checks_enabled = 1'b1;
        it.finalize();
        return it;
    endfunction

    protected function void push(cpu_instr_item it);
        prog.push_back(it);
        cur_idx++;
    endfunction

    // ==================================================================
    // Operand selection helpers (hazard-aware)
    // ==================================================================
    protected function void note_producer(int r);
        if (r == 0) return;
        producers.push_back(r);
        if (producers.size() > 64)
            void'(producers.pop_front());
    endfunction

    // Pick a destination register, honouring the WAW knob.
    protected function bit [4:0] pick_rd(output cpu_hazard_kind_e haz);
        haz = CPU_HAZ_NONE;
        if (producers.size() > 0 && roll(waw_pct)) begin
            int idx = recent_producer();
            if (idx > 0 && idx != int'(data_ptr_reg)) begin
                haz = CPU_HAZ_WAW;
                return 5'(idx);
            end
        end
        return random_dest();
    endfunction

    // Pick a source register, honouring load-use and RAW knobs.
    protected function bit [4:0] pick_src(inout cpu_hazard_kind_e haz,
                                          inout int _dist);
        // Load-use takes priority: consume the immediately prior load.
        if (last_load_rd > 0 && roll(load_use_pct)) begin
            haz  = CPU_HAZ_LOAD_USE;
            _dist = 1;
            return 5'(last_load_rd);
        end
        if (producers.size() > 0 && roll(raw_pct)) begin
            int back = $urandom_range(1, win());
            int pos  = producers.size() - back;
            if (pos >= 0) begin
                int r = producers[pos];
                if (r > 0) begin
                    if (haz == CPU_HAZ_NONE) haz = CPU_HAZ_RAW;
                    _dist = back;
                    return 5'(r);
                end
            end
        end
        return random_src();
    endfunction

    protected function int recent_producer();
        int back = $urandom_range(1, win());
        int pos  = producers.size() - back;
        if (pos < 0) pos = 0;
        return producers[pos];
    endfunction

    protected function int win();
        int n = (dep_window < producers.size()) ? dep_window : producers.size();
        return (n < 1) ? 1 : n;
    endfunction

    protected function bit [4:0] random_dest();
        bit [4:0] r;
        do r = 5'($urandom_range(1, 31)); while (r == data_ptr_reg);
        return r;
    endfunction

    protected function bit [4:0] random_src();
        // Prefer a register with a known value; otherwise any (x0 ok).
        if (producers.size() > 0 && roll(50))
            return 5'(producers[$urandom_range(0, producers.size() - 1)]);
        return 5'($urandom_range(0, 31));
    endfunction

    // ==================================================================
    // Opcode menu selection (weighted by class)
    // ==================================================================
    protected function cpu_isa_op_e pick_op();
        int unsigned total;
        int unsigned pick;
        int unsigned acc;

        total = w_alu_r + w_alu_w + w_mul + w_div + w_alu_i + w_alu_iw +
                w_load + w_store + w_branch + w_jal;
        if (total == 0) return CPU_OP_ADD;
        pick = $urandom_range(0, total - 1);
        acc  = 0;

        acc += w_alu_r;  if (pick < acc) return rand_alu_r();
        acc += w_alu_w;  if (pick < acc) return rand_alu_w();
        acc += w_mul;    if (pick < acc) return rand_mul();
        acc += w_div;    if (pick < acc) return rand_div();
        acc += w_alu_i;  if (pick < acc) return rand_alu_i();
        acc += w_alu_iw; if (pick < acc) return rand_alu_iw();
        acc += w_load;   if (pick < acc) return rand_load();
        acc += w_store;  if (pick < acc) return rand_store();
        acc += w_branch; if (pick < acc) return CPU_OP_BEQ; // class only; op re-picked
        return CPU_OP_JAL;
    endfunction

    protected function cpu_isa_op_e rand_alu_r();
        cpu_isa_op_e o[10] = '{CPU_OP_ADD, CPU_OP_SUB, CPU_OP_SLL, CPU_OP_SLT,
                               CPU_OP_SLTU, CPU_OP_XOR, CPU_OP_SRL, CPU_OP_SRA,
                               CPU_OP_OR, CPU_OP_AND};
        return o[$urandom_range(0, 9)];
    endfunction
    protected function cpu_isa_op_e rand_alu_w();
        cpu_isa_op_e o[5] = '{CPU_OP_ADDW, CPU_OP_SUBW, CPU_OP_SLLW,
                              CPU_OP_SRLW, CPU_OP_SRAW};
        return o[$urandom_range(0, 4)];
    endfunction
    protected function cpu_isa_op_e rand_mul();
        cpu_isa_op_e o[5] = '{CPU_OP_MUL, CPU_OP_MULH, CPU_OP_MULHSU,
                              CPU_OP_MULHU, CPU_OP_MULW};
        return o[$urandom_range(0, 4)];
    endfunction
    protected function cpu_isa_op_e rand_div();
        cpu_isa_op_e o[8] = '{CPU_OP_DIV, CPU_OP_DIVU, CPU_OP_REM, CPU_OP_REMU,
                              CPU_OP_DIVW, CPU_OP_DIVUW, CPU_OP_REMW, CPU_OP_REMUW};
        return o[$urandom_range(0, 7)];
    endfunction
    protected function cpu_isa_op_e rand_alu_i();
        cpu_isa_op_e o[9] = '{CPU_OP_ADDI, CPU_OP_SLTI, CPU_OP_SLTIU, CPU_OP_XORI,
                              CPU_OP_ORI, CPU_OP_ANDI, CPU_OP_SLLI, CPU_OP_SRLI,
                              CPU_OP_SRAI};
        return o[$urandom_range(0, 8)];
    endfunction
    protected function cpu_isa_op_e rand_alu_iw();
        cpu_isa_op_e o[4] = '{CPU_OP_ADDIW, CPU_OP_SLLIW, CPU_OP_SRLIW, CPU_OP_SRAIW};
        return o[$urandom_range(0, 3)];
    endfunction
    protected function cpu_isa_op_e rand_load();
        cpu_isa_op_e o[7] = '{CPU_OP_LB, CPU_OP_LH, CPU_OP_LW, CPU_OP_LD,
                              CPU_OP_LBU, CPU_OP_LHU, CPU_OP_LWU};
        return o[$urandom_range(0, 6)];
    endfunction
    protected function cpu_isa_op_e rand_store();
        cpu_isa_op_e o[4] = '{CPU_OP_SB, CPU_OP_SH, CPU_OP_SW, CPU_OP_SD};
        return o[$urandom_range(0, 3)];
    endfunction

    // ==================================================================
    // Misc
    // ==================================================================
    // Probability roll: returns 1 with probability pct/100.
    protected function bit roll(int unsigned pct);
        if (pct == 0) return 1'b0;
        if (pct >= 100) return 1'b1;
        return ($urandom_range(0, 99) < pct);
    endfunction

endclass
