//****************************************Copyright (c)***********************************//
//ԭ�Ӹ����߽�ѧƽ̨��www.yuanzige.com
//����֧�֣�www.openedv.com
//�Ա����̣�http://openedv.taobao.com 
//��ע΢�Ź���ƽ̨΢�źţ�"����ԭ��"����ѻ�ȡZYNQ & FPGA & STM32 & LINUX���ϡ�
//��Ȩ���У�����ؾ���
//Copyright(C) ����ԭ�� 2018-2028
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           video_display
// Last modified Date:  2019/7/1 9:30:00
// Last Version:        V1.1
// Descriptions:        ��Ƶ��ʾģ�飬��ʾ����
//----------------------------------------------------------------------------------------
// Created by:          ����ԭ��
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
    
    input        [10:0]  pixel_xpos,  //���ص������
    input        [10:0]  pixel_ypos,  //���ص�������
    output  reg  [23:0]  pixel_data   //���ص�����
);

//parameter define
parameter  H_DISP = 11'd1280;                       //�ֱ��ʡ�����
parameter  V_DISP = 11'd720;                        //�ֱ��ʡ�����

localparam WHITE  = 24'b11111111_11111111_11111111;  //RGB888 ��ɫ
localparam BLACK  = 24'b00000000_00000000_00000000;  //RGB888 ��ɫ
localparam RED    = 24'b11111111_00001100_00000000;  //RGB888 ��ɫ
localparam GREEN  = 24'b00000000_11111111_00000000;  //RGB888 ��ɫ
localparam BLUE   = 24'b00000000_00000000_11111111;  //RGB888 ��ɫ
    
//*****************************************************
//**                    main code
//*****************************************************
wire rom_date;

assign ready=w_en;



//���ݵ�ǰ���ص�����ָ����ǰ���ص���ɫ���ݣ�����Ļ����ʾ����
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