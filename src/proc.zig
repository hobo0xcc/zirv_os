const std = @import("std");
const util = @import("util.zig");
const memalloc = @import("memalloc.zig");
const trap = @import("trap.zig");
const uart = @import("uart.zig");
const vm = @import("vm.zig");
const riscv = @import("riscv.zig");
const trampoline = @import("trampoline.zig");
const loader = @import("loader.zig");
const nullproc = @import("nullproc.zig");
const memlayout = @import("memlayout.zig");
const SpinLock = @import("spinlock.zig").SpinLock;
const KernelError = @import("kerror.zig").KernelError;
const Allocator = std.mem.Allocator;
const Exact = Allocator.Exact;

pub const Pid = usize;
pub const Prio = usize;
pub const PriorityQueue = std.PriorityQueue(*Process);
pub const PrioU64 = std.PriorityQueue(u64);
pub const DeltaList = std.SinglyLinkedList(ProcDelay);

pub const ProcDelay = struct {
    pid: Pid,
    delay: usize,

    pub fn init() ProcDelay {
        return ProcDelay{
            .pid = 0,
            .delay = 0,
        };
    }
};

// プロセスの状態
pub const ProcStatus = enum {
    Free, // フリー（使われていない）
    Curr, // 実行中
    Ready, // 実行可能（実行準備完了）
    Susp,
    Sleep,
};

pub const Process = struct {
    lock: SpinLock,

    prstate: ProcStatus, // プロセスの状態
    prprio: Prio, // プロセスの優先度
    prstkptr: u64, // スタックポインタ
    prstkbase: u64, // 実行時スタックのベース
    prstktop: u64, // スタックのトップのアドレス
    prstklen: usize, // スタックの長さ
    prname: []const u8, // プロセスの名前
    prparent: Pid, // 親プロセスのpid
    prpid: Pid, // 自分のpid
    ctx: Context, // 保存されたコンテキスト
    trapframe: *TrapFrame,
    page_table: *vm.Table, // プロセスのページテーブル

    pub fn init() Process {
        return Process{
            .lock = SpinLock.init(),
            .prstate = ProcStatus.Free,
            .prprio = 0,
            .prstkptr = 0,
            .prstkbase = 0,
            .prstktop = 0,
            .prstklen = 0,
            .prname = undefined,
            .prparent = 0,
            .prpid = 0,
            .ctx = Context.init(),
            .trapframe = undefined,
            .page_table = undefined,
        };
    }
};

pub const Context = packed struct {
    ra: u64,
    sp: u64,
    s0: u64,
    s1: u64,
    s2: u64,
    s3: u64,
    s4: u64,
    s5: u64,
    s6: u64,
    s7: u64,
    s8: u64,
    s9: u64,
    s10: u64,
    s11: u64,

    pub fn init() Context {
        return Context{
            .ra = 0,
            .sp = 0,
            .s0 = 0,
            .s1 = 0,
            .s2 = 0,
            .s3 = 0,
            .s4 = 0,
            .s5 = 0,
            .s6 = 0,
            .s7 = 0,
            .s8 = 0,
            .s9 = 0,
            .s10 = 0,
            .s11 = 0,
        };
    }
};

pub const TrapFrame = packed struct {
    // 0
    kernel_satp: u64,
    // 8
    kernel_sp: u64,
    // 16
    kernel_trap: u64,
    // 24
    epc: u64,
    // 32
    kernel_hartid: u64,
    // 40
    ra: u64,
    // 48
    sp: u64,
    // 56
    gp: u64,
    // 64
    tp: u64,
    // 72
    t0: u64,
    // 80
    t1: u64,
    // 88
    t2: u64,
    // 96
    s0: u64,
    // 104
    s1: u64,
    // 112
    a0: u64,
    // 120
    a1: u64,
    // 128
    a2: u64,
    // 136
    a3: u64,
    // 144
    a4: u64,
    // 152
    a5: u64,
    // 160
    a6: u64,
    // 168
    a7: u64,
    // 176
    s2: u64,
    // 184
    s3: u64,
    // 192
    s4: u64,
    // 200
    s5: u64,
    // 208
    s6: u64,
    // 216
    s7: u64,
    // 224
    s8: u64,
    // 232
    s9: u64,
    // 240
    s10: u64,
    // 248
    s11: u64,
    // 256
    t4: u64,
    // 264
    t5: u64,
    // 272
    t6: u64,
    // 280
    t7: u64,
};

