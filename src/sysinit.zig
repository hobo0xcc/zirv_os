const std = @import("std");
const proc = @import("proc.zig");
const trap = @import("trap.zig");
const uart = @import("uart.zig");
const vm = @import("vm.zig");
const memalloc = @import("memalloc.zig");
const riscv = @import("riscv.zig");
const timer = @import("timer.zig");
const csr = @import("csr.zig");
const plic = @import("plic.zig");
const virtio = @import("virtio.zig");
const Allocator = std.mem.Allocator;

pub const KernelEnv = struct {
    root_table: *vm.Table,
    allocator: *Allocator,
    out: *const uart.uart_writer,
};

pub fn init(allocator: *Allocator) !KernelEnv {
    uart.UART.init();
    var out = &uart.out;
    trap.init();
    var root_table = try vm.init(allocator);
    try proc.init(allocator);
    try timer.init();
    plic.init();
    try virtio.init(allocator);
    return KernelEnv{
        .root_table = root_table,
        .allocator = allocator,
        .out = out,
    };
}
