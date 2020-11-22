const std = @import("std");
const heap = std.heap;
const Allocator = std.mem.Allocator;
const mem = std.mem;
const riscv = @import("riscv.zig");
const uart = @import("uart.zig");

const MemBlk = packed struct {
    next: ?*MemBlk,
    len: usize,
};

var memblk_root = MemBlk{ .next = null, .len = riscv.HEAP_SIZE };

pub fn getEndOfKernel() usize {
    return asm volatile ("la %[ret], _end"
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

    memory: [*]u8,

    pub fn free(self: KernelAllocator, buf: []u8) void {
        var cur_blk = @ptrCast(*MemBlk, @ptrCast([*]u8, &buf[0]) - @sizeOf(MemBlk));
        if (memblk_root.next) |blk| {
            cur_blk.next = blk;
            memblk_root.next = cur_blk;
            memblk_root.len += cur_blk.len;
        } else {
            memblk_root.next = cur_blk;
            memblk_root.len += cur_blk.len;
        }
    }

    pub fn init(size: usize) KernelAllocator {
        const writer = uart.UART.get_writer();
        const eok = getEndOfKernel();
        var kallocator = KernelAllocator{ .memory = @intToPtr([*]u8, eok) };

        var root = &memblk_root;
        var first_blk = @ptrCast(*MemBlk, kallocator.memory);
        first_blk.len = root.len - @sizeOf(MemBlk);
        first_blk.next = null;
        root.next = first_blk;

        // Initialize memory by adding blocks to free
        // var offset: usize = 0;
        // var prev = &memblk_root;
        // const end_addr = eok + size;
        // while (eok + offset + riscv.PAGE_SIZE < end_addr) {
        //     var blk: *MemBlk = @ptrCast(*MemBlk, @ptrCast(*u8, kallocator.memory + offset));

        //     prev.next = blk;
        //     blk.len = riscv.PAGE_SIZE;
        //     blk.next = null;
        //     prev = blk;

        //     offset += riscv.PAGE_SIZE;
        // }

        return kallocator;
    }

    pub fn alloc(allocator: *Allocator, n: usize, ptr_align: u29, len_align: u29, ret_addr: usize) Allocator.Error![]u8 {
        const self = @fieldParentPtr(KernelAllocator, "allocator", allocator);
        const writer = uart.UART.get_writer();
        if (n == 0) {
            return Allocator.Error.OutOfMemory;
        }
        if (ptr_align == 0) {
            return Allocator.Error.OutOfMemory;
        }
        var size = n;
        if (len_align != 0) {
            size = mem.alignAllocLen(riscv.PAGE_SIZE, size, len_align);
        }

        var nbytes = round(size + @sizeOf(MemBlk), @sizeOf(MemBlk));
        var prev = &memblk_root;
        var curr = memblk_root.next;
        scan: while (curr) |blk| : ({prev = blk; curr = blk.next;}) {
            if (blk.len == nbytes) {
                const addr = @ptrToInt(@ptrCast([*]u8, blk) + @sizeOf(MemBlk));
                const adjusted_addr = mem.alignForward(addr, ptr_align);
                if (adjusted_addr != addr) {
                    continue :scan;
                } // Already aligned.

                prev.next = blk.next;
                memblk_root.len -= nbytes;

                return @intToPtr([*]u8, @ptrToInt(blk) + @sizeOf(MemBlk))[0..n];
            } else if (blk.len > nbytes) {
                var addr = @ptrToInt(@ptrCast([*]u8, blk) + @sizeOf(MemBlk));
                var adjusted_addr = mem.alignForward(addr, ptr_align);
                if (adjusted_addr + nbytes >= @ptrToInt(blk) + blk.len) {
                    continue :scan;
                } else {
                    var new_addr = adjusted_addr - @sizeOf(MemBlk);
                    var end_of_blk = @ptrToInt(blk) + @sizeOf(MemBlk); 
                    if (new_addr < end_of_blk) {
                        while (new_addr < end_of_blk) {
                            adjusted_addr = mem.alignForward(adjusted_addr + 1, ptr_align);
                            new_addr = adjusted_addr - @sizeOf(MemBlk);
                            if (new_addr >= @ptrToInt(blk) + blk.len) {
                                continue :scan;
                            }
                        }
                    }

                    var new_blk = @intToPtr(*MemBlk, new_addr);
                    new_blk.len = nbytes;
                    var leftover_addr = new_addr + nbytes;
                    var leftover = @intToPtr(*MemBlk, leftover_addr);
                    leftover.len = (@ptrToInt(blk) + blk.len) - (new_addr + nbytes);
                    blk.len = blk.len - new_blk.len - leftover.len;

                    leftover.next = blk.next;
                    blk.next = leftover;
                    prev.next = blk;

                    memblk_root.len -= new_blk.len;
                    return @intToPtr([*]u8, @ptrToInt(new_blk) + @sizeOf(MemBlk))[0..n];
                }
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
