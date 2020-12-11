target remote | qemu-system-riscv64 -machine virt -bios none -kernel zirv.elf -m 128M -smp 1  -drive file=fs.img,if=none,id=foo,format=raw -global virtio-mmio.force-legacy=false -device virtio-blk-device,drive=foo,bus=virtio-mmio-bus.0 -gdb stdio -S
file zirv.elf
