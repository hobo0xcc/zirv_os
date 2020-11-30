const std = @import("std");
const SpinLock = @import("spinlock.zig").SpinLock;
const util = @import("util.zig");
const memalloc = @import("memalloc.zig");
const trap = @import("trap.zig");
const uart = @import("uart.zig");
const KernelError = @import("kerror.zig").KernelError;
const Allocator = std.mem.Allocator;

pub const Pid = usize;
pub const Prio = usize;
pub const PriorityQueue = std.PriorityQueue(*ProcEntry);
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

// プロセスのエントリ
pub const ProcEntry = struct {
    lock: SpinLock,

    prstate: ProcStatus, // プロセスの状態
    prprio: Prio, // プロセスの優先度
    prstkptr: u64, // スタックポインタ
    prstkbase: u64, // 実行時スタックのベース
    prstktop: u64, // スタックのトップのアドレス
    prstklen: usize, // スタックの長さ
    prname: [PNAMELEN]u8, // プロセスの名前
    prparent: Pid, // 親プロセスのpid
    prpid: Pid, // 自分のpid
    ctx: Context,

    pub fn init() ProcEntry {
        return ProcEntry{
            .lock = SpinLock.init(),
            .prstate = ProcStatus.Free,
            .prprio = 0,
            .prstkptr = 0,
            .prstkbase = 0,
            .prstktop = 0,
            .prstklen = 0,
            .prname = [_]u8{0} ** PNAMELEN,
            .prparent = 0,
            .prpid = 0,
            .ctx = Context.init(),
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

var proctab = [_]ProcEntry{ProcEntry.init()} ** NPROC;
var readylist: PriorityQueue = undefined;
var currpid: Pid = 0;
var prcount: usize = 0;
var defer_proc = Defer{ .ndefers = 0, .attempt = false };
pub var sleapq = DeltaList{};
pub var proc_delay_tab = [_]DeltaList.Node{DeltaList.Node{ .next = null, .data = ProcDelay.init() }} ** NPROC;

pub fn prioCompare(a: *ProcEntry, b: *ProcEntry) bool {
    return a.prprio > b.prprio;
}

pub fn compare(a: u64, b: u64) bool {
    return a > b;
}

pub fn init(a: *Allocator) !void {
    readylist = PriorityQueue.init(a, prioCompare);
    var proc = &proctab[NULLPROC];
    util.memcpyConst(@ptrCast([*]u8, &proc.prname[0]), "prnull", 6);
    proc.prstate = ProcStatus.Curr;
    proc.prprio = 0;
    var stk_ptr = try a.alloc(u8, NULLSTK);
    proc.prstktop = @ptrToInt(&stk_ptr[0]);
    proc.prstkbase = proc.prstktop;
    proc.prstklen = NULLSTK;
    proc.prstkptr = 0;
    proc.prpid = NULLPROC;
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

pub fn createProc(allocator: *Allocator, func: u64, stk_size: usize, prio: usize, name: []u8, nargs: usize) !Pid {
    var mask = trap.disable();
    defer trap.restore(mask);
    var stack_len = stk_size;
    if (stack_len < MINSTK) {
        stack_len = MINSTK;
    }

    var pid = try newPid();
    var stack_arr = try memalloc.getStack(allocator, stack_len);
    var saddr: u64 = @ptrToInt(stack_arr);

    prcount += 1;
    var proc = &proctab[pid];
    proc.prstate = ProcStatus.Susp;
    proc.prprio = prio;
    proc.prpid = pid;
    proc.prstkbase = saddr;
    proc.prstklen = stack_len;
    proc.ctx.ra = func;
    proc.ctx.sp = saddr;
    if (name.len >= PNAMELEN) {
        trap.restore(mask);
        return KernelError.SYSERR;
    }
    util.memcpy(@ptrCast([*]u8, &proc.prname[0]), name, name.len);
    proc.prparent = getPid();

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
    try resched_ctrl(DeferStatus.DEFER_START);
    var pid = getPid();
    while (sleapq.first) |node| {
        if (node.data.delay == 0) {
            try ready(sleapq.popFirst().?.data.pid);
        } else {
            break;
        }
    }

    try resched_ctrl(DeferStatus.DEFER_STOP);
}

pub fn ready(pid: Pid) !void {
    if (isBadPid(pid)) {
        return KernelError.SYSERR;
    }
    var proc: *ProcEntry = &proctab[pid];
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
        \\ ld t6, 0(a1)
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
        \\ jr t6
    );
}

pub extern fn swtch(old_ctx: u64, new_ctx: u64) void;

pub fn resched() !void {
    if (defer_proc.ndefers > 0) {
        defer_proc.attempt = true;
    }

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
    swtch(@ptrToInt(&old_proc.ctx), @ptrToInt(&new_proc.ctx));
}

pub fn resched_ctrl(defer_status: DeferStatus) !void {
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
