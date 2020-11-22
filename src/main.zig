const std = @import("std");
const memalloc = @import("memalloc.zig");
const uart = @import("uart.zig");
const riscv = @import("riscv.zig");
const csr = @import("csr.zig");
const trap = @import("trap.zig");
const vm = @import("vm.zig");
const Allocator = std.mem.Allocator;
const Exact = Allocator.Exact;

export var stack0 = [_]u8{0} ** 0x1000;

pub fn main() !void {
    uart.UART.init();
    const writer = uart.UART.get_writer();
    try uart.out.print("\nzirv kernel is booting...\n\n", .{});
    try uart.out.print("Init: Allocator\n", .{});
    var allocator = &memalloc.KernelAllocator.init(riscv.HEAP_SIZE).allocator;
    try uart.out.print("Init: Trap\n", .{});
    trap.initTrap();
    try uart.out.print("Init: VM\n", .{});
    try vm.initVM(allocator);
    try uart.out.print("Hello!\n", .{});
    while (true) {}
}
