const uart = @import("uart.zig");

// arrの値を1-byteごとにvalにする
pub fn memset(arr: []u8, val: u8) void {
    for (arr) |*item| {
        item.* = val;
    }
}

pub fn memcpyConst(arr: [*]u8, src: []const u8, size: usize) void {
    var i: usize = 0;
    while (i < size) : (i += 1) {
        arr[i] = src[i];
    }
}

pub fn memcpy(arr: [*]u8, src: []u8, size: usize) void {
    var i: usize = 0;
    while (i < size) : (i += 1) {
        arr[i] = src[i];
    }
}