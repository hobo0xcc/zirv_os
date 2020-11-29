const std = @import("std");
const memalloc = @import("memalloc.zig");
const uart = @import("uart.zig");
const riscv = @import("riscv.zig");
const csr = @import("csr.zig");
const trap = @import("trap.zig");
const vm = @import("vm.zig");
const sysinit = @import("sysinit.zig");
const spinlock = @import("spinlock.zig");
const proc = @import("proc.zig");
const kerror = @import("kerror.zig");
const PriorityQueue = std.PriorityQueue(usize);
const Allocator = std.mem.Allocator;
const Exact = Allocator.Exact;
const KernelEnv = sysinit.KernelEnv;

export var stack0 = [_]u8{0} ** 0x4000;

fn compare(a: usize, b: usize) bool {
    return a > b;
}

pub fn goodbye() !void {
    try uart.out.print("Goodbye, world!\n", .{});
    try uart.out.print("さよなら世界!\n", .{});
    _ = try proc.suspendProc(proc.getPid());
    // while (true) {}
}

pub fn hello() !void {
    try uart.out.print("Hello, world!\n", .{});
    try uart.out.print("こんにちは世界!\n", .{});
    _ = try proc.suspendProc(proc.getPid());
    // while (true) {}
}

pub fn main() !void {
    var kallocator = memalloc.KernelAllocator.init(riscv.HEAP_SIZE);
    var a = &kallocator.allocator;
    var env = try sysinit.init(a);
    var pid1 = try proc.makeDefaultProc(a, @ptrToInt(hello), "hello");
    var pid2 = try proc.makeDefaultProc(a, @ptrToInt(goodbye), "goodbye");
    _ = try proc.resumeProc(pid1);
    _ = try proc.resumeProc(pid2);
    // var name = try proc.procName(a, "hello");
    // var pid = try proc.createProc(a, @ptrToInt(hello), 0x1000, 10, name, 0);
    // _ = try proc.resumeProc(pid);
    try uart.out.print("returned!\n", .{});
    while (true) {}
}
