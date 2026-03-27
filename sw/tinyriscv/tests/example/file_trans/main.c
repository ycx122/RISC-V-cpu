#include "../include/500a.h"

int wait_read_char()
{
	
	int a=GPIO_UART;
	while(a==256){
		a=GPIO_UART;
	}
	//delay(100);
	return a;
	
	
}

void main ()
{
    cpu_init();
    GPIO_FLAG=0;    
    GPIO_LED=0;

	
	int flag=0;
	
    while (1){
	
	//GPIO_UART=wait_read_char();
	
	
	if(GPIO_UART=='s'){      //start trans
		flag=1;
		xprintf("start");
	}
		
	while(flag==1){
		
	int addr=wait_read_char();
	if(addr!=2){
		break;
	}
	
	int method=wait_read_char();
	
	int list_num=wait_read_char();
	
	int data_length=wait_read_char();
	
	int data[data_length];
	
	for(int i=0;i<data_length;i++){
		data[i]=wait_read_char();
	}
	
	int sum_verifiy=wait_read_char();
	
	/////////////////////////////////////////////////////////////////////////////////////// 
	
	delay(100);

	GPIO_UART=1;		 //地址：1（主机） 2（从机）
	delay(50);
	GPIO_UART=0;         //回复：0 （回复收到） 1（发送消息） 2(收尾消息)
	delay(50);
	GPIO_UART=list_num;  //帧序列
	delay(50);
	GPIO_UART=1;		 //数据长度
	delay(50);
	GPIO_UART=12;
	delay(50);

	int checksum = 1 ^ 0 ^ list_num ^ 1 ^ 12;
	GPIO_UART = checksum & 0xFF; // 取低八位

	//GPIO_UART=1^list_num^1^1^12;	//求和效验
	delay(100);

	}
	
    }
    
    
    
}
