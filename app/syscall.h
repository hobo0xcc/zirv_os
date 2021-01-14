#ifndef SYSCALL_H
#define SYSCALL_H

#include "types.h"

#define SYS_WRITE 1
#define SYS_READ 2
#define SYS_READFILE 3
#define SYS_GETPID 4
#define SYS_RESUME_PROC 5
#define SYS_CREATE_PROC 6
#define SYS_SLEEP_PROC 7
#define SYS_SUSPEND_PROC 8

void sys_write(uint64 dev, uint64 ptr, uint64 size);
void sys_read(uint64 dev, uint64 buf, uint64 size);
void sys_readfile(uint64 dev, uint64 buf, uint64 name, uint64 size);
void sys_getpid(uint64 addr);
void sys_resume_proc(uint64 pid);
void sys_create_proc(uint64 func, uint64 stack_size, uint64 prio, uint64 name, uint64 pid_addr);
void sys_sleep_proc(uint64 pid);
void sys_suspend_proc(uint64 pid);
void sys_exec(uint64 cmd);
void sys_exit();

#endif
