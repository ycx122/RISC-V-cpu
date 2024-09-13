`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2022/01/21 17:18:12
// Design Name: 
// Module Name: ram_c
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module ram_c(
    input clk,
    input i_en,
    input d_en,         //data_en
    input [31:0] d_addr,//
    input [31:0] i_addr,   
    input [31:0] d_data_in,//
    input [2:0] mem_op,//
    input we,           //write_en
    input re,
    
    output reg [31:0] d_data_out,
    output  [31:0] i_data,
    output ram_ready,
    
    
    /////////////////////////////////////dual_port rom
    
    input cpu_clk,
    input [15:0]rom_addr,
    input rom_r_en,
    output [7:0]rom_data,
    
    
    //////////////////////////////////
    input down_load_key,
    input uart_rxd,
    output uart_txd,
    
    input rst_n
    );
    reg [31:0]addr_ram1;//+0
    reg [31:0]addr_ram2;//+1
    reg [31:0]addr_ram3;//+2
    reg [31:0]addr_ram4;//+3
    
    reg [7:0]d_in_ram1;//+0
    reg [7:0]d_in_ram2;//+1
    reg [7:0]d_in_ram3;//+2
    reg [7:0]d_in_ram4;//+3
    
    wire [7:0]d_out_ram1;//+0
    wire [7:0]d_out_ram2;//+1
    wire [7:0]d_out_ram3;//+2
    wire [7:0]d_out_ram4;//+3
    
    reg [7:0]zero=8'b0000_0000;
    
    reg [3:0]w_en;
   // reg [3:0]r_en;

    
    
    wire [7:0] d3,d2,d1,d0;
    
    reg [7:0] d_o1,d_o2,d_o3,d_o0;             //o0 o0
    reg [15:0]rom_w_addr=0;
    
    assign {d3,d2,d1,d0} = d_data_in;
    
    always@(*)
        begin
            case(d_addr[1:0])
            
                0:{d_in_ram4,d_in_ram3,d_in_ram2,d_in_ram1}={d3,d2,d1,d0};
                1:{d_in_ram4,d_in_ram3,d_in_ram2,d_in_ram1}={d2,d1,d0,d3};
                2:{d_in_ram4,d_in_ram3,d_in_ram2,d_in_ram1}={d1,d0,d3,d2};
                3:{d_in_ram4,d_in_ram3,d_in_ram2,d_in_ram1}={d0,d3,d2,d1};
                default:{d_in_ram4,d_in_ram3,d_in_ram2,d_in_ram1}={d3,d2,d1,d0};
            
            endcase
        end 
    
    always@(*)
        begin
            case(d_addr[1:0])
            
                0:{d_o3,d_o2,d_o1,d_o0}={d_out_ram4,d_out_ram3,d_out_ram2,d_out_ram1};
                1:{d_o2,d_o1,d_o0,d_o3}={d_out_ram4,d_out_ram3,d_out_ram2,d_out_ram1};
                2:{d_o1,d_o0,d_o3,d_o2}={d_out_ram4,d_out_ram3,d_out_ram2,d_out_ram1};
                3:{d_o0,d_o3,d_o2,d_o1}={d_out_ram4,d_out_ram3,d_out_ram2,d_out_ram1};
                default:{d_o3,d_o2,d_o1,d_o0}={d_out_ram4,d_out_ram3,d_out_ram2,d_out_ram1};
            
            endcase
        end 
    
    always@(*)    
        if(mem_op[2]==0 && re==1 && d_en==1)
            begin
            if(mem_op==0)                    //lb
                d_data_out=(d_o0[7]==1)?{24'hff_ff_ff,d_o0}:{zero,zero,zero,d_o0};
            else if(mem_op==1)               //lh
                d_data_out=(d_o1[7]==1)?{16'hff_ff,d_o1,d_o0}:{zero,zero,d_o1,d_o0};
            else if(mem_op==2)                //lw
                d_data_out={d_o3,d_o2,d_o1,d_o0};
            else
                d_data_out=0;
            end
        else if(mem_op[2]==1 && re==1 && d_en==1)
            begin
            if(mem_op[0]==0)                        //lbu
                d_data_out={zero,zero,zero,d_o0};
            else if(mem_op[0]==1)                    //lhu
                d_data_out={zero,zero,d_o1,d_o0};
            else
                d_data_out=0;
            end
        else
            d_data_out=0;
            
 
        
 
    always@(*)                              //write en set
        if(d_en==1 && we==1)
            if (mem_op==0)
                case(d_addr[1:0])
                    0:w_en=4'b0001;
                    1:w_en=4'b0010;
                    2:w_en=4'b0100;
                    3:w_en=4'b1000;
                    default:w_en=0;
                endcase
            else if(mem_op==1)
                case(d_addr[1:0])
                    0:w_en=4'b0011;
                    1:w_en=4'b0110;
                    2:w_en=4'b1100;
                    3:w_en=4'b1001;
                    default:w_en=0; 
                endcase
            else if(mem_op[1]==1)
                w_en=4'b1111;
            else
                w_en=0;
        else
            w_en=0;

/*
        always@(*)                          //read en set
        if(d_en==1 && re==1)                                            
            if (mem_op==0 || mem_op==4)
                case(d_addr[1:0])
                    0:r_en=4'b0001;
                    1:r_en=4'b0010;
                    2:r_en=4'b0100;
                    3:r_en=4'b1000;
                    default:r_en=0;
                endcase
            else if(mem_op==1 || mem_op==5)
                case(d_addr[1:0])
                    0:r_en=4'b0011;
                    1:r_en=4'b0110;
                    2:r_en=4'b1100;
                    3:r_en=4'b1001;
                    default:r_en=0; 
                endcase
            else if(mem_op[1]==1)
                r_en=4'b1111;
            else
                r_en=0;
        else
            r_en=0;
            
            */
  
    always@(*)
        begin
        if(mem_op[0]==1)        //16bit
            begin
            if(d_addr[1:0]==2'b11)
            
                begin

                addr_ram1=d_addr[16:2]+1;
                addr_ram2=d_addr[16:2];
                addr_ram3=d_addr[16:2];
                addr_ram4=d_addr[16:2];
                
                end
                
            else
            
                begin
                addr_ram1=d_addr[16:2];
                addr_ram2=d_addr[16:2];
                addr_ram3=d_addr[16:2];
                addr_ram4=d_addr[16:2];
                end
                
            end
        else if ( mem_op[1]==1 )  //32 bit
            begin
            if(d_addr[1:0]==1)
                
                begin
                addr_ram1=d_addr[16:2]+1;
                addr_ram2=d_addr[16:2];
                addr_ram3=d_addr[16:2];
                addr_ram4=d_addr[16:2];
                end
            else if(d_addr[1:0]==2)
                
                begin
                addr_ram1=d_addr[16:2]+1;
                addr_ram2=d_addr[16:2]+1;
                addr_ram3=d_addr[16:2];
                addr_ram4=d_addr[16:2];
                end  
            else if(d_addr[1:0]==3)
                
                begin
                addr_ram1=d_addr[16:2]+1;
                addr_ram2=d_addr[16:2]+1;
                addr_ram3=d_addr[16:2]+1;
                addr_ram4=d_addr[16:2];
                end 
            else
                addr_ram1=d_addr[16:2];
                addr_ram2=d_addr[16:2];
                addr_ram3=d_addr[16:2];
                addr_ram4=d_addr[16:2];
            end
        else 
            begin
                addr_ram1=d_addr[16:2];
                addr_ram2=d_addr[16:2];
                addr_ram3=d_addr[16:2];
                addr_ram4=d_addr[16:2];
            end
        end
    
    wire rx_done_pos;
    wire rx_done;
    wire rom_w_en =rx_done_pos & down_load_key;
    wire [7:0]uart_rx_data;
    edge_detect2 edge_detect2(  
     .clk(cpu_clk),           
     .signal(rx_done),        
     .pe(rx_done_pos),		//上升沿 
     .ne(),		//下降沿 
     .de()		//双边沿  
     );

    //always@(*)
    //if(i_addr==0)
    //    i_data=32'h2000_00b7;
    //else if(i_addr==4)
    //    i_data=32'h0ff0_0113;
    //else if(i_addr==8)
    //    i_data=32'h0020_a1a3;
    //else if(i_addr==12)
    //    i_data=32'h0030_a183;
    //else if(i_addr==16)
    //    i_data=32'h0030_8203;
    //else 
    //    i_data=0;

    
    i_rom i_rom(.clkb(clk) ,.addrb(i_addr[15:2]), .enb(i_en) ,.doutb(i_data
    ),.dinb(0),.web(0),
    .clka(cpu_clk) ,.addra( ((rom_addr)&{16{rom_r_en}}) | ( (rom_w_addr)&{16{rom_w_en}} )    ), .ena(rom_r_en | rom_w_en) ,.douta(rom_data),.dina(uart_rx_data),.wea(rom_w_en)
    );    //only spoort int read
    //ture two port read and write ram
    //portA width 8
    //portB width 32
    
    uart_rx uart_rx(
	.sys_clk(cpu_clk),			//50M系统时钟
	.sys_rst_n(rst_n),			//系统复位
	.uart_rxd(uart_rxd),			//接收数据线
	.uart_rx_done(rx_done),		//数据接收完成标志
	.uart_rx_data(uart_rx_data)		//接收到的数据
);
    
    uart_tx uart_tx(
	.sys_clk(cpu_clk),	//50M系统时钟
	.sys_rst_n(rst_n),	//系统复位
	.uart_data(83),	//发送的8位置数据
	.uart_tx_en(rx_done_pos==1 && rom_w_addr==0),	//发送使能信号
	.uart_txd(uart_txd)	//串口发送数据线
 
);
    
    always @(posedge cpu_clk)
        if(rst_n==0)
            rom_w_addr=0;
        else if(rx_done_pos && down_load_key)
            rom_w_addr=rom_w_addr+1;
        //else if(down_load_key==0)
         //   rom_w_addr=0;
    
    
    dram d_ram_1(.clka(cpu_clk) ,.clkb(cpu_clk) ,.ena(w_en[0]),.enb(re) , .dina(d_in_ram1) ,.doutb(d_out_ram1) ,.addra(addr_ram1[14:0]),.addrb(addr_ram1[14:0]),.wea(w_en[0]));   
    dram d_ram_2(.clka(cpu_clk) ,.clkb(cpu_clk) ,.ena(w_en[1]),.enb(re) , .dina(d_in_ram2) ,.doutb(d_out_ram2) ,.addra(addr_ram2[14:0]),.addrb(addr_ram2[14:0]),.wea(w_en[1]));  
    dram d_ram_3(.clka(cpu_clk) ,.clkb(cpu_clk) ,.ena(w_en[2]),.enb(re) , .dina(d_in_ram3) ,.doutb(d_out_ram3) ,.addra(addr_ram3[14:0]),.addrb(addr_ram3[14:0]),.wea(w_en[2])); 
    dram d_ram_4(.clka(cpu_clk) ,.clkb(cpu_clk) ,.ena(w_en[3]),.enb(re) , .dina(d_in_ram4) ,.doutb(d_out_ram4) ,.addra(addr_ram4[14:0]),.addrb(addr_ram4[14:0]),.wea(w_en[3]));
    //simple two port ram
    //portA width 8
    //portB width 8
    
    wire ram_ready_r;
    wire ram_ready_w=we&d_en;
    
    assign ram_ready=ram_ready_r|ram_ready_w;
    
    delay delay1(cpu_clk,re&d_en,0,ram_ready_r);
    
    endmodule
    
module edge_detect2(
input		clk,
input		signal,
output	reg	pe,		//上升沿
output	reg	ne,		//下降沿
output	reg	de		//双边沿
);

reg reg1;

always@(posedge clk) begin
	reg1	<= signal;
	
	pe		<= (~reg1) & signal;
	ne		<= reg1 & (~signal);
	de		<= reg1 ^ signal;
end

endmodule

    
    
    
    module delay (
    input clk,
    input re,
    input we,
    output reg ready
    );
    localparam IDLE =2'b00;
    localparam D1   =2'b01;
    localparam D2   =2'b10;
    
    wire e;
    
    assign e= we | re;
    
    reg [1:0]state =0;
    reg [1:0] n_state;
    
    always@(*)
        case(state)
            IDLE:begin
                if(e==1)
                    n_state=D2;//D1
                else
                    n_state=IDLE;
                end
            D1:begin
                n_state=D2;
                end
            D2:begin
                    n_state=IDLE;
                end
            default:n_state=IDLE;
            endcase
      

    
    always@(*)
    if(state==D2)
        ready=1;
    else
        ready=0;
        

    
    always@(posedge clk)
        state=n_state;
  
    
    
    
    endmodule
    
    
   // reg state;
    //reg bad_los;
    
    /*
    always@(*)
        begin
        if(mem_op[0]==1)        //16bit
            begin
            if(d_addr[1:0]==2'b11)
                bad_los=1;
            else
                bad_los=0;
            end
        else if ( mem_op[1]==1 )  //32 bit
            begin
            if(d_addr[1:0]!=0)
                bad_los=1;
            else
                bad_los=0;
            end
        else 
            begin
            bad_los=0;
            end
        end
    
    
    */
    
    
/*

module up_find(
input clk,
input up_find_sign,
output up_sign

);
reg up_d1;

always@(posedge clk)
    up_d1=up_find_sign;



endmodule
*/