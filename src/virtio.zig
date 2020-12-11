const std = @import("std");
const memlayout = @import("memlayout.zig");
const memalloc = @import("memalloc.zig");
const riscv = @import("riscv.zig");
const uart = @import("uart.zig");
const KernelError = @import("kerror.zig").KernelError;
const panic = @import("panic.zig").panic;
const util = @import("util.zig");
const Allocator = std.mem.Allocator;

const VIRTIO_RING_SIZE: usize = 1 << 7;

const VIRTIO_MMIO_MAGIC_VALUE: usize = 0x000;
const VIRTIO_MMIO_VERSION: usize = 0x004;
const VIRTIO_MMIO_DEVICE_ID: usize = 0x008;
const VIRTIO_MMIO_VENDOR_ID: usize = 0x00c;
const VIRTIO_MMIO_DEVICE_FEATURES: usize = 0x010;
const VIRTIO_MMIO_DEVICE_FEATURES_SEL: usize = 0x014;
const VIRTIO_MMIO_DRIVER_FEATURES: usize = 0x020;
const VIRTIO_MMIO_DRIVER_FEATURES_SEL: usize = 0x024;
const VIRTIO_MMIO_DRIVER_PAGE_SIZE: usize = 0x028;
const VIRTIO_MMIO_QUEUE_SEL: usize = 0x030;
const VIRTIO_MMIO_QUEUE_NUM_MAX: usize = 0x034;
const VIRTIO_MMIO_QUEUE_NUM: usize = 0x038;
const VIRTIO_MMIO_QUEUE_PFN: usize = 0x040;
const VIRTIO_MMIO_QUEUE_READY: usize = 0x044;
const VIRTIO_MMIO_QUEUE_NOTIFY: usize = 0x050;
const VIRTIO_MMIO_INTERRUPT_STATUS: usize = 0x060;
const VIRTIO_MMIO_INTERRUPT_ACK: usize = 0x064;
const VIRTIO_MMIO_STATUS: usize = 0x070;
const VIRTIO_MMIO_QUEUE_DESC: usize = 0x080;
const VIRTIO_MMIO_QUEUE_DRIVER: usize = 0x090;
const VIRTIO_MMIO_QUEUE_DEVICE: usize = 0x0a0;

const VIRTIO_CONFIG_ACKNOWLEDGE: u32 = 1;
const VIRTIO_CONFIG_DRIVER: u32 = 2;
const VIRTIO_CONFIG_FAILED: u32 = 128;
const VIRTIO_CONFIG_FEATURES_OK: u32 = 8;
const VIRTIO_CONFIG_DRIVER_OK: u32 = 4;
const VIRTIO_CONFIG_DEVICE_NEEDS_RESET: u32 = 64;

const VIRTIO_BLK_F_SIZE_MAX: usize = 1;
const VIRTIO_BLK_F_SEG_MAX: usize = 2;
const VIRTIO_BLK_F_GEOMETRY: usize = 4;
const VIRTIO_BLK_F_RO: usize = 5;
const VIRTIO_BLK_F_BLK_SIZE: usize = 6;
const VIRTIO_BLK_F_FLUSH: usize = 9;
const VIRTIO_BLK_TOPOLOGY: usize = 10;
const VIRTIO_BLK_F_CONFIG_WCE: usize = 11;
const VIRTIO_BLK_F_DISCARD: usize = 13;
const VIRTIO_BLK_F_WRITE_ZEROES: usize = 14;
const VIRTIO_BLK_T_IN: usize = 0;
const VIRTIO_BLK_T_OUT: usize = 1;
const VIRTIO_BLK_T_FLUSH: usize = 4;
const VIRTIO_BLK_T_DISCARD: usize = 11;
const VIRTIO_BLK_T_WRITE_ZEROES: usize = 13;
const VIRTIO_BLK_S_OK: u8 = 0;
const VIRTIO_BLK_S_IOERR: u8 = 1;
const VIRTIO_BLK_S_UNSUPP: u8 = 2;