const Defer = packed struct {
    ndefers: i32,
    attempt: bool,
};

const DeferStatus = enum {
    DEFER_START,
    DEFER_STOP,
};

pub const NPROC: usize = 64; // プロセスの最大数
pub const PNAMELEN: usize = 16; // プロセスの名前の最大文字数
pub const NULLPROC: usize = 0; // Nullプロセスのpid
pub const NULLSTK: usize = 8192; // Nullプロセスのスタックサイズ
pub const MINSTK = 400;
pub const DEFAULTSTK: usize = 8192;
pub const DEFAULTPRIO: usize = 10;

pub var proctab = [_]Process{Process.init()} ** NPROC;
var readylist: PriorityQueue = undefined;
var currpid: Pid = 0;
var prcount: usize = 0;
var defer_proc = Defer{ .ndefers = 0, .attempt = false };

pub var sleapq = DeltaList{};
pub var proc_delay_tab = [_]DeltaList.Node{DeltaList.Node{ .next = null, .data = ProcDelay.init() }} ** NPROC;

pub fn prioCompare(a: *Process, b: *Process) bool {
    return a.prprio > b.prprio;
}

pub fn compare(a: u64, b: u64) bool {
    return a > b;
}

pub fn init(a: *Allocator, root: *vm.Table) !void {
    readylist = PriorityQueue.init(a, prioCompare);
    var pid = NULLPROC;
    try setupProc(a, pid, NULLSTK, 0, try util.getMutStr(a, "null"), 0);
    var proc = &proctab[pid];
    try vm.map(a, proc.page_table, riscv.NULLPROC_ADDR, @ptrToInt(nullproc.nullproc), vm.PTE_R | vm.PTE_X | vm.PTE_U, 0);
    proc.trapframe.epc = riscv.NULLPROC_ADDR;
    // var proc = &proctab[NULLPROC];
    // util.memcpyConst(@ptrCast([*]u8, &proc.prname[0]), "null", 4);
    // proc.prstate = ProcStatus.Curr;
    // proc.prprio = 0;
    // var stk_ptr = try a.alloc(u8, NULLSTK);
    // proc.prstktop = @ptrToInt(&stk_ptr[0]);
    // proc.prstkbase = proc.prstktop;
    // proc.prstklen = NULLSTK;
    // proc.prstkptr = 0;
    // proc.prpid = NULLPROC;
    // var trapframe_ptr = try a.allocAdvanced(u8, 0x1000, 0x1000, Exact.at_least);
    // proc.trapframe = @ptrCast(*TrapFrame, &trapframe_ptr[0]);
    // try vm.map(a, root, riscv.NULLPROC_ADDR, @ptrToInt(nullproc.nullproc), vm.PTE_R | vm.PTE_X | vm.PTE_U, 0);
    // proc.page_table = try makePageTableForProc(a, proc);
    // proc.trapframe.epc = riscv.NULLPROC_ADDR;
    // proc.ctx.ra = @ptrToInt(trap.usertrapret);
    // var stack_arr = try memalloc.getStack(a, NULLSTK);
    // var saddr: u64 = @ptrToInt(stack_arr);
    // try mapProcPageTable(a, NULLPROC, riscv.USER_STACK_TOP, @intCast(usize, saddr), NULLSTK, vm.PTE_R | vm.PTE_W | vm.PTE_U);
    // proc.ctx.sp = saddr;
    currpid = NULLPROC;
}

// pidが無効かどうか
pub fn isBadPid(x: Pid) bool {
    return x < 0 or x >= NPROC or proctab[x].prstate == ProcStatus.Free;
}

pub fn makeDefaultProc(a: *Allocator, func: u64, name: []const u8) !Pid {
    var name_arr = try a.alloc(u8, name.len);
    for (name_arr) |*elem, i| {
        elem.* = name[i];
    }

    return try createProc(a, func, DEFAULTSTK, DEFAULTPRIO, name_arr, 0);
}

