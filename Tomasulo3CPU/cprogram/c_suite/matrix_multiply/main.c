#include "../common/common.h"

#define N 3

static void matmul(const int32_t a[N][N], const int32_t b[N][N], int64_t c[N][N]) {
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            int64_t sum = 0;
            for (int k = 0; k < N; k++) {
                sum += (int64_t)a[i][k] * (int64_t)b[k][j];
            }
            c[i][j] = sum;
        }
    }
}

int main(void) {
    static const int32_t a[N][N] = {
        {1, 2, 3},
        {0, -1, 4},
        {5, 2, 1},
    };
    static const int32_t b[N][N] = {
        {2, 1, 0},
        {3, -2, 1},
        {4, 2, -1},
    };
    static const int64_t expect[N][N] = {
        {20, 3, -1},
        {13, 10, -5},
        {20, 3, 1},
    };
    int64_t c[N][N];
    uint64_t fold = 0;
    uint64_t mix;

    matmul(a, b, c);
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            if (c[i][j] != expect[i][j]) {
                report_fail(0x500u + (uint64_t)(i * 8 + j));
            }
            fold ^= (uint64_t)(c[i][j] * (i + 1) * (j + 3));
        }
    }

    mix = exercise_rv64im(fold + 0x123u);
    if ((mix & 0x1F) == 0x1F) {
        report_fail(0x5EEu);
    }

    report_pass();
}
