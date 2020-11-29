const std = @import("std");
const heap = std.heap;
pub const Allocator = std.mem.Allocator;
const mem = std.mem;
const riscv = @import("riscv.zig");
const uart = @import("uart.zig");
const trap = @import("trap.zig");
const util = @import("util.zig");
const vm = @import("vm.zig");
const assert = std.debug.assert;

// メモリブロックのヘッダ
// nextは次のブロック
// lenはブロックのサイズ
const MemBlk = packed struct {
    len: usize,
    is_free: bool,

    pub fn init() MemBlk {
        return MemBlk{
            .len = riscv.PAGE_SIZE,
            .is_free = true,
        };
    }
};

// メモリブロック全体
// memblk_root.lenはすべてのフリーなメモリの合計サイズ
// var memblk_root = MemBlk{ .next = null, .len = riscv.HEAP_SIZE };
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

    // bufをフリーにする
    pub fn freeLarge(self: *KernelAllocator, buf: []u8) !void {
        var buf_page_idx = (@ptrToInt(&buf[0]) - self.eok) / riscv.PAGE_SIZE;
        var length: usize = mem_table[buf_page_idx].len;
        var idx = buf_page_idx;
        while (length > 0) : ({
            length -= riscv.PAGE_SIZE;
            idx += 1;
        }) {
            mem_table[idx].is_free = true;
        }
    }

    // アロケータを初期化
    pub fn init(size: usize) KernelAllocator {
        const mask = trap.disable();
        const writer = uart.UART.get_writer();
        // カーネルの最後のアドレス
        const eok = mem.alignForward(getEndOfKernel(), riscv.PAGE_SIZE);
        // eokをポインタに変換
        var kallocator = KernelAllocator{ .memory = @intToPtr([*]u8, eok), .eok = eok };

        var end_addr = eok + size;
        var offset: usize = 0;
        var idx: usize = 0;
        while (eok + offset + riscv.PAGE_SIZE < end_addr) : ({
            offset += riscv.PAGE_SIZE;
            idx += 1;
        }) {
            const blk_addr = eok + offset;
            mem_table[idx].is_free = true;
            mem_table[idx].len = riscv.PAGE_SIZE;
        }

        trap.restore(mask);
        return kallocator;
    }

    pub fn allocLarge(allocator: *Allocator, nbytes: usize, ptr_align: u29, curr_idx: usize) ![*]u8 {
        assert(nbytes > riscv.PAGE_SIZE);
        assert(ptr_align <= riscv.PAGE_SIZE);
        const self = @fieldParentPtr(KernelAllocator, "allocator", allocator);
        var allocatable_mem: usize = 0;
        var idx = curr_idx;
        var map_needed = true;
        while (idx < page_maxlen and mem_table[idx].is_free) : (idx += 1) {
            allocatable_mem += riscv.PAGE_SIZE;
            if (allocatable_mem >= nbytes) {
                map_needed = false;
                break;
            }
        }

        if (map_needed) {
            idx += 1;
            var consecutive_mem: usize = 0;
            var consecutive_mem_start: usize = idx;
            var found = false;
            while (idx < page_maxlen) : (idx += 1) {
                if (mem_table[idx].is_free) {
                    consecutive_mem += riscv.PAGE_SIZE;
                    if (consecutive_mem >= nbytes) {
                        found = true;
                        break;
                    }
                } else {
                    consecutive_mem = 0;
                    consecutive_mem_start = idx + 1;
                }
            }

            if (found) {
                var end = consecutive_mem_start + consecutive_mem / riscv.PAGE_SIZE;
                var i: usize = consecutive_mem_start;
                while (i < end) : (i += 1) {
                    mem_table[i].is_free = false;
                }

                mem_table[consecutive_mem_start].len = consecutive_mem / riscv.PAGE_SIZE;
                var addr = mem.alignForward(self.eok + consecutive_mem_start * riscv.PAGE_SIZE, ptr_align);
                return @intToPtr([*]u8, addr);
            } else {
                return Allocator.Error.OutOfMemory;
            }
        } else {
            var i: usize = curr_idx;
            while (i < idx) : (i += riscv.PAGE_SIZE) {
                mem_table[idx].is_free = false;
            }

            mem_table[curr_idx].len = allocatable_mem;
            var addr = mem.alignForward(self.eok + curr_idx * riscv.PAGE_SIZE, ptr_align);
            return @intToPtr([*]u8, addr);
        }
    }

    pub fn alloc(allocator: *Allocator, n: usize, ptr_align: u29, len_align: u29, ret_addr: usize) Allocator.Error![]u8 {
        const mask = trap.disable();
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
        var nbytes = size;
        var idx: usize = 0;
        while (idx < page_maxlen) : (idx += 1) {
            if (mem_table[idx].is_free) {
                if (nbytes > riscv.PAGE_SIZE) {
                    var result = try allocLarge(allocator, nbytes, ptr_align, idx);
                    trap.restore(mask);
                    return result[0..n];
                } else {
                    mem_table[idx].is_free = false;
                    trap.restore(mask);
                    return @intToPtr([*]u8, self.eok + idx * riscv.PAGE_SIZE)[0..n];
                }
            }
        }

        trap.restore(mask);
        return Allocator.Error.OutOfMemory;
    }

    pub fn resizeLarge(self: *KernelAllocator, allocator: *Allocator, buf: []u8, buf_align: u29, new_len: usize, len_align: u29) !usize {
        var mask = trap.disable();
        var len = new_len;
        if (len_align != 0) {
            len = mem.alignForward(new_len, len_align);
        }
        var buf_page_idx = (@ptrToInt(&buf[0]) - self.eok) / riscv.PAGE_SIZE;
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
                trap.restore(mask);
                return new_len;
            } else {
                trap.restore(mask);
                return Allocator.Error.OutOfMemory;
            }
        } else {
            trap.restore(mask);
            return new_len;
        }
    }

    pub fn resize(allocator: *Allocator, buf: []u8, buf_align: u29, new_len: usize, len_align: u29, ret_addr: usize) Allocator.Error!usize {
        const mask = trap.disable();
        defer trap.restore(mask);
        errdefer trap.restore(mask);
        const self = @fieldParentPtr(KernelAllocator, "allocator", allocator);
        if (new_len == 0) {
            try self.freeLarge(buf);
        } else if (new_len > buf.len) {
            if (new_len > riscv.PAGE_SIZE) {
                return resizeLarge(self, allocator, buf, buf_align, new_len, len_align);
            } else {
                return new_len;
            }
        }

        return new_len;
    }
};

pub fn getStack(allocator: *Allocator, n: usize) ![*]u8 {
    const mask = trap.disable();
    if (n == 0) {
        return Allocator.Error.OutOfMemory;
    }

    var block = try allocator.alloc(u8, n);
    return @intToPtr([*]u8, @ptrToInt(&block[0]) + n);
}
