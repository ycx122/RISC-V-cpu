

module uart_tx(
	input 			sys_clk,	//50M系统时钟
	input 			sys_rst_n,	//系统复位
	input	[7:0] 	uart_data,	//发送的8位置数据
	input			uart_tx_en,	//发送使能信号
	output reg 		uart_txd	//串口发送数据线
 
);
 
parameter 	SYS_CLK_FRE=50_000_000;    //50M系统时钟 
parameter 	BPS=115200;                 //波特率9600bps，可更改
localparam	BPS_CNT=SYS_CLK_FRE/BPS;   //传输一位数据所需要的时钟个数
 
reg	uart_tx_en_d0;			//寄存1拍
reg uart_tx_en_d1;			//寄存2拍
reg tx_flag;				//发送标志位
reg [7:0]  uart_data_reg;	//发送数据寄存器
reg [15:0] clk_cnt;			//时钟计数器
reg [3:0]  tx_cnt;			//发送个数计数器
 
wire pos_uart_en_txd;		//使能信号的上升沿
//捕捉使能端的上升沿信号，用来标志输出开始传输
assign pos_uart_en_txd= uart_tx_en_d0 && (~uart_tx_en_d1);
 
always @(posedge sys_clk or negedge sys_rst_n)begin
	if(!sys_rst_n)begin
		uart_tx_en_d0<=1'b0;
		uart_tx_en_d1<=1'b0;		
	end
	else begin
		uart_tx_en_d0<=uart_tx_en;
		uart_tx_en_d1<=uart_tx_en_d0;
	end	
