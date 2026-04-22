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
    output reg [31:0] dout,
    output clnt_ready,
    output reg time_e_inter
    );
    
    reg [63:0] mtime=0;
    reg [63:0] mtime_cmp=64'h0000_0000_02FA_F080;//64'h0000_0000_02FA_F080;//64'h0000_0000_0000_C350;//0.001s
    reg [31:0] clnt_flag=0;
    
    assign clnt_ready=clnt_en;
    
    
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
            mtime<=0;
        else if(clnt_addr==0 && clnt_en==1 && we==1)
            mtime<={mtime[63:32],din};
        else if(clnt_addr==1 && clnt_en==1 && we==1)
            mtime<={din,mtime[31:0]};        
        else
            mtime<=mtime+1;
    
   always@(posedge clk)
        if(rst_n==0)
            mtime_cmp<=64'h0000_0000_02FA_F080;
        else if(clnt_addr==2 && clnt_en==1 && we==1)
            mtime_cmp<={mtime_cmp[63:32],din};
        else if(clnt_addr==3 && clnt_en==1 && we==1)
            mtime_cmp<={din,mtime_cmp[31:0]};     
    
    always@(posedge clk)
        if(rst_n==0)
            clnt_flag<=0;
        else if(clnt_addr==4 && clnt_en==1 && we==1)
            clnt_flag<=din;  

    // Level-sensitive timer interrupt output.  Previously this was a
    // one-cycle pulse generated only when `mtime == mtime_cmp`; that
    // paired with a bespoke pulse->latch chain in cpu_soc.v/cpu_jh.v and
    // is incompatible with the standard CLINT model where mip.MTIP is a
    // level that stays asserted as long as mtime >= mtime_cmp.  Software
    // clears it by bumping mtime_cmp past mtime in the timer handler.
    //
    // `clnt_flag` is kept as a software enable: writing 0 to the flag
    // register forces MTIP low regardless of the comparison, which is
    // the "disable timer" knob bare-metal code expects.
    always@(posedge clk)
        if(rst_n==0)
            time_e_inter<=0;
        else
            time_e_inter<=(clnt_flag!=32'd0) & (mtime>=mtime_cmp);
    
    
    
    
    
endmodule
