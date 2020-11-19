pub const MSTATUS_MPP: u64 = 0b11 << 11;
pub const MSTATUS_MPP_U: u64 = 0b00 << 11;
pub const MSTATUS_MPP_S: u64 = 0b01 << 11;
pub const MSTATUS_MPP_M: u64 = 0b11 << 11;
pub const MSTATUS_SPIE: u64 = 0b1 << 5;
pub const MSTATUS_MIE: u64 = 0b1 << 3;

pub const SIE_SEIE: u64 = 0b1 << 9;
pub const SIE_STIE: u64 = 0b1 << 5;
pub const SIE_SSIE: u64 = 0b1 << 1;

pub fn readMstatus() u64 {
    return asm volatile ("csrr %[ret], mstatus"
        : [ret] "=r" (-> u64)
    );
}

pub fn writeMstatus(val: u64) void {
    asm volatile ("csrw mstatus, %[val]"
        :
        : [val] "r" (val)
    );
}

pub fn readMepc() u64 {
    return asm volatile ("csrr %[ret], mepc"
        : [ret] "=r" (-> u64)
    );
}

pub fn writeMepc(val: u64) void {
    asm volatile ("csrw mepc, %[val]"
        :
        : [val] "r" (val)
    );
}

pub fn readSatp() u64 {
    return asm volatile ("csrr %[ret], satp"
        : [ret] "=r" (-> u64)
    );
}

pub fn writeSatp(val: u64) void {
    asm volatile ("csrw satp, %[val]"
        :
        : [val] "r" (val)
    );
}

pub fn readMedeleg() u64 {
    return asm volatile ("csrr %[ret], medeleg"
        : [ret] "=r" (-> u64)
    );
}

pub fn writeMedeleg(val: u64) void {
    asm volatile ("csrw medeleg, %[val]"
        :
        : [val] "r" (val)
    );
}

pub fn readMideleg() u64 {
    return asm volatile ("csrr %[ret], mideleg"
        : [ret] "=r" (-> 64)
    );
}

pub fn writeMideleg(val: u64) void {
    asm volatile ("csrw mideleg, %[val]"
        :
        : [val] "r" (val)
    );
}

pub fn readSie() u64 {
    return asm volatile ("csrr %[ret], sie"
        : [ret] "=r" (-> u64)
    );
}

pub fn writeSie(val: u64) void {
    asm volatile ("csrw sie, %[val]"
        :
        : [val] "r" (val)
    );
}

pub fn readStvec() u64 {
    return asm volatile ("csrr %[ret], stvec"
        : [ret] "=r" (-> u64)
    );
}

pub fn writeStvec(val: u64) void {
    asm volatile ("csrw stvec, %[val]"
        :
        : [val] "r" (val)
    );
}

pub fn readScause() u64 {
    return asm volatile ("csrr %[ret], scause"
        : [ret] "=r" (-> u64)
    );
}

pub fn writeScause(val: u64) void {
    asm volatile ("csrw scause, %[val]"
        :
        : [val] "r" (val)
    );
}

pub fn readSepc() u64 {
    return asm volatile ("csrr %[ret], sepc"
        : [ret] "=r" (-> u64)
    );
}

pub fn writeSepc(val: u64) void {
    asm volatile ("csrw sepc, %[val]"
        :
        : [val] "r" (val)
    );
}