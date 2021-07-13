module mem (
output [31:0]data_out,
input [31:0]addr,
input clk,
input rst,
input load,
input store,
input [31:0]data_in
);
reg [31:0] mem [64:0];

reg [31:0] data;
reg [50:0]i;
assign data_out=data;

initial
    for(i=0;i<64;i=i+1)
    mem[i]=0;
	 
	 
always@(posedge clk)
if (rst==0)
    for(i=0;i<64;i=i+1)
    mem[i]=0;
else if(store==1)
    begin
        mem[addr]<=data_in;
    end
    

always@(*)
    if(load==1)
        data=mem[addr];
    else
        data={{32{1'bx}}};
        
    endmodule