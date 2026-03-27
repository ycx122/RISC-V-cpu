#include "../include/500a.h"

int *gpio_led_ptr;
int *gpio_uart_ptr;
int *gpio_key_ptr;

int *gpio_clnt_0_ptr;
int *gpio_clnt_1_ptr;
int *gpio_clnt_2_ptr;
int *gpio_clnt_3_ptr;
int *gpio_clnt_4_ptr;

unsigned int *gpio_pic_ptr;
float* cnn_ptr;
int* cnn_ptr_int;

void delay(int time){
    int i;
    int j;
    for(i=0;i<time;i++){
        for(j=0;j<time;j++);         
    };
}

void cpu_init(){
    gpio_led_ptr=(int *)   0x40000000;
    gpio_key_ptr=(int *)   0x41000000;
    gpio_uart_ptr=(int *)  0x43000000;
    gpio_clnt_0_ptr=(int *)0x42000000;
    gpio_clnt_1_ptr=(int *)0x42000001;
    gpio_clnt_2_ptr=(int *)0x42000002;
    gpio_clnt_3_ptr=(int *)0x42000003;
    gpio_clnt_4_ptr=(int *)0x42000004;
    
    gpio_pic_ptr=(unsigned int *)0x50000000;
	cnn_ptr=(float *)0x60000000;
	cnn_ptr_int=(int *)0x60000000;
}

/*------------------·发送字符串-----------------------*/
void send_string(char *str)
{
	int i = 0;
    delay(100);
	do
	{
		GPIO_UART=*(str+i);
		i++;
        delay(100);
	}while( *(str+i) != '\0');
	
	
}

void send_int(int a )
{
    int i=0;
    char buf[10];
    
    delay(100);
    while(a!=0){
    buf[i]=a%10 +0x30;
    a=a/10;
    i=i+1;
    }
    
    while (i!=0){
        i=i-1;
        GPIO_UART=buf[i];
        delay(100);
    }
    
}

void send_float(float b)
{
    int a; 
    int low;
    a=(int)b;
    low=(int)((b-(float)a)*100);
    delay(100);
    send_int(a);
    delay(100);
    send_string(".");
    delay(100);
    send_int(low);
    
}

void start_time(){
    GPIO_MTIME_H=0;
    GPIO_MTIME_L=0;
    
};

long get_time(){
    int time_low;
    int time_high;
    long time=0;
    
    time_low=GPIO_MTIME_L;
    time_high=GPIO_MTIME_H;
    
    time=time_low+(((long)time_high)<<32);
    
    return time;
}


void start_time_inter(){
	
	GPIO_FLAG=1;
	GPIO_MTIME_L=0;
	GPIO_MTIME_H=0;
	
}

void set_time_inter(int usec){   //us
	int clik= usec *  (50);
	GPIO_CMP_L= (int)clik;
	
}

////////////////////////////////////////////////////////////////////////////////////

void wait_cnn_result(){
	
	while(*(cnn_ptr+145) ==0){    //is re valid
		
	}
	
}

void wait_mcnn_result(){
	
	while(*(cnn_ptr_int+145) !=0xff){    //is re valid
	}
	
}

float get_cnn_result(){
	
	return (*(cnn_ptr+146)) ;
	
}

float get_mcnn_result(int i){
	
	return (*(cnn_ptr+146+i)) ;
	
}

void cnn_a_fill(float *a){
	
	
	fill_array(a, cnn_ptr, 16);
	
	
}

void cnn_b_fill(float *b){
	
	fill_array(b, cnn_ptr+16, 16);

	
}

void cnn_k_fill(float *b,int i){
	
	fill_array(b, cnn_ptr+16+16*i, 16);

	
}

void cnn_start(){
	
		*(cnn_ptr+144)=1;  //start computer
	
}


///////////////////////////////////////////////////////////////////////////////////////   math code

float InvSqrt(float x)
{
    float xhalf = 0.5f*x;
    int i = *(int*)&x; // get bits for floating VALUE 
    i = 0x5f375a86- (i>>1); // gives initial guess y0
    x = *(float*)&i; // convert bits BACK to float
    x = x*(1.5f-xhalf*x*x); // Newton step, repeating increases accuracy
    x = x*(1.5f-xhalf*x*x); // Newton step, repeating increases accuracy
    x = x*(1.5f-xhalf*x*x); // Newton step, repeating increases accuracy

    return 1/x;
}
