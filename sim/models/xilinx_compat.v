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

module i_rom (
    input  wire        clkb,
    input  wire [13:0] addrb,
    input  wire        enb,
    output wire [31:0] doutb,
    input  wire [31:0] dinb,
    input  wire        web,

    input  wire        clka,
    input  wire [15:0] addra,
    input  wire        ena,
    output wire [7:0]  douta,
    input  wire [7:0]  dina,
    input  wire        wea
);

localparam ROM_BYTES = 65536;

reg [7:0] mem [0:ROM_BYTES-1];
reg [1023:0] init_file;
integer idx;

wire [15:0] word_byte_addr = {addrb, 2'b00};

initial begin
    for (idx = 0; idx < ROM_BYTES; idx = idx + 1) begin
        mem[idx] = 8'h00;
    end

    if ($value$plusargs("IROM=%s", init_file)) begin
        $display("i_rom: loading image from %0s", init_file);
        $readmemh(init_file, mem);
    end
end

always @(posedge clka) begin
    if (ena && wea) begin
        mem[addra] <= dina;
    end
end

// Port A mirrors the Vivado BRAM "Read-First with output register" mode
// that the real board uses: two pipeline stages on douta.  rtl/memory/rodata.v
// relies on this latency, so leaving douta combinational (as an older version
// of this stub did) breaks ROM-data loads in simulation while silently working
// on hardware.
reg [7:0] douta_r0;
reg [7:0] douta_r1;
always @(posedge clka) begin
    douta_r0 <= ena ? mem[addra] : 8'h00;
    douta_r1 <= douta_r0;
end
assign douta = douta_r1;

assign doutb = enb ? {mem[word_byte_addr + 16'd3],
                      mem[word_byte_addr + 16'd2],
                      mem[word_byte_addr + 16'd1],
                      mem[word_byte_addr]} : 32'h0000_0000;

// Keep unused ports referenced so simulators stay quiet.
wire _unused_irom = clkb ^ web ^ dinb[0];

endmodule

// div_0 (Xilinx IP) stub was retired in Tier 2 of the improvement plan.
// The divider is now provided by the self-contained iterative module in
// rtl/core/div_gen.v, which is used by both simulation and synthesis.
