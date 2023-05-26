module id (
input [31:0]inst,
input [31:0]addr,
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
output reg sub,
output reg [2:0]mem_op,
output reg [14:0]csr
);

always@(*)
if(inst[1:0]==2'b11)
case(inst[6:2])
	5'b01100:		//add and or and .....
		begin
			s=0;					//store
			l=0;              //load
			rs1=inst[19:15];      //reg1
			rs2=inst[24:20];		 //reg2
			rd=inst[11:7];			 //write back reg
			alu_op=inst[14:12];	//op
			im=0;						
			im_c=0;
			pc_im=0;
			pc_c=0;
			wb_en=1;
			b_im=0;
			b_en=0;
			mem_op=0;
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
			im=(inst[31]==1)?({{20{1'b1}},inst[31:20]}):({{20{1'b0}},inst[31:20]});
			im_c=1;
			pc_im=0;
			pc_c=0;
			wb_en=1;
			b_im=0;
			b_en=0;
			mem_op=0;
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
			im=(inst[31]==1)?{20'hff_ff_f,inst[31:20]}:{20'h00_00_0,inst[31:20]};
			im_c=1;
			pc_im=0;
			pc_c=0;
			wb_en=1;
			b_im=0;
			b_en=0;
			sub=0;
			mem_op=inst[14:12];
		end
	else
			begin
			s=1'b0;
			l=1'b0;
			rs1={{5{1'b0}}};
			rs2={{5{1'b0}}};
			rd={{5{1'b0}}};
			alu_op={{3{1'b0}}};
			im={{32{1'b0}}};
			im_c=1'b0;
			pc_im={{21{1'b0}}};
			pc_c={{2{1'b0}}};
			wb_en=1'b0;
			b_im={{13{1'b0}}};
			b_en={1'b0,1'b0};
			sub=1'b0;
			mem_op=3'b000;
		end
	5'b01000:				//store
		begin
			s=1;
			l=0;
			rs1=inst[19:15];
			rs2=inst[24:20];
			rd=0;
			alu_op=0;
			im=(inst[31]==1)?{20'hff_ff_f,inst[31:25],inst[11:7]}:{20'h00_00_0,inst[31:25],inst[11:7]};
			im_c=1;
			pc_im=0;
			pc_c=0;
			wb_en=0;
			b_im=0;
			b_en=0;
			sub=0;
			mem_op=inst[14:12];
		end
	5'b11000:					//b
		begin
			s=0;
			l=0;
			if(inst[14:12]==5||inst[14:12]==7)
			begin
			rs2=inst[19:15];
			rs1=inst[24:20];
			end
			else
			begin
			rs1=inst[19:15];
			rs2=inst[24:20];
			end
			rd=0;
			begin
			case(inst[14:12])
			0:alu_op=0;
			1:alu_op=0;
			4:alu_op=3'b010;
			5:alu_op=3'b010;
			6:alu_op=3'b011;
			7:alu_op=3'b011;
			default:alu_op=1'bx;
			endcase
			end
			im=0;
			im_c=0;
			pc_im=0;
			pc_c=0;
			wb_en=0;
			b_im={inst[31],inst[7],inst[30:25],inst[11:8],1'b0};
			b_en=1;
			if(inst[14:12]==0||inst[14:12]==1)
			sub=1;
			else
			sub=0;
			mem_op=inst[14:12];
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
			mem_op=0;
		end
	5'b11001:				//jalr
		begin
			s=0;
			l=0;
			rs1=inst[19:15];
			rs2=0;
			rd=inst[11:7];
			alu_op=0;
			im=0;
			im_c=0;
			pc_im=inst[31:20];
			pc_c=1;
			wb_en=1;
			b_im=0;
			b_en=2;
			sub=0;
			mem_op=0;
		end		
		5'b01101:	//lui			
		begin
			s=0;
			l=0;
			rs1=0;
			rs2=0;
			rd=inst[11:7];
			alu_op=0;
			im={inst[31:12],{12{1'b0}}};
			im_c=1;
			pc_im=0;
			pc_c=0;
			wb_en=1;
			b_im=0;
			b_en=0;
			mem_op=0;
			sub=0;
		end
		5'b00101:	//auipc
		begin
			s=0;
			l=0;
			rs1=0;
			rs2=0;
			rd=inst[11:7];
			alu_op=0;
			im=(( addr - 4 )+{inst[31:12],{12{1'b0}}});
			im_c=1;
			pc_im=0;
			pc_c=0;
			wb_en=1;
			b_im=0;
			b_en=0;
			mem_op=0;
			sub=0;
		end
		
		5'b11100:	//csr
		begin
			s=0;
			l=0;
			rs1=inst[19:15];
			rs2=0;
			rd=inst[11:7];
			alu_op=0;
			if(inst[14]==1)
				im={{27{1'b0}},inst[19:15]};
			else
				im=0;			
			im_c=1;
			pc_im=0;
			pc_c=0;
			wb_en=1;
			b_im=0;
			b_en=0;
			sub=0;
			mem_op=0;		
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
			pc_im={{21{1'bx}}};			//or stop
			pc_c={{2{1'b0}}};
			wb_en=1'bx;
			b_im={{13{1'bx}}};
			b_en={1'b0,1'b0};
			sub=1'bx;
			mem_op=3'bxxx;
		end
	endcase
	else
	   		begin
			s=0;
			l=0;
			rs1=0;
			rs2=0;
			rd=0;
			alu_op=0;
			im=0;
			im_c=0;
			pc_im=0;
			pc_c=0;
			wb_en=0;
			b_im=0;
			b_en=0;
			mem_op=0;
			sub=0;
		end
	
	
	always@(*)
	if(inst[1:0]==3'b11)
	begin
	   if(inst[6:2]==5'b11100)
		  csr={inst[31:20],1'b1,inst[13:12]};
	   else
		  csr=0;
	end
	else
	   csr=0;
	
endmodule

	