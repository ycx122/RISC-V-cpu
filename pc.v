
module pc(
output reg [31:0] pc_addr=0,
input clk,
input rst,
input op1,
input op2,
input [20:0]jal_add,
input stop,
input [12:0]b_add  //erro
);

always@(posedge clk)
if(stop==0)
begin
if(rst==0)
	pc_addr=0;
else
	begin
		case({op1,op2})
			0:pc_addr=pc_addr+4;
			1:pc_addr=pc_addr+((jal_add[20]==0)?{11'b00000000000,jal_add}:{11'b11111111111,jal_add})-4;
			2:pc_addr=pc_addr+((b_add[12]==0)?{{19{1'b0}},b_add}:{{19{1'b1}},b_add}) -8;
		endcase
	end
end

endmodule			
			
	