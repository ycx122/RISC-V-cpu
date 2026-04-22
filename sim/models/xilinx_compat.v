`timescale 1ns / 1ps

// Lightweight simulation-only stand-ins for Vivado-generated IP.
// Compile this file alongside the RTL when using Icarus Verilog.

module clk_wiz_0 (
    input  wire clk_in1,
    output wire clk_out1,
    output wire clk_out2,
    output wire clk_out3,
    output wire clk_out4,
    output wire locked
);

assign clk_out1 = clk_in1;
assign clk_out2 = clk_in1;
assign clk_out3 = clk_in1;
assign clk_out4 = clk_in1;
assign locked   = 1'b1;

endmodule

// i_rom -- 64KB dual-port BRAM stub matching the Vivado BRAM Generator IP
// configuration used on the board.  Both ports now use a 14-bit *word*
// address space (i.e. 16K x 32-bit = 64 KB), matching Vivado's asymmetric
// BRAM with 32-bit data on both sides and per-byte write strobes on port A.
//
// Port A (clka): 32-bit read + 32-bit data write with 4-bit byte-write
//                enable.  Two registered pipeline stages on douta, matching
//                the "Read-First with output register" mode the real BRAM
//                is configured for.  UART-download uses byte-strobes to
//                write one byte at a time; rodata uses full-word reads.
//
// Port B (clkb): 32-bit read only, 1-cycle latency (instruction fetch).
//
// NOTE: when regenerating the IP in Vivado, make sure port A is set to
// "Byte Write Enable = 8" with a 32-bit interface; the previous 8-bit
// port-A configuration is no longer supported by ram_c.v / rodata.v.
module i_rom (
    input  wire        clkb,
    input  wire [13:0] addrb,
    input  wire        enb,
    output wire [31:0] doutb,
    input  wire [31:0] dinb,
    input  wire        web,

    input  wire        clka,
    input  wire [13:0] addra,
    input  wire        ena,
    output wire [31:0] douta,
    input  wire [31:0] dina,
    input  wire [3:0]  wea
);

localparam ROM_WORDS = 16384;
localparam ROM_BYTES = 65536;

// Underlying storage kept byte-addressable so $readmemh can load the
// .verilog image a byte at a time (same format as before).  Port A's
// per-byte wea[] lets UART download hit one byte at a time without
// needing a read-modify-write.
reg [7:0] mem [0:ROM_BYTES-1];
reg [1023:0] init_file;
integer idx;

wire [15:0] addra_byte = {addra, 2'b00};
wire [15:0] addrb_byte = {addrb, 2'b00};

initial begin
    for (idx = 0; idx < ROM_BYTES; idx = idx + 1) begin
        mem[idx] = 8'h00;
    end

    if ($value$plusargs("IROM=%s", init_file)) begin
        $display("i_rom: loading image from %0s", init_file);
        $readmemh(init_file, mem);
    end
end

// Port A: byte-enable writes.  Any subset of the 4 byte lanes can be
// written in a single cycle.
always @(posedge clka) begin
    if (ena) begin
        if (wea[0]) mem[addra_byte + 16'd0] <= dina[7:0];
        if (wea[1]) mem[addra_byte + 16'd1] <= dina[15:8];
        if (wea[2]) mem[addra_byte + 16'd2] <= dina[23:16];
        if (wea[3]) mem[addra_byte + 16'd3] <= dina[31:24];
    end
end

// Port A: 32-bit read with 2-stage output pipeline.  rodata.v expects
// douta to be valid N+2 cycles after driving addra/ena on cycle N.
reg [31:0] douta_r0;
reg [31:0] douta_r1;
always @(posedge clka) begin
    if (ena) begin
        douta_r0 <= {mem[addra_byte + 16'd3],
                     mem[addra_byte + 16'd2],
                     mem[addra_byte + 16'd1],
                     mem[addra_byte + 16'd0]};
    end else begin
        douta_r0 <= 32'h0000_0000;
    end
    douta_r1 <= douta_r0;
end
assign douta = douta_r1;

// Port B (instruction fetch): 1-cycle combinational read.
assign doutb = enb ? {mem[addrb_byte + 16'd3],
                      mem[addrb_byte + 16'd2],
                      mem[addrb_byte + 16'd1],
                      mem[addrb_byte]} : 32'h0000_0000;

// Port B is read-only; dinb/web are ignored.  Keep them referenced so
// simulators stay quiet.
wire _unused_irom = clkb ^ web ^ dinb[0];

endmodule

// div_0 (Xilinx IP) stub was retired in Tier 2 of the improvement plan.
// The divider is now provided by the self-contained iterative module in
// rtl/core/div_gen.v, which is used by both simulation and synthesis.
