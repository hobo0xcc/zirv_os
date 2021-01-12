.set SYS_WRITE, 1
.set SYS_READ, 2
.set SYS_READFILE, 3
.set SYS_GETPID, 4
.set SYS_RESUME_PROC, 5
.set SYS_CREATE_PROC, 6
.set SYS_SLEEP_PROC, 7
.set SYS_SUSPEND_PROC, 8

.globl sys_write
.globl sys_read
sys_write:
    mv a3, a2
    mv a2, a1
    mv a1, a0
    li a0, SYS_WRITE
    ecall
    ret

sys_read:
    mv a3, a2
    mv a2, a1
    mv a1, a0
    li a0, SYS_READ
    ecall
    ret
sys_readfile:
sys_getpid:
sys_resume_proc:
sys_create_proc:
sys_sleep_proc:
sys_suspend_proc:
    nop
    ret
