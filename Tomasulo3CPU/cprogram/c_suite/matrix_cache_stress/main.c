#include "../common/common.h"

// The matrices alone are modest enough to keep runtime practical. The pressure
// region pushes the live data footprint above the 16 KiB L1D capacity after
// every output row, forcing repeated capacity misses and dirty writebacks.
#define N 20
#define PRESSURE_BYTES (24u * 1024u)
#define PRESSURE_WORDS (PRESSURE_BYTES / sizeof(uint64_t))
#define CACHE_LINE_WORDS 8u

static int32_t matrix_a[N][N];
static int32_t matrix_b[N][N];
static int64_t matrix_c[N][N];
static uint64_t cache_pressure[PRESSURE_WORDS];

static inline int64_t expected_cell(int64_t row, int64_t col) {
    const int64_t sum_k = (N * (N - 1)) / 2;
    const int64_t sum_k2 = (N * (N - 1) * (2 * N - 1)) / 6;
    return sum_k * (row + 1 - col) + sum_k2 - N * (row + 1) * col;
}

static uint64_t pressure_sweep(uint64_t token) {
    uint64_t fold = token;

    // One dirty access per 64-byte line covers 24 KiB, larger than the L1D.
    for (uint64_t i = 0; i < PRESSURE_WORDS; i += CACHE_LINE_WORDS) {
        uint64_t value = cache_pressure[i] ^ token ^ (i * 0x9E37u);
        cache_pressure[i] = value;
        fold ^= value + (fold << 7) + (fold >> 3);
    }
    return fold;
}

int main(void) {
    uint64_t checksum = 0;

    for (int64_t i = 0; i < N; i++) {
        for (int64_t j = 0; j < N; j++) {
            matrix_a[i][j] = (int32_t)(i + j + 1);
            matrix_b[i][j] = (int32_t)(i - j);
            matrix_c[i][j] = 0;
        }
    }

    for (uint64_t i = 0; i < PRESSURE_WORDS; i += CACHE_LINE_WORDS) {
        cache_pressure[i] = i ^ 0xA5A55A5Au;
    }

    for (int64_t i = 0; i < N; i++) {
        for (int64_t j = 0; j < N; j++) {
            int64_t sum = 0;
            for (int64_t k = 0; k < N; k++) {
                sum += (int64_t)matrix_a[i][k] * (int64_t)matrix_b[k][j];
            }
            matrix_c[i][j] = sum;
        }

        checksum ^= pressure_sweep((uint64_t)(i + 1) * 0x100000001B3ull);
    }

    for (int64_t i = 0; i < N; i++) {
        for (int64_t j = 0; j < N; j++) {
            int64_t expected = expected_cell(i, j);
            if (matrix_c[i][j] != expected) {
                report_fail(0xE00u + (uint64_t)(i * N + j));
            }
            checksum ^= (uint64_t)matrix_c[i][j] +
                        ((uint64_t)i << 32) + (uint64_t)j;
        }
    }

    checksum ^= exercise_rv64im(checksum);
    if (checksum == 0ull && matrix_c[0][0] == 1) {
        report_fail(0xEFDu);
    }

    report_pass();
}
