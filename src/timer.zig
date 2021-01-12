const proc = @import("proc.zig");
const memlayout = @import("memlayout.zig");
const csr = @import("csr.zig");
const trap = @import("trap.zig");

pub const INTERVAL: usize = 1000000;

pub export var timer_scratch = [_]u64{0} ** 5;

pub fn init() !void {
    var mtimecmp = @intToPtr(*u64, memlayout.CLINT_BASE + memlayout.CLINT_MTIMECMP);
    mtimecmp.* = INTERVAL;
    var scratch = @ptrCast([*]u64, &timer_scratch[0]);
    scratch[3] = memlayout.CLINT_BASE + memlayout.CLINT_MTIMECMP;
    scratch[4] = INTERVAL;
    asm volatile ("csrw mscratch, %[val]"
        :
        : [val] "r" (scratch)
    );
    csr.writeMtvec(@ptrToInt(trap.timervec));
}
