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

app/hello: app/syscall.S app/hello.c
	riscv64-unknown-elf-gcc  -nostdlib -T app/app.ld -o app/hello $^

fs.img: app/hello
	tar -cvf fs.img app/hello

clean:
	$(RM) src/*.o zig-cache/ $(BIN) fs.img app/hello
