`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: div_gen
// Project: RISC-V CPU (Tier 2)
// Description:
//   32-bit unsigned iterative divider (restoring, radix-4: 2 quotient bits
//   per cycle). Fully synthesizable; identical behavior in simulation and
//   on FPGA. This replaces the earlier radix-2 implementation and the old
//   Xilinx `div_0` IP / matching sim stub.
//
// Interface (level-based, no AXI-stream handshake):
//   start      : request strobe or level. Captured only while !busy (S_IDLE);
//                once captured, subsequent assertions during the run are
//                ignored until the operation completes.
//   ready      : high for exactly one cycle when `quotient`/`remainder` are
//                valid; returns low the next cycle. mul_div.v uses this
//                pulse to release the pipeline stall.
//   quotient   : dividend / divisor  (unsigned).
//   remainder  : dividend % divisor  (unsigned).
//
// Algorithm (restoring, 16 iterations of radix-4):
//   rem_r  : 34-bit working remainder  (2 extra MSBs to hold rem_shift).
//   quot_r : 32-bit shift register, initially loaded with dividend; each
//            iteration shifts out the two MSBs into rem_shift and shifts
//            in two freshly-decided quotient bits on the LSB side.
//   div3_r : 3 * divisor_r, precomputed at latch time as (D<<1) + D so the
//            critical path per iteration is 3 parallel 34-bit subtracts +
//            a priority mux, not a multiply.
//   Per iteration (using divisor_r, div3_r):
//     rem_shift = {rem_r[31:0], quot_r[31:30]};            // 34 bits
//     if      (rem_shift >= div3_r)      { rem<=rem_shift-div3_r;      q=2'b11; }
//     else if (rem_shift >= (D << 1))    { rem<=rem_shift-(D<<1);      q=2'b10; }
//     else if (rem_shift >= D)           { rem<=rem_shift-D;           q=2'b01; }
//     else                               { rem<=rem_shift;             q=2'b00; }
//     quot <= {quot_r[29:0], q};
//
// Divide-by-zero:
//   With divisor == 0 every multiple is 0, so rem_shift >= 3*D is trivially
//   true and q is forced to 2'b11 each iteration. After 16 iterations
//     quot = 32'hFFFF_FFFF, rem = dividend
//   which matches the RV spec (and the Xilinx IP behavior that mul_div.v
//   previously relied on). mul_div.v still masks/overrides this for the
//   signed-overflow case (MIN_INT / -1).
//
// Latency: 1 cycle latch (S_IDLE->S_RUN) + 16 iteration cycles (S_RUN) +
//   1 cycle done pulse (S_DONE) = 18 cycles from the cycle `start` is
//   sampled to the cycle `ready` is observed. Back-to-back operations
//   re-launch the cycle after `ready`, giving an effective throughput of
//   one div every ~18 cycles versus the 33-cycle radix-2 predecessor.
//
//////////////////////////////////////////////////////////////////////////////////

module div_gen (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        start,
    input  wire [31:0] dividend,
    input  wire [31:0] divisor,

    output wire        ready,
    output wire [31:0] quotient,
    output wire [31:0] remainder
);

localparam [1:0] S_IDLE = 2'd0,
                 S_RUN  = 2'd1,
                 S_DONE = 2'd2;

reg [1:0]  state;
reg [4:0]  cnt;          // iterations remaining (0..16)
reg [33:0] rem_r;        // working remainder (34-bit)
reg [31:0] quot_r;       // shift-out dividend / shift-in quotient
reg [31:0] divisor_r;
reg [33:0] div3_r;       // 3 * divisor_r, precomputed at latch time

// --------------------- combinational per-iteration step --------------------

// 34-bit left-shifted working remainder with two new dividend bits shifted in.
wire [33:0] rem_shift = {rem_r[31:0], quot_r[31:30]};

// 34-bit-extended multiples of the divisor.
//   div1 = D, div2 = D << 1, div3 = 3D (precomputed into div3_r).
wire [33:0] div1 = {2'b00, divisor_r};
wire [33:0] div2 = {1'b0, divisor_r, 1'b0};
wire [33:0] div3 = div3_r;

wire ge3 = (rem_shift >= div3);
wire ge2 = (rem_shift >= div2);
wire ge1 = (rem_shift >= div1);

reg [33:0] rem_next;
reg [1:0]  q_next;

always @* begin
    if (ge3) begin
        rem_next = rem_shift - div3;
        q_next   = 2'b11;
    end else if (ge2) begin
        rem_next = rem_shift - div2;
        q_next   = 2'b10;
    end else if (ge1) begin
        rem_next = rem_shift - div1;
        q_next   = 2'b01;
    end else begin
        rem_next = rem_shift;
        q_next   = 2'b00;
    end
end

// --------------------- sequential FSM --------------------------------------

always @(posedge clk) begin
    if (!rst_n) begin
        state     <= S_IDLE;
        cnt       <= 5'd0;
        rem_r     <= 34'b0;
        quot_r    <= 32'b0;
        divisor_r <= 32'b0;
        div3_r    <= 34'b0;
    end else begin
        case (state)
            S_IDLE: begin
                if (start) begin
                    rem_r     <= 34'b0;
                    quot_r    <= dividend;
                    divisor_r <= divisor;
                    // div3 = 2*D + D; widen both operands to 34 bits so the
                    // add never overflows (3 * (2^32-1) < 2^34).
                    div3_r    <= {1'b0, divisor, 1'b0} + {2'b00, divisor};
                    cnt       <= 5'd16;
                    state     <= S_RUN;
                end
            end

            S_RUN: begin
                rem_r  <= rem_next;
                quot_r <= {quot_r[29:0], q_next};
                cnt    <= cnt - 5'd1;
                if (cnt == 5'd1) begin
                    state <= S_DONE;
                end
            end

            S_DONE: begin
                // Pulse `ready` for one cycle, then drop back to IDLE so
                // the next (possibly back-to-back) div can launch next cycle.
                state <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
    end
end

assign ready     = (state == S_DONE);
assign quotient  = quot_r;
assign remainder = rem_r[31:0];

// Power-up defaults for tools that do not honor reset-at-time-0.
initial begin
    state     = S_IDLE;
    cnt       = 5'd0;
    rem_r     = 34'b0;
    quot_r    = 32'b0;
    divisor_r = 32'b0;
    div3_r    = 34'b0;
end

endmodule
