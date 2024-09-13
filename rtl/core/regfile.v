module regfile (
output reg [31:0]data1,
output reg [31:0]data2,
input clk,
input [31:0]write_data,
input [4:0]write_addr,
input [4:0]read_1_addr,
input [4:0]read_2_addr,
input write_ce,
input w_en_2,
input [4:0]w_addr_2,
input [31:0]w_data_2
);
reg reg_0=0;
reg [31:0] regs [31:0];
reg [10:0]i;

initial
begin
for(i=1;i<32;i=i+1)
	regs[i]=0;
end

always@(posedge clk)
begin
if (write_ce==1)
    regs[write_addr]=write_data;
if(w_en_2==1)
    regs[w_addr_2]=w_data_2;
end


		
always@(*)
case(read_1_addr)
		0:data1<=reg_0;
		1:data1<=regs[1];
		2:data1<=regs[2];
		3:data1<=regs[3];
		4:data1<=regs[4];
		5:data1<=regs[5];
		6:data1<=regs[6];
		7:data1<=regs[7];
		8:data1<=regs[8];
		9:data1<=regs[9];
		10:data1<=regs[10];
		11:data1<=regs[11];
		12:data1<=regs[12];
		13:data1<=regs[13];
		14:data1<=regs[14];
		15:data1<=regs[15];
		16:data1<=regs[16];
		17:data1<=regs[17];
		18:data1<=regs[18];
		19:data1<=regs[19];
		20:data1<=regs[20];
		21:data1<=regs[21];
		22:data1<=regs[22];
		23:data1<=regs[23];
		24:data1<=regs[24];
		25:data1<=regs[25];
		26:data1<=regs[26];
		27:data1<=regs[27];
		28:data1<=regs[28];
		29:data1<=regs[29];
		30:data1<=regs[30];
		31:data1<=regs[31];
		default: data1<={32{1'bx}};
endcase

always@(*)
case(read_2_addr)
		0:data2<=reg_0;
		1:data2<=regs[1];
		2:data2<=regs[2];
		3:data2<=regs[3];
		4:data2<=regs[4];
		5:data2<=regs[5];
		6:data2<=regs[6];
		7:data2<=regs[7];
		8:data2<=regs[8];
		9:data2<=regs[9];
		10:data2<=regs[10];
		11:data2<=regs[11];
		12:data2<=regs[12];
		13:data2<=regs[13];
		14:data2<=regs[14];
		15:data2<=regs[15];
		16:data2<=regs[16];
		17:data2<=regs[17];
		18:data2<=regs[18];
		19:data2<=regs[19];
		20:data2<=regs[20];
		21:data2<=regs[21];
		22:data2<=regs[22];
		23:data2<=regs[23];
		24:data2<=regs[24];
		25:data2<=regs[25];
		26:data2<=regs[26];
		27:data2<=regs[27];
		28:data2<=regs[28];
		29:data2<=regs[29];
		30:data2<=regs[30];
		31:data2<=regs[31];
		default: data2<={32{1'bx}};
endcase	


endmodule
		
		
		
		
		
		
		
		
		