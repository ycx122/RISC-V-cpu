`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2023/01/29 00:53:44
// Design Name: 
// Module Name: clnt
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


module clnt(
    input clk,
    input rst_n,
    input clnt_en,
    input re,
    input we,
    input [2:0] clnt_addr,
    input [31:0] din,
    output reg [31:0] dout
    );
    
    reg [63:0] mtime=0;
    reg [63:0] mtime_cmp=64'h0000_0000_0000_0C350;//0.001s
    reg [31:0] clnt_flag=0;
    
    
    always@(*)
    if(clnt_en==1 && re==1)
        case(clnt_addr)
        0:dout=mtime[31:0];
        1:dout=mtime[63:32];
        2:dout=mtime_cmp[31:0];
        3:dout=mtime_cmp[63:32];
        4:dout=clnt_flag;
        default:dout=0;
        endcase
    else
        dout=0;
    
    always@(posedge clk)
        if(rst_n==0)
            mtime=0;
        else if(clnt_addr==0 && clnt_en==1 && we==1)
            mtime={mtime[63:32],din};
        else if(clnt_addr==1 && clnt_en==1 && we==1)
            mtime={din,mtime[31:0]};        
        else
            mtime=mtime+1;
    
   always@(posedge clk)
        if(rst_n==0)
            mtime_cmp=0;
        else if(clnt_addr==2 && clnt_en==1 && we==1)
            mtime_cmp={mtime_cmp[63:32],din};
        else if(clnt_addr==3 && clnt_en==1 && we==1)
            mtime_cmp={din,mtime_cmp[31:0]};     
    
    always@(posedge clk)
        if(rst_n==0)
            clnt_flag=0;
        else if(clnt_addr==4 && clnt_en==1 && we==1)
            clnt_flag=din;  
        else if(mtime>=mtime_cmp)           
            clnt_flag=1;
        else if(mtime<mtime_cmp)           
            clnt_flag=0;
    
    
    
    
    
    
    
endmodule
