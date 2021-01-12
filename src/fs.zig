const virtio = @import("virtio.zig");
const util = @import("util.zig");
const uart = @import("uart.zig");
const memalloc = @import("memalloc.zig");
const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const KernelError = @import("kerror.zig").KernelError;

const UstarHeader = packed struct {
    file_name: [100]u8,
    file_mode: u64,
    owner_user_id: u64,
    group_user_id: u64,
    file_size: [12]u8, // octal base
    last_modify: [12]u8, // octal
    checksum: u64,
    type_flag: u8,
    name_linked: [100]u8,
    indicator: [6]u8,
    version: [2]u8,
    owner_user_name: [32]u8,
    owner_group_name: [32]u8,
    device_major_num: u64,
    device_minor_num: u64,
    filename_prefix: [155]u8,
};

pub const FileData = struct {
    name: []u8,
    size: usize,
    data: [*]u8,

    pub fn init(name: []u8, size: usize, data: [*]u8) FileData {
        return FileData{
            .name = name,
            .size = size,
            .data = data,
        };
    }
};

pub const FileInfo = struct {
    size: usize,
    aligned_size: usize,
};

const USTAR_FILE_NAME: usize = 0;
const USTAR_SIZE_FILE_NAME: usize = 100;
const USTAR_FILE_MODE: usize = 100;
const USTAR_SIZE_FILE_MODE: usize = 8;
const USTAR_OWNER_USER_ID: usize = 108;
const USTAR_SIZE_OWNER_USER_ID: usize = 8;
const USTAR_GROUP_USER_ID: usize = 116;
const USTAR_SIZE_GROUP_USER_ID: usize = 8;
const USTAR_FILE_SIZE: usize = 124;
const USTAR_SIZE_FILE_SIZE: usize = 12;
const USTAR_LAST_MODIFY: usize = 136;
const USTAR_SIZE_LAST_MODIFY: usize = 12;
const USTAR_CHECKSUM: usize = 148;
const USTAR_SIZE_CHECKSUM: usize = 8;
const USTAR_TYPE_FLAG: usize = 156;
const USTAR_SIZE_TYPE_FLAG: usize = 1;
const USTAR_NAME_LINKED: usize = 157;
const USTAR_SIZE_NAME_LINKED: usize = 100;
const USTAR_INDICATOR: usize = 257;
const USTAR_SIZE_INDICATOR: usize = 6;
const USTAR_VERSION: usize = 263;
const USTAR_SIZE_VERSION: usize = 2;
const USTAR_OWNER_USER_NAME: usize = 265;
const USTAR_SIZE_OWNER_USER_NAME: usize = 32;
const USTAR_OWNER_GROUP_NAME: usize = 297;
const USTAR_SIZE_OWNER_GROUP_NAME: usize = 32;
const USTAR_DEVICE_MAJOR_NUMBER: usize = 329;
const USTAR_SIZE_DEVICE_MAJOR_NUMNER: usize = 8;
const USTAR_DEVICE_MINOR_NUMBER: usize = 337;
const USTAR_SIZE_DEVICE_MINOR_NUMBER: usize = 8;
const USTAR_FILENAME_PREFIX: usize = 345;
const USTAR_SIZE_FILENAME_PREFIX: usize = 155;

pub fn isUstar(ptr: [*]u8) bool {
    for ("ustar") |ch, i| {
        if (ch != (ptr + USTAR_INDICATOR)[i]) {
            return false;
        }
    }
    return true;
}

pub fn oct2bin(ptr: [*]u8, size: usize) usize {
    var res: usize = 0;
    var idx: usize = 0;
    while (idx < size) : (idx += 1) {
        res *= 8;
        res += ptr[idx] - '0';
    }

    return res;
}

pub fn getFileSize(ptr: [*]u8) usize {
    return oct2bin(ptr + USTAR_FILE_SIZE, USTAR_SIZE_FILE_SIZE - 1);
}

pub fn getFileSizeAligned(ptr: [*]u8) usize {
    var size = getFileSize(ptr);
    return ((size + 511) / 512) * 512;
}

pub fn getNextIdx(ptr: [*]u8, curr: usize) usize {
    var size = getFileSize(ptr);
    return curr + ((size + 511) / 512 + 1) * 512;
}

pub fn readNextFile(a: *Allocator, dev: usize, ptr: [*]u8, curr: *usize) !void {
    curr.* = getNextIdx(ptr, curr.*);
    try virtio.read(a, dev, ptr, 512, curr.*);
}

pub fn getFileName(ptr: [*]u8) []u8 {
    var name_ptr = (ptr + USTAR_FILE_NAME);
    var idx: usize = 0;
    while (idx < USTAR_SIZE_FILE_NAME) : (idx += 1) {
        if (name_ptr[idx] == 0) {
            break;
        }
    }

    return name_ptr[0..idx];
}

