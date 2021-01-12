const uart = @import("uart.zig");
const memalloc = @import("memalloc.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn round(val: usize, mul: usize) usize {
    if (val % mul == 0) {
        return val;
    }
    return val + mul - val % mul;
}

pub fn getStrFromPtr(ptr: [*]u8) ![]u8 {
    var idx: usize = 0;
    while (ptr[idx] != 0) : (idx += 1) {}
    return ptr[0..idx];
}

pub fn getMutStr(a: *Allocator, const_str: []const u8) ![]u8 {
    var arr = try a.alloc(u8, const_str.len);
    for (const_str) |ch, i| {
        arr[i] = ch;
    }
    return arr;
}

pub fn strcmp(a: []u8, b: []u8) bool {
    if (a.len != b.len) return false;
    if (a.ptr == b.ptr) return true;
    for (a) |ch, i| {
        if (ch != b[i]) return false;
    }
    return true;
}

pub fn memstrcmp(a: [*]u8, b: []const u8) bool {
    for (b) |item, index| {
        if (a[index] != item) return false;
    }
    return true;
}

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

pub fn memcpy(arr: [*]u8, src: [*]u8, size: usize) void {
    var i: usize = 0;
    while (i < size) : (i += 1) {
        arr[i] = src[i];
    }
}