pub fn procName(a: *Allocator, name: []const u8) ![]u8 {
    var proc_name = try a.alloc(u8, name.len);
    for (name) |ch, i| {
        proc_name[i] = ch;
    }

    return proc_name;
}

pub fn newPid() KernelError!Pid {
    var i: Pid = 1;
    while (i < NPROC) : (i += 1) {
        var held = (&proctab[i].lock).acquire();
        if (proctab[i].prstate == ProcStatus.Free) {
            held.release();
            return i;
        } else {
            held.release();
        }
    }

    return KernelError.SYSERR;
}

pub fn getPid() Pid {
    return currpid;
}

pub fn getCurrProc() *Process {
    return &proctab[getPid()];
}

pub fn suspendProc(pid: Pid) !usize {
    var mask = trap.disable();
    defer trap.restore(mask);
    if (isBadPid(pid) or (pid == NULLPROC)) {
        trap.restore(mask);
        return KernelError.SYSERR;
    }

    var proc = &proctab[pid];
    if ((proc.prstate != ProcStatus.Curr) and (proc.prstate != ProcStatus.Ready)) {
        trap.restore(mask);
        return KernelError.SYSERR;
    }
    if (proc.prstate == ProcStatus.Ready) {
        var found = false;
        var idx: usize = 0;
        for (readylist.items) |pr, i| {
            if (pr.prpid == pid) {
                found = true;
                idx = i;
                break;
            }
        }
        if (found) {
            _ = readylist.removeIndex(idx);
        } else {
            return KernelError.SYSERR;
        }
    } else {
        proc.prstate = ProcStatus.Susp;
        try resched();
    }

    var prio = proc.prprio;
    return prio;
}

// for elf loader
pub fn mapProcPageTable(a: *Allocator, pid: Pid, vaddr: usize, paddr: usize, size: usize, bits: u64) !void {
    const proc = &proctab[pid];
    try vm.addrMapRange(a, proc.page_table, vaddr, paddr, size, bits);
}

// make page table with required mappings.
pub fn makePageTableForProc(a: *Allocator, proc: *Process) !*vm.Table {
    var table_arr = try a.allocAdvanced(u8, 0x1000, 0x1000, Exact.at_least);
    var table = @ptrCast(*vm.Table, &table_arr[0]);
    try vm.map(a, table, riscv.TRAMPOLINE, @ptrToInt(trampoline._trampoline), vm.PTE_R | vm.PTE_X, 0);
    // try uart.out.print("debug1: {x}, {x}\n", .{ riscv.trampoline, @ptrtoint(trampoline._trampoline) });
    try vm.map(a, table, riscv.TRAPFRAME, @ptrToInt(proc.trapframe), vm.PTE_R | vm.PTE_W, 0);
    return table;
}

pub fn exec(a: *Allocator, name: []u8) !void {
    const pid = try createProc(a, DEFAULTSTK, DEFAULTPRIO, name, 0);
    const proc = &proctab[pid];
    const entry_addr = try loader.loadExecFile(a, name, proc.page_table);
    proc.trapframe.epc = entry_addr;
    try uart.out.print("entry: {x}\n", .{entry_addr});
    _ = try resumeProc(pid);
}

