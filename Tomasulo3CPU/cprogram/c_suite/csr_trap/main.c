#include "../common/common.h"

// Directed RV64 machine-mode CSR / trap exercise for coverage closure.
//
// Targets the CSR module (src/CSR.sv), which is barely exercised by the rest
// of the C-suite and arch tests, plus the trap/mret commit kinds that the
// functional covergroups never see.
//
// Spike-golden safety notes (cpu_spike_scoreboard compares commit-by-commit):
//   * mscratch is a plain 64-bit R/W register in both the DUT and Spike, so it
//     is used for all writeback value checks.
//   * mstatus/mtvec/mepc/mcause/mtval read values can differ between the DUT
//     (which masks/aligns) and Spike (WARL/WLRL legalization), so those CSRs
//     are written with `csrw` (rd=x0) and read with `csrr x0` (rd=x0). Neither
//     produces a committed register write, so the scoreboard never compares a
//     divergent value while the read/write decode arms still get covered.
//   * mepc reads inside the handler differ only by the Spike DRAM base, which
//     the scoreboard already tolerates for small pointer-like values.

// Handler stores the captured mcause here so main can self-check it.
volatile uint64_t g_mcause = 0;

// Minimal machine-mode trap handler: record mcause, skip the trapping
// instruction (ebreak/ecall are 4 bytes with the C extension disabled), mret.
__attribute__((naked, aligned(4))) static void trap_handler(void) {
    asm volatile(
        "csrr  t0, mcause\n"
        "la    t1, g_mcause\n"
        "sd    t0, 0(t1)\n"
        "csrr  t0, mepc\n"
        "addi  t0, t0, 4\n"
        "csrw  mepc, t0\n"
        "mret\n");
}

// Exercise every csr_cmd form on mscratch: RW/RS/RC, the immediate variants,
// and the no-write corners (RS/RC with x0, RSI/RCI with zimm==0).
static void csr_mscratch_sequence(uint64_t v1, uint64_t v2, uint64_t v3,
                                  uint64_t *chk_rmw, uint64_t *final_val) {
    asm volatile(
        ".option push\n"
        ".option norvc\n"
        "csrrw  t0, mscratch, %2\n"   // t0 = old(0);            mscratch = v1
        "csrrs  t1, mscratch, %3\n"   // t1 = v1;                mscratch |= v2
        "csrrc  t2, mscratch, %4\n"   // t2 = v1|v2;             mscratch &= ~v3
        "csrr   %0, mscratch\n"       // chk_rmw = (v1|v2)&~v3
        "csrrwi t0, mscratch, 31\n"   //                         mscratch = 31
        "csrrsi t1, mscratch, 10\n"   //                         mscratch |= 10  (=31)
        "csrrci t2, mscratch, 5\n"    //                         mscratch &= ~5  (=26)
        "csrrs  t0, mscratch, x0\n"   // no write (rs1 == x0)
        "csrrc  t1, mscratch, x0\n"   // no write (rs1 == x0)
        "csrrsi t2, mscratch, 0\n"    // no write (zimm == 0)
        "csrrci t0, mscratch, 0\n"    // no write (zimm == 0)
        "csrr   %1, mscratch\n"       // final_val = 26
        ".option pop\n"
        : "=&r"(*chk_rmw), "=&r"(*final_val)
        : "r"(v1), "r"(v2), "r"(v3)
        : "t0", "t1", "t2");
}

// Touch the read mux and write case arms for the remaining supported CSRs
// without exposing a divergent value to the scoreboard.
static void csr_decode_arms(void) {
    uint64_t aligned = 0x40u;   // 4-byte aligned: safe for mtvec/mepc WARL
    uint64_t small   = 0x8u;    // mstatus.MIE / a small legal mcause

    asm volatile(
        ".option push\n"
        ".option norvc\n"
        "csrw  mtvec, %0\n"
        "csrr  x0, mtvec\n"
        "csrw  mepc, %0\n"
        "csrr  x0, mepc\n"
        "csrw  mcause, %1\n"
        "csrr  x0, mcause\n"
        "csrw  mtval, %0\n"
        "csrr  x0, mtval\n"
        "csrw  mstatus, %1\n"
        "csrr  x0, mstatus\n"
        ".option pop\n"
        :
        : "r"(aligned), "r"(small)
        : );
}

int main(void) {
    const uint64_t v1 = 0xA5A5A5A5A5A5A5A5ull;
    const uint64_t v2 = 0x0F0F0F0F0F0F0F0Full;
    const uint64_t v3 = 0xFF00FF00FF00FF00ull;

    uint64_t chk_rmw = 0;
    uint64_t final_val = 0;

    csr_mscratch_sequence(v1, v2, v3, &chk_rmw, &final_val);
    if (chk_rmw != ((v1 | v2) & ~v3)) {
        report_fail(0xC01u);
    }
    if (final_val != 26u) {
        report_fail(0xC02u);
    }

    csr_decode_arms();

    // Install the trap handler, then exercise the synchronous trap + mret path.
    asm volatile("csrw mtvec, %0\n"
                 :
                 : "r"((uint64_t)(uintptr_t)&trap_handler)
                 : );

    g_mcause = 0xDEADu;
    asm volatile("ebreak\n" ::: "t0", "t1", "memory");
    if (g_mcause != 3u) {              // MCAUSE_EBREAK
        report_fail(0xC03u);
    }

    g_mcause = 0xDEADu;
    asm volatile("ecall\n" ::: "t0", "t1", "memory");
    if (g_mcause != 11u) {             // MCAUSE_ECALL_MMODE
        report_fail(0xC04u);
    }

    report_pass();
}
