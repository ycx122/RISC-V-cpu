`define MemNum 32768  // memory depth(how many words)
`define MemBus 7:0
`define MemAddrBus 14:0

module dram (
  input clka,
  input ena,
  input wea,
  input [`MemAddrBus]addra,
  input [`MemBus]dina,
  input clkb,
  input enb,
  input [`MemAddrBus]addrb,
  output [`MemBus]doutb
);

ram  u_ram (
    .clk                       ( clka                       ),
    .rst                       ( 0                        ),
    .we_i                      ( wea&ena                       ),
    .addr_i                    (addra                      ),
    .data_i                    (dina                      ),
    .re_i                      (enb),
    .addr_o                    (addrb                      ),
    .data_o                    ( doutb                     )
);


endmodule

module ram(

    input wire clk,
    input wire rst,

    input wire we_i,                   // write enable
    input wire[`MemAddrBus] addr_i,    // addr
    input wire[`MemBus] data_i,
    
    input wire re_i,
    input wire[`MemAddrBus] addr_o,    // addr
    output reg[`MemBus] data_o         // read data

    );

    reg[`MemBus] _ram[0:`MemNum - 1];


    always @ (posedge clk) begin
        if (we_i == 1) begin
            _ram[addr_i[14:0]] <= data_i;
        end
    end

    always @ (*) begin
        if (rst == 1) begin
            data_o = 0;
        end else if(re_i==1)begin
            data_o = _ram[addr_o[14:0]];
        end else
            data_o=0;
        
    end

endmodule