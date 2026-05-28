#include "../common/common.h"

static int bm_strcmp(const char *a, const char *b) {
    while (*a != '\0' && *a == *b) {
        a++;
        b++;
    }
    return (int)((unsigned char)*a - (unsigned char)*b);
}

int main(void) {
    int r0 = bm_strcmp("abc", "abc");
    int r1 = bm_strcmp("abc", "abd");
    int r2 = bm_strcmp("abd", "abc");
    int r3 = bm_strcmp("abc", "ab");
    int r4 = bm_strcmp("ab", "abc");
    uint64_t mix;

    if (r0 != 0) {
        report_fail(0x401u);
    }
    if (r1 >= 0) {
        report_fail(0x402u);
    }
    if (r2 <= 0) {
        report_fail(0x403u);
    }
    if (r3 <= 0) {
        report_fail(0x404u);
    }
    if (r4 >= 0) {
        report_fail(0x405u);
    }

    mix = exercise_rv64im((uint64_t)(r2 - r1 + r3 - r4));
    if ((mix & 1u) == 0u && (mix & 2u) == 0u) {
        report_fail(0x40EEu);
    }

    report_pass();
}
