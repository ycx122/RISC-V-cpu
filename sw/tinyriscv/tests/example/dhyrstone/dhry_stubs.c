#include "../include/500a.h"

/* The functions in this file are only meant to support Dhrystone on an
 * embedded RV32 system and are obviously incorrect in general. */

/* RV32 csr_cycle / csr_instret: read the architectural 64-bit
 * mcycle / minstret CSRs as a single 64-bit value.  We use the standard
 * "read-hi, read-lo, re-read-hi, retry on mismatch" pattern from RVI
 * pseudo-code so we never observe a torn snapshot when the low half
 * overflows between the two CSR reads.  The argument is preserved for
 * source compatibility with the upstream Dhrystone code (which passed
 * `(long *)0`); it is ignored here. */
unsigned long long csr_cycle(void *unused)
{
    unsigned int hi1, lo, hi2;
    (void)unused;
    do {
        __asm__ volatile ("csrr %0, mcycleh" : "=r"(hi1));
        __asm__ volatile ("csrr %0, mcycle"  : "=r"(lo));
        __asm__ volatile ("csrr %0, mcycleh" : "=r"(hi2));
    } while (hi1 != hi2);
    return ((unsigned long long)hi2 << 32) | (unsigned long long)lo;
}

unsigned long long csr_instret(void *unused)
{
    unsigned int hi1, lo, hi2;
    (void)unused;
    do {
        __asm__ volatile ("csrr %0, minstreth" : "=r"(hi1));
        __asm__ volatile ("csrr %0, minstret"  : "=r"(lo));
        __asm__ volatile ("csrr %0, minstreth" : "=r"(hi2));
    } while (hi1 != hi2);
    return ((unsigned long long)hi2 << 32) | (unsigned long long)lo;
}

/* Wall-clock helper retained for code that still expects "seconds". */
#define SOC_TIMER_FREQ 50000000

long time(void)
{
    return get_time() / SOC_TIMER_FREQ;
}
