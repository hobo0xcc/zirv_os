const csr = @import("csr.zig");
const uart = @import("uart.zig");

comptime {
    asm (
        \\ .globl kernelvec
        \\ .align 4
        \\ kernelvec:
        \\   call traphandler
        \\   sret
    );
}

extern fn kernelvec() void;

pub export fn traphandler() void {
    var scause = csr.readScause();
    try uart.out.print("Trap occured: {}\n", .{scause});
    var return_pc = csr.readSepc() + 4;
    csr.writeSepc(return_pc);
}

pub fn initTrap() void {
    csr.writeStvec(@ptrToInt(kernelvec));
}