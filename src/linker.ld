OUTPUT_ARCH( "riscv" )
ENTRY( _entry )

SECTIONS
{
  /*
   * ensure that entry.S / _entry is at 0x80000000,
   * where qemu's -kernel jumps.
   */
  . = 0x80000000;

  .text : {
    PROVIDE(_text_start = .);
    *(.text .text.*)
    . = ALIGN(0x1000);
    _trampoline = .;
    *(trampsec)
    . = ALIGN(0x1000);
    nullproc = .;
    *(nullsec)
    . = ALIGN(0x1000);
    /*ASSERT(. - _trampoline == 0x1000, "error: trampoline larger than one page"); */
    PROVIDE(_text_end = .);
  }

  .rodata : {
    PROVIDE(_rodata_start = .);
    . = ALIGN(16);
    *(.srodata .srodata.*) /* do not need to distinguish this from .rodata */
    . = ALIGN(16);
    *(.rodata .rodata.*)
    PROVIDE(_rodata_end = .);
  }

  .data : {
    PROVIDE(_data_start = .);
    . = ALIGN(16);
    *(.sdata .sdata.*) /* do not need to distinguish this from .data */
    . = ALIGN(16);
    *(.data .data.*)
    PROVIDE(_data_end = .);
  }

  .bss : {
    PROVIDE(_bss_start = .);
    . = ALIGN(16);
    *(.sbss .sbss.*) /* do not need to distinguish this from .bss */
    . = ALIGN(16);
    *(.bss .bss.*)
    PROVIDE(_bss_end = .);
  }

  PROVIDE(_end = .);
}
