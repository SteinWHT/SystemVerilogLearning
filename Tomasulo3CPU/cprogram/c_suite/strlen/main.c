#include "../common/common.h"

static uint64_t bm_strlen(const char *s) {
    uint64_t n = 0;
    while (s[n] != '\0') {
        n++;
    }
    return n;
}

int main(void) {
    static const char s0[] = "";
    static const char s1[] = "riscv";
    static const char s2[] = "Tomasulo3CPU bare metal test";
    uint64_t l0 = bm_strlen(s0);
    uint64_t l1 = bm_strlen(s1);
    uint64_t l2 = bm_strlen(s2);
    uint64_t mix;

    if (l0 != 0u) {
        report_fail(0x301u);
    }
    if (l1 != 5u) {
        report_fail(0x302u);
    }
    if (l2 != 28u) {
        report_fail(0x303u);
    }

    mix = exercise_rv64im((l2 << 8) | (l1 << 4) | l0);
    if ((mix & 0xFFFFu) == 0x55AAu) {
        report_fail(0x30EEu);
    }

    report_pass();
}
