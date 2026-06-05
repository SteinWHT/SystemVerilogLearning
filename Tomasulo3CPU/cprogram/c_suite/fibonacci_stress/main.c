#include "../common/common.h"

#define FIB_DEPTH 256u
#define MIX_FUNCTIONS 32u

static uint64_t memo[FIB_DEPTH + 1u];
static uint8_t memo_valid[FIB_DEPTH + 1u];
static volatile uint64_t recursion_signature;

#define DEFINE_MIX(ID, SHIFT, CONSTANT)                                      \
    __attribute__((noinline)) static uint64_t mix_##ID(uint64_t x) {         \
        x ^= (CONSTANT);                                                      \
        x += x << (SHIFT);                                                    \
        x ^= x >> ((SHIFT) + 1);                                              \
        x *= ((CONSTANT) | 1ull);                                             \
        x ^= x << ((SHIFT) + 3);                                              \
        x += (CONSTANT) ^ ((uint64_t)(ID) << 48);                             \
        return x ^ (x >> 29);                                                 \
    }

DEFINE_MIX(0,  1, 0x9E3779B185EBCA87ull)
DEFINE_MIX(1,  2, 0xC2B2AE3D27D4EB4Full)
DEFINE_MIX(2,  3, 0x165667B19E3779F9ull)
DEFINE_MIX(3,  4, 0x85EBCA77C2B2AE63ull)
DEFINE_MIX(4,  5, 0x27D4EB2F165667C5ull)
DEFINE_MIX(5,  6, 0x94D049BB133111EBull)
DEFINE_MIX(6,  7, 0xD6E8FEB86659FD93ull)
DEFINE_MIX(7,  8, 0xA0761D6478BD642Full)
DEFINE_MIX(8,  9, 0xE7037ED1A0B428DBull)
DEFINE_MIX(9, 10, 0x8EBC6AF09C88C6E3ull)
DEFINE_MIX(10, 11, 0x589965CC75374CC3ull)
DEFINE_MIX(11, 12, 0x1D8E4E27C47D124Full)
DEFINE_MIX(12, 13, 0xEB44ACCAB455D165ull)
DEFINE_MIX(13, 14, 0xDB4F0B9175AE2165ull)
DEFINE_MIX(14, 15, 0xBBE0563303A4615Full)
DEFINE_MIX(15, 16, 0xA0F2EC75A1FE1575ull)
DEFINE_MIX(16,  1, 0x89E182857D9ED689ull)
DEFINE_MIX(17,  2, 0xC6BC279692B5CC83ull)
DEFINE_MIX(18,  3, 0xD3833E804F4C574Bull)
DEFINE_MIX(19,  4, 0xCA5A826395121157ull)
DEFINE_MIX(20,  5, 0xA24BAED4963EE407ull)
DEFINE_MIX(21,  6, 0x9FB21C651E98DF25ull)
DEFINE_MIX(22,  7, 0xB7E151628AED2A6Bull)
DEFINE_MIX(23,  8, 0xBF58476D1CE4E5B9ull)
DEFINE_MIX(24,  9, 0x94D049BB133111EBull)
DEFINE_MIX(25, 10, 0xF1357AEA2E62A9C5ull)
DEFINE_MIX(26, 11, 0xD1B54A32D192ED03ull)
DEFINE_MIX(27, 12, 0xABC98388FB8FAC03ull)
DEFINE_MIX(28, 13, 0x8CB92BA72F3D8DD7ull)
DEFINE_MIX(29, 14, 0xDBE6D5D5FE4CCE2Full)
DEFINE_MIX(30, 15, 0xA3B195354A39B70Dull)
DEFINE_MIX(31, 16, 0xC13FA9A902A6328Full)

__attribute__((noinline)) static uint64_t dispatch_mix(uint64_t index, uint64_t value) {
    switch (index & (MIX_FUNCTIONS - 1u)) {
        case 0: return mix_0(value);
        case 1: return mix_1(value);
        case 2: return mix_2(value);
        case 3: return mix_3(value);
        case 4: return mix_4(value);
        case 5: return mix_5(value);
        case 6: return mix_6(value);
        case 7: return mix_7(value);
        case 8: return mix_8(value);
        case 9: return mix_9(value);
        case 10: return mix_10(value);
        case 11: return mix_11(value);
        case 12: return mix_12(value);
        case 13: return mix_13(value);
        case 14: return mix_14(value);
        case 15: return mix_15(value);
        case 16: return mix_16(value);
        case 17: return mix_17(value);
        case 18: return mix_18(value);
        case 19: return mix_19(value);
        case 20: return mix_20(value);
        case 21: return mix_21(value);
        case 22: return mix_22(value);
        case 23: return mix_23(value);
        case 24: return mix_24(value);
        case 25: return mix_25(value);
        case 26: return mix_26(value);
        case 27: return mix_27(value);
        case 28: return mix_28(value);
        case 29: return mix_29(value);
        case 30: return mix_30(value);
        default: return mix_31(value);
    }
}

__attribute__((noinline)) static uint64_t fibonacci(uint64_t n) {
    volatile uint64_t frame[4];
    uint64_t value;

    frame[0] = n;
    frame[1] = n ^ 0xAAAAAAAAAAAAAAAAull;
    frame[2] = n + 0x12345678u;
    frame[3] = n * 0x9E37u;

    if (memo_valid[n]) {
        return memo[n];
    }

    value = fibonacci(n - 1u) + fibonacci(n - 2u);
    memo[n] = value;
    memo_valid[n] = 1u;

    // Read the local frame after recursion so every level retains a real stack
    // frame. The 256-level descent exceeds the four-entry RAS by a wide margin.
    recursion_signature ^= dispatch_mix(n, value ^ frame[n & 3u]);
    return value;
}

static uint64_t fibonacci_iterative(uint64_t n) {
    uint64_t prev = 0;
    uint64_t curr = 1;

    for (uint64_t i = 0; i < n; i++) {
        uint64_t next = prev + curr;
        prev = curr;
        curr = next;
    }
    return prev;
}

int main(void) {
    uint64_t recursive_value;
    uint64_t expected_value;
    uint64_t mix;

    memo[0] = 0;
    memo[1] = 1;
    memo_valid[0] = 1;
    memo_valid[1] = 1;

    recursive_value = fibonacci(FIB_DEPTH);
    expected_value = fibonacci_iterative(FIB_DEPTH);
    if (recursive_value != expected_value) {
        report_fail(0xF01u);
    }

    for (uint64_t i = 0; i <= FIB_DEPTH; i++) {
        if (!memo_valid[i]) {
            report_fail(0xF10u + (i & 0xFFu));
        }
    }

    mix = exercise_rv64im(recursive_value ^ recursion_signature);
    if (mix == 0ull && recursion_signature == 1ull) {
        report_fail(0xFFDu);
    }

    report_pass();
}
