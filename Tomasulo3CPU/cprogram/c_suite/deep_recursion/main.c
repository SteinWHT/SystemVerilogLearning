#include "../common/common.h"

// Directed deep / mutual recursion to close the return-address-stack coverage
// gap (RAS at ~19%, sync_lifo at ~52%).
//
// RAS_DEPTH is 4 in the DUT. Recursing far deeper forces the underlying
// sync_lifo to overflow (push-when-full / round-robin wrap) on the way down and
// to hit its underflow-protect path as the many returns unwind past the four
// retained entries. The larger call footprint also raises the PC values that
// flow into the RAS, toggling its address bits. Mutual recursion varies the
// return-address stream to stress the BPB / RAS interaction.

// Optimization barrier so each level performs a real JAL/JALR and is not
// constant-folded or inlined away.
static inline int64_t opaque(int64_t x) {
    asm volatile("" : "+r"(x));
    return x;
}

// Non-tail recursion: work happens *after* the call, so the compiler cannot
// turn it into a loop (which would defeat the RAS exercise).
static int64_t descend(int64_t n) {
    if (n <= 0) {
        return 0;
    }
    int64_t below = descend(n - 1);
    return below + n;
}

static int64_t pong(int64_t n);

static int64_t ping(int64_t n) {
    if (n <= 0) {
        return 1;
    }
    return 1 + pong(n - 1);
}

static int64_t pong(int64_t n) {
    if (n <= 0) {
        return 2;
    }
    return 2 + ping(n - 1);
}

int main(void) {
    int64_t s = 0;
    uint64_t mix;

    // Each descent pushes (16..20) return addresses (RAS holds only 4) and then
    // pops them all back, exercising overflow then underflow-protect per pass.
    for (int64_t k = 0; k < 5; k++) {
        int64_t depth = 16 + k;
        int64_t d = descend(opaque(depth));
        int64_t expect = depth * (depth + 1) / 2; // sum 1..depth
        if (d != expect) {
            report_fail(0x801u + (uint64_t)k);
        }
        s += d;
    }

    // Mutual-recursion sweep: alternating call sites vary the RAS stream.
    for (int64_t k = 0; k < 6; k++) {
        int64_t p = ping(opaque(12 + k));
        s ^= p;
    }

    mix = exercise_rv64im((uint64_t)s);
    if ((mix & 0xFu) == 0xFu) {
        report_fail(0x8EEu);
    }

    report_pass();
}
