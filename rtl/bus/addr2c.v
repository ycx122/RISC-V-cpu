`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2022/01/21 15:26:31
// Design Name: 
// Module Name: addr2c
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


module addr2c(
    input [31:0] addr,
    input d_en,
    
    output reg ram_en,
    output reg led_en,
    output reg key_en,
    output reg rom_en,
    output reg uart_en,
    output reg clnt_en,
    output reg pic_en,
    output reg cnn_en
    );
    
////////////////////////////////////////////////////////////////////////////      inst
    always @(*)
        if(d_en==1)
        begin
            if(addr>= 32'h00_00_00_00 && addr < 32'h10_00_00_00)
                rom_en=1;
             else
                rom_en=0;
         end
         else
            rom_en=0;
////////////////////////////////////////////////////////////////////////////       data  
    always @(*)
        if(d_en==1)
        begin
            if(addr>=32'h20_00_00_00 && addr<32'h30_00_00_00)
                ram_en=1;
             else
                ram_en=0;
         end
         else
            ram_en=0;
////////////////////////////////////////////////////////////////////////////   out_device
    always @(*)
        if(d_en==1)
        begin
            if(addr>=32'h40_00_00_00 && addr<32'h41_00_00_00)
                led_en=1;
             else
                led_en=0;
         end
         else
            led_en=0;
////////////////////////////////////////////////////////////////////////////   
    always @(*)
        if(d_en==1)
        begin
            if(addr>=32'h41_00_00_00 && addr<32'h42_00_00_00)
                key_en=1;
             else
                key_en=0;
         end
         else
            key_en=0;
////////////////////////////////////////////////////////////////////////////   
    always @(*)
        if(d_en==1)
        begin
            if(addr>=32'h42_00_00_00 && addr<32'h43_00_00_00)
                clnt_en=1;
             else
                clnt_en=0;
         end
         else
            clnt_en=0;
////////////////////////////////////////////////////////////////////////////  
     always @(*)
        if(d_en==1)
        begin
            if(addr>=32'h43_00_00_00 && addr<32'h44_00_00_00)
                uart_en=1;
             else
                uart_en=0;
         end
         else
            uart_en=0;
//////////////////////////////////////////////////////////////////////////// pic_data
    always @(*)
        if(d_en==1)
        begin
            if(addr>=32'h50_00_00_00 && addr<32'h60_00_00_00)
                pic_en=1;
             else
                pic_en=0;
         end
         else
            pic_en=0;
//////////////////////////////////////////////////////////////////////////// cnn_en     
    always @(*)
        if(d_en==1)
        begin
            if(addr>=32'h60_00_00_00 && addr<32'h70_00_00_00)
                cnn_en=1;
             else
                cnn_en=0;
         end
         else
            cnn_en=0;



endmodule
