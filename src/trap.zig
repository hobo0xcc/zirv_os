const csr = @import("csr.zig");
const uart = @import("uart.zig");
const memlayout = @import("memlayout.zig");
const timer = @import("timer.zig");
const proc = @import("proc.zig");

comptime {
    asm (
        \\ .globl timervec
        \\ .align 4
        \\ timervec:
        \\ addi sp, sp, -256
        \\ sd ra, 0(sp)
        \\ sd sp, 8(sp)
        \\ sd gp, 16(sp)
        \\ sd tp, 24(sp)
        \\ sd t0, 32(sp)
        \\ sd t1, 40(sp)
        \\ sd t2, 48(sp)
        \\ sd s0, 56(sp)
        \\ sd s1, 64(sp)
        \\ sd a0, 72(sp)
        \\ sd a1, 80(sp)
        \\ sd a2, 88(sp)
        \\ sd a3, 96(sp)
        \\ sd a4, 104(sp)
        \\ sd a5, 112(sp)
        \\ sd a6, 120(sp)
        \\ sd a7, 128(sp)
        \\ sd s2, 136(sp)
        \\ sd s3, 144(sp)
        \\ sd s4, 152(sp)
        \\ sd s5, 160(sp)
        \\ sd s6, 168(sp)
        \\ sd s7, 176(sp)
        \\ sd s8, 184(sp)
        \\ sd s9, 192(sp)
        \\ sd s10, 200(sp)
        \\ sd s11, 208(sp)
        \\ sd t3, 216(sp)
        \\ sd t4, 224(sp)
        \\ sd t5, 232(sp)
        \\ sd t6, 240(sp)
        \\   call timertrap
        \\ ld ra, 0(sp)
        \\ ld sp, 8(sp)
        \\ ld gp, 16(sp)
        \\ ld t0, 32(sp)
        \\ ld t1, 40(sp)
        \\ ld t2, 48(sp)
        \\ ld s0, 56(sp)
        \\ ld s1, 64(sp)
        \\ ld a0, 72(sp)
        \\ ld a1, 80(sp)
        \\ ld a2, 88(sp)
        \\ ld a3, 96(sp)
        \\ ld a4, 104(sp)
        \\ ld a5, 112(sp)
        \\ ld a6, 120(sp)
        \\ ld a7, 128(sp)
        \\ ld s2, 136(sp)
        \\ ld s3, 144(sp)
        \\ ld s4, 152(sp)
        \\ ld s5, 160(sp)
        \\ ld s6, 168(sp)
        \\ ld s7, 176(sp)
        \\ ld s8, 184(sp)
        \\ ld s9, 192(sp)
        \\ ld s10, 200(sp)
        \\ ld s11, 208(sp)
        \\ ld t3, 216(sp)
        \\ ld t4, 224(sp)
        \\ ld t5, 232(sp)
        \\ ld t6, 240(sp)
        \\ addi sp, sp, 256
        \\   mret
        \\
        \\ .globl kernelvec
        \\ .align 4
        \\ kernelvec:
        \\ addi sp, sp, -256
        \\ sd ra, 0(sp)
        \\ sd sp, 8(sp)
        \\ sd gp, 16(sp)
        \\ sd tp, 24(sp)
        \\ sd t0, 32(sp)
        \\ sd t1, 40(sp)
        \\ sd t2, 48(sp)
        \\ sd s0, 56(sp)
        \\ sd s1, 64(sp)
        \\ sd a0, 72(sp)
        \\ sd a1, 80(sp)
        \\ sd a2, 88(sp)
        \\ sd a3, 96(sp)
        \\ sd a4, 104(sp)
        \\ sd a5, 112(sp)
        \\ sd a6, 120(sp)
        \\ sd a7, 128(sp)
        \\ sd s2, 136(sp)
        \\ sd s3, 144(sp)
        \\ sd s4, 152(sp)
        \\ sd s5, 160(sp)
        \\ sd s6, 168(sp)
        \\ sd s7, 176(sp)
        \\ sd s8, 184(sp)
        \\ sd s9, 192(sp)
        \\ sd s10, 200(sp)
        \\ sd s11, 208(sp)
        \\ sd t3, 216(sp)
        \\ sd t4, 224(sp)
        \\ sd t5, 232(sp)
        \\ sd t6, 240(sp)
        \\   call traphandler
        \\ ld ra, 0(sp)
        \\ ld sp, 8(sp)
        \\ ld gp, 16(sp)
        \\ ld t0, 32(sp)
        \\ ld t1, 40(sp)
        \\ ld t2, 48(sp)
        \\ ld s0, 56(sp)
        \\ ld s1, 64(sp)
        \\ ld a0, 72(sp)
        \\ ld a1, 80(sp)
        \\ ld a2, 88(sp)
        \\ ld a3, 96(sp)
        \\ ld a4, 104(sp)
        \\ ld a5, 112(sp)
        \\ ld a6, 120(sp)
        \\ ld a7, 128(sp)
        \\ ld s2, 136(sp)
        \\ ld s3, 144(sp)
        \\ ld s4, 152(sp)
        \\ ld s5, 160(sp)
        \\ ld s6, 168(sp)
        \\ ld s7, 176(sp)
        \\ ld s8, 184(sp)
        \\ ld s9, 192(sp)
        \\ ld s10, 200(sp)
        \\ ld s11, 208(sp)
        \\ ld t3, 216(sp)
        \\ ld t4, 224(sp)
        \\ ld t5, 232(sp)
        \\ ld t6, 240(sp)
        \\ addi sp, sp, 256
        \\   sret
    );
}

pub const SSI: u64 = 0x1;

pub extern fn kernelvec() void;
pub extern fn timervec() void;

pub export var timer_scratch = [_]u64{0} ** 5;

pub export fn timertrap() void {
    var mcause = csr.readMcause();
    // try uart.out.print("Timer Trap occured: mepc: {x}\n", .{csr.readMepc()});
    var mtimecmp = @intToPtr(*u64, memlayout.CLINT_BASE + memlayout.CLINT_MTIMECMP);
    mtimecmp.* += timer.INTERVAL;
    csr.writeSip(csr.readSip() | csr.SIP_SSIP);
}

pub fn is_interrupt(cause: u64) bool {
    return (cause & (0b1 << 63)) != 0;
}

pub export fn traphandler() void {
    var scause = csr.readScause();
    // try uart.out.print("Trap occured: {x}, sepc: {x}\n", .{ scause, csr.readSepc() });
    var sip_cause = @as(u64, 0b1) << @intCast(u6, scause & ~(@as(u64, 0b1 << 63)));
    csr.writeSip(csr.readSip() & ~sip_cause);
    var return_pc = csr.readSepc();
    if ((scause & (0b1 << 63)) == 0) {
        return_pc += 4;
    }

    if (is_interrupt(scause)) {
        // Supervisor Software Interrupt
        if ((scause & 0xffff) == SSI) {
            return_pc = @ptrToInt(proc.resched);
            if (proc.sleapq.first) |node| {
                node.data.delay -= 1;
                if (node.data.delay == 0) {
                    proc.wakeupProc() catch {};
                }
            }
        }
    }

    csr.writeSepc(return_pc);
}

pub fn init() void {
    csr.writeStvec(@ptrToInt(kernelvec));
}

pub fn disable() u64 {
    var prev = csr.readSstatus();
    csr.writeSstatus(prev & ~csr.SSTATUS_SIE);
    var mask = prev & csr.SSTATUS_SIE;
    return mask;
}

pub fn restore(mask: u64) void {
    csr.writeSstatus(csr.readSstatus() | mask);
}
