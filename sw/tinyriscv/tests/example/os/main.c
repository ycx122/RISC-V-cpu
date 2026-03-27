#include "../include/500a.h"

extern void os_main(void);
extern void sched_init();
extern void schedule();

void main ()
{
    cpu_init();
    GPIO_FLAG=0;    
    GPIO_LED=0;
	

	
	sched_init();
	os_main();

	set_time_inter(50000);
	start_time_inter();

	schedule();
	
	
	
    while (1){
		
	xprintf("hello_world3\n");
	
	delay(1000);
	
    }
    
    
    
}
