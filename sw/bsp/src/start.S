/*
 * sw/bsp/src/start.S
 *
 * crt0 for bare-metal programs running on this SoC.  Responsible for:
 *
 *   1. Establishing gp and sp (the linker script supplies both symbols).
 *   2. Copying .data from its ROM LMA to its RAM VMA (no loader).
 *   3. Clearing .bss and .sbss (the default C startup contract).
 *   4. Calling `main()`.  If main returns, we fall into a halt loop.
 *
 * Unlike the old tinyriscv crt0, this version does not pre-initialise
 * the BSP pointer table (that was all tied to the legacy CLNT layout).
 * bsp_init() takes care of hardware setup the moment main() is entered.
 *
 * The `_start` symbol is the ELF entry point and placed at the very top
 * of the .init section by the linker script.
 */

    .section .init
    .globl   _start
    .type    _start, @function

_start:
.option push
.option norelax
    la      gp, __global_pointer$
.option pop
    la      sp, __stack_top

    /* ------------------------------------------------------------- */
    /* Copy .data: ROM LMA at _data_lma into RAM VMA [_data, _edata) */
    /* ------------------------------------------------------------- */
    la      a0, _data_lma
    la      a1, _data
    la      a2, _edata
    bgeu    a1, a2, 2f
1:
    lw      t0, 0(a0)
    sw      t0, 0(a1)
    addi    a0, a0, 4
    addi    a1, a1, 4
    bltu    a1, a2, 1b
2:

    /* ------------------------------------------------------------- */
    /* Zero-fill .bss + .sbss: [_fbss, _end)                         */
    /* ------------------------------------------------------------- */
    la      a0, _fbss
    la      a1, _end
    bgeu    a0, a1, 2f
1:
    sw      zero, 0(a0)
    addi    a0, a0, 4
    bltu    a0, a1, 1b
2:

    /* ------------------------------------------------------------- */
    /* Off to C.                                                     */
    /* ------------------------------------------------------------- */
    call    main

    /* If main ever returns, loop forever so a hang is visible in the
     * testbench.  Programs that want the sim to exit cleanly should
     * either (a) set x26=1,x27=1 before returning (legacy protocol)
     * or (b) print a UART_PASS_PATTERN banner.                       */
.L_halt:
    j       .L_halt

    .size   _start, . - _start
