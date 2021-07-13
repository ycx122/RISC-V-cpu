module regfile (
output reg [31:0]data1,
output reg [31:0]data2,
input clk,
input [31:0]write_data,
input [4:0]w_a,
input [4:0]r1_a,
input [4:0]r2_a,
input w_ce
);
reg reg0=0;
reg [31:0] regs [31:1];
reg [10:0]i;

initial
begin
for(i=1;i<32;i=i+1)
	regs[i]=0;
end

always@(posedge clk)
if (w_ce==1)
begin
	case(w_a)
		0:reg0<=0;
		1:regs[1]<=write_data;
		2:regs[2]<=write_data;
		3:regs[3]<=write_data;
		4:regs[4]<=write_data;
		5:regs[5]<=write_data;
		6:regs[6]<=write_data;
		7:regs[7]<=write_data;
		8:regs[8]<=write_data;
		9:regs[9]<=write_data;
		10:regs[10]<=write_data;
		11:regs[11]<=write_data;
		12:regs[12]<=write_data;
		13:regs[13]<=write_data;
		14:regs[14]<=write_data;
		15:regs[15]<=write_data;
		16:regs[16]<=write_data;
		17:regs[17]<=write_data;
		18:regs[18]<=write_data;
		19:regs[19]<=write_data;
		20:regs[20]<=write_data;
		21:regs[21]<=write_data;
		22:regs[22]<=write_data;
		23:regs[23]<=write_data;
		24:regs[24]<=write_data;
		25:regs[25]<=write_data;
		26:regs[26]<=write_data;
		27:regs[27]<=write_data;
		28:regs[28]<=write_data;
		29:regs[29]<=write_data;
		30:regs[30]<=write_data;
		31:regs[31]<=write_data;
		endcase
end

		
always@(*)
case(r1_a)
		0:data1<=reg0;
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
case(r2_a)
		0:data2<=reg0;
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
		
		
		
		
		
		
		
		
		