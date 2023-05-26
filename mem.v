module mem (
output [31:0]data_out,
input [31:0]addr,
input clk,
input rst,
input load,
input store,
input [31:0]data_in,
input [2:0]mem_op
);
reg [7:0] mem [255:0];

reg [31:0] data;
reg [50:0]i;
assign data_out=(load==1)?data:0;

initial
    for(i=0;i<256;i=i+1)
    mem[i]=0;
	 
	 
always@(posedge clk)
if (rst==0)
    for(i=0;i<64;i=i+1)
    mem[i]=0;
else if(store==1)
    begin
	 case(mem_op)
         0:mem[addr]<=data_in[7:0];
			1:{mem[addr+1],mem[addr]}<=data_in[15:0];
			2:{mem[addr+3],mem[addr+2],mem[addr+1],mem[addr]}<=data_in[31:0];
	 endcase
    end
    

always@(*)
    if(load==1)
		begin
		case(mem_op)
			0:data=(mem[addr][7]==1)? {{24{1'b1}},mem[addr]} : {{24{1'b0}},mem[addr]};
			1:data=(mem[addr+1][7]==1)? {{16{1'b1}},mem[addr+1],mem[addr]} : {{16{1'b0}},mem[addr+1],mem[addr]};
			2:data={mem[addr+3],mem[addr+2],mem[addr+1],mem[addr]};
			4:data={{24{1'b0}},mem[addr]};
			5:data={{16{1'b0}},mem[addr+1],mem[addr]};
			default:data={{32{1'bx}}};
		endcase
		end
    else
        data={{32{1'bx}}};
        
    endmodule