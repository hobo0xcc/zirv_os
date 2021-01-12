const memalloc = @import("memalloc.zig");
const uart = @import("uart.zig");
const fs = @import("fs.zig");
const std = @import("std");
const vm = @import("vm.zig");
const util = @import("util.zig");
const elf = std.elf;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const Exact = Allocator.Exact;
const KernelError = @import("kerror.zig").KernelError;

const SectionHeaderIterator = struct {
    header: *elf.Elf64_Ehdr,
    buf: [*]u8,
    index: usize,
    len: usize,

    pub fn next(self: *SectionHeaderIterator) ?*elf.Elf64_Shdr {
        if (self.index >= self.len) return null;
        var new_offset = self.header.e_shoff + @sizeOf(elf.Elf64_Shdr) * self.index;
        var shdr_ptr = @ptrCast(*elf.Elf64_Shdr, @alignCast(8, self.buf + new_offset));

        self.index += 1;
        return shdr_ptr;
    }
};

const ProgramHeaderIterator = struct {
    header: *elf.Elf64_Ehdr,
    buf: [*]u8,
    index: usize,
    len: usize,

    pub fn next(self: *ProgramHeaderIterator) ?*elf.Elf64_Phdr {
        if (self.index >= self.len) return null;
        var new_offset = self.header.e_phoff + @sizeOf(elf.Elf64_Phdr) * self.index;
        var phdr_ptr = @ptrCast(*elf.Elf64_Phdr, @alignCast(8, self.buf + new_offset));

        self.index += 1;
        return phdr_ptr;
    }
};

pub fn sectionIter(header: *elf.Elf64_Ehdr, buf: [*]u8) SectionHeaderIterator {
    return SectionHeaderIterator{
        .header = header,
        .buf = buf,
        .index = 0,
        .len = header.e_shnum,
    };
}

pub fn programIter(header: *elf.Elf64_Ehdr, buf: [*]u8) ProgramHeaderIterator {
    return ProgramHeaderIterator{
        .header = header,
        .buf = buf,
        .index = 0,
        .len = header.e_phnum,
    };
}

pub fn isElfFormat(data: [*]u8) bool {
    return mem.eql(u8, data[0..4], "\x7fELF");
}

pub fn loadExecFile(a: *Allocator, name: []u8, page_table: *vm.Table) !u64 {
    var info_opt = try fs.getFileInfo(a, 1, name);
    var info: *fs.FileInfo = undefined;
    if (info_opt) |i| {
        info = i;
    } else {
        try uart.out.print("loadExecFile: file `{}` not found\n", .{name});
        return KernelError.SYSERR;
    }

    var buf_arr = try a.allocAdvanced(u8, 8, info.aligned_size, Allocator.Exact.exact);
    var buf = @ptrCast([*]u8, &buf_arr[0]);
    var ok = try fs.loadFileDataIntoBuf(a, 1, buf, name, info.aligned_size);
    if (!ok) {
        try uart.out.print("loadExecFile: loading `{}` failed\n", .{name});
        return KernelError.SYSERR;
    }

    if (!isElfFormat(buf)) {
        try uart.out.print("loadExecFile: file `{}` is not an elf format\n", .{name});
        return KernelError.SYSERR;
    }

    var header = @ptrCast(*elf.Elf64_Ehdr, @alignCast(8, buf));
    try uart.out.print("Debug: e_machine: {}\n", .{header.e_machine});
    try uart.out.print("Debug: e_entry: {x}\n", .{header.e_entry});
    try uart.out.print("Debug: e_phoff: {x}\n", .{header.e_phoff});
    try uart.out.print("Debug: e_phnum: {x}\n", .{header.e_phnum});

    if (header.e_type != elf.ET.EXEC) {
        try uart.out.print("loadExecFile: file `{}` is not an executable file\n", .{name});
        return KernelError.SYSERR;
    }

    var shstrtab_ptr = buf + header.e_shoff + (@sizeOf(elf.Elf64_Shdr) * header.e_shstrndx);
    var shstrtab = @ptrCast(*elf.Elf64_Shdr, @alignCast(8, shstrtab_ptr));
    var strtab = buf + shstrtab.sh_offset;

    var program_iter = try a.create(ProgramHeaderIterator);
    defer a.destroy(program_iter);
    program_iter.* = programIter(header, buf);
    var program_mem: [*]u8 = undefined;
    var offset: usize = undefined;
    var p_idx: usize = 0;
    while (program_iter.next()) |program| : (p_idx += 1) {
        try uart.out.print("program: memsz: {}\n", .{program.p_memsz});
        var arr = try a.allocAdvanced(
            u8,
            0x1000,
            program.p_memsz,
            Exact.at_least,
        );
        program_mem = @ptrCast([*]u8, &arr[0]);
        offset = @intCast(usize, program.p_offset);
        try vm.addrMapRange(
            a,
            page_table,
            program.p_vaddr,
            @ptrToInt(&program_mem[0]),
            program.p_memsz,
            vm.PTE_R | vm.PTE_W | vm.PTE_X | vm.PTE_U,
        );
    }

    var section_iter = try a.create(SectionHeaderIterator);
    defer a.destroy(section_iter);
    section_iter.* = sectionIter(header, buf);
    var s_idx: usize = 0;
    while (section_iter.next()) |section| : (s_idx += 1) {
        if (section.sh_addr != 0 and section.sh_size != 0) {
            util.memcpy(program_mem + section.sh_addr - offset, buf + section.sh_offset, section.sh_size);
        }
        try uart.out.print("section {}: `{}`\n", .{ s_idx, util.getStrFromPtr(strtab + section.sh_name) });
        try uart.out.print("\tsh_addr: {x}\n", .{section.sh_addr});
        try uart.out.print("\tsh_offset: {x}\n", .{section.sh_offset});
    }
    try uart.out.print("loading `{}`...\n", .{name});

    return header.e_entry;
}
