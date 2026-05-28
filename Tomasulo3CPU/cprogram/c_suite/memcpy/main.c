#include "../common/common.h"

static void *bm_memcpy(void *dst, const void *src, uint64_t n) {
    uint8_t *d = (uint8_t *)dst;
    const uint8_t *s = (const uint8_t *)src;
    for (uint64_t i = 0; i < n; i++) {
        d[i] = s[i];
    }
    return dst;
}

int main(void) {
    uint8_t src[32];
    uint8_t dst[32];
    uint64_t sum = 0;
    uint64_t mix;

    for (uint64_t i = 0; i < 32; i++) {
        src[i] = (uint8_t)((i * 7u) ^ 0x5Au);
        dst[i] = 0;
    }

    bm_memcpy(dst, src, 32);

    for (uint64_t i = 0; i < 32; i++) {
        if (dst[i] != src[i]) {
            report_fail(0x101u + i);
        }
        sum += dst[i];
    }

    mix = exercise_rv64im(sum + 3u);
    if ((mix & 0xFFu) == 0u) {
        report_fail(0x10FFu);
    }

    report_pass();
}
