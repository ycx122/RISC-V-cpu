`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/01/25 23:58:20
// Design Name: 
// Module Name: cpu_uart
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module cpu_uart(
    input clk,
    input rst_n,
    input rx,
    input uart_en,
    input w_en,
    input r_en,
    input [7:0]uart_w_data,
    output reg [7:0]uart_r_data_reg,
    output tx,
    output uart_ready
    );
    
    
    reg ram_ready;
    assign uart_ready=ram_ready;
    
    reg [5:0]w_cnt;
    
    reg [8:0]wait_cnt;
    reg c;
    
    wire rx_done;
    wire [7:0]uart_rx_data;
    
    wire [7:0]uart_tx_data;
    wire tx_en;
    reg tx_en_delay;
    
    wire rx_done_pos;
    
    wire fifo_1_w_pos;
    wire fifo_1_w=uart_en & w_en & (~ram_ready);
    
    wire fifo_0_r_pos;
    wire fifo_0_r=uart_en & r_en;    
    wire [7:0]uart_r_data;
    wire empty;
    reg empty_delay;
    reg fifo_0_r_pos_delay;
/**    
    ila_2 ila_2(
    .clk(clk),
    .probe0(rx),
    .probe1(rx_done),
    .probe2(uart_rx_data),
    
    .probe3(fifo_0_r_pos),
    .probe4(uart_r_data)
    
    );
 **/   
    always@(posedge clk)
        if(rst_n==0)
        empty_delay=0;
        else
        empty_delay=empty;
        
    always@(posedge clk)
        if(rst_n==0)
            uart_r_data_reg=0;
        else if(fifo_0_r_pos_delay==1)
            uart_r_data_reg=(empty_delay==1)?0:uart_r_data;
        else if(ram_ready==1)
            uart_r_data_reg=0;

        
    always@(posedge clk)
        if(rst_n==0)
        tx_en_delay=0;
        else
        tx_en_delay=tx_en;
        
    always@(posedge clk)
        if(rst_n==0)
        fifo_0_r_pos_delay=0;
        else
        fifo_0_r_pos_delay=fifo_0_r_pos;
    
     uart_rx uart_rx(
	.sys_clk(clk),			//50Mϵͳʱ��
	.sys_rst_n(rst_n),			//ϵͳ��λ
	.uart_rxd(rx),			//����������
	.uart_rx_done(rx_done),		//���ݽ�����ɱ�־
	.uart_rx_data(uart_rx_data)		//���յ�������
);
    
     uart_tx uart_tx(
	.sys_clk(clk),	//50Mϵͳʱ��
	.sys_rst_n(rst_n),	//ϵͳ��λ
	.uart_data(uart_tx_data),	//���͵�8λ������
	.uart_tx_en(tx_en_delay),	//����ʹ���ź�
	.uart_txd(tx)	//���ڷ���������
 
);
     edge_detect2 edge1(  
     .clk(clk),           
     .signal(rx_done),        
     .pe(rx_done_pos),		//������ 
     .ne(),		//�½��� 
     .de()		//˫����  
);
    
     edge_detect2 edge2(  
     .clk(clk),           
     .signal(fifo_1_w),        
     .pe(fifo_1_w_pos),		//������ 
     .ne(),		//�½��� 
     .de()		//˫����  
);
    
     edge_detect2 edge3(  
     .clk(clk),           
     .signal(fifo_0_r),        
     .pe(fifo_0_r_pos),		//������ 
     .ne(),		//�½��� 
     .de()		//˫����  
);
        
    
    fifo_0 fifo_0(
    .clk(clk),
    .srst(~rst_n),
    .wr_en(rx_done_pos),
    .din(uart_rx_data),
    .rd_en(fifo_0_r_pos),
    .dout(uart_r_data),
    
    .full(),
    .empty(empty)
    );
    
    fifo_0 fifo_1(
    .clk(clk),
    .srst(~rst_n),
    .wr_en(fifo_1_w_pos),
    .din(uart_w_data),
    .rd_en(tx_en),
    .dout(uart_tx_data),
    
    .full(),
    .empty()
    );
    assign tx_en=(w_cnt!=0)?c:0;
    
    always@(posedge clk)
        if(rst_n==0)
            w_cnt=0;
        else if(uart_en & w_en & ram_ready & (c!=1))
            w_cnt=w_cnt+1;
        else if((w_cnt!=0) & (c==1))
            w_cnt=w_cnt-1;
    
    always@(posedge clk)
        if(rst_n==0)
            wait_cnt=0;
        else
            {c,wait_cnt}=wait_cnt+1;
    reg ram_ready_d1;
    reg ram_ready_d2;
    reg ram_ready_d3;
    reg ram_ready_d4;
    wire uart_en_pos;
     edge_detect2 edge4(  
     .clk(clk),           
     .signal(uart_en),        
     .pe(uart_en_pos),		//������ 
     .ne(),		//�½��� 
     .de()		//˫����  
);
    always@(posedge clk)
        if(rst_n==0)
        begin
         ram_ready    <=0;
         ram_ready_d1 <=0;
         ram_ready_d2 <=0;
         ram_ready_d3 <=0;
         ram_ready_d4 <=0;
        end        
        else
        begin
         ram_ready    <=ram_ready_d1;
         ram_ready_d1 <=ram_ready_d2;
         ram_ready_d2 <=ram_ready_d3;
         ram_ready_d3 <=ram_ready_d4;
         ram_ready_d4 <=uart_en_pos;
        end
    
endmodule
