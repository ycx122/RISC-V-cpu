`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: mul_div
// Project: RISC-V CPU
// Description:
//   RV32M multiply / divide / remainder unit.
//
//   opcode encoding (matches id.v):
//     0  MUL      (low 32 bits of signed*signed)
//     1  MULH     (high 32 bits of signed*signed)
//     2  MULHSU   (high 32 bits of signed*unsigned)
//     3  MULHU    (high 32 bits of unsigned*unsigned)
//     4  DIV      (signed)
//     5  DIVU     (unsigned)
//     6  REM      (signed remainder)
//     7  REMU     (unsigned remainder)
//
//   Corner-case semantics (RV32M spec):
//     DIV/REM by zero  -> quotient = -1 (0xFFFF_FFFF), remainder = dividend
//     DIVU/REMU by 0   -> quotient = 0xFFFF_FFFF, remainder = dividend
//     DIV overflow     -> MIN_INT / -1 : quotient = MIN_INT, remainder = 0
//
//   The iterative divider (rtl/core/div_gen.v) is invoked in unsigned form
//   with pre-negated operands; sign reconstruction happens in the output mux
//   below. Divide-by-zero / overflow cases bypass the divider output entirely
//   and return the spec values directly.
//////////////////////////////////////////////////////////////////////////////////


module mul_div(
    input  [31:0] op1,
    input  [31:0] op2,
    input  [2:0]  opcode,
    input         en,

    input         clk,
    input         rst_n,

    output reg [31:0] mul_div_output,
    output            ready
);

wire op1_neg = op1[31];
wire op2_neg = op2[31];

wire [31:0] op1_postive = op1_neg ? -op1 : op1;
wire [31:0] op2_postive = op2_neg ? -op2 : op2;

wire mul    = en & (opcode == 3'd0);
wire mulh   = en & (opcode == 3'd1);
wire mulhsu = en & (opcode == 3'd2);
wire mulhu  = en & (opcode == 3'd3);
wire div    = en & (opcode == 3'd4);
wire divu   = en & (opcode == 3'd5);
wire rem    = en & (opcode == 3'd6);
wire remu   = en & (opcode == 3'd7);

wire [31:0] mul_din1 = (mulh | mulhsu) ? op1_postive : op1;
wire [31:0] mul_din2 = (mulh)          ? op2_postive : op2;

wire [31:0] div_din1 = (div | rem) ? op1_postive : op1;
wire [31:0] div_din2 = (div | rem) ? op2_postive : op2;

wire [63:0] mul_output;
wire [31:0] div_result;
wire [31:0] rem_result;
wire        div_ready;

wire div_zero     = (op2 == 32'b0);
wire div_overflow = (op1 == 32'h8000_0000) && (op2 == 32'hffff_ffff);

mul mul_test(
    .clk (clk),
    .rst (1'b0),
    .en  (mul | mulh | mulhsu | mulhu),
    .din1(mul_din1),
    .din2(mul_din2),
    .dout(mul_output)
);

// Iterative restoring radix-4 divider (see rtl/core/div_gen.v).
// `start` is held for the entire duration that the div/rem op sits in
// stage 2 of the pipeline; div_gen only latches the operands on the
// IDLE->RUN transition, so repeated assertions during the ~18-cycle run
// are harmless.
div_gen div_gen_u (
    .clk      (clk),
    .rst_n    (rst_n),
    .start    (div | divu | rem | remu),
    .dividend (div_din1),
    .divisor  (div_din2),
    .ready    (div_ready),
    .quotient (div_result),
    .remainder(rem_result)
);

always @(*) begin
    if (mul) begin
        mul_div_output = mul_output[31:0];
    end else if (mulh) begin
        mul_div_output = (((op1_neg ^ op2_neg) ? -mul_output : mul_output) >> 32);
    end else if (mulhsu) begin
        mul_div_output = ((op1_neg ? -mul_output : mul_output) >> 32);
    end else if (mulhu) begin
        mul_div_output = mul_output[63:32];
    end else if (div) begin
        if (div_zero)
            mul_div_output = 32'hffff_ffff;
        else if (div_overflow)
            mul_div_output = 32'h8000_0000;
        else
            mul_div_output = (op1_neg ^ op2_neg) ? -div_result : div_result;
    end else if (divu) begin
        mul_div_output = div_zero ? 32'hffff_ffff : div_result;
    end else if (rem) begin
        if (div_zero)
            mul_div_output = op1;
        else if (div_overflow)
            mul_div_output = 32'h0000_0000;
        else
            mul_div_output = op1_neg ? -rem_result : rem_result;
    end else if (remu) begin
        mul_div_output = div_zero ? op1 : rem_result;
    end else begin
        mul_div_output = 32'b0;
    end
end

// Multiplication is combinational (1-cycle, mostly LUT adder tree), so any
// mul op is "ready" in the same cycle it is presented. Div/rem wait for the
// iterative divider's one-cycle `ready` pulse.
assign ready = mul | mulh | mulhsu | mulhu |
               ((div | divu | rem | remu) & div_ready);

endmodule
