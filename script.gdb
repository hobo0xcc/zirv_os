target remote | qemu-system-riscv64 -machine virt -bios none -kernel zirv.elf -m 128M -smp 1 -gdb stdio -S
file zirv.elf
