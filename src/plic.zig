const memlayout = @import("memlayout.zig");

pub const VIRTIO_FIRST_IRQ: usize = 1;
pub const VIRTIO_END_IRQ: usize = 8;
pub const UART_IRQ: usize = 10;

pub fn init() void {
    var uart_prio_ptr = @intToPtr(*u32, memlayout.PLIC_BASE + UART_IRQ * 4);
    uart_prio_ptr.* = 1;
    var virtio_prio_ptr = @intToPtr(*u32, memlayout.PLIC_BASE + VIRTIO_FIRST_IRQ * 4);
    virtio_prio_ptr.* = 1;
    var plic_senable = @intToPtr(*u32, memlayout.PLIC_BASE + memlayout.PLIC_SENABLE);
    plic_senable.* = (1 << UART_IRQ) | (1 << VIRTIO_FIRST_IRQ);
    var plic_sprio = @intToPtr(*u32, memlayout.PLIC_BASE + memlayout.PLIC_SPRIORITY);
    plic_sprio.* = 0;
}

pub fn claim() u32 {
    var sclaim_ptr = @intToPtr(*u32, memlayout.PLIC_BASE + memlayout.PLIC_SCLAIM);
    return sclaim_ptr.*;
}

pub fn complete(irq: u32) void {
    var sclaim_ptr = @intToPtr(*u32, memlayout.PLIC_BASE + memlayout.PLIC_SCLAIM);
    sclaim_ptr.* = irq;
}
