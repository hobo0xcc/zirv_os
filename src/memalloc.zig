const std = @import("std");
const heap = std.heap;
pub const Allocator = std.mem.Allocator;
const mem = std.mem;
const riscv = @import("riscv.zig");
const uart = @import("uart.zig");
const trap = @import("trap.zig");
const util = @import("util.zig");
const vm = @import("vm.zig");
const panic = @import("panic.zig").panic;
const assert = std.debug.assert;

pub var a: *Allocator = undefined;

// メモリブロックのヘッダ
// nextは次のブロック
// lenはブロックのサイズ
const MemBlk = packed struct {
    len: usize,
    next: usize,
    is_free: bool,

    pub fn init() MemBlk {
        return MemBlk{
            .len = riscv.PAGE_SIZE,
            .next = 0,
            .is_free = true,
        };
    }
};

const SmallMemBlk = packed struct {
    len: usize,
    next: ?*SmallMemBlk,
};

// メモリブロック全体
var small_freelist = SmallMemBlk{ .len = 0, .next = null };
var mem_table = [_]MemBlk{MemBlk.init()} ** (riscv.HEAP_SIZE / 4096);
var page_maxlen = riscv.HEAP_SIZE / 4096;

// カーネルの最後のアドレスを返す
// このアドレスから先がHeap領域になる
pub fn getEndOfKernel() usize {
    return asm volatile ("la %[ret], _end"
        : [ret] "=r" (-> usize)
    );
}

// valをmulの倍数に切り上げ
pub fn round(val: usize, mul: usize) usize {
    if (val % mul == 0) {
        return val;
    }
    return val + mul - val % mul;
}

pub fn bitsCount(val: u29) u29 {
    var v = val;
    v = (v & 0x5555) + ((v & 0xAAAA) >> 1);
    v = (v & 0x3333) + ((v & 0xCCCC) >> 2);
    v = (v & 0x0F0F) + ((v & 0xF0F0) >> 4);
    v = (v & 0x00FF) + ((v & 0xFF00) >> 8);
    return v;
}

