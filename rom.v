module rom(
input [31:0] addr,
output [31:0] rom_data
);
reg [7:0] rom [256:1];

reg [10:0] i;
initial
begin
for(i=1;i<257;i=i+1)
rom[i]=0;

rom[1]=8'h03;
rom[2]=8'h20;
rom[3]=8'h00;
rom[4]=8'h93;

rom[1+4]=8'h00;
rom[2+4]=8'h00;
rom[3+4]=8'h00;
rom[4+4]=8'h33;

rom[1+8]=8'h00;
rom[2+8]=8'h00;
rom[3+8]=8'h00;
rom[4+8]=8'h33;

rom[1+12]=8'h00;
rom[2+12]=8'h21;
rom[3+12]=8'h01;
rom[4+12]=8'h13;

rom[1+16]=8'h00;
rom[2+16]=8'h10;
rom[3+16]=8'h80;
rom[4+16]=8'h93;

rom[1+20]=8'hfe;
rom[2+20]=8'h11;
rom[3+20]=8'h4c;
rom[4+20]=8'he3;
end

reg [7:0]	data_p1, data_p2, data_p3, data_p4;
always@(*)
begin

data_p1=rom[addr+1];
data_p2=rom[addr+2];
data_p3=rom[addr+3];
data_p4=rom[addr+4];

end


assign rom_data={data_p1,data_p2,data_p3,data_p4};

endmodule
