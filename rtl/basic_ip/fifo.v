//��������ʵ��ͬ��FIFO
module	sync_fifo_cnt
#(
	parameter   DATA_WIDTH = 'd8  ,							//FIFOλ��
    parameter   DATA_DEPTH = 'd64 							//FIFO���
)
(
	input									clk		,		//ϵͳʱ��
	input									rst_n	,       //�͵�ƽ��Ч�ĸ�λ�ź�
	input	[DATA_WIDTH-1:0]				data_in	,       //д�������
	input									rd_en	,       //��ʹ���źţ��ߵ�ƽ��Ч
	input									wr_en	,       //дʹ���źţ��ߵ�ƽ��Ч
															
	output	reg	[DATA_WIDTH-1:0]			data_out,	    //���������
	output									empty	,	    //�ձ�־���ߵ�ƽ��ʾ��ǰFIFO�ѱ�д��
	output									full	       //����־���ߵ�ƽ��ʾ��ǰFIFO�ѱ�����
	//output	reg	[$clog2(DATA_DEPTH) : 0]	fifo_cnt		//$clog2����2Ϊ��ȡ����	
);
 reg	[$clog2(DATA_DEPTH) : 0]	fifo_cnt;
//reg define
reg [DATA_WIDTH - 1 : 0] fifo_buffer[DATA_DEPTH - 1 : 0];	//�ö�ά����ʵ��RAM	
reg [$clog2(DATA_DEPTH) - 1 : 0]	wr_addr;				//д��ַ
reg [$clog2(DATA_DEPTH) - 1 : 0]	rd_addr;				//����ַ
 
//�����������¶���ַ
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n)
		rd_addr <= 0;
	else if (!empty && rd_en)begin							//��ʹ����Ч�ҷǿ�
		rd_addr <= rd_addr + 1'd1;
		data_out <= fifo_buffer[rd_addr];
	end
end
//д����,����д��ַ
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n)
		wr_addr <= 0;
	else if (!full && wr_en)begin							//дʹ����Ч�ҷ���
		wr_addr <= wr_addr + 1'd1;
		fifo_buffer[wr_addr]<=data_in;
	end
end
//���¼�����
always @ (posedge clk or negedge rst_n) begin
	if (!rst_n)
		fifo_cnt <= 0;
	else begin
		case({wr_en,rd_en})									//ƴ�Ӷ�дʹ���źŽ����ж�
			2'b00:fifo_cnt <= fifo_cnt;						//������д
			2'b01:	                               			//������
				if(fifo_cnt != 0)				   			//fifoû�б�����
					fifo_cnt <= fifo_cnt - 1'b1;   			//fifo����-1
			2'b10:                                 			//����д
				if(fifo_cnt != DATA_DEPTH)         			//fifoû�б�д��
					fifo_cnt <= fifo_cnt + 1'b1;   			//fifo����+1
			2'b11:fifo_cnt <= fifo_cnt;	           			//��дͬʱ
			default:;                              	
		endcase
	end
end
//���ݼ�����״̬����ָʾ�ź�
//���ݲ�ͬ��ֵ��������ư�ա����� �������ա�������
assign full  = (fifo_cnt == DATA_DEPTH) ? 1'b1 : 1'b0;		//���ź�
assign empty = (fifo_cnt == 0)? 1'b1 : 1'b0;				//���ź�
 
endmodule