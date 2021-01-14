#include "libc.h"
#include "syscall.h"

int main(void) {
    print("Hello, world!\n");
    killme();
    return 0;
}
