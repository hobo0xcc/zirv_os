comptime {
    // RISC-Vが最初にジャンプする関数
    asm (
        \\ .text
        \\ .globl _entry
        \\ _entry:
        \\     la sp, stack0
        \\     addi a1, zero, 1
        \\     slli a1, a1, 15
        \\     add sp, sp, a1
        \\     call start
        \\ spin:
        \\     j spin
    );
}
