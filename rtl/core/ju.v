module ju ( 
output reg [31:0] ju_out,
output reg [1:0] pc_c=0,
output reg [12:0] b_im_out,
input [1:0]ju_c,
input [12:0] im_in,
input [31:0] pc_addr,
input [31:0] alu_out,
input [2:0]  mem_op,

input [31:0]mul_div_out,
input mul_div_ready
);

always@(*)
begin
	if(ju_c==0 & mul_div_ready==0)
		begin
		ju_out=alu_out;
		pc_c=0;
		b_im_out=0;
		end
	else if(ju_c==0 & mul_div_ready==1)
		begin
		ju_out=mul_div_out;
		pc_c=0;
		b_im_out=0;
		end
	else if(ju_c==1)     //b
		begin
			case(mem_op)
			0:	
			begin
			if(alu_out==0)
				begin
				ju_out=0;
				pc_c=2;
				b_im_out=im_in;
				end
			else
				begin
				ju_out=0;				
				pc_c=0;
				b_im_out=0;
				end
			end
			1:
			begin
			if(alu_out!=0)
				begin
				ju_out=0;
				pc_c=2;
				b_im_out=im_in;
				end
			else
				begin
				ju_out=0;				
				pc_c=0;
				b_im_out=0;
				end
			end
			4:
			begin
			if(alu_out[0]==1)
				begin
				ju_out=0;
				pc_c=2;
				b_im_out=im_in;
				end
			else
				begin
				ju_out=0;				
				pc_c=0;
				b_im_out=0;
				end
			end
			5://eero
			begin
			if(alu_out[0]==0)
				begin
				ju_out=0;
				pc_c=2;
				b_im_out=im_in;
				end
			else
				begin
				ju_out=0;				
				pc_c=0;
				b_im_out=0;
				end
			end
			6:
			begin
			if(alu_out[0]==1)
				begin
				ju_out=0;
				pc_c=2;
				b_im_out=im_in;
				end
			else
				begin
				ju_out=0;				
				pc_c=0;
				b_im_out=0;
				end
			end
			7:
			begin
			if(alu_out[0]==0)
				begin
				ju_out=0;
				pc_c=2;
				b_im_out=im_in;
				end
			else
				begin
				ju_out=0;				
				pc_c=0;
				b_im_out=0;
				end
			end
			default:		
			begin
			ju_out={{32{1'bx}}};
			pc_c={1'bx,1'bx};
			b_im_out={{13{1'bx}}};
			end
			endcase
		end
	else if(ju_c==2)   //jal
		begin
			ju_out=pc_addr;
			pc_c=0;
			b_im_out=0;
		end
	else
		begin
			ju_out={{32{1'bx}}};
			pc_c={1'b0,1'b0};
			b_im_out={{13{1'bx}}};
		end
end	

endmodule
		
		
		
		
		
		
		