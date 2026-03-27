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
    output reg clnt_en
    );

    // Decode the target only once so the comparator tree is shared.
    always @(*) begin
        rom_en  = 1'b0;
        ram_en  = 1'b0;
        led_en  = 1'b0;
        key_en  = 1'b0;
        clnt_en = 1'b0;
        uart_en = 1'b0;

        if (d_en == 1'b1) begin
            case (addr[31:24])
                8'h40: led_en  = 1'b1;
                8'h41: key_en  = 1'b1;
                8'h42: clnt_en = 1'b1;
                8'h43: uart_en = 1'b1;
                default: begin
                    if (addr[31:28] == 4'h0)
                        rom_en = 1'b1;
                    else if (addr[31:28] == 4'h2)
                        ram_en = 1'b1;
                end
            endcase
        end
    end
endmodule
