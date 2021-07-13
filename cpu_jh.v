module cpu_jh(
input clk1,
input clk2,
input clk3,
input clk4,
input clk5
 );
 

 
 wire id_s,id_l,id_im_c,id_wb_en;
 wire [4:0] id_rs1,id_rs2,id_rd;
 wire [31:0] id_im;
 wire [2:0] id_alu_op;
 wire [1:0] id_b_en,id_pc_c;
 wire [12:0] id_b_im;
 wire [20:0] id_pc_im;
 wire id_sub;
 
 wire [31:0] reg_data1,reg_data2;
  
 wire [31:0]inst_in;
 
 wire [31:0] id_inst_in,reg_2_in1;
 
 wire rst1;
 
 wire [31:0] i2o_s_data, i2o_op2_out;
 
  
 wire reg_2_store;	
 wire reg_2_load;
 wire [31:0]reg_2_sdata;
 wire [31:0]reg_2_op2;
 wire [31:0]reg_2_op1;
 wire [12:0]reg_2_b_im;
 wire [1:0]reg_2_b_en;
 wire [2:0]reg_2_op;
 wire [4:0]reg_2_rd;
 wire reg_2_wb_en_in;
 wire [31:0]reg_2_pc_rd;
 wire reg_2_id_sub;
 
 wire rst2;
 
 wire [31:0] p_out;
wire [1:0] ju_pc_c;
wire [12:0] ju_im;

wire 		 reg_3_store;
wire 		 reg_3_load;
wire [31:0]reg_3_sdata;
wire [31:0]reg_3_p_out;
wire [4:0] reg_3_rd;
wire 		 reg_3_wb_en_in;

wire [31:0] alu_outdata;
  
wire [31:0] pc_addr;	//pc
wire rst,stop;

wire [31:0]mem_data;
reg [31:0]mem_addr;
reg [31:0]j_p_out;
wire [31:0]j2_p_out;

wire [1:0]pc_c;

wire [31:0]r4_j2_p_out;
wire [4:0]r4_rd;
wire r4_wb_en;


 
assign pc_c= ju_pc_c | id_pc_c;
//pc
 pc c1(pc_addr,clk1,1'b1,pc_c[1],pc_c[0],id_pc_im, 1'b0 ,ju_im);
 

//rom
 rom c2(pc_addr,inst_in);
 
 //stop 
 //assign stop=(inst_in==0)?1:0;
 

 
assign rst1=(pc_c==2'b01 || pc_c==2'b10)?0:1;

//reg1
 reg_1 c3(inst_in,pc_addr,clk2, rst1 ,id_inst_in,reg_2_in1);
 
