const std = @import("std");
const layout = @import("memlayout.zig");
const trap = @import("trap.zig");
const SpinLock = @import("spinlock.zig").SpinLock;
const io = std.io;

const UART_PTR: [*]u8 = @intToPtr([*]u8, layout.UART_BASE);

const RBR: usize = 0;
const THR: usize = 0;
const IER: usize = 1;
const FCR: usize = 2;
const IIR: usize = 2;
const LCR: usize = 3;
const LSR: usize = 5;

const LCR_DLAB: usize = 1 << 7;
const FCR_FIFO_ENABLE: usize = 1 << 0;
const FCR_FIFO_CLEAR: usize = 3 << 1;
const IER_TX_ENABLE: usize = 1 << 1;
const IER_RX_ENABLE: usize = 1 << 0;

const WriteError = error{};
const ReadError = error{};

pub const UART = Uart{};
pub const uart_writer = io.Writer(Uart, WriteError, Uart.kprint);
pub const uart_reader = io.Reader(Uart, ReadError, Uart.kread);
var uart_lock = SpinLock.init();
pub const out = uart_writer{ .context = UART };
pub const in = uart_reader{ .context = UART };

pub const INPUT_BUF_LEN: usize = 0x100;
pub var echoback: bool = true;
pub var input_buf = [_]u8{0} ** INPUT_BUF_LEN;
pub var input_pos: usize = 0;
pub var input_curr: usize = 0;

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

    pub fn init(self: Uart) void {
        self.writeReg(IER, 0x00);
        self.writeReg(LCR, LCR_DLAB);
        // Baud rate
        self.writeReg(0, 0x03);
        self.writeReg(1, 0x00);

        self.writeReg(LCR, 0x03);
        self.writeReg(FCR, FCR_FIFO_ENABLE | FCR_FIFO_CLEAR);
        self.writeReg(IER, IER_RX_ENABLE);
    }

    pub fn readChar(self: Uart) ?u8 {
        if ((self.readReg(LSR) & 0x01) != 0) {
            return self.readReg(RBR);
        } else {
            return null;
        }
    }

    pub fn storeInputBuf(self: Uart, ch: u8) void {
        input_buf[input_pos % INPUT_BUF_LEN] = ch;
        input_pos += 1;
    }

    pub fn interrupt(self: Uart) !void {
        var ch_opt: ?u8 = null;
        while (true) {
            ch_opt = self.readChar();
            if (ch_opt) |ch| {
                self.storeInputBuf(ch);
                if (echoback) {
                    try self.kputc(ch);
                }
            } else {
                break;
            }
        }
    }

    pub fn kputc(self: Uart, ch: u8) WriteError!void {
        // var held = (&uart_lock).acquire();
        // defer held.release();
        self.writeReg(THR, ch);
        // TODO: debug
        while ((self.readReg(LSR) & (1 << 5)) == 0) {}
        return;
    }

    pub fn kgetc(self: Uart) u8 {
        var mask = trap.ienable();
        defer trap.restore(mask);
        while (input_curr == input_pos) {}
        var ch = input_buf[input_curr % INPUT_BUF_LEN];
        input_curr += 1;
        return ch;
    }

    pub fn kprint(self: Uart, bytes: []const u8) WriteError!usize {
        for (bytes) |ch| {
            try self.kputc(ch);
        }

        return bytes.len;
    }

    pub fn kread(self: Uart, buffer: []u8) ReadError!usize {
        for (buffer) |*ch| {
            ch.* = self.kgetc();
        }

        return buffer.len;
    }

    pub fn getWriter(self: Uart) writer {
        return writer{
            .context = self,
        };
    }
};