// メモリアロケータ
pub const KernelAllocator = struct {
    // zigのアロケータのテンプレート
    allocator: Allocator = Allocator{
        .allocFn = alloc,
        .resizeFn = resize,
    },

    // Heap領域のポインタ
    memory: [*]u8,
    eok: usize,

    // アロケータを初期化
    pub fn init(size: usize) KernelAllocator {
        const mask = trap.disable();
        const writer = uart.UART.get_writer();
        // カーネルの最後のアドレス
        const eok = mem.alignForward(getEndOfKernel(), riscv.PAGE_SIZE);
        // eokをポインタに変換
        var kallocator = KernelAllocator{ .memory = @intToPtr([*]u8, eok), .eok = eok };

        mem_table[0].len = 0;
        mem_table[0].next = 1;
        mem_table[0].is_free = false;
        var end_addr = eok + size;
        var offset: usize = 0;
        var idx: usize = 1;
        while (eok + offset + riscv.PAGE_SIZE < end_addr) : ({
            offset += riscv.PAGE_SIZE;
            idx += 1;
        }) {
            const blk_addr = eok + offset;
            mem_table[idx].is_free = true;
            mem_table[idx].next = idx + 1;
            mem_table[idx].len = riscv.PAGE_SIZE;
        }
        mem_table[idx - 1].next = 0;

        trap.restore(mask);
        return kallocator;
    }

    pub fn allocLarge(allocator: *Allocator, nbytes: usize, ptr_align: u29) ![*]u8 {
        if (bitsCount(ptr_align) != 1) {
            return Allocator.Error.OutOfMemory;
        }
        const self = @fieldParentPtr(KernelAllocator, "allocator", allocator);
        var allocatable_mem: usize = 0;
        var prev: usize = 0;
        var idx: usize = mem_table[prev].next;
        var prev_end: usize = 0;
        var begin: usize = mem_table[prev].next;
        var found = false;
        while (idx < page_maxlen) : ({
            prev = idx;
            idx += 1;
        }) {
            if (idx == 0) {
                break;
            }
            if (mem_table[idx].is_free) {
                allocatable_mem += riscv.PAGE_SIZE;
                if (allocatable_mem >= nbytes) {
                    found = true;
                    break;
                }
            } else {
                allocatable_mem = 0;
                prev_end = prev;
                idx = mem_table[prev].next - 1;
                begin = mem_table[prev].next;
            }
        }

        if (found) {
            var i: usize = begin;
            while (i <= idx) : (i += 1) {
                mem_table[i].is_free = false;
            }
            mem_table[prev_end].next = mem_table[idx].next;
            mem_table[begin].len = allocatable_mem;
            var addr = self.eok + (begin - 1) * riscv.PAGE_SIZE;
            return @intToPtr([*]u8, addr);
        } else {
            return Allocator.Error.OutOfMemory;
        }
    }

    // pub fn walkFreeList() !void {
    //     var opt: ?*SmallMemBlk = &small_freelist;
    //     try uart.out.print("small_freelist: {x}\n", .{@ptrToInt(&small_freelist)});
    //     while (opt) |block| : (opt = block.next) {
    //         try uart.out.print("walk: block.len: {x}\n", .{block.len});
    //         try uart.out.print("walk: block.next: {x}\n", .{@ptrToInt(block.next)});
    //         if (block.next != null and block.next.?.len >= riscv.PAGE_SIZE) {
    //             var next_blk_ptr: usize = @ptrToInt(block.next);
    //             var idx: usize = 0;
    //             var ptr = @intToPtr([*]u8, next_blk_ptr - 100);
    //             var cnt: usize = 0;
    //             while (idx < 100) : (idx += 1) {
    //                 try uart.out.print("{x:0^2} ", .{ptr[idx]});
    //                 if (ptr[idx] == 0xaa) {
    //                     try uart.out.print("\nundefined zone!: {x}\n", .{@ptrToInt(ptr + idx)});
    //                     break;
    //                 }
    //                 cnt += 1;
    //                 if (cnt % 16 == 0) {
    //                     try uart.out.print("\n", .{});
    //                 }
    //             }
    //         }
    //     }
    // }

    pub fn allocSmall(allocator: *Allocator, nbytes: usize, ptr_align: u29, len_align: u29) ![*]u8 {
        var nbytes_aligned = mem.alignAllocLen(riscv.PAGE_SIZE, nbytes + @sizeOf(SmallMemBlk), len_align);
        if (bitsCount(ptr_align) != 1) {
            return Allocator.Error.OutOfMemory;
        }

        if (ptr_align >= riscv.PAGE_SIZE) {
            return try allocLarge(allocator, riscv.PAGE_SIZE, ptr_align);
        }

        var prev = &small_freelist;
        var curr: ?*SmallMemBlk = null;
        if (small_freelist.next) |first_blk| {
            curr = first_blk;
        } else {
            var first_mem_page = try allocLarge(allocator, riscv.PAGE_SIZE, ptr_align);
            var blk = @ptrCast(*SmallMemBlk, &first_mem_page[0]);
            blk.len = riscv.PAGE_SIZE;
            blk.next = null;
            small_freelist.next = blk;
            curr = small_freelist.next;
            small_freelist.len += riscv.PAGE_SIZE;
        }

        var end_idx: usize = 0;
        scan: while (curr) |blk| : ({
            if (blk.next == null) {
                var page = try allocLarge(allocator, riscv.PAGE_SIZE, ptr_align);
                var page_blk = @ptrCast(*SmallMemBlk, page);
                page_blk.len = riscv.PAGE_SIZE;
                page_blk.next = null;
                blk.next = page_blk;
                small_freelist.len += riscv.PAGE_SIZE;
            }
            prev = blk;
            curr = blk.next;
        }) {
            if (blk.len == nbytes_aligned) {
                var addr = @ptrToInt(blk) + @sizeOf(SmallMemBlk);
                if (!mem.isAligned(addr, ptr_align)) {
                    continue :scan;
                }
                prev.next = blk.next;
                small_freelist.len -= nbytes_aligned;
                return @intToPtr([*]u8, addr);
            } else if (blk.len > nbytes_aligned) {
                var addr = @ptrToInt(@ptrCast([*]u8, blk) + @sizeOf(SmallMemBlk));
                var adjusted_addr = mem.alignForward(addr, ptr_align);
                if (adjusted_addr + nbytes_aligned >= @ptrToInt(blk) + blk.len) {
                    continue :scan;
                } else {
                    var new_addr = adjusted_addr - @sizeOf(SmallMemBlk);
                    var end_of_blk = @ptrToInt(blk) + @sizeOf(SmallMemBlk);
                    if (new_addr + nbytes_aligned < end_of_blk and new_addr != @ptrToInt(blk)) {
                        while (new_addr + nbytes_aligned < end_of_blk) {
                            adjusted_addr = mem.alignForward(adjusted_addr + 1, ptr_align);
                            new_addr = adjusted_addr - @sizeOf(SmallMemBlk);
                            if (new_addr + nbytes_aligned >= @ptrToInt(blk) + blk.len) {
                                continue :scan;
                            }
                        }
                    }

                    if (new_addr == @ptrToInt(blk)) {
                        var leftover_addr = new_addr + nbytes_aligned;
                        var leftover_size = blk.len - nbytes_aligned;
                        if (leftover_size <= @sizeOf(SmallMemBlk)) {
                            continue :scan;
                        }
                        var leftover = @intToPtr(*SmallMemBlk, leftover_addr);
                        leftover.len = leftover_size;
                        leftover.next = blk.next;
                        prev.next = leftover;
                        blk.len = nbytes_aligned;
                        small_freelist.len -= nbytes_aligned;
                        return @intToPtr([*]u8, @ptrToInt(blk) + @sizeOf(SmallMemBlk));
                    } else {
                        if (blk.len >= riscv.PAGE_SIZE) {
                            panic("Small-block size must be less than page-size.\n", .{});
                        }
                        var new_blk = @intToPtr(*SmallMemBlk, new_addr);
                        new_blk.len = nbytes_aligned;
                        var leftover_addr = new_addr + nbytes_aligned;
                        var leftover = @intToPtr(*SmallMemBlk, leftover_addr);
                        leftover.len = (@ptrToInt(blk) + blk.len) - (new_addr + nbytes_aligned);
                        if (leftover.len <= @sizeOf(SmallMemBlk)) {
                            continue :scan;
                        }
                        blk.len = blk.len - new_blk.len - leftover.len;

                        leftover.next = blk.next;
                        blk.next = leftover;
                        prev.next = blk;

                        small_freelist.len -= nbytes_aligned;
                        return @intToPtr([*]u8, @ptrToInt(new_blk) + @sizeOf(SmallMemBlk));
                    }
                }
            }
        }

        return Allocator.Error.OutOfMemory;
    }

    pub fn alloc(allocator: *Allocator, n: usize, ptr_align: u29, len_align: u29, ret_addr: usize) Allocator.Error![]u8 {
        const mask = trap.disable();
        defer trap.restore(mask);
        const self = @fieldParentPtr(KernelAllocator, "allocator", allocator);
        if (n == 0) { // 確保するメモリサイズが0だった
            return Allocator.Error.OutOfMemory;
        }
        if (ptr_align == 0) { // 確保するアドレスのalign指定が0だった（ゼロ除算はできない）
            return Allocator.Error.OutOfMemory;
        }
        var size = n;
        if (len_align != 0) { // サイズのalignが要求されていた場合
            size = mem.alignAllocLen(riscv.PAGE_SIZE, size, len_align);
        }

        // 要求するメモリサイズをメモリブロックヘッダの倍数にする
        var nbytes = mem.alignAllocLen(riscv.HEAP_SIZE, size, len_align);
        if (nbytes < riscv.PAGE_SIZE) {
            var result = try allocSmall(allocator, nbytes, ptr_align, len_align);
            return result[0..n];
        } else {
            var result = try allocLarge(allocator, nbytes, ptr_align);
            return result[0..n];
        }

        return Allocator.Error.OutOfMemory;
    }

    pub fn freeLarge(self: *KernelAllocator, buf: []u8) !void {
        var buf_page_idx = (@ptrToInt(&buf[0]) - self.eok) / riscv.PAGE_SIZE + 1;
        var length: usize = mem_table[buf_page_idx].len;
        var idx = buf_page_idx;
        while (length > 0) : ({
            length -= riscv.PAGE_SIZE;
            idx += 1;
        }) {
            mem_table[idx].is_free = true;
            mem_table[idx].len = riscv.PAGE_SIZE;
            mem_table[idx].next = mem_table[0].next;
            mem_table[0].next = idx;
        }
    }

    pub fn freeSmall(self: *KernelAllocator, buf: []u8) !void {
        var addr: usize = @ptrToInt(&buf[0]) - @sizeOf(SmallMemBlk);
        var blk = @intToPtr(*SmallMemBlk, addr);
        blk.next = small_freelist.next;
        small_freelist.next = blk;
    }

    pub fn resizeLarge(self: *KernelAllocator, allocator: *Allocator, buf: []u8, buf_align: u29, new_len: usize, len_align: u29) !usize {
        var mask = trap.disable();
        defer trap.restore(mask);
        var len = new_len;
        if (len_align != 0) {
            len = mem.alignForward(new_len, len_align);
        }
        var buf_page_idx = (@ptrToInt(&buf[0]) - self.eok) / riscv.PAGE_SIZE + 1;
        var buf_page_len = mem_table[buf_page_idx].len;
        if (buf_page_len < new_len) {
            var buf_start_page_idx_alloc_newly = buf_page_idx + buf_page_len / riscv.PAGE_SIZE;
            var mem_size_alloc_newly = new_len - buf_page_len;

            var buf_next_page_idx = buf_start_page_idx_alloc_newly;
            var required_size: isize = @intCast(isize, mem_size_alloc_newly);
            var is_allocatable = true;
            while (required_size > 0) : ({
                required_size -= @intCast(isize, riscv.PAGE_SIZE);
                buf_next_page_idx += 1;
            }) {
                if (!mem_table[buf_next_page_idx].is_free) {
                    is_allocatable = false;
                    break;
                }
            }

            if (is_allocatable) {
                var end_of_page_alloc_newly = buf_start_page_idx_alloc_newly + mem_size_alloc_newly / riscv.PAGE_SIZE;
                var idx = buf_start_page_idx_alloc_newly;
                while (idx < end_of_page_alloc_newly) : (idx += 1) {
                    mem_table[idx].is_free = false;
                }

                mem_table[buf_page_idx].len += round(mem_size_alloc_newly, 4096);
                return new_len;
            } else {
                return Allocator.Error.OutOfMemory;
            }
        } else {
            return new_len;
        }
    }

    pub fn resizeSmall(self: *KernelAllocator, allocator: *Allocator, buf: []u8, buf_align: u29, new_len: usize, len_align: u29) Allocator.Error!usize {
        var blk = @intToPtr(*SmallMemBlk, @ptrToInt(&buf[0]) - @sizeOf(SmallMemBlk));
        if ((blk.len - @sizeOf(SmallMemBlk)) >= new_len) {
            return new_len;
        } else {
            // try uart.out.print("resizeSmall\n", .{});
            return Allocator.Error.OutOfMemory;
        }
    }

    pub fn resize(allocator: *Allocator, buf: []u8, buf_align: u29, new_len: usize, len_align: u29, ret_addr: usize) Allocator.Error!usize {
        const mask = trap.disable();
        defer trap.restore(mask);
        const self = @fieldParentPtr(KernelAllocator, "allocator", allocator);
        var addr = @ptrToInt(&buf[0]);
        var is_large = false;
        if (mem.isAligned(addr, riscv.PAGE_SIZE)) {
            is_large = true;
        }

        if (new_len == 0) {
            if (is_large) {
                try self.freeLarge(buf);
            } else {
                try self.freeSmall(buf);
            }
            return new_len;
        } else if (new_len > buf.len) {
            if (is_large) {
                return try resizeLarge(self, allocator, buf, buf_align, new_len, len_align);
            } else {
                return try resizeSmall(self, allocator, buf, buf_align, new_len, len_align);
            }
        }

        return new_len;
    }
};

pub fn getStack(allocator: *Allocator, n: usize) ![*]u8 {
    const mask = trap.disable();
    defer trap.restore(mask);
    if (n == 0) {
        return Allocator.Error.OutOfMemory;
    }

    var block = try allocator.alloc(u8, n);
    return @intToPtr([*]u8, @ptrToInt(&block[0]) + n);
}
