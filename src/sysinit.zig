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
const syscall = @import("syscall.zig");
const util = @import("util.zig");
const Allocator = std.mem.Allocator;

pub const KernelEnv = struct {
    root_table: *vm.Table,
    a: *Allocator,
    out: *const uart.uart_writer,
    in: *const uart.uart_reader,
};

pub fn init(a: *Allocator) !KernelEnv {
    uart.UART.init();
    var out = &uart.out;
    var in = &uart.in;
    trap.init();
    var root_table = try vm.init(a);
    try trap.userinit(a, root_table);
    try proc.init(a, root_table);
    plic.init();
    try virtio.init(a);
    syscall.env = try a.create(syscall.SysCall);
    syscall.env.* = syscall.SysCall.init(root_table, a);
    return KernelEnv{
        .root_table = root_table,
        .a = a,
        .out = out,
        .in = in,
    };
}
