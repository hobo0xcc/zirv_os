const std = @import("std");
const layout = @import("memlayout.zig");
const io = std.io;

const UART_PTR: [*]u8 = @intToPtr([*]u8, layout.UART_BASE);

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

const WriteError = error{};

pub const UART = Uart{};
pub const uart_writer = io.Writer(Uart, WriteError, Uart.kprint);
pub const out = uart_writer{ .context = UART };

pub const Uart = struct {
    pub const writer = io.Writer(Uart, WriteError, kprint);
    // UARTのMMIOレジスタに書き込み
    pub fn writeReg(self: Uart, reg: usize, value: u8) void {
        UART_PTR[reg] = value;
    }

    // UARTのMMIOレジスタを読み込み
    pub fn readReg(self: Uart, reg: usize) u8 {
        return UART_PTR[reg];
    }

    // UARTを初期化
    pub fn init(self: Uart) void {
        self.writeReg(IER, 0x00);
        self.writeReg(LCR, LCR_DLAB);
        // Baud rate.
        self.writeReg(0, 0x03);
        self.writeReg(1, 0x00);

        self.writeReg(LCR, 0x03);
        self.writeReg(FCR, FCR_FIFO_ENABLE | FCR_FIFO_CLEAR);
        self.writeReg(IER, IER_TX_ENABLE | IER_RX_ENABLE);
    }

    pub fn kputc(self: Uart, ch: u8) WriteError!void {
        UART_PTR[RBR] = ch;
        return;
    }

    pub fn kprint(self: Uart, bytes: []const u8) WriteError!usize {
        for (bytes) |ch| {
            try self.kputc(ch);
        }

        return bytes.len;
    }

    pub fn get_writer(self: Uart) writer {
        return writer{
            .context = self,
        };
    }
};

pub fn kputc(ch: u8) void {
    UART_PTR[RBR] = ch;
    return;
}

pub fn kprint(bytes: []const u8) usize {
    for (bytes) |ch| {
        kputc(ch);
    }

    return bytes.len;
}
