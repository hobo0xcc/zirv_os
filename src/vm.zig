const std = @import("std");
const Allocator = std.mem.Allocator;
const Exact = Allocator.Exact;
const uart = @import("uart.zig");
const riscv = @import("riscv.zig");
const panic = @import("panic.zig").panic;
const util = @import("util.zig");
const csr = @import("csr.zig");
const memlayout = @import("memlayout.zig");

pub const PTE_V = 0b1 << 0;
pub const PTE_R = 0b1 << 1;
pub const PTE_W = 0b1 << 2;
pub const PTE_X = 0b1 << 3;
pub const PTE_U = 0b1 << 4;
pub const PTE_G = 0b1 << 5;
pub const PTE_A = 0b1 << 6;
pub const PTE_D = 0b1 << 7;
pub const PTE_RSW = 0b11 << 8;
pub const PTE_PPN = [_]u64{ 0x1ff << 10, 0x1ff << 19, 0x3ff_ffff << 28 };

extern const _text_start: usize;
extern const _text_end: usize;
extern const _rodata_start: usize;
extern const _rodata_end: usize;
extern const _data_start: usize;
extern const _data_end: usize;
extern const _bss_start: usize;
extern const _bss_end: usize;
extern const _end: usize;

pub var root_page_table: *Table = undefined;

pub const Table = packed struct {
    entries: [512]Entry,

    pub fn len(self: *Table) usize {
        return 512;
    }
};

pub const Entry = packed struct {
    entry: u64,

    pub fn init() Entry {
        return Entry{
            .entry = 0,
        };
    }

    pub fn is_valid(self: *Entry) bool {
        return (self.entry & PTE_V) != 0;
    }

    pub fn is_invalid(self: *Entry) bool {
        return !self.is_valid();
    }

    pub fn is_leaf(self: *Entry) bool {
        return (self.entry & (PTE_R | PTE_W | PTE_X)) != 0;
    }

    pub fn is_branch(self: *Entry) bool {
        return !self.is_leaf();
    }

    pub fn set_entry(self: *Entry, entry: u64) void {
        self.entry = entry;
    }

    pub fn get_entry(self: *Entry) u64 {
        return self.entry;
    }
};

// pub var root_table: Table = Table { .entries = [_]Entry{ Entry.init() } ** 512 };

pub fn isCurrentModeBare() bool {
    return csr.readSatp() >> 60 == 0;
}

pub fn map(a: *Allocator, root: *Table, vaddr: usize, paddr: usize, bits: u64, level: usize) !void {
    if ((bits & (PTE_R | PTE_W | PTE_X)) == 0) {
        panic("Cannot map a non-leaf page\n", .{});
    }

    const vpn = [_]u64{
        (vaddr >> 12) & 0x1ff,
        (vaddr >> 21) & 0x1ff,
        (vaddr >> 30) & 0x1ff,
    };

    const ppn = [_]u64{
        (paddr >> 12) & 0x1ff,
        (paddr >> 21) & 0x1ff,
        (paddr >> 30) & 0x3ff_ffff,
    };

    var v = &root.entries[vpn[2]];
    var i: isize = 1;
    while (i >= level) : (i -= 1) {
        if (v.is_invalid()) {
            var page = try a.allocAdvanced(u8, 4096, 4096, Exact.exact);
            util.memset(page, 0);
            var page_ptr = @ptrToInt(&page[0]);
            v.set_entry((page_ptr >> 2) | PTE_V);
        }

        var entry = @intToPtr([*]Entry, (v.get_entry() & ~@intCast(u64, 0x3ff)) << 2);
        v = &entry[vpn[@intCast(usize, i)]];
    }

    const entry = (ppn[2] << 28) |
        (ppn[1] << 19) |
        (ppn[0] << 10) |
        bits |
        PTE_V;
    v.set_entry(entry);
}

pub fn unmap(a: *Allocator, root: *Table) void {
    var lv2 = 0;
    while (lv2 < Table.len()) : (lv2 += 1) {
        var entry_lv2 = root.entries[lv2];
        if (entry_lv2.is_valid() and entry_lv2.is_branch()) {
            const memaddr_lv1 = (entry_lv2.get_entry() & ~0x3ff) << 2;
            const table_lv1 = @intToPtr(*Table, memaddr_lv1);
            var lv1: usize = 0;
            while (lv1 < Table.len()) : (lv1 += 1) {
                const entry_lv1 = table_lv1.entries[lv1];
                if (entry_lv1.is_valid() and entry_lv1.is_branch()) {
                    const memaddr_lv0 = (entry_lv1.get_entry() & ~0x3ff) << 2;
                    a.destroy(@intToPtr(*u8, memaddr_lv0));
                }
            }

            a.destroy(@intToPtr(*u8, memaddr_lv1));
        }
    }
}

pub fn virtAddrGetEntry(root: *Table, vaddr: usize) ?*Entry {
    const vpn = [_]u64{
        (vaddr >> 12) & 0x1ff,
        (vaddr >> 21) & 0x1ff,
        (vaddr >> 30) & 0x1ff,
    };

    var v = &root.entries[vpn[2]];
    var i: usize = 2;
    while (i >= 0) : (i -= 1) {
        if (v.is_invalid()) {
            break;
        } else if (v.is_leaf()) {
            const off_mask = (@as(usize, 1) << @as(u6, 12 + @intCast(u6, i) * 9)) - 1;
            const vaddr_pgoff = vaddr & off_mask;
            const addr = (v.get_entry() << 2) & ~off_mask;
            return v;
        }

        const entry = @intToPtr([*]Entry, (v.get_entry() & ~@intCast(u64, 0x3ff)) << 2);
        v = &entry[vpn[i - 1]];
    }

    return null;
}

