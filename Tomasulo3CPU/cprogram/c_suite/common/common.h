#ifndef C_SUITE_COMMON_H
#define C_SUITE_COMMON_H

#include <stdint.h>

extern volatile uint64_t tohost;
extern volatile uint64_t fromhost;

__attribute__((noreturn)) static inline void report_pass(void) {
    tohost = 1u;
    for (;;)
        ;
}

__attribute__((noreturn)) static inline void report_fail(uint64_t code) {
    tohost = (code == 0u) ? 2u : code;
    for (;;)
        ;
}

static inline int64_t op_mulh(int64_t a, int64_t b) {
    int64_t out;
    asm volatile("mulh %0, %1, %2" : "=r"(out) : "r"(a), "r"(b));
    return out;
}

static inline uint64_t op_mulhu(uint64_t a, uint64_t b) {
    uint64_t out;
    asm volatile("mulhu %0, %1, %2" : "=r"(out) : "r"(a), "r"(b));
    return out;
}

static inline int64_t op_mulhsu(int64_t a, uint64_t b) {
    int64_t out;
    asm volatile("mulhsu %0, %1, %2" : "=r"(out) : "r"(a), "r"(b));
    return out;
}

static inline int64_t op_mulw(int64_t a, int64_t b) {
    int64_t out;
    asm volatile("mulw %0, %1, %2" : "=r"(out) : "r"(a), "r"(b));
    return out;
}

static inline int64_t op_divw(int64_t a, int64_t b) {
    int64_t out;
    asm volatile("divw %0, %1, %2" : "=r"(out) : "r"(a), "r"(b));
    return out;
}

static inline uint64_t op_divuw(uint64_t a, uint64_t b) {
    uint64_t out;
    asm volatile("divuw %0, %1, %2" : "=r"(out) : "r"(a), "r"(b));
    return out;
}

static inline int64_t op_remw(int64_t a, int64_t b) {
    int64_t out;
    asm volatile("remw %0, %1, %2" : "=r"(out) : "r"(a), "r"(b));
    return out;
}

static inline uint64_t op_remuw(uint64_t a, uint64_t b) {
    uint64_t out;
    asm volatile("remuw %0, %1, %2" : "=r"(out) : "r"(a), "r"(b));
    return out;
}

static inline uint64_t exercise_rv64im(uint64_t seed) {
    volatile int8_t b8 = -7;
    volatile uint8_t ub8 = 0xF2u;
    volatile int16_t h16 = -1234;
    volatile uint16_t uh16 = 0xF0E1u;
    volatile int32_t w32 = -500000;
    volatile uint32_t uw32 = 0xFEDCBA98u;
    volatile int64_t d64 = -0x1234567;

    int64_t s = (int64_t)seed;
    uint64_t u = seed ^ 0xA5A55A5A1234u;

    s += b8;
    s += (int64_t)ub8;
    s += h16;
    s += (int64_t)uh16;
    s += w32;
    s += (int64_t)uw32;
    s += d64;

    s = (s << 3) ^ (s >> 5);
    u = (u << 11) | (u >> 7);
    s ^= (int64_t)u;

    if (s < 0) {
        s = -s;
    } else {
        s = s + 17;
    }

    s += (int64_t)op_mulh(s, 0x12345);
    s += (int64_t)op_mulhu((uint64_t)s, 0x23456u);
    s += (int64_t)op_mulhsu(-1234567, 0x123456789u);
    s += op_mulw(s, 11);
    s += op_divw(s + 99, 7);
    s += (int64_t)op_divuw((uint64_t)s + 123u, 9u);
    s += op_remw(s + 199, 13);
    s += (int64_t)op_remuw((uint64_t)s + 17u, 5u);

    return (uint64_t)s ^ (u >> 9);
}

#endif
