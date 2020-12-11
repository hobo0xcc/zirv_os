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
const KernelError = kerror.KernelError;
const virtio = @import("virtio.zig");
const PriorityQueue = std.PriorityQueue(usize);
const Allocator = std.mem.Allocator;
const Exact = Allocator.Exact;
const KernelEnv = sysinit.KernelEnv;

export var stack0 = [_]u8{0} ** 0x4000;

fn compare(a: usize, b: usize) bool {
    return a > b;
}

pub fn goodbye() !void {
    try proc.sleepProc(100);
    try uart.out.print("Goodbye, world!\n", .{});
    try uart.out.print("さよなら世界!\n", .{});
    _ = try proc.suspendProc(proc.getPid());
    while (true) {}
}

pub fn hello() !void {
    try proc.sleepProc(10);
    try uart.out.print("Hello, world!\n", .{});
    try uart.out.print("こんにちは世界!\n", .{});
    _ = try proc.suspendProc(proc.getPid());
    while (true) {}
}

pub fn errorOccur() !void {
    return KernelError.SYSERR;
}

pub fn main() !noreturn {
    try uart.out.print("a0: {x}\n", .{asm volatile ("mv %[ret], a0"
        : [ret] "=r" (-> u64)
    )});
    var kallocator = memalloc.KernelAllocator.init(riscv.HEAP_SIZE);
    var a = &kallocator.allocator;
    memalloc.a = a;
    var env = try sysinit.init(a);
    var blk = try a.alloc(u8, 512);
    try virtio.read(1, @ptrCast([*]u8, &blk[0]), 512, 0);
    var cnt: usize = 0;
    for (blk) |byte| {
        cnt += 1;
        try uart.out.print("{x:0>2} ", .{byte});
        if (cnt % 16 == 0) {
            try uart.out.print("\n", .{});
        }
    }
    var pid1 = try proc.makeDefaultProc(a, @ptrToInt(hello), "hello");
    var pid2 = try proc.makeDefaultProc(a, @ptrToInt(goodbye), "goodbye");
    _ = try proc.resumeProc(pid1);
    _ = try proc.resumeProc(pid2);
    while (true) {}
}
