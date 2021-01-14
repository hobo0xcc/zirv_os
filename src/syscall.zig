const trap = @import("trap.zig");
const uart = @import("uart.zig");
const vm = @import("vm.zig");
const std = @import("std");
const fs = @import("fs.zig");
const panic = @import("panic.zig").panic;
const proc = @import("proc.zig");
const csr = @import("csr.zig");
const util = @import("util.zig");
const memalloc = @import("memalloc.zig");
const Allocator = std.mem.Allocator;
const KernelError = @import("kerror.zig").KernelError;

pub const SysCallArgs = struct {
    a1: u64,
    a2: u64,
    a3: u64,
    a4: u64,
    a5: u64,
    a6: u64,
    a7: u64,
};

pub var env: *SysCall = undefined;

pub const SysCall = struct {
    root_table: *vm.Table,
    a: *Allocator,

    pub fn init(root_table: *vm.Table, a: *Allocator) SysCall {
        return SysCall{
            .root_table = root_table,
            .a = a,
        };
    }

    pub fn getProcPageTable(self: *SysCall) *vm.Table {
        return proc.getCurrProc().page_table;
    }

    pub fn sysWrite(self: *SysCall, dev: u64, virt_ptr: u64, size: u64) void {
        var page_table = self.getProcPageTable();
        var ptr = vm.virtToPhys(page_table, virt_ptr).?;
        if (dev == 0) {
            _ = try uart.out.write(@intToPtr([*]u8, ptr)[0..size]);
            // try uart.out.print("dev: {}, ptr: {x}, size: {}\n", .{ dev, ptr, size });
        }
    }

    pub fn sysRead(self: *SysCall, dev: u64, virt_buf: u64, size: u64) void {
        var page_table = self.getProcPageTable();
        var buf = vm.virtToPhys(page_table, virt_buf);
        if (buf == null) {
            panic("cannot translate addr: {x}\n", .{virt_buf});
        }
        if (dev == 0) {
            _ = try uart.in.read(@intToPtr([*]u8, buf.?)[0..size]);
        }
    }

    pub fn sysReadFile(self: *SysCall, dev: u64, buf: u64, name: u64, size: u64) !void {
        var idx: usize = 0;
        var name_ptr = @intToPtr([*]u8, name);
        while (name_ptr[idx] != 0) : (idx += 1) {}
        _ = try fs.loadFileDataIntoBuf(self.a, dev, @intToPtr([*]u8, buf), name_ptr[0..idx], size);
    }

    pub fn sysGetPid(self: *SysCall, addr: u64) void {
        var ptr = @intToPtr(*proc.Pid, addr);
        ptr.* = proc.getPid();
    }

    pub fn sysResumeProc(self: *SysCall, pid: u64) !void {
        _ = try proc.resumeProc(@intCast(usize, pid));
    }

    pub fn sysCreateProc(self: *SysCall, func: u64, stack_size: u64, prio: u64, name: u64, pid_addr: u64) !void {
        var name_ptr = @intToPtr([*]u8, name);
        var idx: usize = 0;
        while (name_ptr[idx] != 0) : (idx += 1) {}
        // var pid = try proc.createProc(self.a, stack_size, prio, name_ptr[0..idx], 0);
        // var pid_ptr = @intToPtr(*usize, pid_addr);
        // pid_ptr.* = pid;
    }

    pub fn sysSleepProc(self: *SysCall, delay: u64) !void {
        try proc.sleepProc(delay);
    }

    pub fn sysSuspendProc(self: *SysCall, pid: u64) !void {
        _ = try proc.suspendProc(@intCast(proc.Pid, pid));
    }

    pub fn sysExec(self: *SysCall, cmd: u64) !void {
        var page_table = self.getProcPageTable();
        var cmd_paddr = vm.virtToPhys(page_table, cmd);
        if (cmd_paddr == null) {
            panic("cannot translate addr: {x}\n", .{cmd});
        }
        const ptr = @intToPtr([*]u8, cmd_paddr.?);
        try proc.exec(self.a, util.getStrFromCStr(ptr));
    }

    pub fn sysExit(self: *SysCall) !void {
        try proc.exitProc(proc.getPid());
    }

    pub fn execSysCall(self: *SysCall, syscall_number: u64, regs: *const SysCallArgs) void {
        _ = switch (syscall_number) {
            1 => {
                self.sysWrite(regs.a1, regs.a2, regs.a3);
            },
            2 => {
                self.sysRead(regs.a1, regs.a2, regs.a3);
            },
            3 => {
                self.sysReadFile(regs.a1, regs.a2, regs.a3, regs.a4) catch {};
            },
            4 => {
                self.sysGetPid(regs.a1);
            },
            5 => {
                self.sysResumeProc(regs.a1) catch {};
            },
            6 => {
                self.sysCreateProc(regs.a1, regs.a2, regs.a3, regs.a4, regs.a5) catch {};
            },
            7 => {
                self.sysSleepProc(regs.a1) catch {};
            },
            8 => {
                self.sysSuspendProc(regs.a1) catch {};
            },
            9 => {
                self.sysExec(regs.a1) catch {};
            },
            10 => {
                self.sysExit() catch {};
            },
            else => {
                panic("unknown syscall: {}\n", .{syscall_number});
                // return KernelError.SYSERR;
            },
        };
    }
};
