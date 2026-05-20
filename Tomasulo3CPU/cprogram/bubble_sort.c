// Minimal bare-metal bubble sort for Tomasulo3CPU
// No stdlib, no OS — runs directly on hardware.
// Array lives in registers/stack with small immediate offsets.

#define ARRAY_SIZE 8

void _start(void) __attribute__((naked, section(".text.start")));
void bubble_sort(int *arr, int n);

void _start(void) {
    // Set stack pointer to end of data memory (small address space)
    // SP = 0x400 (1024 bytes of stack space)
    asm volatile (
        "li sp, 0x400\n"
        "j main\n"
    );
}

void main(void) {
    int arr[ARRAY_SIZE];

    // Initialize array with unsorted values (small constants only)
    arr[0] = 7;
    arr[1] = 3;
    arr[2] = 5;
    arr[3] = 1;
    arr[4] = 8;
    arr[5] = 2;
    arr[6] = 6;
    arr[7] = 4;

    bubble_sort(arr, ARRAY_SIZE);

    // After sorting: arr = {1, 2, 3, 4, 5, 6, 7, 8}
    // Signal completion by writing result to a known address
    volatile int *done_flag = (volatile int *)0x200;
    *done_flag = arr[0]; // Should be 1

    // Infinite loop (halt)
    while (1) {}
}

void bubble_sort(int *arr, int n) {
    int i, j, temp;
    for (i = 0; i < n - 1; i++) {
        for (j = 0; j < n - 1 - i; j++) {
            if (arr[j] > arr[j + 1]) {
                temp = arr[j];
                arr[j] = arr[j + 1];
                arr[j + 1] = temp;
            }
        }
    }
}
