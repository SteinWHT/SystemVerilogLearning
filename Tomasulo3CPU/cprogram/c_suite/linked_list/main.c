#include "../common/common.h"

typedef struct Node {
    int32_t value;
    struct Node *next;
} Node;

static Node *build_list(Node *pool, int count) {
    for (int i = 0; i < count; i++) {
        pool[i].value = i + 1;
        pool[i].next = (i + 1 < count) ? &pool[i + 1] : (Node *)0;
    }
    return &pool[0];
}

static int64_t sum_list(Node *head) {
    int64_t sum = 0;
    while (head != (Node *)0) {
        sum += head->value;
        head = head->next;
    }
    return sum;
}

static Node *reverse(Node *head) {
    Node *prev = (Node *)0;
    Node *cur = head;
    while (cur != (Node *)0) {
        Node *nxt = cur->next;
        cur->next = prev;
        prev = cur;
        cur = nxt;
    }
    return prev;
}

int main(void) {
    Node pool[8];
    Node *head;
    int64_t s0;
    int64_t s1;
    uint64_t mix;

    head = build_list(pool, 8);
    s0 = sum_list(head);
    if (s0 != 36) {
        report_fail(0x601u);
    }

    head = reverse(head);
    if (head->value != 8) {
        report_fail(0x602u);
    }

    s1 = sum_list(head);
    if (s1 != 36) {
        report_fail(0x603u);
    }

    mix = exercise_rv64im((uint64_t)(s0 + s1));
    if ((mix & 0xFFu) == 0xC3u) {
        report_fail(0x6EEu);
    }

    report_pass();
}