//id
 id c4(id_inst_in , id_s , id_l , id_rs1 , id_rs2 , id_rd , id_alu_op , id_im , id_im_c , id_pc_im , id_pc_c , id_wb_en , id_b_im , id_b_en ,id_sub);
 

 //regs
 regfile c5(reg_data1,reg_data2,clk1, r4_j2_p_out , r4_rd ,id_rs1,id_rs2, r4_wb_en);
 

 //im2op
 im2op c6(i2o_s_data,i2o_op2_out,reg_data2,id_im,id_im_c);

 
 assign rst2=(pc_c==2'b01)?0:1;
 
 //reg2
 
reg_2 c7(clk3,rst2 , 
id_s, id_l, i2o_s_data, i2o_op2_out, reg_data1, id_b_im, id_b_en, id_alu_op, id_rd, id_wb_en, reg_2_in1, 
reg_2_store, reg_2_load, reg_2_sdata, reg_2_op2, reg_2_op1, reg_2_b_im, reg_2_b_en, reg_2_op, reg_2_rd, reg_2_wb_en_in, reg_2_pc_rd,
id_sub, reg_2_id_sub
);

//alu

alu c8 (alu_outdata, , ,reg_2_op, reg_2_op1 , reg_2_op2 ,reg_2_id_sub);


//beq jump 

ju c9 (p_out, ju_pc_c ,ju_im , reg_2_b_en ,reg_2_b_im ,reg_2_pc_rd ,alu_outdata);


//reg3

reg_3 c10(clk4,1'b1, reg_2_store, reg_2_load, reg_2_sdata , p_out, reg_2_rd , reg_2_wb_en_in,
reg_3_store,
reg_3_load,
reg_3_sdata,
reg_3_p_out,
reg_3_rd,
reg_3_wb_en_in);

//store or load or read_back

always@(*)
if(reg_3_load==1 || reg_3_store==1)
	begin
	mem_addr=reg_3_p_out;
	j_p_out=0;
	end
else
	begin
	j_p_out=reg_3_p_out;
	mem_addr=0;
	end

assign j2_p_out=(reg_3_store==1)?mem_data:j_p_out;

//data store

mem c11(mem_data ,mem_addr , clk5, 1'b1, reg_3_load, reg_3_store , reg_3_sdata );


//reg4

reg_4 c12 (clk5 , 1'b1 ,j2_p_out ,reg_3_rd ,reg_3_wb_en_in ,
r4_j2_p_out,
r4_rd,
r4_wb_en);


endmodule



module reg_4(
input clk,
input rst,
input [31:0]j2_p_out,
input [4:0]rd,
input wb_en,

output reg [31:0]r4_j2_p_out,
output reg [4:0]r4_rd,
output reg r4_wb_en


);
always@(posedge clk)
if(rst==0)
	begin
	r4_j2_p_out<=0;
	r4_rd<=0;
	r4_wb_en<=0;
	end
else
	begin
	r4_j2_p_out<=j2_p_out;
	r4_rd<=rd;
	r4_wb_en<=wb_en;	
	end

endmodule

module reg_3(
input clk,
input rst,
input store,
input load,
input [31:0]sdata,
input [31:0]p_out,
input [4:0]rd,
input wb_en_in,

output reg 		 reg_3_store,
output reg 		 reg_3_load,
output reg [31:0]reg_3_sdata,
output reg [31:0]reg_3_p_out,
output reg [4:0] reg_3_rd,
output reg 		 reg_3_wb_en_in
);
always@(posedge clk)
	if(rst==0)
		begin
		reg_3_store    <=0;		
      reg_3_load     <=0;     
		reg_3_sdata    <=0; 
		reg_3_p_out    <=0;    
		reg_3_rd       <=0;
		reg_3_wb_en_in <=0;
		end
	else
		begin
		reg_3_store    <=store   ;		
      reg_3_load     <=load    ;     
		reg_3_sdata    <=sdata   ; 
		reg_3_p_out    <=p_out   ;    
		reg_3_rd       <=rd      ;
		reg_3_wb_en_in <=wb_en_in;
		end
endmodule		
		
module reg_2(
input clk,
input rst,
input store,
input load,
input [31:0]sdata,
input [31:0]op2,
input [31:0]op1,
input [12:0]b_im,
input [1:0]b_en,
input [2:0]op,
input [4:0]rd,
input wb_en_in,
input [31:0]pc_rd,
output reg reg_2_store,
output reg reg_2_load,
output reg [31:0]reg_2_sdata,
output reg [31:0]reg_2_op2,
output reg [31:0]reg_2_op1,
output reg [12:0]reg_2_b_im,
output reg [1:0]reg_2_b_en,
output reg [2:0]reg_2_op,
output reg [4:0]reg_2_rd,
output reg reg_2_wb_en_in,
output reg [31:0]reg_2_pc_rd,
input id_sub,
output reg reg_2_id_sub
);

always@(posedge clk)
	if(rst==0)
		begin
		reg_2_store<=0;
      reg_2_load<=0;
      reg_2_sdata<=0;
		reg_2_op2<=0;
		reg_2_op1<=0;
		reg_2_b_im<=0;
		reg_2_b_en<=0;
		reg_2_op<=0;
		reg_2_rd<=0;
		reg_2_wb_en_in<=0;
		reg_2_pc_rd<=0;
		reg_2_id_sub<=0;
		end
	else
		begin
		reg_2_store   <=store   ;
      reg_2_load    <=load    ;
      reg_2_sdata   <=sdata   ;
		reg_2_op2     <=op2     ;
		reg_2_op1     <=op1     ;
		reg_2_b_im    <=b_im    ;
		reg_2_b_en    <=b_en    ;
		reg_2_op      <=op      ;
		reg_2_rd      <=rd      ;
		reg_2_wb_en_in<=wb_en_in;
		reg_2_pc_rd   <=pc_rd   ;
		reg_2_id_sub  <=id_sub  ;
		end
endmodule
		
		
module reg_1 (
input [31:0]rom_out,
input [31:0]pc_out,
input clk,
input rst,
output reg [31:0]id_in,
output reg [31:0]reg_2_in
);
always@(posedge clk)
	if(rst==0)
		begin
		id_in<=0;
		reg_2_in<=0;
		end
	else
		begin
		id_in<=rom_out;
		reg_2_in<=pc_out;
		end
		
endmodule
