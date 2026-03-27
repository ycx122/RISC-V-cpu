#include <stdint.h>

#include "../include/utils.h"
#include "../include/500a.h"


uint64_t get_cycle_value()
{
    uint64_t cycle;

    cycle = (uint64_t)GPIO_MTIME_L;
    cycle += (uint64_t)(GPIO_MTIME_H) << 32;

    return cycle;
}

void busy_wait(uint32_t us)
{
    uint64_t tmp;
    uint32_t count;

    count = us * CPU_FREQ_MHZ;
    tmp = get_cycle_value();

    while (get_cycle_value() < (tmp + count));
}
