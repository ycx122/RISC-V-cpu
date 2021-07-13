module ju ( 
output reg [31:0] p_out,
output reg [1:0] pc_c,
output reg [12:0] im_out,
input [1:0]ju_c,
input [12:0] im_in,
input [31:0] pc_addr,
input [31:0] alu_out
);

always@(*)
begin
	if(ju_c==0)
		begin
		p_out=alu_out;
		pc_c=0;
		im_out=0;
		end
	else if(ju_c==1)     //blt
		begin
			if(alu_out[0]==1)
				begin
				p_out=0;
				pc_c=2;
				im_out=im_in;
				end
			else
				begin
				p_out=0;				
				pc_c=0;
				im_out=0;
				end
		end
	else if(ju_c==2)   //jal
		begin
			p_out=pc_addr+4;
			pc_c=1;
			im_out=0;
		end
	else
		begin
			p_out={{32{1'bx}}};
			pc_c={1'bx,1'bx};
			im_out={{13{1'bx}}};
		end
end	

endmodule
		