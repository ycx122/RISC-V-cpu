#include <stdint.h>
#include "include/500a.h"

int timer_count=0;

void timer0_irq_handler(){
    
    GPIO_MTIME_L=0;
    GPIO_MTIME_H=0;
    GPIO_FLAG=1;
    timer_count=timer_count+1;
    
    
}




void trap_handler(uint32_t mcause, uint32_t mepc)
{
    // we have only timer0 interrupt here
    timer0_irq_handler();
}



