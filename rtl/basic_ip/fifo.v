//计数器法实现同步FIFO
module	sync_fifo_cnt
#(
	parameter   DATA_WIDTH = 'd8  ,							//FIFO位宽
    parameter   DATA_DEPTH = 'd64 							//FIFO深度
)
(
	input									clk		,		//系统时钟
	input									rst_n	,       //低电平有效的复位信号
	input	[DATA_WIDTH-1:0]				data_in	,       //写入的数据
	input									rd_en	,       //读使能信号，高电平有效
	input									wr_en	,       //写使能信号，高电平有效
															
	output	reg	[DATA_WIDTH-1:0]			data_out,	    //输出的数据
	output									empty	,	    //空标志，高电平表示当前FIFO已被写满
	output									full	       //满标志，高电平表示当前FIFO已被读空
	//output	reg	[$clog2(DATA_DEPTH) : 0]	fifo_cnt		//$clog2是以2为底取对数	
);
 reg	[$clog2(DATA_DEPTH) : 0]	fifo_cnt;
//reg define
reg [DATA_WIDTH - 1 : 0] fifo_buffer[DATA_DEPTH - 1 : 0];	//用二维数组实现RAM	
reg [$clog2(DATA_DEPTH) - 1 : 0]	wr_addr;				//写地址
reg [$clog2(DATA_DEPTH) - 1 : 0]	rd_addr;				//读地址
 
//读操作，更新读地址
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n)
		rd_addr <= 0;
	else if (!empty && rd_en)begin							//读使能有效且非空
		rd_addr <= rd_addr + 1'd1;
		data_out <= fifo_buffer[rd_addr];
	end
end
//写操作,更新写地址
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n)
		wr_addr <= 0;
	else if (!full && wr_en)begin							//写使能有效且非满
		wr_addr <= wr_addr + 1'd1;
		fifo_buffer[wr_addr]<=data_in;
	end
end
//更新计数器
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n)
		fifo_cnt <= 0;
	else begin
		case({wr_en,rd_en})									//拼接读写使能信号进行判断
			2'b00:fifo_cnt <= fifo_cnt;						//不读不写
			2'b01:	                               			//仅仅读
				if(fifo_cnt != 0)				   			//fifo没有被读空
					fifo_cnt <= fifo_cnt - 1'b1;   			//fifo个数-1
			2'b10:                                 			//仅仅写
				if(fifo_cnt != DATA_DEPTH)         			//fifo没有被写满
					fifo_cnt <= fifo_cnt + 1'b1;   			//fifo个数+1
			2'b11:fifo_cnt <= fifo_cnt;	           			//读写同时
			default:;                              	
		endcase
	end
end
//依据计数器状态更新指示信号
//依据不同阈值还可以设计半空、半满 、几乎空、几乎满
assign full  = (fifo_cnt == DATA_DEPTH) ? 1'b1 : 1'b0;		//满信号
assign empty = (fifo_cnt == 0)? 1'b1 : 1'b0;				//空信号
 
endmodule