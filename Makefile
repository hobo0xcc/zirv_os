RISCV_PREFIX=riscv64-unknown-elf-
LD=$(RISCV_PREFIX)ld
AS=$(RISCV_PREFIX)as
ZIG=zig
ZIGOPT=-target riscv64-freestanding --cache-dir $(CACHE) -mcmodel=medium
RM=rm -rf

SRC=$(wildcard src/*.zig)
OBJ=$(SRC:.zig=.o)
CACHE=./zig-cache/

.PHONY: main
main:
	$(ZIG) build-obj $(ZIGOPT) src/entry.zig -femit-bin=src/entry.o
	$(ZIG) build-obj $(ZIGOPT) src/start.zig -femit-bin=src/start.o
	$(LD) -nostdlib src/entry.o src/start.o -o main -T src/linker.ld

qemu: main
	qemu-system-riscv64 -machine virt -bios none -kernel $^ -m 128M -smp 1 -nographic

rve: main
	~/d/src/rve/bin/rve $^

clean:
	$(RM) src/*.o zig-cache/ main