const VIRTIO_DESC_F_NEXT: u16 = 1;
const VIRTIO_DESC_F_WRITE: u16 = 2;
const VIRTIO_DESC_F_INDIRECT: u16 = 4;

const VirtioRegs = packed struct {
    MagicValue: u32, // 0x000
    Version: u32, // 0x004
    DeviceID: u32, // 0x008
    VecdorID: u32, // 0x00c
    DeviceFeatures: u32, // 0x010
    DeviceFeaturesSel: u32, // 0x014
    _reserved0: [2]u32,
    DriverFeatures: u32, // 0x020
    DriverFeaturesSel: u32, // 0x024
    _reserved1: [2]u32,
    QueueSel: u32, // 0x030
    QueueNumMax: u32, // 0x034
    QueueNum: u32, // 0x038
    _reserved2: [2]u32,
    QueueReady: u32, // 0x044
    _reserved3: [2]u32,
    QueueNotify: u32, // 0x050
    InterruptStatus: u32, // 0x060
    InterruptACK: u32, // 0x064
    _reserved4: [2]u32,
    Status: u32, // 0x070
    QueueDesc: u64, // 0x080
    _reserved5: [2]u32,
    QueueDriver: u64, // 0x090
    _reserved6: [2]u32,
    QueueDevice: u64,
};

pub const Descriptor = packed struct {
    addr: u64,
    len: u32,
    flags: u16,
    next: u16,

    pub fn init(addr: u64, len: u32, flags: u16, next: u16) Descriptor {
        return Descriptor{
            .addr = addr,
            .len = len,
            .flags = flags,
            .next = next,
        };
    }
};

pub const Available = packed struct {
    flags: u16,
    idx: u16,
    ring: [VIRTIO_RING_SIZE]u16,
    event: u16,

    pub fn init(flags: u16, idx: u16, event: u16) Available {
        return Available{
            .flags = flags,
            .idx = idx,
            .ring = [_]u16{0} ** VIRTIO_RING_SIZE,
            .event = event,
        };
    }
};

pub const UsedElem = packed struct {
    id: u32,
    len: u32,

    pub fn init(id: u32, len: u32) UsedElem {
        return UsedElem{
            .id = id,
            .len = len,
        };
    }
};

pub const Used = packed struct {
    flags: u16,
    idx: u16,
    ring: [VIRTIO_RING_SIZE]UsedElem,
    event: u16,

    pub fn init(flags: u16, idx: u16, event: u16) Used {
        return Used{
            .flags = flags,
            .idx = idx,
            .ring = [_]UsedElem{UsedElem.init(0, 0)} ** VIRTIO_RING_SIZE,
            .event = event,
        };
    }
};

pub const Queue = packed struct {
    desc: [*]Descriptor,
    avail: *Available,
    used: *Used,

    pub fn init(desc: [*]Descriptor, avail: *Available, used: *Used) Queue {
        return Queue{
            .desc = desc,
            .avail = avail,
            .used = used,
        };
    }
};

const VirtioBlkReq = packed struct {
    type_: u32,
    reserved: u32,
    sector: u64,
};

fn readReg32(ptr: usize, offset: usize) u32 {
    var addr = ptr + offset;
    return @intToPtr(*u32, addr).*;
}

fn readReg64(ptr: usize, offset: usize) u64 {
    var addr = ptr + offset;
    return @intToPtr(*u64, addr).*;
}

fn writeReg32(ptr: usize, offset: usize, val: u32) void {
    var addr = ptr + offset;
    @intToPtr(*u32, addr).* = val;
}

fn writeReg64(ptr: usize, offset: usize, val: u32) void {
    var addr = ptr + offset;
    @intToPtr(*u64, addr).* = val;
}

pub const BlockDevice = struct {
    addr: usize,
    queue: *Queue,
    idx: u16,
    ack_used_idx: u16, // last acknowledged index of the used ring
    read_only: bool,
    free: [VIRTIO_RING_SIZE]bool,
    status: [VIRTIO_RING_SIZE]u8,

    pub fn init(addr: usize, queue: *Queue, read_only: bool) BlockDevice {
        return BlockDevice{
            .addr = addr,
            .queue = queue,
            .idx = 0,
            .ack_used_idx = 0,
            .read_only = read_only,
            .free = [_]bool{true} ** VIRTIO_RING_SIZE,
            .status = [_]u8{0} ** VIRTIO_RING_SIZE,
        };
    }
};

