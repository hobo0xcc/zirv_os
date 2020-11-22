const uart = @import("uart.zig");

pub fn panic(comptime fmt: []const u8, args: anytype) noreturn {
    try uart.out.print("Panic occured: ", .{});
    try uart.out.print(fmt, args);

    while (true) {}
}