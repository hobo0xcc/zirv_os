comptime {
    asm (
        \\ .section nullsec
        \\ .globl nullproc
        \\ nullproc:
        \\ _loop:
        \\     j _loop
        \\     ret
    );
}

pub extern fn nullproc() void;
