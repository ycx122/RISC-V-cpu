/////////////////////////////////////////
//21/7/15           //
//21/10/19          //all i
//¹éÁã¸´Î»£¬³£Ì¬Îª¸ß
/////////////////////////////////////////

module cpu_jh
(
input clk,
input cpu_rst,
input [31:0]bus_data_in,
input d_bus_ready,
input i_bus_ready,
input [31:0]i_data_in,
input pc_set_en,
input [31:0]pc_set_data,
input e_inter,

output reg [31:0]data_addr_out,
output reg [31:0]d_data_out,
output reg d_bus_en,
output reg i_bus_en,
output [31:0]pc_addr_out,
//output reg [31:0]pc_bus_data,
//output reg [3:0]pc_bus_addr,
//output reg pc_bus_en,
output reg ram_we,
output reg ram_re,

output [2:0]mem_op_out
 );
 //

wire reg1_en,reg2_en,reg3_en,reg4_en;
wire pc_en;
wire local_stop;
 
initial
 begin
    i_bus_en=1'b1;
 end
 
stop_control ca1 (
d_bus_en,
d_bus_ready,
i_bus_en,
i_bus_ready,
cpu_rst,
local_stop,
reg1_en,
reg2_en,
reg3_en,
reg4_en,
pc_en);



 wire [31:0] pc_addr;	//pc


//1-2

wire id_s, id_l, id_im_c, id_wb_en;
wire [4:0] id_rs1, id_rs2, id_rd;
wire [31:0] id_im;
wire [2:0] id_alu_op;
wire [1:0] id_b_en,id_pc_c;
wire [12:0] id_b_im;
wire [20:0] id_pc_im;
wire id_sub;
wire [2:0]id_mem_op;
wire [14:0] id_csr;
 
wire [31:0] regfile_data1,regfile_data2;
 

 
wire [31:0] reg_1_inst,reg_1_pcaddr;

wire [31:0] im2op_s_data, im2op_op2_out;
 
 //2-3
  
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
wire [31:0]reg_2_pcaddr;
wire reg_2_id_sub;
wire [2:0]reg_2_mem_op;
wire [14:0]reg_2_csr;
 
 
wire [31:0] p_out;
wire [1:0] ju_pc_c;
wire [12:0] ju_im;
wire [31:0] alu_outdata;

//3-4

wire 		 reg_3_store;
wire 		 reg_3_load;
wire [31:0]reg_3_sdata;
wire [31:0]reg_3_p_out;
wire [4:0] reg_3_rd;
wire 		 reg_3_wb_en_in;
wire [2:0]reg_3_mem_op;
wire [14:0] reg_3_csr;
wire [31:0] reg_3_pcaddr;

reg j_load;
reg j_store;

wire [31:0]mem_data;
reg [31:0]mem_addr;
reg [31:0]j_p_out;
wire [31:0]j2_p_out;

wire [1:0]c_pc;

//4-5

wire [31:0]reg_4_j2_p_out;
wire [4:0]reg_4_rd;
wire reg_4_wb_en;
wire [14:0]reg_4_csr;
wire [31:0]reg_4_pcaddr;
wire [31:0]csr_reg_wb_data;


wire pc_set_en_pc;
wire [31:0]pc_set_data_pc;

wire csr_pc_en;
wire [31:0]csr_pc_data;
wire csr_data_c;
wire [3:0]rst;
wire  id_pc_im_f;

 reg [4:0]id_rd_pc;

assign pc_set_en_pc= csr_pc_en | pc_set_en;
assign pc_set_data_pc= (csr_pc_en==1)? csr_pc_data : ((pc_set_en==1) ? pc_set_data : 0);

assign c_pc= ju_pc_c | id_pc_c;
assign pc_addr_out =pc_addr;

