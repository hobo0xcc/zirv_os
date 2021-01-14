SCRIPT=app.ld
CC=riscv64-unknown-elf-gcc
CFLAGS=-nostdlib -T $(SCRIPT)
LIB=syscall.S libc.c
RM=rm -rf
CMDS=cmds
BIN=$(shell cat $(CMDS))

all: $(BIN)

hello: hello.c $(LIB)
	$(CC) $(CFLAGS) -o $@ $^

shell: shell.c $(LIB)
	$(CC) $(CFLAGS) -o $@ $^

fib: fib.c $(LIB)
	$(CC) $(CFLAGS) -o $@ $^

clean:
	$(RM) $(BIN)
