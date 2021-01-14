#include "syscall.h"
#include "types.h"

int str_len(char *str) {
    int i;
    for (i = 0; str[i] != '\0'; i++);

    return i; 
}

void print(char *str) {
    sys_write(0, (uint64)str, str_len(str));
}

char get_ch() {
    char ch;
    sys_read(0, (uint64)&ch, 1);
    return ch;
}

void put_ch(char ch) {
    sys_write(0, (uint64)&ch, 1);
}

void killme() {
    sys_exit();
}
