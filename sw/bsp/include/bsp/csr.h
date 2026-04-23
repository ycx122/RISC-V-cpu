/*
 * sw/bsp/include/bsp/csr.h
 *
 * Machine-mode CSR read/write helpers.  Kept tiny on purpose: the
 * project only needs the standard RV32 M-mode CSRs, and inlining
 * `csrr` / `csrw` / `csrrs` / `csrrc` via preprocessor macros keeps
 * the calling site one instruction wide.
 */

#ifndef BSP_CSR_H
#define BSP_CSR_H

#include <stdint.h>

/* Read a CSR into a 32-bit C lvalue. */
#define csr_read(csr)                                                          \
    ({                                                                         \
        uint32_t __v;                                                          \
        __asm__ volatile("csrr %0, " #csr : "=r"(__v));                        \
        __v;                                                                   \
    })

/* Write a CSR.  Accepts a C expression of any width <= 32 bits. */
#define csr_write(csr, val)                                                    \
    do {                                                                       \
        uint32_t __v = (uint32_t)(val);                                        \
        __asm__ volatile("csrw " #csr ", %0" : : "r"(__v));                    \
    } while (0)

/* Atomic set bits: returns the previous CSR value. */
#define csr_set(csr, bits)                                                     \
    ({                                                                         \
        uint32_t __v, __b = (uint32_t)(bits);                                  \
        __asm__ volatile("csrrs %0, " #csr ", %1" : "=r"(__v) : "r"(__b));     \
        __v;                                                                   \
    })

/* Atomic clear bits: returns the previous CSR value. */
#define csr_clear(csr, bits)                                                   \
    ({                                                                         \
        uint32_t __v, __b = (uint32_t)(bits);                                  \
        __asm__ volatile("csrrc %0, " #csr ", %1" : "=r"(__v) : "r"(__b));     \
        __v;                                                                   \
    })

/* ------------------------------------------------------------------ */
/* mstatus bits we use                                                 */
/* ------------------------------------------------------------------ */
#define MSTATUS_MIE    (1u << 3)
#define MSTATUS_MPIE   (1u << 7)
#define MSTATUS_MPP    (3u << 11)       /* WARL: both bits tied to 11 (M) */

/* ------------------------------------------------------------------ */
/* mie / mip bits                                                      */
/* ------------------------------------------------------------------ */
#define MIE_MSIE       (1u << 3)
#define MIE_MTIE       (1u << 7)
#define MIE_MEIE       (1u << 11)

#define MIP_MSIP       (1u << 3)
#define MIP_MTIP       (1u << 7)
#define MIP_MEIP       (1u << 11)

/* ------------------------------------------------------------------ */
/* mcause decoding                                                     */
/* ------------------------------------------------------------------ */
#define MCAUSE_INTERRUPT_BIT   (1u << 31)
#define MCAUSE_CODE_MASK       (0x7fffffffu)

/* Standard synchronous exception codes (Volume II, Table 3.6) */
#define MCAUSE_EXC_INSTR_ALIGN      0u
#define MCAUSE_EXC_INSTR_ACCESS     1u
#define MCAUSE_EXC_ILLEGAL          2u
#define MCAUSE_EXC_BREAKPOINT       3u
#define MCAUSE_EXC_LOAD_ALIGN       4u
#define MCAUSE_EXC_LOAD_ACCESS      5u
#define MCAUSE_EXC_STORE_ALIGN      6u
#define MCAUSE_EXC_STORE_ACCESS     7u
#define MCAUSE_EXC_ECALL_U          8u
#define MCAUSE_EXC_ECALL_S          9u
#define MCAUSE_EXC_ECALL_M         11u

/* Standard interrupt codes (Volume II, Table 3.6) */
#define MCAUSE_INT_MSI              3u
#define MCAUSE_INT_MTI              7u
#define MCAUSE_INT_MEI             11u

#endif /* BSP_CSR_H */
