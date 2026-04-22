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
output reg [14:0]csr,
output mul_div_ctrl,
output reg wq,

// FENCE / FENCE.I decode hint.  Both opcode=0001111 encodings are treated as
// a drain-the-pipeline NOP by cpu_jh.v so the subsequent fetch observes the
// effects of every earlier store.  fence.i (funct3=001) and fence (funct3=000)
// do not have architecturally distinct semantics on this single-core, no-I$
// pipeline, so we collapse them into the same signal.
output is_fence_i,

// IllegalInstruction decode.  Asserted in WB at the same pipeline slot as
// `csr` so csr_reg.v can raise an M-mode exception with mcause=2.
//
// An instruction is flagged illegal when:
//   * its low two bits != 2'b11 AND inst != 0   (compressed/unknown while
//     C is not implemented).  All-zero is kept as a non-trapping bubble
//     so pipeline bubbles / reset state / flushed fetches don't fire a
//     spurious trap.
//   * or the RV32I opcode field (inst[6:2]) decodes into the `default`
//     branch below (unknown opcode).
output reg illegal
);

assign mul_div_ctrl=(inst[6:2]==5'b01100 & inst[25]==1)?1:0;
assign is_fence_i  =(inst[1:0]==2'b11 & inst[6:2]==5'b00011) ? 1'b1 : 1'b0;

always@(*) begin
illegal = 1'b0;   // overridden below for unknown opcodes / compressed
if(inst[1:0]==2'b11)
case(inst[6:2])
	5'b01100:		//add and or and .....
	   if(inst[25]==0)
		begin
			s=0;					//store
			l=0;                   //load
			rs1=inst[19:15];       //reg1
			rs2=inst[24:20];	   //reg2
			rd=inst[11:7];		   //write back reg
			alu_op=inst[14:12];	   //op
			im=0;						
			im_c=0;
			pc_im=0;
			pc_c=0;
			wb_en=1;
			b_im=0;
			b_en=0;
			mem_op=0;
			wq=1;
			if(inst[30]==1)
				sub=1;
			else
				sub=0;
		end
		else begin                   //mul div
			s=0;					 //store
			l=0;                    //load
			rs1=inst[19:15];        //reg1
			rs2=inst[24:20];		//reg2
			rd=inst[11:7];			//write back reg
			alu_op=inst[14:12];	    //op
			im=0;						
			im_c=0;
			pc_im=0;
			pc_c=0;
			wb_en=1;
			b_im=0;
			b_en=0;
			mem_op=0;
			sub=0;
			wq=1;
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
			wq=1;
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
			wq=0;
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
			wq=0;
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
			wq=0;
			mem_op=inst[14:12];
		end
	5'b11000:					//b
		begin
			s=0;
			l=0;
			//if(inst[14:12]==5||inst[14:12]==7)
			//begin
			//rs2=inst[19:15];
			//rs1=inst[24:20];
			//end
			//else
			//begin
			rs1=inst[19:15];
			rs2=inst[24:20];
			//end
			rd=0;
			begin
			case(inst[14:12])
			0:alu_op=0;
			1:alu_op=0;
			4:alu_op=3'b010;
			5:alu_op=3'b010;//?
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
			wq=0;
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
			wq=1;
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
			wq=1;
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
			wq=1;
		end
		5'b00101:	//auipc
		begin
			s=0;
			l=0;
			rs1=0;
			rs2=0;
			rd=inst[11:7];
			alu_op=0;
			// auipc: rd = PC + (imm20 << 12).  Earlier versions used
			// `(addr - 4)` here; that was -4 low and was cancelling an
			// equal -4 offset in ju.v's link computation and in pc.v's
			// JALR target.  All three have been fixed together so that
			// absolute addresses computed via `la` are now spec-correct
			// (needed for sb/sh/sw store tests, which hang the bus when
			// `la` resolves to 0x1FFFFFFC instead of 0x20000000).
			im= addr + {inst[31:12],{12{1'b0}}};
			im_c=1;
			pc_im=0;
			pc_c=0;
			wb_en=1;
			b_im=0;
			b_en=0;
			mem_op=0;
			sub=0;
			wq=1;
		end
		
	5'b11100:	//csr
	begin
		s=0;
		l=0;
		rs2=0;
		rd=inst[11:7];
		alu_op=0;
		if(inst[14]==1) begin
			im={{27{1'b0}},inst[19:15]};
			rs1=0;
			end
		else begin
			im=0;
			rs1=inst[19:15];	
			end		
		im_c=1;
		pc_im=0;
		pc_c=0;
		wb_en=1;
		b_im=0;
		b_en=0;
		sub=0;
		mem_op=0;		
		wq=0;
	end

	5'b00011: // fence / fence.i -> architectural NOP, drained externally
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
		wq=0;
	end

default:
		// Unknown RV32I opcode: emit a safe NOP (wb_en=0, no memory, no
		// branch) and flag `illegal` so csr_reg.v raises a spec-compliant
		// M-mode IllegalInstruction exception (mcause=2) when this
		// instruction reaches WB.
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
			sub=0;
			mem_op=0;
			wq=0;
			illegal=1'b1;
		end
	endcase
	else
	   		begin
			// inst[1:0] != 2'b11: compressed encoding (or truly unknown).
			// This core does not implement C, so treat non-zero values as
			// illegal while keeping the all-zero case as a non-trapping
			// pipeline bubble (reset / flushed-fetch / explicit NOP).
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
			wq=0;
			if(inst != 32'h0000_0000)
				illegal = 1'b1;
		end
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

	