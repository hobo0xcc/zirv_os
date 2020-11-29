const proc = @import("proc.zig");
const memlayout = @import("memlayout.zig");

pub const INTERVAL: usize = 1000000;

pub fn init() !void {
    var mtimecmp = @intToPtr(*u64, memlayout.CLINT_BASE + memlayout.CLINT_MTIMECMP);
    mtimecmp.* = INTERVAL;
}
