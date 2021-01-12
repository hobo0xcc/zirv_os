#define SYS_WRITE 1
#define SYS_READ 2
#define SYS_READFILE 3
#define SYS_GETPID 4
#define SYS_RESUME_PROC 5
#define SYS_CREATE_PROC 6
#define SYS_SLEEP_PROC 7
#define SYS_SUSPEND_PROC 8

void sys_write(long dev, long ptr, long size);
void sys_read(long dev, long buf, long size);
void sys_readfile(long dev, long buf, long name, long size);
void sys_getpid(long addr);
void sys_resume_proc(long pid);
void sys_create_proc(long func, long stack_size, long prio, long name, long pid_addr);
void sys_sleep_proc(long pid);
void sys_suspend_proc(long pid);