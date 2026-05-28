#include "../common/common.h"

static int64_t factorial(int64_t n) {
    if (n <= 1) {
        return 1;
    }
    return n * factorial(n - 1);
}

static int64_t fib(int64_t n) {
    if (n <= 1) {
        return n;
    }
    return fib(n - 1) + fib(n - 2);
}

int main(void) {
    int64_t f6 = factorial(6);
    int64_t f7 = fib(7);
    int64_t q = f6 / 9;
    int64_t r = f6 % 9;
    uint64_t mix;

    if (f6 != 720) {
        report_fail(0x701u);
    }
    if (f7 != 13) {
        report_fail(0x702u);
    }
    if (q != 80 || r != 0) {
        report_fail(0x703u);
    }

    mix = exercise_rv64im((uint64_t)(f6 + f7 + q + r));
    if ((mix & 0x7u) == 0x0u) {
        report_fail(0x7EEu);
    }

    report_pass();
}