pub const disk_idx: usize = 0;
var block_devices = [_]?BlockDevice{null} ** memlayout.VIRTIO_SIZE_IDX;

pub fn setupVirtioBlk(ptr: usize) !void {
    // 3.1.1 Driver Requirements: Device Initialization
    if (readReg32(ptr, VIRTIO_MMIO_MAGIC_VALUE) != 0x74726976 or
        readReg32(ptr, VIRTIO_MMIO_VERSION) != 0x2 or
        readReg32(ptr, VIRTIO_MMIO_DEVICE_ID) != 2)
    {
        panic("Can't initialize virtio-blk device.", .{});
    }

    var status_bits: u32 = 0;

    // 2. Set the ACKNOWLEDGE status bit: the
    // guest OS has noticed the device.
    status_bits |= VIRTIO_CONFIG_ACKNOWLEDGE;
    writeReg32(ptr, VIRTIO_MMIO_STATUS, status_bits);
    // 3. Set the DRIVER status bit: the guest
    // OS knows how to drive the device.
    status_bits |= VIRTIO_CONFIG_DRIVER;
    writeReg32(ptr, VIRTIO_MMIO_STATUS, status_bits);
    // 4. Read device feature bits, and write the
    // subset of feature bits understood by the OS
    // and driver to the device. During this step
    // the driver MAY read (but MUST NOT write)
    // the device-specific configuration fields
    // to check that it can support the device
    // before accepting it.
    var features = readReg32(ptr, VIRTIO_MMIO_DEVICE_FEATURES);
    features &= ~@intCast(u32, 1 << VIRTIO_BLK_F_RO);
    features &= ~@intCast(u32, 1 << VIRTIO_BLK_F_CONFIG_WCE);
    writeReg32(ptr, VIRTIO_MMIO_DEVICE_FEATURES, features);
    // 5. Set the FEATURES_OK status bit. The
    // driver MUST NOT accept new feature bits after this step.
    status_bits |= VIRTIO_CONFIG_FEATURES_OK;
    writeReg32(ptr, VIRTIO_MMIO_STATUS, status_bits);
    // 6. Re-read device status to ensure the
    // FEATURES_OK bit is still set: otherwise,
    // the device does not support our subset of
    // features and the device is unusable.
    if ((readReg32(ptr, VIRTIO_MMIO_STATUS) & VIRTIO_CONFIG_FEATURES_OK) == 0) {
        writeReg32(ptr, VIRTIO_MMIO_STATUS, VIRTIO_CONFIG_FAILED);
        panic("Your virtio-blk does not support the required features.\n", .{});
    }

    // 7. Perform device-specific setup,
    // including discovery of virtqueues for the
    // device, optional per-bus setup, reading
    // and possibly writing the device's virtio
    // configuration space, and population of virtqueues.

    // 4.2.3.2 Virtqueue Configuration
    // 1. Select the queue writing its index (first queue is 0) to QueueSel.
    writeReg32(ptr, VIRTIO_MMIO_QUEUE_SEL, 0);
    // 2. Check if the queue is not already
    // in use: read QueueReady, and expect
    // a returned value of zero (0x0).
    if (readReg32(ptr, VIRTIO_MMIO_QUEUE_READY) != 0) {
        panic("Queue is already in use.\n", .{});
    }
    // 3. Read maximum queue size
    // (number of elements) from QueueNumMax.
    // If the returned value is zero (0x0)
    // the queue is not available.
    const queue_num_max = readReg32(ptr, VIRTIO_MMIO_QUEUE_NUM_MAX);
    if (queue_num_max == 0) {
        panic("Queue is not available.\n", .{});
    } else if (queue_num_max < VIRTIO_RING_SIZE) {
        panic("QueueNumMax too short.\n", .{});
    }

    // 4. Allocate and zero the queue memory,
    // making sure the memory is physically contiguous.
    var desc_ptr = try memalloc.a.allocAdvanced(u8, 16, 16 * VIRTIO_RING_SIZE, .exact);
    var desc = @ptrCast([*]Descriptor, &desc_ptr[0]);
    var i: usize = 0;
    while (i < VIRTIO_RING_SIZE) : (i += 1) {
        desc[i] = Descriptor.init(0, 0, 0, 0);
    }
    var avail_ptr = try memalloc.a.allocAdvanced(u8, 2, 6 + 2 * VIRTIO_RING_SIZE, .exact);
    var avail = @ptrCast(*Available, &avail_ptr[0]);
    avail.* = Available.init(0, 0, 0);
    var used_ptr = try memalloc.a.allocAdvanced(u8, 2, 6 + 8 * VIRTIO_RING_SIZE, .exact);
    var used = @ptrCast(*Used, &used_ptr[0]);
    used.* = Used.init(0, 0, 0);
    var virtqueue = try memalloc.a.alloc(Queue, 1);
    virtqueue[0] = Queue.init(desc, avail, used);
    // 5. Notify the device about the queue size by writing the size to QueueNum.
    writeReg32(ptr, VIRTIO_MMIO_QUEUE_NUM, VIRTIO_RING_SIZE);
    // 6. Write physical addresses of
    // the queue's Descriptor Area, Driver Area
    // and Device Area to (respectively)
    // the QueueDescLow/QueueDescHigh,
    // QueueDriverLow/QueueDriverHigh and
    // QueueDeviceLow/QueueDeviceHigh register pairs.
    writeReg64(ptr, VIRTIO_MMIO_QUEUE_DESC, @intCast(u32, @ptrToInt(virtqueue[0].desc)));
    writeReg64(ptr, VIRTIO_MMIO_QUEUE_DRIVER, @intCast(u32, @ptrToInt(virtqueue[0].avail)));
    writeReg64(ptr, VIRTIO_MMIO_QUEUE_DEVICE, @intCast(u32, @ptrToInt(virtqueue[0].used)));
    // 7. Write 0x1 to QueueReady.
    writeReg32(ptr, VIRTIO_MMIO_QUEUE_READY, 0x1);

    // 3.1.1 Driver Requirements: Device Initialization
    // 8. Set the DRIVER_OK status bit. At this point the device is “live”.
    status_bits |= VIRTIO_CONFIG_DRIVER_OK;
    writeReg32(ptr, VIRTIO_MMIO_STATUS, status_bits);

    const idx = (ptr - memlayout.VIRTIO_BASE) >> 12;
    block_devices[idx] = BlockDevice.init(ptr, &virtqueue[0], false);
}

