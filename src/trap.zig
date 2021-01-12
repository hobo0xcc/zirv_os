const csr = @import("csr.zig");
const uart = @import("uart.zig");
const memlayout = @import("memlayout.zig");
const timer = @import("timer.zig");
const proc = @import("proc.zig");
const plic = @import("plic.zig");
const virtio = @import("virtio.zig");
const panic = @import("panic.zig").panic;
const syscall = @import("syscall.zig");
const util = @import("util.zig");
const vm = @import("vm.zig");
const riscv = @import("riscv.zig");
const trampoline = @import("trampoline.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;

export var saved_sp: u64 = 0;
pub export var trap_stack = [_]u8{0} ** 0x1000;

comptime {
    asm (
        \\ .globl timervec
        \\ .align 4
        \\ timervec:
        \\     csrrw a0, mscratch, a0
        \\     sd a1, 0(a0)
        \\     sd a2, 8(a0)
        \\     sd a3, 16(a0)
        \\     ld a1, 24(a0)
        \\     ld a2, 32(a0)
        \\     ld a3, 0(a1)
        \\     add a3, a3, a2
        \\     sd a3, 0(a1)
        \\     li a1, 2
        \\     csrw sip, a1
        \\     ld a3, 16(a0)
        \\     ld a2, 8(a0)
        \\     ld a1, 0(a0)
        \\     csrrw a0, mscratch, a0
        \\     mret
        \\
        \\ .globl kernelvec
        \\ .align 4
        \\ kernelvec:
        \\     addi sp, sp, -256
        \\     sd ra, 0(sp)
        \\     sd sp, 8(sp)
        \\     sd gp, 16(sp)
        \\     sd tp, 24(sp)
        \\     sd t0, 32(sp)
        \\     sd t1, 40(sp)
        \\     sd t2, 48(sp)
        \\     sd s0, 56(sp)
        \\     sd s1, 64(sp)
        \\     sd a0, 72(sp)
        \\     sd a1, 80(sp)
        \\     sd a2, 88(sp)
        \\     sd a3, 96(sp)
        \\     sd a4, 104(sp)
        \\     sd a5, 112(sp)
        \\     sd a6, 120(sp)
        \\     sd a7, 128(sp)
        \\     sd s2, 136(sp)
        \\     sd s3, 144(sp)
        \\     sd s4, 152(sp)
        \\     sd s5, 160(sp)
        \\     sd s6, 168(sp)
        \\     sd s7, 176(sp)
        \\     sd s8, 184(sp)
        \\     sd s9, 192(sp)
        \\     sd s10, 200(sp)
        \\     sd s11, 208(sp)
        \\     sd t3, 216(sp)
        \\     sd t4, 224(sp)
        \\     sd t5, 232(sp)
        \\     sd t6, 240(sp)
        \\     la t6, saved_sp
        \\     sd sp, 0(t6)
        \\     call traphandler
        \\     ld ra, 0(sp)
        \\     ld sp, 8(sp)
        \\     ld gp, 16(sp)
        \\     ld t0, 32(sp)
        \\     ld t1, 40(sp)
        \\     ld t2, 48(sp)
        \\     ld s0, 56(sp)
        \\     ld s1, 64(sp)
        \\     ld a0, 72(sp)
        \\     ld a1, 80(sp)
        \\     ld a2, 88(sp)
        \\     ld a3, 96(sp)
        \\     ld a4, 104(sp)
        \\     ld a5, 112(sp)
        \\     ld a6, 120(sp)
        \\     ld a7, 128(sp)
        \\     ld s2, 136(sp)
        \\     ld s3, 144(sp)
        \\     ld s4, 152(sp)
        \\     ld s5, 160(sp)
        \\     ld s6, 168(sp)
        \\     ld s7, 176(sp)
        \\     ld s8, 184(sp)
        \\     ld s9, 192(sp)
        \\     ld s10, 200(sp)
        \\     ld s11, 208(sp)
        \\     ld t3, 216(sp)
        \\     ld t4, 224(sp)
        \\     ld t5, 232(sp)
        \\     ld t6, 240(sp)
        \\     addi sp, sp, 256
        \\     sret
    );
}

pub const SSI: u64 = 0x1;
pub const SEI: u64 = 0x9;

pub extern fn kernelvec() void;
pub extern fn timervec() void;

pub const SavedRegs = packed struct {
    ra: u64,
    sp: u64,
    gp: u64,
    tp: u64,
    t0: u64,
    t1: u64,
    t2: u64,
    s0: u64,
    s1: u64,
    a0: u64,
    a1: u64,
    a2: u64,
    a3: u64,
    a4: u64,
    a5: u64,
    a6: u64,
    a7: u64,
    s2: u64,
    s3: u64,
    s4: u64,
    s5: u64,
    s6: u64,
    s7: u64,
    s8: u64,
    s9: u64,
    s10: u64,
    s11: u64,
    t3: u64,
    t4: u64,
    t5: u64,
    t6: u64,
};

pub export fn timertrap() void {
    var mcause = csr.readMcause();
    // try uart.out.print("Timer Trap occured: mepc: {x}\n", .{csr.readMepc()});
    var mtimecmp = @intToPtr(*u64, memlayout.CLINT_BASE + memlayout.CLINT_MTIMECMP);
    mtimecmp.* += timer.INTERVAL;
    csr.writeSip(csr.readSip() | csr.SIP_SSIP);
}

pub fn isInterrupt(cause: u64) bool {
    return (cause & (0b1 << 63)) != 0;
}

pub fn interrupt(scause: u64) void {
    var sip_cause = @as(u64, 0b1) << @intCast(u6, scause & ~(@as(u64, 0b1 << 63)));
    csr.writeSip(csr.readSip() & ~sip_cause);
    // Supervisor Software Interrupt
    if ((scause & 0xff) == SSI) {
        if (proc.sleapq.first) |node| {
            node.data.delay -= 1;
            if (node.data.delay == 0) {
                proc.wakeupProc() catch {};
            }
            proc.resched() catch |err| {
                panic("timer interrupt failed\n", .{});
            };
        }
    } else if ((scause & 0xff) == SEI) {
        const irq = plic.claim();
        if (irq >= plic.VIRTIO_FIRST_IRQ and irq <= plic.VIRTIO_END_IRQ) {
            virtio.interrupt(irq) catch {};
        } else if (irq == plic.UART_IRQ) {
            uart.UART.interrupt() catch {};
            // try uart.out.print("uart\n", .{});
        }

        if (irq != 0) {
            plic.complete(irq);
        }
    } else {
        panic("unknown interrupt cause: {x}\n", .{scause});
    }
}

pub fn getSysCallNumber() u64 {
    var p = proc.getCurrProc();
    return p.trapframe.a0;
}

pub fn getSysCallArgs() syscall.SysCallArgs {
    var p = proc.getCurrProc();
    return syscall.SysCallArgs{
        .a1 = p.trapframe.a1,
        .a2 = p.trapframe.a2,
        .a3 = p.trapframe.a3,
        .a4 = p.trapframe.a4,
        .a5 = p.trapframe.a5,
        .a6 = p.trapframe.a6,
        .a7 = p.trapframe.a7,
    };
}

pub export fn traphandler() void {
    // var mask = disable();
    // defer restore(mask);
    if ((csr.readSstatus() & csr.SSTATUS_SPP) == 0) {
        panic("not from supervisor mode: sstatus: {b}\n", .{csr.readSstatus()});
    }
    var saved_regs = @ptrCast(*SavedRegs, @intToPtr(*u8, saved_sp));
    var scause = csr.readScause();
    // try uart.out.print("Trap from s-mode: {x}, sepc: {x}\n", .{ scause, csr.readSepc() });
    var return_pc = csr.readSepc();
    if ((scause & (0b1 << 63)) == 0) {
        return_pc += 4;
    }

    if (isInterrupt(scause)) {
        interrupt(scause);
    } else {
        if (scause == 0x9) {
            panic("syscall must be caused in user-mode\n", .{});
        } else {
            if (scause == 0xc) {
                try uart.out.print("Instruction Page Fault: addr: {x}, virtToPhys: {x}\n", .{ csr.readStval(), vm.virtToPhys(syscall.env.root_table, csr.readStval()) });
                var entry = vm.virtAddrGetEntry(syscall.env.root_table, csr.readStval());
                try uart.out.print("entry: {b}\n", .{entry.?.get_entry()});
                try uart.out.print("satp: {x}\n", .{csr.readSatp()});
                try uart.out.print("root_table: {x}\n", .{@ptrToInt(syscall.env.root_table)});
                try uart.out.print("sstatus: {b}\n", .{csr.readSstatus()});
            }
            panic("Exception occured: cause: {x}, stval: {x}, sepc: {x}\n", .{ scause, csr.readStval(), csr.readSepc() });
        }
    }

    csr.writeSstatus(csr.readSstatus() | csr.SSTATUS_SPP);
    csr.writeSepc(return_pc);
}

pub export fn usertrapret() void {
    // try uart.out.print("usertrapret: {}\n", .{proc.getPid()});
    const p: *proc.Process = &proc.proctab[proc.getPid()];
    intrOff();
    csr.writeStvec(riscv.TRAMPOLINE + (@ptrToInt(trampoline.uservec) - @ptrToInt(trampoline._trampoline)));
    p.trapframe.kernel_satp = csr.readSatp();
    // p.trapframe.kernel_sp = asm volatile ("mv %[ret], sp"
    //     : [ret] "=r" (-> u64)
    // );
    p.trapframe.kernel_trap = @ptrToInt(usertrap);
    p.trapframe.kernel_hartid = asm volatile ("mv %[ret], tp"
        : [ret] "=r" (-> u64)
    );

    var sstatus = csr.readSstatus();
    sstatus &= ~(csr.SSTATUS_SPP);
    sstatus |= csr.SSTATUS_SPIE;
    csr.writeSstatus(sstatus);
    csr.writeSepc(p.trapframe.epc);
    const satp = vm.makeSatp(p.page_table);
    // try uart.out.print("usertrapret: sepc: {x}\n", .{p.trapframe.epc});
    // in process's page table
    const userret_addr = riscv.TRAMPOLINE + (@ptrToInt(trampoline.userret) - @ptrToInt(trampoline._trampoline));
    const userret_func = @intToPtr(fn (u64, u64) void, userret_addr);
    userret_func(riscv.TRAPFRAME, satp);
}

pub export fn usertrap() void {
    if ((csr.readSstatus() & csr.SSTATUS_SPP) != 0) {
        panic("not from user mode\n", .{});
    }
    csr.writeStvec(@ptrToInt(kernelvec));
    var p = proc.getCurrProc();
    p.trapframe.epc = csr.readSepc();
    const scause = csr.readScause();
    if ((scause & (0b1 << 63)) == 0) {
        p.trapframe.epc += 4;
    }
    if (scause == 0x8) {
        const syscall_args = getSysCallArgs();
        const syscall_num = getSysCallNumber();
        syscall.env.execSysCall(syscall_num, &syscall_args);
    } else if (isInterrupt(scause)) {
        interrupt(scause);
    } else {
        panic("exception occurred\n", .{});
    }
    usertrapret();
}

pub fn userinit(a: *Allocator, root_table: *vm.Table) !void {
    try vm.map(a, root_table, riscv.TRAMPOLINE, @ptrToInt(trampoline._trampoline), vm.PTE_R | vm.PTE_X, 0);
}

pub fn init() void {
    csr.writeStvec(@ptrToInt(kernelvec));
}

pub fn ienable() u64 {
    var prev = csr.readSstatus();
    csr.writeSstatus(prev | csr.SSTATUS_SIE);
    var mask = prev & csr.SSTATUS_SIE;
    return mask;
}

pub fn disable() u64 {
    var prev = csr.readSstatus();
    csr.writeSstatus(prev & ~csr.SSTATUS_SIE);
    var mask = prev & csr.SSTATUS_SIE;
    return mask;
}

pub fn restore(mask: u64) void {
    csr.writeSstatus((csr.readSstatus() & ~mask) | mask);
}

pub fn intrOn() void {
    csr.writeSstatus(csr.readSstatus() | csr.SSTATUS_SIE);
}

pub fn intrOff() void {
    csr.writeSstatus(csr.readSstatus() & ~csr.SSTATUS_SIE);
}
