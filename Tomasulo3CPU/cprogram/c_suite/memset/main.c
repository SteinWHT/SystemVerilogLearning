#include "../common/common.h"

static void *bm_memset(void *dst, int value, uint64_t n) {
    uint8_t *d = (uint8_t *)dst;
    uint8_t v = (uint8_t)value;
    for (uint64_t i = 0; i < n; i++) {
        d[i] = v;
    }
    return dst;
}

int main(void) {
    uint8_t buf[64];
    uint64_t checksum = 0;
    uint64_t mix;

    bm_memset(buf, 0xA5, 64);
    for (uint64_t i = 0; i < 64; i++) {
        if (buf[i] != 0xA5u) {
            report_fail(0x201u + i);
        }
        checksum ^= ((uint64_t)buf[i] << (i & 7u));
    }

    bm_memset(buf + 10, 0x3C, 11);
    for (uint64_t i = 10; i < 21; i++) {
        if (buf[i] != 0x3Cu) {
            report_fail(0x250u + i);
        }
    }

    mix = exercise_rv64im(checksum ^ 0x112233u);
    if ((mix & 0x3u) == 0x3u) {
        report_pass();
    }
    report_pass();
}
