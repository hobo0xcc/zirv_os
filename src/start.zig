const csr = @import("csr.zig");
const main = @import("main.zig");
const uart = @import("uart.zig");

// ## start()
// - Will make CPU mode into supervisor and enable exceptions and interrupts.
pub export fn start() void {
    // mret will change the mode to supervisor.
    var mstatus = csr.readMstatus();
    mstatus &= ~csr.MSTATUS_MPP;
    mstatus |= csr.MSTATUS_MPP_S;
    csr.writeMstatus(mstatus);

    // mret will return to main.
    csr.writeMepc(@ptrToInt(main.main));

    // Disable paging.
    csr.writeSatp(0);

    // Delegate all exceptions and interrupts.
    csr.writeMedeleg(0xffff);
    csr.writeMideleg(0xffff);

    csr.writeSie(csr.readSie() | csr.SIE_SEIE | csr.SIE_STIE | csr.SIE_SSIE);

    // Let's move into supervisor!
    asm volatile ("mret");
}
