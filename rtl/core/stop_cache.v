// -----------------------------------------------------------------------------
// IF-stage stall latch for the incoming instruction word.
//
// When the pipeline stalls (load-use, CSR-use, bus wait, etc.), the IF stage
// keeps emitting i_data_in for whatever PC happens to sit on the bus.  Since
// reg_1_en is gated in the same cycle, the underlying IF->ID handoff is fine,
// but downstream observers that look at `i_data_out` combinationally
// (notably waveforms / debug probes) would see the instruction word flicker
// one cycle into the stall.  This helper latches the last pre-stall value
// and replays it for the stall duration, so i_data_out reads as the "real"
// in-flight instruction.
//
// Lifted verbatim out of cpu_jh.v (was the trailing `stop_cache` module).
// -----------------------------------------------------------------------------
module stop_cache (
    input        clk,
    input        rst,
    input [31:0] i_data_in,
    input        local_stop,
    output reg [31:0] i_data_out
);

    reg        local_stop_d1;
    reg [31:0] i_cache;
    reg        local_stop_pos;

    always @(posedge clk)
        if (rst == 1'b0) local_stop_d1 <= 1'b0;
        else             local_stop_d1 <= local_stop;

    always @(*)
        local_stop_pos = local_stop & (~local_stop_d1);

    always @(posedge clk)
        if (rst == 1'b0)         i_cache <= 32'd0;
        else if (local_stop_pos) i_cache <= i_data_in;

    always @(*) begin
        if (local_stop_d1 == 1'b0)
            i_data_out = i_data_in;
        else if (local_stop_d1 == 1'b1)
            i_data_out = i_cache;
        else
            i_data_out = 32'd0;
    end

endmodule
