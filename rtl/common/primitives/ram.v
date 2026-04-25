// MemNum is the per-bank byte depth.  Four banks make up one logical
// 32-bit RAM (see rtl/memory/ram_c.v), so total RAM = 4 * MemNum bytes.
//
// 2026-04 (Tier 2 / A1+A2 scale-up): bumped from 32 KiB/bank (128 KB
// total) to 64 KiB/bank (256 KB total) to match the larger MCU footprint
// targeted at Artix-7 200T.  The 200T has plenty of BRAM headroom; the
// extra 4 BRAM tiles per bank pull RAM up without affecting the boot
// ROM or peripheral timing.  default.lds has been updated alongside.
`define MemNum 65536
`define MemBus 7:0
`define MemAddrBus 15:0

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
    .rst                       ( 1'b0                     ),
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
            _ram[addr_i] <= data_i;
        end
    end

    // Combinational read.  We deliberately use a hard sensitivity list
    // (`addr_o`, `re_i`, `rst`) instead of `@*`, because Icarus expands
    // `_ram[addr_o]` under `@*` into "sensitive to all `MemNum` words of
    // _ram" (it warns about it during elaboration).  At MemNum=65536 with
    // four banks, every write re-fires this block 256K times, which makes
    // the `+DRAM` preload + ISA-test simulation crawl to a halt.  A
    // BRAM-style read does not need the array on its sensitivity list:
    // writes already take effect at the next clock edge, and the read
    // address is what changes when the consumer wants a new value.
    always @ (addr_o or re_i or rst) begin
        if (rst == 1) begin
            data_o = 0;
        end else if(re_i==1)begin
            data_o = _ram[addr_o];
        end else
            data_o=0;

    end

endmodule