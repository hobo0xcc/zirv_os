#include "libc.h"
#include "types.h"

int fib(int n) {
    if (n < 2) {
        return 1;
    }

    return fib(n - 1) + fib(n - 2);
}

void print_int(int n) {
    char buf[100];
    int cnt = 0;
    while (n != 0) {
        buf[cnt++] = ((n % 10) + '0');
        n /= 10;
    }
    while (--cnt != -1) {
        put_ch(buf[cnt]);
    }
}

int main(void) {
    while (1) {
        print(">> ");
        char ch = get_ch();
        if (ch == 'q') {
            put_ch('\n');
            killme();
        }
        int n = ch - '0';
        while (1) {
            ch = get_ch();
            if (ch == 'q') {
                put_ch('\n');
                killme();
            } else if (ch == '\n') {
                break;
            }
            n = n * 10 + (ch - '0');
        }
        int res = fib(n);
        print_int(res);
        put_ch('\n');
    }
}
