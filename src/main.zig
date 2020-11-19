const std = @import("std");
const memalloc = @import("memalloc.zig");
const uart = @import("uart.zig");
const riscv = @import("riscv.zig");
const trap = @import("trap.zig");

export const stack0 = [_]u8{0} ** 0x1000;

pub fn main() !void {
    uart.UART.init();
    const writer = uart.UART.get_writer();
    try uart.out.print("\nzirv kernel is booting...\n\n", .{});
    try uart.out.print("Init: Allocator\n", .{});
    var allocator = &memalloc.KernelAllocator.init(riscv.MEM_SIZE).allocator;
    try uart.out.print("Init: Trap\n", .{});
    trap.initTrap();
    asm volatile ("ecall");
    while (true) {}
}
