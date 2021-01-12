OUTPUT_ARCH( "riscv" )
ENTRY( main )

SECTIONS
{
  . = 0x1000;

  .text : {
    PROVIDE(_text_start = .);
    *(.text .text.*)
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