pub fn setupProc(a: *Allocator, pid: Pid, stk_size: usize, prio: usize, name: []u8, nargs: usize) !void {
    var mask = trap.disable();
    defer trap.restore(mask);
    var stack_len = stk_size;
    if (stack_len < MINSTK) {
        stack_len = MINSTK;
    }
    var stack_arr = try memalloc.getStack(a, stack_len);
    var saddr: u64 = @ptrToInt(stack_arr);

    prcount += 1;
    var proc = &proctab[pid];
    // proc.ctx.ra = func;
    var trapframe_ptr = try a.allocAdvanced(u8, 0x1000, 0x1000, Exact.at_least);
    proc.trapframe = @ptrCast(*TrapFrame, &trapframe_ptr[0]);
    proc.page_table = try makePageTableForProc(a, proc);
    try mapProcPageTable(a, pid, riscv.USER_STACK_TOP - stack_len, saddr - stack_len, stack_len, vm.PTE_W | vm.PTE_R | vm.PTE_U);
    try vm.map(a, proc.page_table, memlayout.UART_BASE, memlayout.UART_BASE, vm.PTE_R | vm.PTE_W, 0);
    proc.ctx.ra = @ptrToInt(trap.usertrapret);
    proc.ctx.sp = @ptrToInt(&trap.trap_stack[0]);
    var kernel_stack = try a.allocAdvanced(u8, 0x1000, 0x1000, Exact.exact);
    var kernel_stack_top = @ptrToInt(&kernel_stack[0]) + 0x1000;
    proc.trapframe.kernel_sp = kernel_stack_top;
    proc.trapframe.sp = riscv.USER_STACK_TOP;
    proc.prstate = ProcStatus.Susp;
    proc.prprio = prio;
    proc.prpid = pid;
    proc.prstkbase = saddr;
    proc.prstklen = stack_len;
    if (name.len >= PNAMELEN) {
        return KernelError.SYSERR;
    }
    // util.memcpy(@ptrCast([*]u8, &proc.prname[0]), name, name.len);
    proc.prname = name;
    proc.prparent = getPid();
}

pub fn createProc(a: *Allocator, stk_size: usize, prio: usize, name: []u8, nargs: usize) !Pid {
    var mask = trap.disable();
    defer trap.restore(mask);

    var stack_len = stk_size;
    if (stack_len < MINSTK) {
        stack_len = MINSTK;
    }
    var pid = try newPid();
    try setupProc(a, pid, stk_size, prio, name, nargs);
    // var stack_arr = try memalloc.getStack(a, stack_len);
    // var saddr: u64 = @ptrToInt(stack_arr);

    // prcount += 1;
    // var proc = &proctab[pid];
    // // proc.ctx.ra = func;
    // var trapframe_ptr = try a.allocAdvanced(u8, 0x1000, 0x1000, Exact.at_least);
    // proc.trapframe = @ptrCast(*TrapFrame, &trapframe_ptr[0]);
    // proc.page_table = try makePageTableForProc(a, proc);
    // try mapProcPageTable(a, pid, riscv.USER_STACK_TOP - stack_len, saddr - stack_len, stack_len, vm.PTE_W | vm.PTE_R | vm.PTE_U);
    // try vm.map(a, proc.page_table, memlayout.UART_BASE, memlayout.UART_BASE, vm.PTE_R | vm.PTE_W, 0);
    // proc.ctx.ra = @ptrToInt(trap.usertrapret);
    // proc.ctx.sp = @ptrToInt(&trap.trap_stack[0]);
    // proc.trapframe.sp = riscv.USER_STACK_TOP;
    // proc.prstate = ProcStatus.Susp;
    // proc.prprio = prio;
    // proc.prpid = pid;
    // proc.prstkbase = saddr;
    // proc.prstklen = stack_len;
    // if (name.len >= PNAMELEN) {
    //     trap.restore(mask);
    //     return KernelError.SYSERR;
    // }
    // util.memcpy(@ptrCast([*]u8, &proc.prname[0]), name, name.len);
    // proc.prparent = getPid();

    return pid;
}

pub fn resumeProc(pid: Pid) !usize {
    var mask = trap.disable();
    defer trap.restore(mask);
    if (isBadPid(pid)) {
        trap.restore(mask);
        return KernelError.SYSERR;
    }

    var proc = &proctab[pid];
    if (proc.prstate != ProcStatus.Susp) {
        trap.restore(mask);
        return KernelError.SYSERR;
    }

    var prio = proc.prprio;
    try ready(pid);
    return prio;
}

pub fn sleepProc(delay: u64) !void {
    var mask = trap.disable();
    defer trap.restore(mask);

    var pid = getPid();
    proc_delay_tab[pid].data = ProcDelay{
        .pid = pid,
        .delay = delay,
    };
    var prev: ?*DeltaList.Node = null;
    var curr = sleapq.first;
    var sum: usize = 0;
    while (curr) |proc_delay| : ({
        prev = proc_delay;
        curr = proc_delay.next;
    }) {
        sum += proc_delay.data.delay;
        if (sum > proc_delay_tab[pid].data.delay) {
            break;
        }
    }

    if (prev) |insert_to| {
        proc_delay_tab[pid].data.delay -= insert_to.data.delay;
        if (curr) |after| {
            after.data.delay -= proc_delay_tab[pid].data.delay;
        }
        insert_to.insertAfter(&proc_delay_tab[pid]);
    } else {
        if (sleapq.first) |first| {
            first.data.delay -= proc_delay_tab[pid].data.delay;
        }
        proc_delay_tab[pid].next = sleapq.first;
        sleapq.first = &proc_delay_tab[pid];
    }

    proctab[pid].prstate = ProcStatus.Sleep;
    try resched();
}