// fn setupVirtioBlk(a: *Allocator, ptr: usize) !void {
//     const idx = (ptr - memlayout.VIRTIO_BASE) >> 12;
//     writeReg32(ptr, VIRTIO_MMIO_STATUS, 0);
//     var status_bits = VIRTIO_CONFIG_ACKNOWLEDGE;
//     writeReg32(ptr, VIRTIO_MMIO_STATUS, status_bits);
//     status_bits |= VIRTIO_CONFIG_DRIVER_OK;
//     writeReg32(ptr, VIRTIO_MMIO_STATUS, status_bits);
//     const host_features = readReg32(ptr, VIRTIO_MMIO_DEVICE_FEATURES);
//     const guest_features = host_features & ~(@as(usize, 1) << VIRTIO_BLK_F_RO);
//     const readonly = host_features & (@as(usize, 1) << VIRTIO_BLK_F_RO) != 0;
//     writeReg32(ptr, VIRTIO_MMIO_DRIVER_FEATURES, @intCast(u32, guest_features));
//     status_bits |= VIRTIO_CONFIG_FEATURES_OK;
//     writeReg32(ptr, VIRTIO_MMIO_STATUS, status_bits);
//     const status_ok = readReg32(ptr, VIRTIO_MMIO_STATUS);
//     if (status_ok & VIRTIO_CONFIG_FEATURES_OK == 0) {
//         writeReg32(ptr, VIRTIO_MMIO_STATUS, VIRTIO_CONFIG_FAILED);
//         return KernelError.SYSERR;
//     }
//
//     const queue_num_max = readReg32(ptr, VIRTIO_MMIO_QUEUE_NUM_MAX);
//     writeReg32(ptr, VIRTIO_MMIO_QUEUE_NUM, @intCast(u32, VIRTIO_RING_SIZE));
//     if (@intCast(u32, VIRTIO_RING_SIZE) > queue_num_max) {
//         return KernelError.SYSERR;
//     }
//     writeReg32(ptr, VIRTIO_MMIO_QUEUE_READY, 1);
//
//     const num_pages = (@sizeOf(Queue) + riscv.PAGE_SIZE - 1) / riscv.PAGE_SIZE;
//     writeReg32(ptr, VIRTIO_MMIO_QUEUE_SEL, 0);
//     var queue_arr = try a.alloc(u8, riscv.PAGE_SIZE * num_pages);
//     util.memset(queue_arr, 0);
//     var queue_ptr = @ptrCast(*Queue, &queue_arr[0]);
//     var queue_pfn = @intCast(u32, @ptrToInt(queue_ptr));
//     writeReg32(ptr, VIRTIO_MMIO_DRIVER_PAGE_SIZE, @intCast(u32, riscv.PAGE_SIZE));
//     writeReg32(ptr, VIRTIO_MMIO_QUEUE_PFN, (queue_pfn / @intCast(u32, riscv.PAGE_SIZE)));
//     block_devices[idx] = BlockDevice{
//         .addr = ptr,
//         .queue = queue_ptr,
//         .idx = 0,
//         .ack_used_idx = 0,
//         .read_only = readonly,
//         .free = [_]bool{true} ** VIRTIO_RING_SIZE,
//         .status = [_]u8{0} ** VIRTIO_RING_SIZE,
//     };
//     status_bits |= VIRTIO_CONFIG_DRIVER_OK;
//     writeReg32(ptr, VIRTIO_MMIO_STATUS, status_bits);
// }

