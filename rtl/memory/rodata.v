`timescale 1ns / 1ps

module rodata(
input clk,
input rst_n,
input rom_en,   //come from addr2c
input [2:0]mem_op,
input re,
input [7:0]rom_data,
input [31:0]addr,

output reg [15:0]rom_addr,
output rom_r_en,    //to rom
output reg [31:0]reg_data,
output reg rom_r_ready
    );

assign rom_r_en=rom_en;

reg [6:0] state=1;
reg [6:0] n_state=1;

localparam	IDLE  = 7'b0000001,
			ONE   = 7'b0000010,
			TWO   = 7'b0000100,
			THREE = 7'b0001000,
			FOUR  = 7'b0010000,
			WAIT  = 7'b0100000,
			READY = 7'b1000000;
			
localparam  LB=3'b000,
            LH=3'b001,
            LW=3'b010,
            LBU=3'b100,
            LHU=3'b101;

always@(posedge clk)
case (state)
     IDLE:      begin 
        reg_data<=0;
     end
     ONE:      begin 
        reg_data<=0;
     end
     TWO:       begin 
        reg_data[7:0]<=rom_data;
     end
     THREE:       begin 
        case(mem_op)
            LB:  reg_data[15:8]<=(reg_data[7]==1)?8'hff:0;
            LH:  reg_data[15:8]<=rom_data;
            LW:  reg_data[15:8]<=rom_data;
            LBU: reg_data[15:8]<=0;
            LHU: reg_data[15:8]<=rom_data;
            default:reg_data[15:8]<=0;
        endcase
     end
     FOUR:     begin 
        case(mem_op)
            LB:  reg_data[23:16]<=(reg_data[7]==1)?8'hff:0;
            LH:  reg_data[23:16]<=(reg_data[15]==1)?8'hff:0;
            LW:  reg_data[23:16]<=rom_data;
            LBU: reg_data[23:16]<=0;
            LHU: reg_data[23:16]<=0;
            default:reg_data[23:16]<=0;
        endcase
     end
     WAIT:      begin 
            case(mem_op)
                LB:  reg_data[31:24]<=(reg_data[7]==1)?8'hff:0;
                LH:  reg_data[31:24]<=(reg_data[15]==1)?8'hff:0;
                LW:  reg_data[31:24]<=rom_data;
                LBU: reg_data[31:24]<=0;
                LHU: reg_data[31:24]<=0;
            default: reg_data[31:24]<=0;
     endcase
     end

endcase

always@(*)                  //change for ruanjian
case (state)
     IDLE:      begin 
        rom_addr=addr+0; 
        rom_r_ready=0;      
     end
     ONE:       begin 
        rom_addr=addr+1;      
        rom_r_ready=0;     
     end
     TWO:       begin 
        rom_addr=addr+2;       
        rom_r_ready=0;
     end
     THREE:     begin 
        rom_addr=addr+3;       
        rom_r_ready=0;
     end
     FOUR:      begin 
        rom_addr=0;       
        rom_r_ready=0;
     end
     WAIT:      begin 
        rom_addr=0;       
        rom_r_ready=0;
     end
     READY:      begin 
        rom_addr=0;       
        rom_r_ready=1;
     end
     default:   begin 
        rom_addr=0;      
        rom_r_ready=1;
     end
endcase

always @(*)
    case(state)
        IDLE:    n_state=ONE;
        ONE:     n_state=TWO;
        TWO:     n_state=THREE;
        THREE:   n_state=FOUR;
        FOUR:    n_state=WAIT;
        WAIT:    n_state=READY;
        READY:   n_state=IDLE;
        default: n_state=IDLE;
        endcase


always @(posedge clk)
    if(rst_n==0)
        state<=1;
    else if(re==1 && rom_en==1)
        state<=n_state;
    
endmodule
