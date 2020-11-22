const uart = @import("uart.zig");

pub fn memset(arr: []u8, val: u8) void {
    for (arr) |*item| {
        item.* = val;
    }
}