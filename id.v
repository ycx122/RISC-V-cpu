module id (
input [31:0]inst,
output reg s,
output reg l,
output reg [4:0]rs1,
output reg [4:0]rs2,
output reg [4:0]rd,
output reg [2:0]alu_op,
output reg [31:0]im,
output reg im_c,
output reg [20:0]pc_im,
output reg [1:0]pc_c=0,
output reg wb_en,
output reg [12:0]b_im,
output reg [1:0]b_en,
output reg sub
);

always@(*)
case(inst[6:2])
	5'b01100:		//add
		begin
			s=0;
			l=0;
			rs1=inst[19:15];
			rs2=inst[24:20];
			rd=inst[11:7];
			alu_op=inst[14:12];
			im=0;
			im_c=0;
			pc_im=0;
			pc_c=0;
			wb_en=1;
			b_im=0;
			b_en=0;
			if(inst[30]==1)
				sub=1;
			else
				sub=0;
		end
	
	5'b00100:				//addi
		begin
			s=0;
			l=0;
			rs1=inst[19:15];
			rs2=0;
			rd=inst[11:7];
			alu_op=inst[14:12];
			im=inst[31:20];
			im_c=1;
			pc_im=0;
			pc_c=0;
			wb_en=1;
			b_im=0;
			b_en=0;
			if(inst[30]==1 && (inst[14:12]==3'b101))
				sub=1;
			else
				sub=0;
		end
	5'b00000:				//load
	if(inst!=0)
		begin
			s=0;
			l=1;
			rs1=inst[19:15];
			rs2=0;
			rd=inst[11:7];
			alu_op=0;
			im=inst[31:20];
			im_c=1;
			pc_im=0;
			pc_c=0;
			wb_en=1;
			b_im=0;
			b_en=0;
			sub=0;
		end
	else
			begin
			s=1'bx;
			l=1'bx;
			rs1={{5{1'bx}}};
			rs2={{5{1'bx}}};
			rd={{5{1'bx}}};
			alu_op={{3{1'bx}}};
			im={{32{1'bx}}};
			im_c=1'bx;
			pc_im={{21{1'bx}}};
			pc_c={{2{1'b0}}};
			wb_en=1'bx;
			b_im={{13{1'bx}}};
			b_en={1'b0,1'b0};
			sub=1'bx;
		end
	5'b01000:				//store
		begin
			s=1;
			l=0;
			rs1=inst[19:15];
			rs2=inst[24:20];
			rd=0;
			alu_op=0;
			im={inst[31:25],inst[11:7]};
			im_c=1;
			pc_im=0;
			pc_c=0;
			wb_en=0;
			b_im=0;
			b_en=0;
			sub=0;
		end
	5'b11000:					//beq
		begin
			s=0;
			l=0;
			rs1=inst[19:15];
			rs2=inst[24:20];
			rd=0;
			alu_op=3'b010;
			im=0;
			im_c=0;
			pc_im=0;
			pc_c=0;
			wb_en=0;
			b_im={inst[31],inst[7],inst[30:25],inst[11:8],1'b0};
			b_en=1;
			sub=0;
		end
	5'b11011:				//jal
		begin
			s=0;
			l=0;
			rs1=0;
			rs2=0;
			rd=inst[11:7];
			alu_op=0;
			im=0;
			im_c=0;
			pc_im={inst[31],inst[19:12],inst[20],inst[30:21],1'b0};
			pc_c=1;
			wb_en=1;
			b_im=0;
			b_en=2;
			sub=0;
		end
	default: 
		begin
			s=1'bx;
			l=1'bx;
			rs1={{5{1'bx}}};
			rs2={{5{1'bx}}};
			rd={{5{1'bx}}};
			alu_op={{3{1'bx}}};
			im={{32{1'bx}}};
			im_c=1'bx;
			pc_im={{21{1'bx}}};
			pc_c={{2{1'bx}}};
			wb_en=1'bx;
			b_im={{13{1'bx}}};
			b_en={1'bx,1'bx};
			sub=1'bx;
		end
	endcase
	
endmodule

	