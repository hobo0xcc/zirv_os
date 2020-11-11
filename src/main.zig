const uart = @import("uart.zig");

export const stack0 = [_]u8{0} ** 0x1000;

pub export fn main() usize {
    uart.init();
    uart.println("Hello");
    while (true) {}
}
