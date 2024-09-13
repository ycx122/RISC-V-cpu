module otof1(
    input clk,
    input [4:0] rs1,
    input [4:0] rs2,
    input [4:0] rd,//
    input [4:0] rd_wb,
    input wb_en_2,//
    input wb_en_5,
    input rst,
    
    input en,//
    
    input [4:0] rd_3,
    input [4:0] rd_4,
    input wb_en_3,
    input wb_en_4,
    
    output local_stop
    );

reg stop_0;
reg stop_1;

assign local_stop=stop_0|stop_1;

always@(*)begin
if(((rs1==rd_3&wb_en_3) | (rs1==rd_4&wb_en_4) | (rs1==rd_wb&wb_en_5))&rs1!=0)
    stop_0=1;
else
    stop_0=0;
end

always@(*)begin
if(((rs2==rd_3&wb_en_3) | (rs2==rd_4&wb_en_4) | (rs2==rd_wb&wb_en_5))&rs2!=0)
    stop_1=1;
else
    stop_1=0;
end

endmodule