pub fn getData(a: *Allocator, dev: usize, header: [*]u8, curr: usize, read_size: ?usize) ![*]u8 {
    var size = if (read_size) |s| s else getFileSizeAligned(header);
    var data_arr = try a.alloc(u8, size);
    var data_ptr = @ptrCast([*]u8, &data_arr[0]);
    try loadDataIntoBuf(a, dev, data_ptr, curr, size);

    return data_ptr;
}

pub fn loadDataIntoBuf(a: *Allocator, dev: usize, buf: [*]u8, offset: usize, read_size: ?usize) !void {
    var header = try a.alloc(u8, 512);
    var header_ptr = header.ptr;
    try virtio.read(a, dev, header_ptr, 512, offset);
    var size = if (read_size) |s| s else getFileSizeAligned(header_ptr);
    var data_ptr = buf;
    var curr_idx: usize = 0;
    var curr_offset: usize = offset + 512;
    var remainder: isize = @intCast(isize, size);
    while (remainder > 0) : ({
        remainder -= 512;
        curr_offset += 512;
        curr_idx += 512;
    }) {
        if (remainder < 512) {
            try virtio.read(a, dev, (data_ptr + curr_idx), @intCast(u32, remainder), curr_offset);
        } else {
            try virtio.read(a, dev, (data_ptr + curr_idx), 512, curr_offset);
        }
    }
}

pub fn isExceededDiskSize(dev: usize, curr: usize) bool {
    return curr >= virtio.getDiskSectorLen(dev) * 512;
}

pub fn findFile(a: *Allocator, dev: usize, name: []u8) !?usize {
    var buf = try a.alloc(u8, 512);
    var ptr = @ptrCast([*]u8, &buf[0]);
    var curr: usize = 0;
    try virtio.read(a, dev, ptr, 512, curr);
    var found = false;
    while (isUstar(ptr) and !isExceededDiskSize(dev, curr)) : (try readNextFile(a, dev, ptr, &curr)) {
        if (util.strcmp(name, getFileName(ptr))) {
            found = true;
            break;
        }
    }

    return if (found) curr else null;
}

pub fn loadFileDataIntoBuf(a: *Allocator, dev: usize, buf: [*]u8, name: []u8, read_size: ?usize) !bool {
    if (try findFile(a, dev, name)) |offset| {
        try loadDataIntoBuf(a, dev, buf, offset, read_size);
        return true;
    } else {
        return false;
    }
}

pub fn getFileInfo(a: *Allocator, dev: usize, name: []u8) !?*FileInfo {
    var buf_arr = try a.alloc(u8, 512);
    var buf = @ptrCast([*]u8, &buf_arr[0]);
    defer a.free(buf_arr);
    var curr: usize = 0;
    try virtio.read(a, dev, buf, 512, curr);
    var found = false;
    while (isUstar(buf) and !isExceededDiskSize(dev, curr)) : (try readNextFile(a, dev, buf, &curr)) {
        if (util.strcmp(name, getFileName(buf))) {
            found = true;
            break;
        }
    }

    if (found) {
        var info = try a.create(FileInfo);
        info.size = getFileSize(buf);
        info.aligned_size = getFileSizeAligned(buf);
        return info;
    } else {
        return null;
    }
}

pub fn getFileData(a: *Allocator, dev: usize, name: []u8, size: ?usize) !?*FileData {
    var buf = try a.alloc(u8, 512);
    var ptr = @ptrCast([*]u8, &buf[0]);
    var curr: usize = 0;
    try virtio.read(a, dev, ptr, 512, curr);
    var found = false;
    while (isUstar(ptr) and !isExceededDiskSize(dev, curr)) : (try readNextFile(a, dev, ptr, &curr)) {
        if (util.strcmp(name, getFileName(ptr))) {
            found = true;
            break;
        }
    }

    if (found) {
        var file_data_ptr = try a.create(FileData);
        file_data_ptr.* = FileData.init(name, getFileSizeAligned(ptr), try getData(a, dev, ptr, curr, size));
        return file_data_ptr;
    } else {
        return null;
    }
}

pub fn listAllFiles(a: *Allocator, dev: usize) !void {
    var cur_idx: usize = 0;
    var buf = try a.alloc(u8, 512);
    var ptr = @ptrCast([*]u8, &buf[0]);
    try virtio.read(a, dev, @ptrCast([*]u8, &buf[0]), 512, cur_idx);
    var disk_size = virtio.getDiskSectorLen(dev) * 512;
    while (isUstar(ptr) and cur_idx < disk_size) {
        var size = oct2bin(ptr + USTAR_FILE_SIZE, USTAR_SIZE_FILE_SIZE - 1);
        try uart.out.print("{s} - size: {}\n", .{ (ptr + USTAR_FILE_NAME)[0..USTAR_SIZE_FILE_NAME], size });
        cur_idx += ((size + 511) / 512 + 1) * 512;
        try virtio.read(a, dev, ptr, 512, cur_idx);
    }

    a.free(buf);
}