pub fn allocDesc(bdev: *BlockDevice) ?u16 {
    for (bdev.free) |*is_free, idx| {
        if (is_free.*) {
            is_free.* = false;
            return @intCast(u16, idx);
        }
    }

    return null;
}

pub fn freeDesc(bdev: *BlockDevice, id: u16) void {
    bdev.free[id] = true;
}

pub fn allocNDesc(bdev: *BlockDevice, n: usize, idxes: [*]u16) bool {
    var i: usize = 0;
    var failed = false;
    while (i < n) : (i += 1) {
        if (allocDesc(bdev)) |id| {
            idxes[i] = id;
        } else {
            failed = true;
            break;
        }
    }

    if (failed) {
        var j: usize = 0;
        while (j <= i) : (j += 1) {
            freeDesc(bdev, @intCast(u16, j));
        }

        return false;
    }

    return true;
}

pub fn writeDescTab(bdev: *BlockDevice, desc: Descriptor, idx: u16) void {
    bdev.queue.desc[idx] = desc;
}

pub fn blockOp(a: *Allocator, dev_id: usize, buffer: [*]u8, size: u32, offset: u64, write_flag: bool) !void {
    if (block_devices[dev_id - 1] != null) {
        var bdev = &block_devices[dev_id - 1].?;
        if (bdev.read_only and write_flag) {
            panic("Trying too write to read-only\n", .{});
        }

        const sector = offset / 512;
        const blk_request_size = @sizeOf(VirtioBlkReq);
        var blk_req_arr = try a.alloc(u8, blk_request_size);
        const blk_request = @ptrCast(*VirtioBlkReq, &blk_req_arr[0]);
        var desc_idxes_addr = try a.alloc(u16, 3);
        var desc_idxes = @ptrCast([*]u16, &desc_idxes_addr[0]);
        if (!allocNDesc(bdev, 3, desc_idxes)) {
            return KernelError.SYSERR;
        }
        const desc0 = Descriptor{
            .addr = @ptrToInt(blk_request),
            .len = @sizeOf(VirtioBlkReq),
            .flags = VIRTIO_DESC_F_NEXT,
            .next = desc_idxes[1],
        };
        writeDescTab(bdev, desc0, desc_idxes[0]);
        blk_request.sector = sector;
        if (write_flag) {
            blk_request.type_ = VIRTIO_BLK_T_OUT;
        } else {
            blk_request.type_ = VIRTIO_BLK_T_IN;
        }
        // blk_request.data = buffer;
        // blk_request.status = 0xff;
        var flags1 = VIRTIO_DESC_F_NEXT;
        if (!write_flag) {
            flags1 |= VIRTIO_DESC_F_WRITE;
        }
        const desc1 = Descriptor{
            .addr = @ptrToInt(buffer),
            .len = size,
            .flags = flags1,
            .next = desc_idxes[2],
        };
        writeDescTab(bdev, desc1, desc_idxes[1]);
        const desc2 = Descriptor{
            .addr = @ptrToInt(&bdev.status[desc_idxes[0]]),
            .len = 1,
            .flags = VIRTIO_DESC_F_WRITE,
            .next = 0,
        };
        writeDescTab(bdev, desc2, desc_idxes[2]);

        var idx = @intCast(usize, bdev.queue.avail.idx % VIRTIO_RING_SIZE);
        var ring_ptr = @ptrCast([*]align(1:0:2048) u16, &bdev.queue.avail.ring[0]);
        // ring_ptr[idx] = desc_idxes[0];
        bdev.queue.avail.ring[idx] = desc_idxes[0];
        bdev.queue.avail.idx += 1;
        writeReg32(bdev.addr, VIRTIO_MMIO_QUEUE_NOTIFY, 0);
        // try uart.out.print("addr: {x}, status: {x}\n", .{ bdev.addr, readReg32(bdev.addr, VIRTIO_MMIO_STATUS) });
    }
}

