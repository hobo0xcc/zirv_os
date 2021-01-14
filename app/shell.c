#include "syscall.h"
#include "types.h"
#include "libc.h"

int shell_proccmd() {
    print("shell> ");
    int p = 0;
    char buf[100];
    char ch = 0;
    do {
        ch = get_ch();
        buf[p++] = ch;
    } while (ch != '\n');

    buf[p - 1] = '\0';

    sys_exec((uint64)buf);

    return 0;
}

int main(void) {
    while (1) {
        shell_proccmd();
    }
    
    return 0;
}
