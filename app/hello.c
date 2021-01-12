#include "syscall.h"

int main(void) {
    char *hello = "Hello\n";
    sys_write(0, (long)hello, 6);
    char buf[100];
    char buf2;
    while (1) {
        sys_read(0, (long)&buf2, 1);
        // sys_write(0, (long)hello, 6);
    }
    // return 0;
    while (1) {}
}
