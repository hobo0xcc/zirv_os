const csr = @import("csr.zig");
const main = @import("main.zig");
const uart = @import("uart.zig");
const trap = @import("trap.zig");
const timer = @import("timer.zig");

const StackTrace = struct {
    index: usize,
    instruction_addresses: [*]usize,
};

pub var ins_addrs = [_]usize{0} ** 0x1000;

pub export var stack_trace = StackTrace{
    .index = 0,
    .instruction_addresses = @ptrCast([*]usize, &ins_addrs[0]),
};

pub export fn start() void {
    var mstatus = csr.readMstatus();
    mstatus &= ~csr.MSTATUS_MPP;
    // mstatusのMPPにSuperVisor（3）を書き込む
    mstatus |= csr.MSTATUS_MPP_S;
    mstatus |= csr.MSTATUS_SPIE;
    mstatus |= csr.MSTATUS_MIE;
    csr.writeMstatus(mstatus);
    var sstatus = csr.readSstatus();
    sstatus |= csr.SSTATUS_SIE;
    csr.writeSstatus(sstatus);

    csr.writeMepc(@ptrToInt(main.main));

    // ページングを無効にする
    csr.writeSatp(0);

    // すべての例外・割り込みを有効にする
    csr.writeMedeleg(0xffff);
    csr.writeMideleg(0xffff);

    csr.writeSie(csr.readSie() | csr.SIE_SEIE | csr.SIE_STIE | csr.SIE_SSIE);
    csr.writeMie(csr.readMie() | csr.MIE_MTIE);
    try timer.init();

    asm volatile ("la ra, errorOccurred");

    asm volatile ("la a0, stack_trace");

    // mstatus.MPPの値をモードに設定してmainにジャンプ
    asm volatile ("mret");
}
