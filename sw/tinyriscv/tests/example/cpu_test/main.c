#include "../include/500a.h"

float kernel_0[16],
kernel_1[16],
kernel_2[16],
kernel_3[16],

kernel_4[16],
kernel_5[16],
kernel_6[16],
kernel_7[16],
a[16];

void main ()
{
    cpu_init();
    GPIO_FLAG=0;    
    GPIO_LED=0;
	float result_0,
		  result_1,
		  result_2,
		  result_3,
		  result_4,
		  result_5,
		  result_6,
		  result_7;
	
	
    while (1){
		
	for (int i=0;i<16;i++){
		kernel_0[i]=1;
		kernel_1[i]=2;
		kernel_2[i]=3;
		kernel_3[i]=4;		
		kernel_4[i]=5;		
		kernel_5[i]=6;		
		kernel_6[i]=7;		
		kernel_7[i]=8;		
		a[i]=1;
	}
	
	
	
		cnn_a_fill(a);
		cnn_k_fill(kernel_0,0);
		cnn_k_fill(kernel_1,1);
		cnn_k_fill(kernel_2,2);
		cnn_k_fill(kernel_3,3);
		cnn_k_fill(kernel_4,4);
		cnn_k_fill(kernel_5,5);
		cnn_k_fill(kernel_6,6);
		cnn_k_fill(kernel_7,7);	
		
		
		cnn_start();
		wait_mcnn_result();
		result_0=get_mcnn_result(0);
		result_1=get_mcnn_result(1);
		result_2=get_mcnn_result(2);
		result_3=get_mcnn_result(3);
		result_4=get_mcnn_result(4);
		result_5=get_mcnn_result(5);		
		result_6=get_mcnn_result(6);
		result_7=get_mcnn_result(7);
		
	xprintf("re_0=%f \n",result_0);
	xprintf("re_1=%f \n",result_1);
	xprintf("re_2=%f \n",result_2);
	xprintf("re_3=%f \n",result_3);
	xprintf("re_4=%f \n",result_4);
	xprintf("re_5=%f \n",result_5);
	xprintf("re_6=%f \n",result_6);
	xprintf("re_7=%f \n",result_7);
	
	
	}
}