assign id_pc_im_f=(reg_1_inst[6:2]==5'b11001)?1:0;

//reg1_en,reg2_en,reg3_en,reg4_en


//pc
 pc a1(
 pc_addr,
 clk,
 cpu_rst,
 c_pc[1],
 c_pc[0],
 id_pc_im, 
 pc_en,
 ju_im,
 pc_set_data_pc,
 pc_set_en_pc,
 id_pc_im_f,
 regfile_data1
 );
 

//rom
wire [31:0]i_data_in_rst;
reg [31:0] pc_addr_reg0;     //leve 0 register
reg flu_c_6;
reg flu_c_t=0;

wire [31:0]stop_cache_reg1;

wire d_wait,i_wait;

 assign d_wait= d_bus_en&(!d_bus_ready);
 assign i_wait= i_bus_en&(!i_bus_ready);

always@(posedge clk)
    flu_c_t=rst[0];
    
always@(*)
    flu_c_6=rst[0] & flu_c_t;    
 
assign i_data_in_rst=(flu_c_6==0)?0:i_data_in;
 
 always@(*)           //level 0
    pc_addr_reg0=pc_addr;
    
stop_cache b1(.clk(clk) ,
.rst(cpu_rst),
.i_data_in(i_data_in_rst), 
.local_stop(local_stop | d_wait | i_wait),
.i_data_out(stop_cache_reg1)
);
 

//reg1
 reg_1 a1_2(
 reg1_en,
 stop_cache_reg1,
 pc_addr_reg0,
 clk, 
 (rst[0] | ( ( local_stop| d_wait | i_wait)  &(c_pc==2'b01) )  ),
 reg_1_inst,
 reg_1_pcaddr
 );

//id
 id a2(
 reg_1_inst , 
 reg_1_pcaddr ,
 id_s , 
 id_l , 
 id_rs1 , 
 id_rs2 , 
 id_rd , 
 id_alu_op , 
 id_im , 
 id_im_c , 
 id_pc_im , 
 id_pc_c , 
 id_wb_en , 
 id_b_im , 
 id_b_en ,
 id_sub,
 id_mem_op,
 id_csr
 );
 
 

 //regs
 regfile b2(
 regfile_data1,
 regfile_data2,
 clk, 
 
 csr_reg_wb_data ,      //write_back
 reg_4_rd ,
 id_rs1,id_rs2, 
 reg_4_wb_en
 );
 

 
 always@(*)
    if(ju_pc_c==2) //2?
        id_rd_pc=0;
    else 
        id_rd_pc=id_rd;

 //reg reg2_en_delay=1;
 
 otof d2(
 .clk(clk),
 .rs1(id_rs1),
 .rs2(id_rs2),
 .rd(id_rd_pc),
 .rd_wb(reg_4_rd),
 .wb_en_2(id_wb_en),
 .wb_en_5(reg_4_wb_en),
 .rst(cpu_rst),
 .local_stop(local_stop),
 .en(reg2_en)
 );

 //im2op
 im2op c2(
 im2op_s_data,
 im2op_op2_out,
 regfile_data2,
 id_im,
 id_im_c
 );

 
reg local_stop_d1;

always@(posedge clk)
    if(rst==0)
        local_stop_d1=0;
    else
        local_stop_d1=local_stop&(reg1_en|reg2_en|reg3_en|reg4_en);

 //reg2
 
reg_2 a2_3(
reg2_en,
clk,
rst[1] , 
id_s, 
id_l, 
im2op_s_data, 
im2op_op2_out, 
regfile_data1, 
id_b_im, 
id_b_en, 
id_alu_op, 
id_rd, 
id_wb_en, 
reg_1_pcaddr, 
id_mem_op,
id_csr,

reg_2_store, 
reg_2_load, 
reg_2_sdata, 
reg_2_op2, 
reg_2_op1, 
reg_2_b_im, 
reg_2_b_en, 
reg_2_op, 
reg_2_rd, 
reg_2_wb_en_in, 
reg_2_pcaddr,
id_sub, 
reg_2_id_sub,
reg_2_mem_op,
reg_2_csr,
local_stop_d1
);

//alu

alu a3 (
alu_outdata,
 ,
 ,
 reg_2_op, 
 reg_2_op1 , 
 reg_2_op2 ,
 reg_2_id_sub
 );


//beq jump 

ju b3 (
p_out, 
ju_pc_c ,
ju_im , 
reg_2_b_en ,
reg_2_b_im ,
reg_2_pcaddr ,
alu_outdata,
reg_2_mem_op        //sport blt 
);


//reg3


reg_3 a3_4(
reg3_en,
clk,
rst[2], 
reg_2_store, 
reg_2_load, 
reg_2_sdata, 
p_out, 
reg_2_rd, 
reg_2_wb_en_in,
reg_2_mem_op,
reg_2_csr,
reg_2_pcaddr,

reg_3_store,
reg_3_load,
reg_3_sdata,
reg_3_p_out,
reg_3_rd,
reg_3_wb_en_in,
reg_3_mem_op,
reg_3_csr,
reg_3_pcaddr
);

//store or load or read_back

always@(*)	//j module
if(reg_3_load==1 || reg_3_store==1)

		begin
		j_p_out=0;
		d_bus_en=1;
		data_addr_out=reg_3_p_out;
		d_data_out=reg_3_sdata;
		j_load=reg_3_load;
		j_store=reg_3_store;
		
		end

else
	begin						//data transport
	j_p_out=reg_3_p_out;
	d_bus_en=0;
	data_addr_out=0;
	d_data_out=0;
	j_load=0;
	j_store=0;
	
	end

assign j2_p_out=(reg_3_load==1)?bus_data_in:j_p_out;		//j2 module

//data store

always@(*)
ram_we=reg_3_store;

always@(*)
ram_re=reg_3_load;

assign mem_op_out=reg_3_mem_op;


//reg4

reg_4 a4_5 (reg4_en, clk , rst[3] ,j2_p_out ,reg_3_rd ,reg_3_wb_en_in ,reg_3_csr,reg_3_pcaddr,

reg_4_j2_p_out,
reg_4_rd,
reg_4_wb_en,
reg_4_csr,
reg_4_pcaddr
);



csr_reg a5 (clk,reg_4_csr[14:3],reg_4_j2_p_out,reg_4_csr[2:0],e_inter,reg_4_pcaddr
,csr_reg_wb_data,csr_pc_en ,csr_pc_data ,csr_data_c);

data_f_control b5 (c_pc ,csr_data_c ,rst);



endmodule



module reg_4(
input reg4_en,
input clk,
input rst,
input [31:0]j2_p_out,
input [4:0]rd,
input wb_en,
input [14:0]csr,
input [31:0]pcaddr,

output reg [31:0]r4_j2_p_out,
output reg [4:0]r4_rd,
output reg r4_wb_en,
output reg [14:0]r4_csr,
output reg [31:0]r4_pcaddr

);
always@(posedge clk)
if(reg4_en==1)
if(rst==0)
	begin
	r4_j2_p_out<=0;
	r4_rd<=0;
	r4_wb_en<=0;
	r4_csr<=0;
	r4_pcaddr<=0;
	end
else
	begin
	r4_j2_p_out<=j2_p_out;
	r4_rd<=rd;
	r4_wb_en<=wb_en;	
	r4_csr<=csr;
	r4_pcaddr<=pcaddr;
	end

endmodule

module reg_3(
input reg3_en,
input clk,
input rst,
input store,
input load,
input [31:0]sdata,
input [31:0]p_out,
input [4:0]rd,
input wb_en_in,
input [2:0]mem_op,
input [14:0]csr,
input [31:0]pcaddr,

output reg 		 reg_3_store=0,
output reg 		 reg_3_load=0,
output reg [31:0]reg_3_sdata,
output reg [31:0]reg_3_p_out,
output reg [4:0] reg_3_rd,
output reg 		 reg_3_wb_en_in,
output reg [2:0]reg_3_mem_op,
output reg [14:0]reg_3_csr,
output reg [31:0]reg_3_pcaddr
);
always@(posedge clk)
if(reg3_en==1)
	if(rst==0)
		begin
		reg_3_store    <=0;		
      reg_3_load     <=0;     
		reg_3_sdata    <=0; 
		reg_3_p_out    <=0;    
		reg_3_rd       <=0;
		reg_3_wb_en_in <=0;
		reg_3_mem_op   <=0;
		reg_3_csr      <=0;
		reg_3_pcaddr   <=0;
		end
	else
		begin
		reg_3_store    <=store   ;		
      reg_3_load     <=load    ;     
		reg_3_sdata    <=sdata   ; 
		reg_3_p_out    <=p_out   ;    
		reg_3_rd       <=rd      ;
		reg_3_wb_en_in <=wb_en_in;
		reg_3_mem_op   <=mem_op  ;
		reg_3_csr      <=csr     ;
		reg_3_pcaddr	<=pcaddr  ;
		end 
endmodule		
		
module reg_2(
input reg2_en,
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
input [2:0]mem_op,
input [14:0]csr,

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
output reg [31:0]reg_2_pcaddr,
input id_sub,
output reg reg_2_id_sub,
output reg [2:0]reg_2_mem_op,
output reg [14:0]reg_2_csr,
input local_stop
);
reg reg_2_store_r;
reg reg_2_load_r;
reg [31:0]reg_2_sdata_r;
reg [31:0]reg_2_op2_r;
reg [31:0]reg_2_op1_r;
reg [12:0]reg_2_b_im_r;
reg [1:0]reg_2_b_en_r;
reg [2:0]reg_2_op_r;
reg [4:0]reg_2_rd_r;
reg reg_2_wb_en_in_r;
reg [31:0]reg_2_pcaddr_r;
reg reg_2_id_sub_r;
reg [2:0]reg_2_mem_op_r;
reg [14:0]reg_2_csr_r;


    always@(*)
/**    if(local_stop==1)
        begin
        reg_2_store   <=0;
        reg_2_load    <=0;
        reg_2_sdata   <=0;
        reg_2_op2     <=0;
        reg_2_op1     <=0;
        reg_2_b_im    <=0;
        reg_2_b_en    <=0;
        reg_2_op      <=0;
        reg_2_rd      <=0;
        reg_2_wb_en_in<=0;
        reg_2_pcaddr  <=0;
        reg_2_id_sub  <=0;
        reg_2_mem_op  <=0;
        reg_2_csr     <=0;
        end
    else                     **/
		begin
		reg_2_store   <=reg_2_store_r   ;
        reg_2_load    <=reg_2_load_r    ;
        reg_2_sdata   <=reg_2_sdata_r   ;
		reg_2_op2     <=reg_2_op2_r     ;
		reg_2_op1     <=reg_2_op1_r     ;
		reg_2_b_im    <=reg_2_b_im_r    ;
		reg_2_b_en    <=reg_2_b_en_r    ;
		reg_2_op      <=reg_2_op_r      ;
		reg_2_rd      <=reg_2_rd_r      ;
		reg_2_wb_en_in<=reg_2_wb_en_in_r;
		reg_2_pcaddr  <=reg_2_pcaddr_r  ;
		reg_2_id_sub  <=reg_2_id_sub_r  ;
		reg_2_mem_op  <=reg_2_mem_op_r  ;
		reg_2_csr     <=reg_2_csr_r     ;
		end


always@(posedge clk)
	if(rst==0)
		begin
		reg_2_store_r   <=0;
        reg_2_load_r    <=0;
        reg_2_sdata_r   <=0;
		reg_2_op2_r     <=0;
		reg_2_op1_r     <=0;
		reg_2_b_im_r    <=0;
		reg_2_b_en_r    <=0;
		reg_2_op_r      <=0;
		reg_2_rd_r      <=0;
		reg_2_wb_en_in_r<=1;	//?
		reg_2_pcaddr_r  <=0;
		reg_2_id_sub_r  <=0;
		reg_2_mem_op_r  <=0;
		reg_2_csr_r     <=0;
		end
	else if(reg2_en==1)
		begin
		reg_2_store_r   <=store   ;
        reg_2_load_r    <=load    ;
        reg_2_sdata_r   <=sdata   ;
		reg_2_op2_r     <=op2     ;
		reg_2_op1_r     <=op1     ;
		reg_2_b_im_r    <=b_im    ;
		reg_2_b_en_r    <=b_en    ;
		reg_2_op_r      <=op      ;
		reg_2_rd_r      <=rd      ;
		reg_2_wb_en_in_r<=wb_en_in;
		reg_2_pcaddr_r  <=pc_rd   ;
		reg_2_id_sub_r  <=id_sub  ;
		reg_2_mem_op_r  <=mem_op  ;
		reg_2_csr_r     <=csr     ;
		end
	else if(local_stop==1)
	begin
		reg_2_store_r   <=0;
        reg_2_load_r    <=0;
        reg_2_sdata_r   <=0;
		reg_2_op2_r     <=0;
		reg_2_op1_r     <=0;
		reg_2_b_im_r    <=0;
		reg_2_b_en_r    <=0;
		reg_2_op_r      <=0;
		reg_2_rd_r      <=0;
		reg_2_wb_en_in_r<=1;	//?
		reg_2_pcaddr_r  <=0;
		reg_2_id_sub_r  <=0;
		reg_2_mem_op_r  <=0;
		reg_2_csr_r     <=0;
		end
        
endmodule
		
		
module reg_1 (
input reg1_en,
input [31:0]rom_out,
input [31:0]pc_out,
input clk,
input rst,
output reg [31:0]id_in,
output reg [31:0]reg_2_in
);
always@(posedge clk)
	begin
	if(rst==0)
		begin
		id_in<=0;
		reg_2_in<=0;
		end
	else if(reg1_en==1)
		begin
		id_in<=rom_out;
		reg_2_in<=pc_out;
		end
    end

		
endmodule

module stop_control(                            //ÔİÍ£¿ØÖÆ
 input d_bus_en,d_bus_ready,i_bus_en,i_bus_ready,cpu_rst,local_stop,
 output wire reg1_en,reg2_en,reg3_en,reg4_en,
 output wire pc_en
);
 
 wire d_wait;
 wire i_wait;
 wire read_wait_f;
 wire local_stop_nor;
 
 assign d_wait= d_bus_en&(!d_bus_ready);
 assign i_wait= i_bus_en&(!i_bus_ready);
 assign read_wait_f=( ! (  d_wait |i_wait   ) );
 assign local_stop_nor=~local_stop;
 
 
 
 assign reg1_en=(cpu_rst==0)?(1'b1):(read_wait_f && local_stop_nor);   //rst 0 have function
 assign reg2_en=(cpu_rst==0)?(1'b1):(read_wait_f && local_stop_nor);
 assign reg3_en=(cpu_rst==0)?(1'b1):read_wait_f;
 assign reg4_en=(cpu_rst==0)?(1'b1):read_wait_f;
 assign pc_en  =(cpu_rst==0)?(1'b1):(read_wait_f && local_stop_nor);
 
 endmodule
 
 module data_f_control (            //³åË¢Ä£¿é
 input [1:0]c_pc,
 input csr_data_c,
 
 output [3:0]rst
 );
  assign rst[0]=(c_pc==2'b01 || c_pc==2'b10 || c_pc==2'b11 || csr_data_c==1)?1'b0:1'b1;   //0 function
  assign rst[1]=(c_pc==2'b10 || c_pc==2'b11 || csr_data_c==1)?1'b0:1'b1;
  assign rst[2]=(csr_data_c==1)?1'b0:1'b1;
  assign rst[3]=1'b1;

	
 
 endmodule
 
 module stop_cache(
 input clk,
 input rst,
 input [31:0]i_data_in,
 input local_stop,
 
 output reg [31:0]i_data_out
 );
 reg local_stop_d1;
 reg [31:0] i_cache;
 reg local_stop_pos;
 always@(posedge clk)
    if(rst==0)
        local_stop_d1=0;
    else
        local_stop_d1=local_stop;
        
 always@(*)
    local_stop_pos=local_stop & (~local_stop_d1);
 
 always@(posedge clk)
    if(rst==0)
        i_cache=0;
    else if(local_stop_pos==1)
        i_cache=i_data_in;
 
 always@(*)
 if(local_stop_d1==0)
    i_data_out=i_data_in;
 else if(local_stop_d1==1)
    i_data_out=i_cache;
 else
    i_data_out=0;
 
 
endmodule