`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/05/27 12:48:57
// Design Name: 
// Module Name: mul
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


module mul(
    input clk,
    input rst,
    input en,
    
    input [31:0] din1,
    input [31:0] din2,
    output [63:0] dout
    );
    wire [63:0]add_0 =(en==1)?((din1<<0 )&({64{din2[0 ]}})):0;
    wire [63:0]add_1 =(en==1)?((din1<<1 )&({64{din2[1 ]}})):0;
    wire [63:0]add_2 =(en==1)?((din1<<2 )&({64{din2[2 ]}})):0;
    wire [63:0]add_3 =(en==1)?((din1<<3 )&({64{din2[3 ]}})):0;
    wire [63:0]add_4 =(en==1)?((din1<<4 )&({64{din2[4 ]}})):0;
    wire [63:0]add_5 =(en==1)?((din1<<5 )&({64{din2[5 ]}})):0;
    wire [63:0]add_6 =(en==1)?((din1<<6 )&({64{din2[6 ]}})):0;
    wire [63:0]add_7 =(en==1)?((din1<<7 )&({64{din2[7 ]}})):0;
    wire [63:0]add_8 =(en==1)?((din1<<8 )&({64{din2[8 ]}})):0;
    wire [63:0]add_9 =(en==1)?((din1<<9 )&({64{din2[9 ]}})):0;
    wire [63:0]add_10=(en==1)?((din1<<10)&({64{din2[10]}})):0;
    wire [63:0]add_11=(en==1)?((din1<<11)&({64{din2[11]}})):0;
    wire [63:0]add_12=(en==1)?((din1<<12)&({64{din2[12]}})):0;
    wire [63:0]add_13=(en==1)?((din1<<13)&({64{din2[13]}})):0;
    wire [63:0]add_14=(en==1)?((din1<<14)&({64{din2[14]}})):0;
    wire [63:0]add_15=(en==1)?((din1<<15)&({64{din2[15]}})):0;
    wire [63:0]add_16=(en==1)?((din1<<16)&({64{din2[16]}})):0;
    wire [63:0]add_17=(en==1)?((din1<<17)&({64{din2[17]}})):0;
    wire [63:0]add_18=(en==1)?((din1<<18)&({64{din2[18]}})):0;
    wire [63:0]add_19=(en==1)?((din1<<19)&({64{din2[19]}})):0;
    wire [63:0]add_20=(en==1)?((din1<<20)&({64{din2[20]}})):0;
    wire [63:0]add_21=(en==1)?((din1<<21)&({64{din2[21]}})):0;
    wire [63:0]add_22=(en==1)?((din1<<22)&({64{din2[22]}})):0;
    wire [63:0]add_23=(en==1)?((din1<<23)&({64{din2[23]}})):0;
    wire [63:0]add_24=(en==1)?((din1<<24)&({64{din2[24]}})):0;
    wire [63:0]add_25=(en==1)?((din1<<25)&({64{din2[25]}})):0;
    wire [63:0]add_26=(en==1)?((din1<<26)&({64{din2[26]}})):0;
    wire [63:0]add_27=(en==1)?((din1<<27)&({64{din2[27]}})):0;
    wire [63:0]add_28=(en==1)?((din1<<28)&({64{din2[28]}})):0;
    wire [63:0]add_29=(en==1)?((din1<<29)&({64{din2[29]}})):0;
    wire [63:0]add_30=(en==1)?((din1<<30)&({64{din2[30]}})):0;
    wire [63:0]add_31=(en==1)?((din1<<31)&({64{din2[31]}})):0;

    wire [63:0]add1_0 =add_0 +add_1 ;
    wire [63:0]add1_1 =add_2 +add_3 ;
    wire [63:0]add1_2 =add_4 +add_5 ;
    wire [63:0]add1_3 =add_6 +add_7 ;
    wire [63:0]add1_4 =add_8 +add_9 ;
    wire [63:0]add1_5 =add_10+add_11;
    wire [63:0]add1_6 =add_12+add_13;
    wire [63:0]add1_7 =add_14+add_15;
    wire [63:0]add1_8 =add_16+add_17;
    wire [63:0]add1_9 =add_18+add_19;
    wire [63:0]add1_10=add_20+add_21;
    wire [63:0]add1_11=add_22+add_23;
    wire [63:0]add1_12=add_24+add_25;
    wire [63:0]add1_13=add_26+add_27;
    wire [63:0]add1_14=add_28+add_29;
    wire [63:0]add1_15=add_30+add_31;

    wire [63:0]add2_0=add1_0 +add1_1 ;
    wire [63:0]add2_1=add1_2 +add1_3 ;
    wire [63:0]add2_2=add1_4 +add1_5 ;
    wire [63:0]add2_3=add1_6 +add1_7 ;
    wire [63:0]add2_4=add1_8 +add1_9 ;
    wire [63:0]add2_5=add1_10+add1_11;
    wire [63:0]add2_6=add1_12+add1_13;
    wire [63:0]add2_7=add1_14+add1_15;
    
    wire [63:0]add3_0=add2_0 +add2_1 ;
    wire [63:0]add3_1=add2_2 +add2_3 ;
    wire [63:0]add3_2=add2_4 +add2_5 ;
    wire [63:0]add3_3=add2_6 +add2_7 ;
    
    wire [63:0]add4_0=add3_0 +add3_1 ; 
    wire [63:0]add4_1=add3_2 +add3_3 ; 
    
    assign dout=add4_0+add4_1;
    
    
    
endmodule
