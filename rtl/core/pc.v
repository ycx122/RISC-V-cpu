
module pc(
output reg [31:0] pc_addr=0,
input clk,
input rst,
input pc_c_1,
input pc_c_0,
input [20:0]jal_add,
input pc_en,
input [12:0]b_add,  //erro
input [31:0]set_addr,
input set_en,
input id_pc_im_f,
input [31:0]reg_data
);

always@(posedge clk)//if(pc_en==1)
	begin
	if(rst==0)
		pc_addr=0;
	else	if( set_en==1 )//&& pc_en==1)

			pc_addr=set_addr;	
			
	else
			begin
			case({pc_c_1,pc_c_0})
				0:begin if(pc_en==1)
				            pc_addr=pc_addr+4;end//常规跳转
				1:begin if(pc_en==1)
				        pc_addr=(id_pc_im_f==1)?(reg_data+((jal_add[11]==0)?{11'b00000000000,jal_add}:{{20{1'b1}},jal_add[11:0]})):(pc_addr+((jal_add[20]==0)?{11'b00000000000,jal_add}:{11'b11111111111,jal_add})-8);		
				end
				2:pc_addr=pc_addr+((b_add[12]==0)?{{19{1'b0}},b_add}:{{19{1'b1}},b_add}) -12;		//判断跳转，符号数
				3:pc_addr=pc_addr+((b_add[12]==0)?{{19{1'b0}},b_add}:{{19{1'b1}},b_add}) -12;
				default:begin   if(pc_en==1)
				                pc_addr=pc_addr+4; 
				end
			endcase
		end
		
   end

endmodule			
			
	

