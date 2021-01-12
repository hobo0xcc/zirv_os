pub const PAGE_SIZE: usize = 4096;
// size of heap memory
pub const HEAP_SIZE: usize = 30 * 1024 * 1024;
// maximum value of virtual address
pub const MAX_VA: usize = (1 << (9 + 9 + 9 + 12 - 1));
// an address which is used for mapping trampoline section
pub const TRAMPOLINE: usize = MAX_VA - PAGE_SIZE;
pub const TRAPFRAME: usize = TRAMPOLINE - PAGE_SIZE;
pub const USER_STACK_TOP: usize = TRAPFRAME - 2 * PAGE_SIZE;
pub const NULLPROC_ADDR: usize = 0x1000;