pub fn wakeupProc() !void {
    try reschedCtrl(DeferStatus.DEFER_START);
    var pid = getPid();
    while (sleapq.first) |node| {
        if (node.data.delay == 0) {
            try ready(sleapq.popFirst().?.data.pid);
        } else {
            break;
        }
    }

    try reschedCtrl(DeferStatus.DEFER_STOP);
}

pub fn ready(pid: Pid) !void {
    if (isBadPid(pid)) {
        return KernelError.SYSERR;
    }
    var proc: *Process = &proctab[pid];
    proc.prstate = ProcStatus.Ready;
    try readylist.add(proc);
    try resched();
}

comptime {
    asm (
        \\swtch:
        \\ sd ra, 0(a0)
        \\ sd sp, 8(a0)
        \\ sd s0, 16(a0)
        \\ sd s1, 24(a0)
        \\ sd s2, 32(a0)
        \\ sd s3, 40(a0)
        \\ sd s4, 48(a0)
        \\ sd s5, 56(a0)
        \\ sd s6, 64(a0)
        \\ sd s7, 72(a0)
        \\ sd s8, 80(a0)
        \\ sd s9, 88(a0)
        \\ sd s10, 96(a0)
        \\ sd s11, 104(a0)
        \\ ld ra, 0(a1)
        \\ ld sp, 8(a1)
        \\ ld s0, 16(a1)
        \\ ld s1, 24(a1)
        \\ ld s2, 32(a1)
        \\ ld s3, 40(a1)
        \\ ld s4, 48(a1)
        \\ ld s5, 56(a1)
        \\ ld s6, 64(a1)
        \\ ld s7, 72(a1)
        \\ ld s8, 80(a1)
        \\ ld s9, 88(a1)
        \\ ld s10, 96(a1)
        \\ ld s11, 104(a1)
        \\ ret
    );
}

pub extern fn swtch(old_ctx: u64, new_ctx: u64) void;

pub fn resched() !void {
    if (defer_proc.ndefers > 0) {
        defer_proc.attempt = true;
        return;
    }

    trap.intrOn();

    var old_proc = &proctab[currpid];
    if (old_proc.prstate == ProcStatus.Curr) {
        if (readylist.len == 0) {
            return;
        }
        if (old_proc.prprio > readylist.peek().?.prprio) {
            return;
        }

        old_proc.prstate = ProcStatus.Ready;
        try readylist.add(old_proc);
    }

    var new_proc = readylist.remove();
    currpid = new_proc.prpid;
    new_proc.prstate = ProcStatus.Curr;

    // try uart.out.print("Context switch: {} -> {}\n", .{ old_proc.prpid, new_proc.prpid });
    try uart.out.print("Debug1: resched: old_proc.pid: {}, new_proc.pid: {}, new_proc.ctx.ra: {x}\n", .{ old_proc.prpid, new_proc.prpid, new_proc.ctx.ra });
    swtch(@ptrToInt(&old_proc.ctx), @ptrToInt(&new_proc.ctx));
}

pub fn reschedCtrl(defer_status: DeferStatus) !void {
    switch (defer_status) {
        .DEFER_START => {
            if (defer_proc.ndefers == 0) {
                defer_proc.attempt = false;
            }
            defer_proc.ndefers += 1;
            return;
        },
        .DEFER_STOP => {
            if (defer_proc.ndefers <= 0) {
                return KernelError.SYSERR;
            }
            defer_proc.ndefers -= 1;
            if ((defer_proc.ndefers == 0) and defer_proc.attempt) {
                try resched();
            }
            return;
        },
    }
}
