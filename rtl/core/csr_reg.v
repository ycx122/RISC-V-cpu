module csr_reg(
input clk,
input rst_n,
input [11:0]csr,
input [31:0]csr_data,
input [2:0]csr_op,
input e_inter,
input [31:0]pc_addr,

output reg [31:0]wb_data_out,
output reg set_pc_en,
output reg [31:0]set_pc_addr,
output reg data_c
);

reg [31:0]mstatus  ;
reg [31:0]misa     ;
reg [31:0]mie      ;
reg [31:0]mtvec    ;
reg [31:0]mscratch ;
reg [31:0]mepc     ;
reg [31:0]mcause   ;
reg [31:0]mtval    ;
reg [31:0]mip      ;
reg wifi           ;


reg [31:0]csr_data_out;

////////////////////////////////////////////////////////////////////////////////////////////////初始化csr寄存器

initial
begin
misa=32'b0100_0000_0000_0000_0000_0001_0000_0000;	    //机器模式指令集架构寄存器
mstatus=32'b0000_0000_0000_0000_0001_1000_1000_1000;	//机器模式状态寄存器Machine Status Register
mie     =32'b1111_1111_1111_1111_1111_1111_1111_1111;	//机器模式中断使能寄存器Machine Interrupt Enable Register
mtvec   =0;	//机器模式异常入口基地址寄存器Machine Trap-Vector Base-Address Register
mscratch=0;		//机器模式擦写寄存器
mepc    =0;		//机器模式异常pc寄存器Machine Exception Program Counter
mcause  =2;		//机器模式异常原因寄存器
mtval   =0;		//机器模式异常值寄存器
mip     =0;		//机器模式中断等待寄存器
wifi    =0;     //低功耗寄存器
end

////////////////////////////////////////////////////////////////////////////////////////////////数据通路

always@(*)
begin
	if(csr_op[2]==1)
		wb_data_out=csr_data_out;
	else
		wb_data_out=csr_data;
end

////////////////////////////////////////////////////////////////////////////////////////////////特殊寄存器赋值

always@(posedge clk)begin
if(rst_n==0) begin
    misa=32'b0100_0000_0000_0000_0000_0001_0000_0000;	    //机器模式指令集架构寄存器
    mstatus=32'b0000_0000_0000_0000_0001_1000_1000_1000;	//机器模式状态寄存器Machine Status Register
    mie     =32'b1111_1111_1111_1111_1111_1111_1111_1111;	//机器模式中断使能寄存器Machine Interrupt Enable Register
    mtvec   =0;	//机器模式异常入口基地址寄存器Machine Trap-Vector Base-Address Register
    mscratch=0;		//机器模式擦写寄存器
    mepc    =0;		//机器模式异常pc寄存器Machine Exception Program Counter
    mcause  =2;		//机器模式异常原因寄存器
    mtval   =0;		//机器模式异常值寄存器
    mip     =0;		//机器模式中断等待寄存器
    wifi    =0;     //低功耗寄存器
end
else if(e_inter==1 & mstatus[3]==1 & mie[7]==1)begin                                                                           //中断处理
	mcause  =32'h80_00_00_07;
	mepc=pc_addr;
	mstatus={24'b0000_0000_0000_0000_0001_1000,mstatus[3],7'b000_0000};
	wifi=0;
end
else begin                                                                                    //ecall ebreak wifi
if(csr_op==3'b100)begin
	case(csr)
	0:begin//ecall                                                                
       mepc=pc_addr-4;
	   mcause  =32'h00_00_00_0b;
	   mstatus={24'b0000_0000_0000_0000_0001_1000,mstatus[3],7'b000_0000};
	end
	1:begin//ebreak
	   mepc=pc_addr-4;
	   mcause  =32'h00_00_00_03;
	   mstatus={24'b0000_0000_0000_0000_0001_1000,mstatus[3],7'b000_0000};
	end
	770://mert
	   mstatus={24'b0000_0000_0000_0000_0001_1000,1'b1,3'b000,mstatus[7],3'b000};
	261: 			//wifi
	   wifi=1;
	endcase
end                                                                                          //csr inst
else if(csr_op==3'b101)//csrrw 写入
	begin
	case(csr)
	12'h300:mstatus =csr_data;
	12'h301:misa    =csr_data;
	12'h304:mie     =csr_data;
	12'h305:mtvec   =csr_data;
	12'h340:mscratch=csr_data;
	12'h341:mepc    =csr_data;
	12'h342:mcause  =csr_data;
	12'h343:mtval   =csr_data;
	12'h344:mip     =csr_data;
	endcase
	end
else if(csr_op==3'b110)//csrrs 置一
	begin
	case(csr)
	12'h300:mstatus =csr_data| mstatus ;
	12'h301:misa    =csr_data| misa    ;
	12'h304:mie     =csr_data| mie     ;
	12'h305:mtvec   =csr_data| mtvec   ;
	12'h340:mscratch=csr_data| mscratch;
	12'h341:mepc    =csr_data| mepc    ;
	12'h342:mcause  =csr_data| mcause  ;
	12'h343:mtval   =csr_data| mtval   ;
	12'h344:mip     =csr_data| mip     ;
	endcase
	end
else if(csr_op==3'b111)//csrrc 清零
	begin
	case(csr)
	12'h300:mstatus =(~csr_data) & mstatus ;
	12'h301:misa    =(~csr_data) & misa    ;
	12'h304:mie     =(~csr_data) & mie     ;
	12'h305:mtvec   =(~csr_data) & mtvec   ;
	12'h340:mscratch=(~csr_data) & mscratch;
	12'h341:mepc    =(~csr_data) & mepc    ;
	12'h342:mcause  =(~csr_data) & mcause  ;
	12'h343:mtval   =(~csr_data) & mtval   ;
	12'h344:mip     =(~csr_data) & mip     ;
	endcase
	end
	
end
end

always@(*)
begin
	case(csr)                      //csr_read
	12'h300:csr_data_out=mstatus ;
	12'h301:csr_data_out=misa    ;
	12'h304:csr_data_out=mie     ;
	12'h305:csr_data_out=mtvec   ;
	12'h340:csr_data_out=mscratch;
	12'h341:csr_data_out=mepc    ;
	12'h342:csr_data_out=mcause  ;
	12'h343:csr_data_out=mtval   ;
	12'h344:csr_data_out=mip     ;
	default:csr_data_out={{32{1'bx}}};
	endcase
	
end

/////////////////////////////////////////////////////////////////////中断pc控制

always@(*)
begin
if(e_inter==1 & mstatus[3]==1)          //中断
begin
	set_pc_en=1;
	set_pc_addr=mtvec;
	data_c=1;
end
else if(csr_op==3'b100)
begin
	case(csr)
		0:begin	       //ecall
		set_pc_en=1;
		set_pc_addr=mtvec;
		data_c=1;
		end
		1:begin	       //ebreak
		set_pc_en=1;
		set_pc_addr=mtvec;
		data_c=1;
		end
		770:begin	   //mert
		set_pc_en=1;
		set_pc_addr=mepc;
		data_c=1;
		end
		default: begin
		set_pc_en=0;
		set_pc_addr=0;
		data_c=0;
		end
		endcase
end
else if(wifi==1)       //wifi
begin
	set_pc_en=1;
	set_pc_addr=0;				//
	data_c=1;
end
else
begin
	set_pc_en=0;
	set_pc_addr=0;
	data_c=0;
end
end

endmodule
