`timescale 1ns / 1ps

module cpu_uart(
    input clk,
    input rst_n,
    input rx,
    input uart_en,
    input w_en,
    input r_en,
    input [7:0]uart_w_data,
    output reg [8:0]uart_r_data_reg,
    output tx,
    output uart_ready,
    input [31:0]addr
    );
    
    
    reg ram_ready;
    assign uart_ready=ram_ready;
    
    reg [6:0]w_cnt;
    
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
    

    always@(posedge clk)
        if(rst_n==0)
        empty_delay<=0;
        else
        empty_delay<=empty;
        
    always@(posedge clk)
        if(rst_n==0)
            uart_r_data_reg<=0;
        else if(fifo_0_r_pos_delay==1)
            uart_r_data_reg<=(empty_delay==1)?9'b1_0000_0000:{1'b0,uart_r_data};
        else if(ram_ready==1)
            uart_r_data_reg<=0;

        
    always@(posedge clk)
        if(rst_n==0)
        tx_en_delay<=0;
        else
        tx_en_delay<=tx_en;
        
    always@(posedge clk)
        if(rst_n==0)
        fifo_0_r_pos_delay<=0;
        else
        fifo_0_r_pos_delay<=fifo_0_r_pos;
    
     uart_rx uart_rx(
	.sys_clk(clk),                                  // 50 MHz system clock
	.sys_rst_n(rst_n),                              // active-low reset
	.uart_rxd(rx),                                  // UART RX line
	.uart_rx_done(rx_done),                         // byte received strobe
	.uart_rx_data(uart_rx_data)                     // received byte
);

     uart_tx uart_tx(
	.sys_clk(clk),                                  // 50 MHz system clock
	.sys_rst_n(rst_n),                              // active-low reset
	.uart_data(uart_tx_data),                       // byte to send
	.uart_tx_en(tx_en_delay),                       // TX enable pulse
	.uart_txd(tx)                                   // UART TX line
);
     edge_detect2 edge1(
     .clk(clk),
     .signal(rx_done),
     .pe(rx_done_pos),                              // rising  edge pulse
     .ne(),                                         // falling edge pulse (unused)
     .de()                                          // either  edge pulse (unused)
);

     edge_detect2 edge2(
     .clk(clk),
     .signal(fifo_1_w),
     .pe(fifo_1_w_pos),                             // rising  edge pulse
     .ne(),                                         // falling edge pulse (unused)
     .de()                                          // either  edge pulse (unused)
);

     edge_detect2 edge3(
     .clk(clk),
     .signal(fifo_0_r),
     .pe(fifo_0_r_pos),                             // rising  edge pulse
     .ne(),                                         // falling edge pulse (unused)
     .de()                                          // either  edge pulse (unused)
);

// RX FIFO: UART receiver pushes bytes in, CPU pulls them out.
sync_fifo_cnt sync_fifo_cnt_0
(
	.clk(clk),                                      // system clock
	.rst_n(rst_n),                                  // active-low reset
	.data_in(uart_rx_data),                         // write-side data
	.rd_en(fifo_0_r_pos),                           // read  enable
	.wr_en(rx_done_pos),                            // write enable

	.data_out(uart_r_data),                         // read-side data
	.empty(empty),                                  // FIFO empty flag
	.full()                                         // FIFO full  flag (unused)

);
    
wire tx_empty;
 
// TX FIFO: CPU pushes bytes in, UART transmitter pulls them out.
sync_fifo_cnt sync_fifo_cnt_1
(
	.clk(clk),                                      // system clock
	.rst_n(rst_n),                                  // active-low reset
	.data_in(uart_w_data),                          // write-side data
	.rd_en(tx_en),                                  // read  enable
	.wr_en(fifo_1_w_pos),                           // write enable

	.data_out(uart_tx_data),                        // read-side data
	.empty(tx_empty),                               // FIFO empty flag
	.full()                                         // FIFO full  flag (unused)

);

    assign tx_en=(tx_empty==0)?c:0;
    
    always@(posedge clk)
        if(rst_n==0)
            w_cnt<=0;
        else if(uart_en & w_en & ram_ready & (c!=1))
            w_cnt<=w_cnt+1;
        else if((w_cnt!=0) & (c==1))
            w_cnt<=w_cnt-1;
    
    always@(posedge clk)
        if(rst_n==0)
            wait_cnt<=0;
        else
            {c,wait_cnt}<=wait_cnt+1;
    reg ram_ready_d1;
    reg ram_ready_d2;
    reg ram_ready_d3;
    reg ram_ready_d4;
    wire uart_en_pos;
     edge_detect2 edge4(
     .clk(clk),
     .signal(uart_en),
     .pe(uart_en_pos),                              // rising  edge pulse
     .ne(),                                         // falling edge pulse (unused)
     .de()                                          // either  edge pulse (unused)
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