end
//捕获到使能端的上升沿信号，拉高传输开始标志位，并在第9个数据（终止位）的传输过程正中（数据比较稳定）再将传输开始标志位拉低，标志传输结束
always @(posedge sys_clk or negedge sys_rst_n)begin
	if(!sys_rst_n)begin
		tx_flag<=1'b0;
		uart_data_reg<=8'd0;
	end
	else if(pos_uart_en_txd)begin
		uart_data_reg<=uart_data;
		tx_flag<=1'b1;
	end
	else if((tx_cnt==4'd9) && (clk_cnt==BPS_CNT/2))begin//在第9个数据（终止位）的传输过程正中（数据比较稳定）再将传输开始标志位拉低，标志传输结束
		tx_flag<=1'b0;
		uart_data_reg<=8'd0;
	end
	else begin
		uart_data_reg<=uart_data_reg;
		tx_flag<=tx_flag;	
	end
end
//时钟每计数一个BPS_CNT（传输一位数据所需要的时钟个数），即将数据计数器加1，并清零时钟计数器
always @(posedge sys_clk or negedge sys_rst_n)begin
	if(!sys_rst_n)begin
		clk_cnt<=16'd0;
		tx_cnt <=4'd0;
	end
	else if(tx_flag) begin
		if(clk_cnt<BPS_CNT-1)begin
			clk_cnt<=clk_cnt+1'b1;
			tx_cnt <=tx_cnt;
		end
		else begin
			clk_cnt<=16'd0;
			tx_cnt <=tx_cnt+1'b1;
		end
	end
	else begin
		clk_cnt<=16'd0;
		tx_cnt<=4'd0;
	end
end
//在每个数据的传输过程正中（数据比较稳定）将数据寄存器的数据赋值给数据线
always @(posedge sys_clk or negedge sys_rst_n)begin
	if(!sys_rst_n)
		uart_txd<=1'b1;
	else if(tx_flag)
		case(tx_cnt)
			4'd0:	uart_txd<=1'b0;
			4'd1:	uart_txd<=uart_data_reg[0];
			4'd2:	uart_txd<=uart_data_reg[1];
			4'd3:	uart_txd<=uart_data_reg[2];
			4'd4:	uart_txd<=uart_data_reg[3];
			4'd5:	uart_txd<=uart_data_reg[4];
			4'd6:	uart_txd<=uart_data_reg[5];
			4'd7:	uart_txd<=uart_data_reg[6];
			4'd8:	uart_txd<=uart_data_reg[7];
			4'd9:	uart_txd<=1'b1;
			default:;
		endcase
	else 	
		uart_txd<=1'b1;
end
endmodule




module uart_rx(
	input 			sys_clk,			//50M系统时钟
	input 			sys_rst_n,			//系统复位
	input 			uart_rxd,			//接收数据线
	output reg 		uart_rx_done,		//数据接收完成标志
	output reg [7:0]uart_rx_data		//接收到的数据
);
//常量化波特率，可更改
parameter	BPS=115200;					//波特率9600bps，可更改
parameter	SYS_CLK_FRE=50_000_000;		//50M系统时钟
localparam	BPS_CNT=SYS_CLK_FRE/BPS;	//传输一位数据所需要的时钟个数
 
reg 			uart_rx_d0;		//寄存1拍
reg 			uart_rx_d1;		//寄存2拍
reg [15:0]		clk_cnt;				//时钟计数器
reg [3:0]		rx_cnt;					//接收计数器
reg 			rx_flag;				//接收标志位
reg [7:0]		uart_rx_data_reg;		//数据寄存
	
wire 			neg_uart_rx_data;		//数据的下降沿
 
assign	neg_uart_rx_data=uart_rx_d1 & (~uart_rx_d0);  //捕获数据线的下降沿，用来标志数据传输开始
//将数据线打两拍，作用1：同步不同时钟域信号，防止亚稳态；作用2：用以捕获下降沿
always@(posedge sys_clk or negedge sys_rst_n)begin
	if(!sys_rst_n)begin
		uart_rx_d0<=1'b0;
		uart_rx_d1<=1'b0;
	end
	else begin
		uart_rx_d0<=uart_rxd;
		uart_rx_d1<=uart_rx_d0;
	end		
end
//捕获到数据下降沿（起始位0）后，拉高传输开始标志位，并在第9个数据（终止位）的传输过程正中（数据比较稳定）再将传输开始标志位拉低，标志传输结束
always@(posedge sys_clk or negedge sys_rst_n)begin
	if(!sys_rst_n)
		rx_flag<=1'b0;
	else begin 
		if(neg_uart_rx_data)
			rx_flag<=1'b1;
		else if((rx_cnt==4'd9)&&(clk_cnt==BPS_CNT/2))//在第9个数据（终止位）的传输过程正中（数据比较稳定）再将传输开始标志位拉低，标志传输结束
			rx_flag<=1'b0;
		else 
			rx_flag<=rx_flag;			
	end
end
//时钟每计数一个BPS_CNT（传输一位数据所需要的时钟个数），即将数据计数器加1，并清零时钟计数器
always@(posedge sys_clk or negedge sys_rst_n)begin
	if(!sys_rst_n)begin
		rx_cnt<=4'd0;
		clk_cnt<=16'd0;
	end
	else if(rx_flag)begin
		if(clk_cnt<BPS_CNT-1'b1)begin
			clk_cnt<=clk_cnt+1'b1;
			rx_cnt<=rx_cnt;
		end
		else begin
			clk_cnt<=16'd0;
			rx_cnt<=rx_cnt+1'b1;
		end
	end
	else begin
		rx_cnt<=4'd0;
		clk_cnt<=16'd0;
	end		
end
//在每个数据的传输过程正中（数据比较稳定）将数据线上的数据赋值给数据寄存器
always@(posedge sys_clk or negedge sys_rst_n)begin
	if(!sys_rst_n)
		uart_rx_data_reg<=8'd0;
	else if(rx_flag)
		if(clk_cnt==BPS_CNT/2) begin
			case(rx_cnt)			
				4'd1:uart_rx_data_reg[0]<=uart_rxd;
				4'd2:uart_rx_data_reg[1]<=uart_rxd;
				4'd3:uart_rx_data_reg[2]<=uart_rxd;
				4'd4:uart_rx_data_reg[3]<=uart_rxd;
				4'd5:uart_rx_data_reg[4]<=uart_rxd;
				4'd6:uart_rx_data_reg[5]<=uart_rxd;
				4'd7:uart_rx_data_reg[6]<=uart_rxd;
				4'd8:uart_rx_data_reg[7]<=uart_rxd;
				default:;
			endcase
		end
		else
			uart_rx_data_reg<=uart_rx_data_reg;
	else
		uart_rx_data_reg<=8'd0;
end	
//当数据传输到终止位时，拉高传输完成标志位，并将数据输出
always@(posedge sys_clk or negedge sys_rst_n)begin
	if(!sys_rst_n)begin
		uart_rx_done<=1'b0;
		uart_rx_data<=8'd0;
	end	
	else if(rx_cnt==4'd9)begin
		uart_rx_done<=1'b1;
		uart_rx_data<=uart_rx_data_reg;
	end		
	else begin
		uart_rx_done<=1'b0;
		uart_rx_data<=8'd0;
	end
end
endmodule


