const std = @import("std");
const heap = std.heap;
const Allocator = std.mem.Allocator;
const Exact = Allocator.Exact;
const mem = std.mem;
const riscv = @import("riscv.zig");
const uart = @import("uart.zig");
const trap = @import("trap.zig");
const util = @import("util.zig");
const vm = @import("vm.zig");
const panic = @import("panic.zig").panic;
const assert = std.debug.assert;

pub var a: *Allocator = undefined;

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

var mem_table = [_]MemBlk{MemBlk.init()} ** (riscv.HEAP_SIZE / 4096);
var page_maxlen = riscv.HEAP_SIZE / 4096;

pub fn getEndOfKernel() usize {
    return asm volatile ("la %[ret], _end"
        : [ret] "=r" (-> usize)
    );
}

pub fn bitsCount(val: u29) u29 {
    var v = val;
    v = (v & 0x5555) + ((v & 0xAAAA) >> 1);
    v = (v & 0x3333) + ((v & 0xCCCC) >> 2);
    v = (v & 0x0F0F) + ((v & 0xF0F0) >> 4);
    v = (v & 0x00FF) + ((v & 0xFF00) >> 8);
    return v;
}

pub const KernelAllocator = struct {
    allocator: Allocator = Allocator{
        .allocFn = alloc,
        .resizeFn = resize,
    },

    memory: [*]u8,
    eok: usize,

    pub fn init(size: usize) KernelAllocator {
        const mask = trap.disable();
        defer trap.restore(mask);
        const eok = mem.alignForward(getEndOfKernel(), riscv.PAGE_SIZE);
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

        return kallocator;
    }

    pub fn allocPage(allocator: *Allocator, nbytes: usize, ptr_align: u29) ![*]u8 {
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
        if (len_align != 0) {
            size = mem.alignForward(size, len_align);
        }

        var nbytes = size;
        var result = try allocPage(allocator, nbytes, ptr_align);
        return result[0..n];
    }

    pub fn freePage(self: *KernelAllocator, buf: []u8) !void {
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

    pub fn resizePage(self: *KernelAllocator, allocator: *Allocator, buf: []u8, buf_align: u29, new_len: usize, len_align: u29) !usize {
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

                mem_table[buf_page_idx].len += util.round(mem_size_alloc_newly, 4096);
                return new_len;
            } else {
                return Allocator.Error.OutOfMemory;
            }
        } else {
            return new_len;
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
            try self.freePage(buf);
            return new_len;
        } else if (new_len > buf.len) {
            return try resizePage(self, allocator, buf, buf_align, new_len, len_align);
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

    var block = try allocator.allocAdvanced(u8, 0x1000, n, Exact.at_least);
    return @intToPtr([*]u8, @ptrToInt(&block[0]) + n);
}
