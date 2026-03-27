#include "../include/500a.h"
#include "../include/xprintf.h"



void main ()
{
    cpu_init();
    GPIO_FLAG=0;    
    GPIO_LED=0;
	
	//cnn_ptr=(float *)0x60000000;
	
	
    while (1){
		

	GPIO_LED=~GPIO_LED;
	//xprintf("test");


	//delay(100);
	}
}
