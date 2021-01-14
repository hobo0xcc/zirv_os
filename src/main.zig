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
const virtio = @import("virtio.zig");
const fs = @import("fs.zig");
const util = @import("util.zig");
const syscall = @import("syscall.zig");
const loader = @import("loader.zig");
const KernelError = kerror.KernelError;
const PriorityQueue = std.PriorityQueue(usize);
const Allocator = std.mem.Allocator;
const Exact = Allocator.Exact;
const KernelEnv = sysinit.KernelEnv;
const SpinLock = @import("spinlock.zig").SpinLock;

export var stack0 = [_]u8{0} ** 0x8000;
var lock = SpinLock.init();

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
    var str = "Hello, world!\n";
    asm volatile (
        \\ mv a2, %[str]
        \\ mv a3, %[size]
        \\ li a0, 1
        \\ li a1, 0
        :
        : [str] "r" (str),
          [size] "r" (str.len)
    );
    asm volatile ("ecall");
    try uart.out.print("こんにちは世界!\n", .{});
    var pid_ptr = try memalloc.a.create(proc.Pid);
    asm volatile (
        \\ mv a1, %[pid_addr]
        \\ li a0, 4
        \\ ecall
        :
        : [pid_addr] "r" (pid_ptr)
    );
    asm volatile (
        \\ mv a1, %[pid]
        \\ li a0, 8
        \\ ecall
        :
        : [pid] "r" (pid_ptr.*)
    );
    // _ = try proc.suspendProc(proc.getPid());
    while (true) {}
}

pub fn errorOccur() !void {
    return KernelError.SYSERR;
}

pub fn main() !noreturn {
    try uart.out.print("a0: {x}\n", .{asm volatile ("mv %[ret], a0"
        : [ret] "=r" (-> u64)
    )});
    var ka = memalloc.KernelAllocator.init(riscv.HEAP_SIZE);
    var page_a = &ka.allocator;
    var arena_a = std.heap.ArenaAllocator.init(page_a);
    var a = &arena_a.allocator;
    var env = try sysinit.init(a);
    memalloc.a = env.a;
    try fs.listAllFiles(env.a, 1);
    try proc.exec(a, try util.getMutStr(a, "shell"));
    while (true) {}
}
