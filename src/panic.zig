const uart = @import("uart.zig");
const start = @import("start.zig");

// パニックを起こす
pub fn panic(comptime fmt: []const u8, args: anytype) noreturn {
    try uart.out.print("Panic occured: ", .{});
    try uart.out.print(fmt, args);

    while (true) {}
}

pub export fn errorOccurred() noreturn {
    var error_idx: usize = 0; // start.stack_trace.index - 1;
    var cause = start.stack_trace.instruction_addresses[error_idx];
    panic("Error occurred: {x}\n", .{cause});
}
