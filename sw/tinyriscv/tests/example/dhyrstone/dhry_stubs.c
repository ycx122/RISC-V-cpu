#include "../include/500a.h"

/* The functions in this file are only meant to support Dhrystone on an
 * embedded RV32 system and are obviously incorrect in general. */
 #define SOC_TIMER_FREQ 50000000

long csr_cycle(void)
{
  return get_time();
}

long csr_instret(void)
{
  return get_time();
}

long time(void)
{
  return get_time() / SOC_TIMER_FREQ;
}

