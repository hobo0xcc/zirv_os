const UART_BASE: usize = 0x10000000;
const UART_PTR: [*]u8 = @intToPtr([*]u8, UART_BASE);

const RBR: usize = 0;
const THR: usize = 0;
const IER: usize = 1;
const FCR: usize = 2;
const ISR: usize = 2;
const LCR: usize = 3;
const LSR: usize = 5;

const LCR_DLAB: usize = 1 << 7;
const FCR_FIFO_ENABLE: usize = 1 << 0;
const FCR_FIFO_CLEAR: usize = 3 << 1;
const IER_TX_ENABLE: usize = 1 << 1;
const IER_RX_ENABLE: usize = 1 << 0;

pub fn writeReg(reg: usize, value: u8) void {
    UART_PTR[reg] = value;
}

pub fn readReg(reg: usize) u8 {
    return UART_PTR[reg];
}

pub fn init() void {
    writeReg(IER, 0x00);
    writeReg(LCR, LCR_DLAB);
    // Baud rate.
    writeReg(0, 0x03);
    writeReg(1, 0x00);

    writeReg(LCR, 0x03);
    writeReg(FCR, FCR_FIFO_ENABLE | FCR_FIFO_CLEAR);
    writeReg(IER, IER_TX_ENABLE | IER_RX_ENABLE);
}

pub fn putc(ch: u8) void {
    UART_PTR[RBR] = ch;
}

pub fn print(str: []const u8) void {
    for (str) |ch| {
        putc(ch);
    }
}

pub fn println(str: []const u8) void {
    print(str);
    putc('\n');
}