pub fn virtToPhys(root: *Table, vaddr: usize) ?usize {
    const vpn = [_]u64{
        (vaddr >> 12) & 0x1ff,
        (vaddr >> 21) & 0x1ff,
        (vaddr >> 30) & 0x1ff,
    };

    var v = &root.entries[vpn[2]];
    var i: usize = 2;
    while (i >= 0) : (i -= 1) {
        if (v.is_invalid()) {
            break;
        } else if (v.is_leaf()) {
            const off_mask = (@as(usize, 1) << @as(u6, 12 + @intCast(u6, i) * 9)) - 1;
            const vaddr_pgoff = vaddr & off_mask;
            const addr = (v.get_entry() << 2) & ~off_mask;
            return addr | vaddr_pgoff;
        }

        const entry = @intToPtr([*]Entry, (v.get_entry() & ~@intCast(u64, 0x3ff)) << 2);
        v = &entry[vpn[i - 1]];
    }

    try uart.out.print("virtToPhys: {}\n", .{i});

    return null;
}

pub fn idMapRange(a: *Allocator, root: *Table, start: usize, end: usize, bits: u64) !void {
    var memaddr = start & ~(@as(usize, 4096 - 1));
    const num_kb_pages = (std.mem.alignForward(end, 4096) - memaddr) / 4096;
    var i: usize = 0;
    while (i < num_kb_pages) : (i += 1) {
        try map(a, root, memaddr, memaddr, bits, 0);
        memaddr += 4096;
    }
}

pub fn addrMapRange(a: *Allocator, root: *Table, vaddr: usize, paddr: usize, size: usize, bits: u64) !void {
    var mem_remain: isize = @intCast(isize, size);
    var curr_vaddr = vaddr & ~(@as(usize, 4096 - 1));
    var curr_paddr = paddr & ~(@as(usize, 4096 - 1));
    while (mem_remain > 0) : (mem_remain -= @intCast(isize, riscv.PAGE_SIZE)) {
        try map(a, root, curr_vaddr, curr_paddr, bits, 0);
        curr_vaddr += riscv.PAGE_SIZE;
        curr_paddr += riscv.PAGE_SIZE;
    }
}

pub fn makeSatp(page_table: *Table) u64 {
    const root_ppn = @ptrToInt(page_table) >> 12;
    const satp_val = 8 << 60 | root_ppn;
    return satp_val;
}

pub fn init(a: *Allocator) !*Table {
    const text_start = @ptrToInt(&_text_start);
    const text_end = @ptrToInt(&_text_end);
    const rodata_start = @ptrToInt(&_rodata_start);
    const rodata_end = @ptrToInt(&_rodata_end);
    const data_start = @ptrToInt(&_data_start);
    const data_end = @ptrToInt(&_data_end);
    const bss_start = @ptrToInt(&_bss_start);
    const bss_end = @ptrToInt(&_bss_end);
    const heap_start = @ptrToInt(&_end);
    const heap_end = @ptrToInt(&_end) + riscv.HEAP_SIZE;

    try uart.out.print("TEXT: 0x{x} -> 0x{x}\n", .{ text_start, text_end });
    try uart.out.print("RODATA: 0x{x} -> 0x{x}\n", .{ rodata_start, rodata_end });
    try uart.out.print("DATA: 0x{x} -> 0x{x}\n", .{ data_start, data_end });
    try uart.out.print("BSS: 0x{x} -> 0x{x}\n", .{ bss_start, bss_end });
    try uart.out.print("HEAP: 0x{x} -> 0x{x}\n", .{ heap_start, heap_end });

    var root_table = try a.allocAdvanced(Table, 4096, 1, Exact.exact);
    var root = &root_table[0];

    try idMapRange(a, root, heap_start, heap_end, PTE_R | PTE_W);
    try idMapRange(a, root, rodata_start, rodata_end, PTE_R | PTE_X);
    try idMapRange(a, root, data_start, data_end, PTE_R | PTE_W);
    try idMapRange(a, root, bss_start, bss_end, PTE_R | PTE_W);
    try idMapRange(a, root, text_start, text_end, PTE_R | PTE_X | PTE_A);

    try map(a, root, memlayout.UART_BASE, memlayout.UART_BASE, PTE_R | PTE_W, 0);
    try idMapRange(a, root, memlayout.VIRTIO_BASE, memlayout.VIRTIO_BASE + memlayout.VIRTIO_SIZE, PTE_R | PTE_W);
    try idMapRange(a, root, memlayout.CLINT_BASE, memlayout.CLINT_BASE + memlayout.CLINT_SIZE, PTE_R | PTE_W);
    try idMapRange(a, root, memlayout.PLIC_BASE, memlayout.PLIC_BASE + memlayout.PLIC_SIZE, PTE_R | PTE_W);

    const satp_val = makeSatp(root);
    asm volatile ("csrw satp, %[val]"
        :
        : [val] "r" (satp_val)
    );
    asm volatile ("sfence.vma zero, zero");
    root_page_table = root;
    return root;
}
