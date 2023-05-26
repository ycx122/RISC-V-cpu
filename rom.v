module rom(
input [31:0] addr,
input cpu_en,
output ready,
output [31:0] rom_data
);
reg [7:0] rom [256:1];

reg [10:0] i;

assign ready=cpu_en;



initial
begin
for(i=1;i<257;i=i+1)
rom[i]=0;

rom[1]=8'h13;
rom[2]=8'h01;
rom[3]=8'h10;
rom[4]=8'h00;

rom[1+4]=8'h93;
rom[2+4]=8'h01;
rom[3+4]=8'h10;
rom[4+4]=8'h00;

rom[1+8]=8'h13;
rom[2+8]=8'h02;
rom[3+8]=8'h10;
rom[4+8]=8'h00;

rom[1+12]=8'h93;
rom[2+12]=8'h00;
rom[3+12]=8'h00;
rom[4+12]=8'h00;

rom[1+16]=8'h93;
rom[2+16]=8'h02;
rom[3+16]=8'ha0;
rom[4+16]=8'h00;

rom[1+20]=8'h33;
rom[2+20]=8'h02;
rom[3+20]=8'h31;
rom[4+20]=8'h00;

rom[1+24]=8'h13;
rom[2+24]=8'h81;
rom[3+24]=8'h01;
rom[4+24]=8'h00;

rom[1+28]=8'h33;
rom[2+28]=8'h00;
rom[3+28]=8'h00;
rom[4+28]=8'h00;

rom[1+32]=8'h33;
rom[2+32]=8'h00;
rom[3+32]=8'h00;
rom[4+32]=8'h00;

rom[1+36]=8'h93;
rom[2+36]=8'h01;
rom[3+36]=8'h02;
rom[4+36]=8'h00;

rom[1+40]=8'h93;
rom[2+40]=8'h80;
rom[3+40]=8'h10;
rom[4+40]=8'h00;

rom[1+44]=8'he3;
rom[2+44]=8'hc4;
rom[3+44]=8'h50;
rom[4+44]=8'hfe;

rom[1+48]=8'h33;
rom[2+48]=8'h00;
rom[3+48]=8'h00;
rom[4+48]=8'h00;
end

reg [7:0]	data_p1, data_p2, data_p3, data_p4;
always@(*)
begin

data_p1=rom[addr+1];
data_p2=rom[addr+2];
data_p3=rom[addr+3];
data_p4=rom[addr+4];

end


assign rom_data={data_p4,data_p3,data_p2,data_p1};

endmodule