pub fn read(dev: usize, buffer: [*]u8, size: u32, offset: u64) !void {
    try blockOp(memalloc.a, dev, buffer, size, offset, false);
}

pub fn write(dev: usize, buffer: [*]u8, size: u32, offset: u64) !void {
    try blockOp(memalloc.a, dev, buffer, size, offset, true);
}

pub fn init(a: *Allocator) !void {
    var virtio_ptr = memlayout.VIRTIO_BASE;
    while (virtio_ptr < memlayout.VIRTIO_BASE + memlayout.VIRTIO_SIZE) : (virtio_ptr += 0x1000) {
        var magic_value = readReg32(virtio_ptr, VIRTIO_MMIO_MAGIC_VALUE);
        var device_id = readReg32(virtio_ptr, VIRTIO_MMIO_DEVICE_ID);
        if (magic_value != 0x74726976) {
            continue;
        }
        try uart.out.print("addr: {x}, device_id: {}\n", .{ virtio_ptr, device_id });

        if (device_id == 2) {
            try uart.out.print("Block Device: 0x{x}\n", .{virtio_ptr});
            try setupVirtioBlk(virtio_ptr);
        }
    }
}

pub fn pending(a: *Allocator, bdev: *BlockDevice) void {
    while (bdev.ack_used_idx != bdev.queue.used.idx) {
        var idx = @intCast(usize, bdev.ack_used_idx);
        var ring_ptr = @ptrCast([*]UsedElem, &bdev.queue.used.ring[0]);
        var elem = bdev.queue.used.ring[idx];
        bdev.ack_used_idx = @intCast(u16, (bdev.ack_used_idx + 1) % VIRTIO_RING_SIZE);
        var request_ptr = @intToPtr([*]u8, bdev.queue.desc[elem.id].addr);
        var request_arr = request_ptr[0..bdev.queue.desc[elem.id].len];
        a.free(request_arr);
    }
}

pub fn interrupt(intr_id: u32) !void {
    const idx = @intCast(usize, intr_id - 1);
    if (block_devices[idx]) |*bdev| {
        pending(memalloc.a, bdev);
    } else {
        try uart.out.print("Invalid virtio device: {}\n", .{idx});
    }
}
