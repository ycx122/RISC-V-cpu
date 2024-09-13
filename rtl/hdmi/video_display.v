//****************************************Copyright (c)***********************************//
//原子哥在线教学平台：www.yuanzige.com
//技术支持：www.openedv.com
//淘宝店铺：http://openedv.taobao.com 
//关注微信公众平台微信号："正点原子"，免费获取ZYNQ & FPGA & STM32 & LINUX资料。
//版权所有，盗版必究。
//Copyright(C) 正点原子 2018-2028
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           video_display
// Last modified Date:  2019/7/1 9:30:00
// Last Version:        V1.1
// Descriptions:        视频显示模块，显示彩条
//----------------------------------------------------------------------------------------
// Created by:          正点原子
// Created date:        2019/7/1 9:30:00
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

module  video_display(
    input                cpu_clk,
    input                pixel_clk,
    input                sys_rst_n,
    
    input [14:0]addr,
    input [31:0]data_in,
    input       w_en,
    output      ready,
    
    input        [10:0]  pixel_xpos,  //像素点横坐标
    input        [10:0]  pixel_ypos,  //像素点纵坐标
    output  reg  [23:0]  pixel_data   //像素点数据
);

//parameter define
parameter  H_DISP = 11'd1280;                       //分辨率——行
parameter  V_DISP = 11'd720;                        //分辨率——列

localparam WHITE  = 24'b11111111_11111111_11111111;  //RGB888 白色
localparam BLACK  = 24'b00000000_00000000_00000000;  //RGB888 黑色
localparam RED    = 24'b11111111_00001100_00000000;  //RGB888 红色
localparam GREEN  = 24'b00000000_11111111_00000000;  //RGB888 绿色
localparam BLUE   = 24'b00000000_00000000_11111111;  //RGB888 蓝色
    
//*****************************************************
//**                    main code
//*****************************************************
wire rom_date;

assign ready=w_en;



//根据当前像素点坐标指定当前像素点颜色数据，在屏幕上显示彩条
always @(posedge pixel_clk ) begin
    if (!sys_rst_n)
        pixel_data <= 16'd0;
    else begin
        pixel_data<={24{rom_date}};
    end
end

blk_mem_gen_0 dp(
.clka(cpu_clk),
.addra(addr),
.dina(data_in),
.ena(1),
.wea(w_en),

.clkb(pixel_clk),
.addrb((pixel_ypos<<8)+(pixel_ypos<<10)+pixel_xpos),
.doutb(rom_date),
.enb(1)
);

endmodule