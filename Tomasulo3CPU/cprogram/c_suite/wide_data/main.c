#include "../common/common.h"

// Directed wide-operand exercise for toggle-coverage closure.
//
// The rest of the C-suite and the arch tests use small operand values, so the
// upper bits of the 64-bit datapath (PRF/ROB/CDB/ALU/MUL/DIV and the issue
// queues) never toggle. This program pushes high-entropy 64-bit patterns through
// every arithmetic/logic/shift path plus full- and sub-width load/store, so the
// data bits flip across their whole range.
//
// All in-program checks use identities that hold for *any* operand, so they can
// never false-fail; the Spike-golden scoreboard remains the real correctness
// check on every commit.

static const uint64_t PATTERNS[] = {
    0x0000000000000000ull,
    0xFFFFFFFFFFFFFFFFull,
    0xAAAAAAAAAAAAAAAAull,
    0x5555555555555555ull,
    0x8000000000000000ull,
    0x7FFFFFFFFFFFFFFFull,
    0x0123456789ABCDEFull,
    0xFEDCBA9876543210ull,
    0x00000000FFFFFFFFull,
    0xFFFFFFFF00000000ull,
    0xF0F0F0F0F0F0F0F0ull,
    0xDEADBEEFCAFEBABEull,
};
#define NPAT (sizeof(PATTERNS) / sizeof(PATTERNS[0]))

// Optimization barrier: keeps a value in a GPR and stops constant folding so the
// real instructions are emitted and committed.
static inline uint64_t opaque(uint64_t x) {
    asm volatile("" : "+r"(x));
    return x;
}

int main(void) {
    volatile uint64_t mem[NPAT];
    uint64_t acc = 0;

    for (uint64_t i = 0; i < NPAT; i++) {
        uint64_t a = opaque(PATTERNS[i]);

        // Full-width store then load: toggles the 64-bit memory data bus.
        mem[i] = a;
        if (mem[i] != a) {
            report_fail(0xD01u + i);
        }

        // Bit-wise identities toggle every bit lane of the ALU logic ops.
        if ((a ^ ~a) != 0xFFFFFFFFFFFFFFFFull) {
            report_fail(0xD10u + i);
        }
        if ((a & ~a) != 0ull) {
            report_fail(0xD20u + i);
        }
        if ((a | ~a) != 0xFFFFFFFFFFFFFFFFull) {
            report_fail(0xD30u + i);
        }

        // Shifts across the entire width exercise the shifter data path.
        for (uint64_t s = 0; s < 64; s += 7) {
            uint64_t l = a << s;
            uint64_t r = a >> s;
            int64_t ar = (int64_t)a >> s;
            acc += l ^ r ^ (uint64_t)ar;
        }

        for (uint64_t j = 0; j < NPAT; j++) {
            uint64_t b = opaque(PATTERNS[j]);

            acc += a + b;
            acc += a - b;
            acc ^= a & b;
            acc ^= a | b;
            acc += a * b; // 64x64 -> low 64 (MUL)
            acc += (uint64_t)op_mulh((int64_t)a, (int64_t)b);
            acc += op_mulhu(a, b);
            acc += (uint64_t)op_mulhsu((int64_t)a, b);

            if (b != 0ull) {
                // Unsigned Euclid identity holds for any a, b!=0.
                uint64_t q = a / b;
                uint64_t r = a % b;
                if (opaque(q * b + r) != a) {
                    report_fail(0xD40u + ((i * NPAT + j) & 0x3Fu));
                }
                acc += q ^ r;

                int64_t sa = (int64_t)a;
                int64_t sb = (int64_t)b;
                // Skip only the INT64_MIN / -1 signed-overflow corner (UB).
                if (!(sa == INT64_MIN && sb == -1)) {
                    int64_t sq = sa / sb;
                    int64_t sr = sa % sb;
                    if (opaque((uint64_t)(sq * sb + sr)) != a) {
                        report_fail(0xD60u + ((i * NPAT + j) & 0x3Fu));
                    }
                    acc += (uint64_t)(sq ^ sr);
                }

                // 32-bit word ops exercise the *W sign/zero-extension paths.
                int32_t wb = (int32_t)b;
                int32_t wa = (int32_t)a;
                if (wb != 0 && !(wa == INT32_MIN && wb == -1)) {
                    acc += (uint64_t)op_mulw(sa, sb);
                    acc += (uint64_t)op_divw(sa, sb);
                    acc += (uint64_t)op_remw(sa, sb);
                    acc += op_divuw(a, b);
                    acc += op_remuw(a, b);
                }
            }
        }
    }

    // Sub-width load/store with sign- and zero-extension (LB/LBU/LH/LHU/LW/LWU).
    for (uint64_t i = 0; i < NPAT; i++) {
        volatile uint8_t b8;
        volatile uint16_t h16;
        volatile uint32_t w32;
        uint64_t a = opaque(PATTERNS[i]);

        b8 = (uint8_t)a;
        acc += (uint64_t)(int64_t)(int8_t)b8;
        acc += (uint64_t)b8;

        h16 = (uint16_t)a;
        acc += (uint64_t)(int64_t)(int16_t)h16;
        acc += (uint64_t)h16;

        w32 = (uint32_t)a;
        acc += (uint64_t)(int64_t)(int32_t)w32;
        acc += (uint64_t)w32;
    }

    acc ^= exercise_rv64im(acc);

    // Liveness guard: uses acc so it stays live; the condition is unreachable
    // (PATTERNS[0] is 0), so it can never false-fail.
    if (opaque(acc) == 0ull && PATTERNS[0] == 1ull) {
        report_fail(0xDEEu);
    }

    report_pass();
}
