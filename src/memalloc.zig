const std = @import("std");
const heap = std.heap;
const Allocator = std.mem.Allocator;
const riscv = @import("riscv.zig");
const uart = @import("uart.zig");

const MemBlk = packed struct {
    next: ?*MemBlk,
    len: usize,
};

var memblk_root = MemBlk{ .next = null, .len = riscv.MEM_SIZE };

pub fn getEndOfKernel() usize {
    return asm volatile ("la %[ret], end"
        : [ret] "=r" (-> usize)
    );
}

pub fn round(val: usize, mul: usize) usize {
    if (val % mul == 0) {
        return val;
    }
    return val + mul - val % mul;
}

pub const KernelAllocator = struct {
    allocator: Allocator = Allocator{
        .allocFn = alloc,
        .resizeFn = resize,
    },

    mem: [*]u8,

    pub fn free(self: KernelAllocator, buf: []u8) void {
        var cur_blk = @ptrCast(*MemBlk, @ptrCast([*]u8, &buf[0]) - @sizeOf(MemBlk));
        if (memblk_root.next) |blk| {
            cur_blk.next = blk;
            memblk_root.next = cur_blk;
        } else {
            memblk_root.next = cur_blk;
        }
    }

    pub fn init(size: usize) KernelAllocator {
        const writer = uart.UART.get_writer();
        const eok = getEndOfKernel();
        var kallocator = KernelAllocator{ .mem = @intToPtr([*]u8, eok) };

        // Initialize memory by adding page to free
        var offset: usize = 0;
        var prev = &memblk_root;
        const end_addr = eok + size;
        while (eok + offset + riscv.PAGE_SIZE < end_addr) {
            var blk: *MemBlk = @ptrCast(*MemBlk, @ptrCast(*u8, kallocator.mem + offset));

            prev.next = blk;
            blk.len = riscv.PAGE_SIZE;
            blk.next = null;
            prev = blk;

            offset += riscv.PAGE_SIZE;
        }

        return kallocator;
    }

    pub fn alloc(allocator: *Allocator, n: usize, ptr_align: u29, len_align: u29, ret_addr: usize) Allocator.Error![]u8 {
        const self = @fieldParentPtr(KernelAllocator, "allocator", allocator);
        const writer = uart.UART.get_writer();
        if (n == 0) {
            return Allocator.Error.OutOfMemory;
        }

        var nbytes = round(n + @sizeOf(MemBlk), @sizeOf(MemBlk));
        var prev = &memblk_root;
        var curr = memblk_root.next;
        while (curr) |blk| {
            if (blk.len == nbytes) {
                prev.next = blk.next;
                memblk_root.len -= nbytes;
                return (@ptrCast([*]u8, blk) + @sizeOf(MemBlk))[0..n];
            } else if (blk.len > nbytes) {
                var leftover = @ptrCast(*MemBlk, @ptrCast([*]u8, blk) + nbytes);
                prev.next = leftover;
                leftover.next = blk.next;
                leftover.len = blk.len - nbytes;
                memblk_root.len -= nbytes;
                return (@ptrCast([*]u8, blk) + @sizeOf(MemBlk))[0..n];
            } else {
                prev = blk;
                curr = blk.next;
            }
        }

        return Allocator.Error.OutOfMemory;
    }

    pub fn resize(allocator: *Allocator, buf: []u8, buf_align: u29, new_len: usize, len_align: u29, ret_addr: usize) Allocator.Error!usize {
        const self = @fieldParentPtr(KernelAllocator, "allocator", allocator);
        if (new_len > buf.len) {
            return Allocator.Error.OutOfMemory;
        }
        if (new_len == 0) {
            self.free(buf);
        }
        return new_len;
    }
};
