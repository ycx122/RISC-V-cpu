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

module div_0 (
    input  wire        aclk,
    input  wire [31:0] s_axis_divisor_tdata,
    input  wire        s_axis_divisor_tvalid,
    input  wire [31:0] s_axis_dividend_tdata,
    input  wire        s_axis_dividend_tvalid,
    output reg  [63:0] m_axis_dout_tdata,
    output reg         m_axis_dout_tvalid
);

reg busy;
reg [63:0] result_next;
wire start_div = s_axis_divisor_tvalid && s_axis_dividend_tvalid && !busy;

always @(posedge aclk) begin
    if (start_div) begin
        busy <= 1'b1;
        m_axis_dout_tvalid <= 1'b0;

        if (s_axis_divisor_tdata == 32'b0) begin
            result_next[63:32] <= 32'hffff_ffff;
            result_next[31:0]  <= s_axis_dividend_tdata;
        end else begin
            result_next[63:32] <= s_axis_dividend_tdata / s_axis_divisor_tdata;
            result_next[31:0]  <= s_axis_dividend_tdata % s_axis_divisor_tdata;
        end
    end else if (busy) begin
        busy <= 1'b0;
        m_axis_dout_tdata <= result_next;
        m_axis_dout_tvalid <= 1'b1;
    end else begin
        m_axis_dout_tvalid <= 1'b0;
    end
end

initial begin
    busy = 1'b0;
    result_next = 64'b0;
    m_axis_dout_tdata = 64'b0;
    m_axis_dout_tvalid = 1'b0;
end

endmodule
