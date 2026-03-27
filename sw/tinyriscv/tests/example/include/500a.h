#ifndef _500A_H_
#define _500A_H_

extern int *gpio_led_ptr;
extern int *gpio_uart_ptr;
extern int *gpio_key_ptr;

extern int *gpio_clnt_0_ptr;
extern int *gpio_clnt_1_ptr;
extern int *gpio_clnt_2_ptr;
extern int *gpio_clnt_3_ptr;
extern int *gpio_clnt_4_ptr;

extern unsigned int *gpio_pic_ptr;

extern float* cnn_ptr;
extern int* cnn_ptr_int;

extern void delay(int time);
extern void cpu_init();
extern void send_string(char *str);
extern void send_int(int a );
extern void send_float(float b);

extern void start_time();
extern long get_time();

extern void start_time_inter();
extern void set_time_inter(int usec);

extern void fill_array(float* src, float* dest, int len);


extern void cnn_a_fill(float *a);
extern void cnn_b_fill(float *b);
extern void cnn_k_fill(float *b,int i);
extern void cnn_start();
extern float get_cnn_result();
extern float get_mcnn_result(int i);
extern void wait_cnn_result();
extern void wait_mcnn_result();


////////////////////////////////////////////////////////////////math

extern float InvSqrt(float x);



#define GPIO_LED (*gpio_led_ptr)
#define GPIO_UART (*gpio_uart_ptr)
#define GPIO_KEY (*gpio_key_ptr)

#define GPIO_MTIME_L (*gpio_clnt_0_ptr)
#define GPIO_MTIME_H (*gpio_clnt_1_ptr)
#define GPIO_CMP_L   (*gpio_clnt_2_ptr)
#define GPIO_CMP_H   (*gpio_clnt_3_ptr)
#define GPIO_FLAG    (*gpio_clnt_4_ptr)

#define PIC_PTR gpio_pic_ptr

#endif