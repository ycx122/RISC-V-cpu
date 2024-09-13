`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2024/04/06 18:38:49
// Design Name: You CX
// Module Name: mul_div
// Project Name: mul and div
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


module mul_div(
    input [31:0] op1,
    input [31:0] op2,
    input [2:0] opcode,
    input en,
    
    input clk,
    input rst_n,
    
    output reg [31:0] mul_div_output,
    output ready
    );
    
wire op1_neg=op1[31];
wire op2_neg=op2[31];

wire [31:0] op1_postive=(op1_neg==1)?-op1:op1;
wire [31:0] op2_postive=(op2_neg==1)?-op2:op2;
    
wire [63:0]mul_out;

wire mul   =(en==1 & opcode==0)?1:0;
wire mulh  =(en==1 & opcode==1)?1:0;
wire mulhsu=(en==1 & opcode==2)?1:0;
wire mulhu  =(en==1 & opcode==3)?1:0;
wire div   =(en==1 & opcode==4)?1:0;
wire divu  =(en==1 & opcode==5)?1:0;
wire rem   =(en==1 & opcode==6)?1:0;
wire remu  =(en==1 & opcode==7)?1:0;

wire [31:0] mul_din1=(mulh|mulhsu)?op1_postive:op1;
wire [31:0] mul_din2=(mulh)?op2_postive:op2;

wire [31:0] div_din1=(div|rem)?op1_postive:op1;
wire [31:0] div_din2=(div|rem)?op2_postive:op2;

wire [63:0]mul_output;
wire [63:0]div_output;

wire [31:0]div_result=div_output[63:32];
wire [31:0]rem_result=div_output[31:0];

wire div_ready;
wire div_valid;

div_state_machine dsm_0(
    .clk(clk),            // ʱ���ź�
    .rst_n(rst_n),          // ��λ�ź�
    .start(div|divu|rem|remu),          // ��ʼ�ź�
    .ready(div_ready),          // ��������źţ�ready��
    .start_signal(div_valid)    // ��ʼ�źű�־
);
    
    mul mul_test(
    .clk(clk),
    .rst(0),
    .en(mul|mulh|mulhsu|mulhu),
    
    .din1(mul_din1),
    .din2(mul_din2),
    .dout(mul_output)
    );
    
    div_0 div_0(
    .aclk(clk),
    .s_axis_divisor_tdata(div_din2),
    .s_axis_divisor_tvalid(div_valid),
    .s_axis_dividend_tdata(div_din1),
    .s_axis_dividend_tvalid(div_valid),
    
    .m_axis_dout_tdata(div_output),
    .m_axis_dout_tvalid(div_ready)
    
    
    );

always@(*)
    if(mul==1)
        mul_div_output<=mul_output[31:0];
    else if(mulh==1)    
        mul_div_output<=((op1_neg^op2_neg)?-mul_output:mul_output)>>32;
    else if(mulhsu==1)
        mul_div_output<=((op1_neg)?-mul_output:mul_output)>>32;
    else if(mulhu==1)
        mul_div_output<=mul_output[63:32];
    else if(div==1)
        mul_div_output<=(op1_neg^op2_neg)?-div_result:div_result;
    else if(divu==1)
        mul_div_output<=div_result;
    else if(rem==1)
        mul_div_output<=(op1_neg)?-rem_result:rem_result;
    else if(remu==1)
        mul_div_output<=rem_result;
    else
        mul_div_output<=0;
        
assign ready=mul|mulh|mulhsu|mulhu|(div&div_ready)|(divu&div_ready)|(rem&div_ready)|(remu&div_ready);
    
endmodule

module div_state_machine(
    input wire clk,            // ʱ���ź�
    input wire rst_n,          // ��λ�ź�
    input wire start,          // ��ʼ�ź�
    input wire ready,          // ��������źţ�ready��
    output reg start_signal    // ��ʼ�źű�־
);

// ״̬����
localparam IDLE              = 1'b0,
           WAIT_FOR_COMPLETION = 1'b1;

// ״̬�Ĵ���
reg state;

// ״̬ת���߼�
always @(posedge clk ) begin
    if (rst_n==0) begin
        // �첽��λ��IDLE״̬
        state <= IDLE;
        start_signal <= 1'b0;
    end else begin
        case (state)
            IDLE: begin
                // �ڿ���״̬�յ�start�źţ�����ȴ��������״̬
                if (start) begin
                    state <= WAIT_FOR_COMPLETION;
                    start_signal <= 1'b1;  // ���Ϳ�ʼ�źű�־
                end
            end
            WAIT_FOR_COMPLETION: begin
                start_signal <= 1'b0;  // �����ʼ�źű�־
                // �ڵȴ�״̬�յ�ready�źţ�����IDLE״̬
                if (ready) begin
                    state <= IDLE;
                end
            end
            default: begin
                // �쳣������ص���ʼ״̬
                state <= IDLE;
            end
        endcase
    end
end

endmodule
