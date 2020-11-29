ZIG=zig
ZIGOPT=-target riscv64-freestanding --cache-dir $(CACHE) -mcmodel=medium
ZIGEXEOPT=-target riscv64-freestanding --cache-dir $(CACHE)
RM=rm -rf

SRC=$(wildcard src/*.zig)
OBJ=$(SRC:.zig=.o)
BIN=zirv.elf
CACHE=./zig-cache/

.PHONY: $(BIN)
$(BIN):
	$(ZIG) build-obj $(ZIGOPT) src/entry.zig -femit-bin=src/entry.o
	$(ZIG) build-obj $(ZIGOPT) src/start.zig -femit-bin=src/start.o
	$(ZIG) build-exe $(ZIGEXEOPT) src/entry.o src/start.o --script src/linker.ld -femit-bin=$(BIN)

qemu: $(BIN)
	qemu-system-riscv64 -machine virt -bios none -kernel $^ -m 128M -smp 1 -nographic

qemu-gdb: $(BIN)
	riscv64-unknown-elf-gdb -x script.gdb

rve: $(BIN)
	~/d/src/rve/bin/rve $^

clean:
	$(RM) src/*.o zig-cache/ $(BIN)
