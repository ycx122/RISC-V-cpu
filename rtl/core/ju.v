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

reg branch_taken;
reg branch_valid;

always @(*) begin
	branch_taken = 1'bx;
	branch_valid = 1'b1;

	case(mem_op)
		3'd0: branch_taken = (alu_out == 0);
		3'd1: branch_taken = (alu_out != 0);
		3'd4,
		3'd6: branch_taken = alu_out[0];
		3'd5,
		3'd7: branch_taken = ~alu_out[0];
		default: branch_valid = 1'b0;
	endcase
end

always @(*) begin
	if(ju_c==0) begin
		ju_out = (mul_div_ready==1'b1) ? mul_div_out : alu_out;
		pc_c = 0;
		b_im_out = 0;
	end
	else if(ju_c==1) begin    // b
		if(branch_valid==1'b1) begin
			ju_out = 0;
			pc_c = branch_taken ? 2 : 0;
			b_im_out = branch_taken ? im_in : 0;
		end
		else begin
			ju_out = {{32{1'bx}}};
			pc_c = {1'bx,1'bx};
			b_im_out = {{13{1'bx}}};
		end
	end
	else if(ju_c==2) begin   // jal
		ju_out = pc_addr;
		pc_c = 0;
		b_im_out = 0;
	end
	else begin
		ju_out = {{32{1'bx}}};
		pc_c = {1'b0,1'b0};
		b_im_out = {{13{1'bx}}};
	end
end

endmodule
		
		
		
		
		
		
		