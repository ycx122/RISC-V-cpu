module im2op(
output reg [31:0] store_data,
output reg [31:0] op2_out,
input [31:0] op2_in,
input [31:0] im_in,
input ce
);

always@(*)
begin
	if(ce==1)
		begin
		op2_out=im_in;
		store_data=op2_in;
		end
	else
		begin
		op2_out=op2_in;
		store_data=im_in;
		end
		
end


endmodule
		