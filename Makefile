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

qemu: $(BIN) fs.img
	qemu-system-riscv64 -machine virt -bios none -kernel $^ -m 128M -smp 1 -nographic -drive file=fs.img,if=none,id=foo,format=raw -global virtio-mmio.force-legacy=false -device virtio-blk-device,drive=foo,bus=virtio-mmio-bus.0

qemu-gdb: $(BIN) fs.img
	riscv64-unknown-elf-gdb -x script.gdb

rve: $(BIN) fs.img
	~/d/src/rve/bin/rve $^

fs.img:
	dd if=/dev/urandom of=$@ bs=1m count=32

clean:
	$(RM) src/*.o zig-cache/ $(BIN) fs.img
