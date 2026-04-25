/*
 * sw/bsp/ld/default.lds
 *
 * Default linker script for the RISC-V CPU SoC.  Matches the on-chip
 * memory sizes in rtl/memory/ram_c.v (256 KB RAM) and the BRAM-backed
 * boot ROM (64 KB) wired up in rtl/soc/cpu_soc.v.
 *
 * Summary:
 *   ROM 0x0000_0000  64 KB   .init / .text / .rodata / .data LMA
 *   RAM 0x2000_0000 256 KB   .data VMA / .bss / heap / stack (top-down)
 *
 * 2026-04 (Tier 2 / A1+A2 scale-up): RAM doubled from 128 KB to 256 KB
 * for the Artix-7 200T target.  The CPU's 8 KB write-back D-Cache and
 * 4-deep store buffer make the larger working set practical without a
 * proportional latency hit.  Stack default also bumped to 32 KB so a
 * deeper call stack (e.g. a recursive demo or task switching) doesn't
 * collide with the heap.
 *
 * If the image grows past 64 KB (most likely cause: enabling -O0 on a
 * big demo, or pulling in newlib's printf), swap this script for the
 * larger one a future "RAM-backed .text" port would use.  For now the
 * simple layout keeps Dhrystone + the OS demo comfortably under 40 KB.
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    rom (rxai!w) : ORIGIN = 0x00000000, LENGTH = 64K
    ram (wa!rix) : ORIGIN = 0x20000000, LENGTH = 256K
}

PROVIDE(__stack_size = 32K);

SECTIONS
{
    /* ------------------------------------------------------------- */
    /* Code / read-only data (all in ROM).                            */
    /* ------------------------------------------------------------- */
    .init : {
        KEEP (*(SORT_NONE(.init)))
    } > rom AT> rom

    .text : {
        *(.text.trap)
        *(.text .text.*)
    } > rom AT> rom

    . = ALIGN(4);
    .rodata : {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    } > rom AT> rom

    . = ALIGN(4);
    PROVIDE(__etext = .);
    PROVIDE(_etext  = .);

    /* Init/fini arrays.  We don't run them from _start (no C++ objects
     * expected), but keeping them in ROM lets future code use them
     * without rewriting the script.                                   */
    .preinit_array : {
        PROVIDE_HIDDEN(__preinit_array_start = .);
        KEEP(*(.preinit_array))
        PROVIDE_HIDDEN(__preinit_array_end = .);
    } > rom AT> rom

    .init_array : {
        PROVIDE_HIDDEN(__init_array_start = .);
        KEEP(*(SORT_BY_INIT_PRIORITY(.init_array.*) SORT_BY_INIT_PRIORITY(.ctors.*)))
        KEEP(*(.init_array .ctors))
        PROVIDE_HIDDEN(__init_array_end = .);
    } > rom AT> rom

    .fini_array : {
        PROVIDE_HIDDEN(__fini_array_start = .);
        KEEP(*(SORT_BY_INIT_PRIORITY(.fini_array.*) SORT_BY_INIT_PRIORITY(.dtors.*)))
        KEEP(*(.fini_array .dtors))
        PROVIDE_HIDDEN(__fini_array_end = .);
    } > rom AT> rom

    /* ------------------------------------------------------------- */
    /* .data: stored in ROM, copied to RAM by crt0.                    */
    /* ------------------------------------------------------------- */
    . = ALIGN(4);
    PROVIDE(_data_lma = LOADADDR(.data));
    .data : ALIGN(4) {
        PROVIDE(_data = .);
        *(.data .data.*)
        *(.sdata .sdata.*)
        . = ALIGN(4);
        PROVIDE(__global_pointer$ = . + 0x800);
        PROVIDE(_edata = .);
        PROVIDE(edata  = .);
    } > ram AT> rom

    /* ------------------------------------------------------------- */
    /* .bss / .sbss: allocated in RAM, zero-filled by crt0.            */
    /* ------------------------------------------------------------- */
    .bss : ALIGN(4) {
        PROVIDE(_fbss       = .);
        PROVIDE(__bss_start = .);
        *(.sbss .sbss.*)
        *(.bss  .bss.*)
        *(COMMON)
        . = ALIGN(4);
        PROVIDE(_end = .);
        PROVIDE(end  = .);
    } > ram AT> ram

    /* ------------------------------------------------------------- */
    /* Stack grows down from the top of RAM.                           */
    /* ------------------------------------------------------------- */
    .stack ORIGIN(ram) + LENGTH(ram) - __stack_size : ALIGN(16) {
        PROVIDE(__stack_bottom = .);
        . = . + __stack_size;
        PROVIDE(__stack_top = .);
    } > ram

    /* Heap fills whatever RAM is left between _end and the stack.     */
    PROVIDE(__heap_start = _end);
    PROVIDE(__heap_end   = __stack_bottom);

    /DISCARD/ : { *(.note.*) *(.comment) *(.eh_frame) }
}
