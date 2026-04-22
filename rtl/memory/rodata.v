`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// rodata - boot-ROM 32-bit data-read adapter (AXI4-Lite friendly).
//
// History:
//   2026-04 (Tier 4.1): sign/zero-extension was ripped out; the ROM slave
//                       always returns the raw aligned 32-bit word and
//                       leaves per-size extraction to the master bridge.
//                       i_rom port A was still 8-bit though, so the
//                       FSM walked four byte addresses across 7 states
//                       (12+ cycle load-to-use).
//
//   2026-04 (Tier 4.2): i_rom port A was widened to 32-bit read + 4-bit
//                       byte-strobe write (see sim/models/xilinx_compat.v
//                       and rtl/memory/ram_c.v).  This module collapses
//                       to a 3-state FSM that clocks out the 2-cycle
//                       BRAM output pipeline and asserts rom_r_ready in
//                       the 3rd cycle, dropping ROM load-to-use from
//                       ~12 cycles down to ~5 cycles end-to-end.
//
// Timing sketch (cycle numbers relative to the first cycle `rom_en` and
// `re` are high, which is the first cycle the axil_slave_wrapper sits
// in S_READ with a valid address):
//
//   cycle 0 (IDLE,  re=rom_en=1): addra/ena driven -> BRAM samples.
//   cycle 1 (WAIT1)            : BRAM douta_r0 becomes valid internally.
//   cycle 2 (WAIT2)            : BRAM douta exposes data.  rom_r_ready=1
//                                 comb -> axil_slave_wrapper pushes
//                                 s_rvalid=1 comb -> master captures
//                                 rdata the same cycle.
//
// The FSM stays in WAIT2 (rom_r_ready=1) as long as rom_en is high, to
// tolerate a master that is momentarily not rready.  Once the slave
// wrapper de-asserts dev_en (and therefore rom_en), the FSM falls back
// to IDLE on the next edge and is ready to service the next request.
// -----------------------------------------------------------------------------
module rodata(
    input              clk,
    input              rst_n,

    // Device-side handshake (driven by axil_slave_wrapper in cpu_soc)
    input              rom_en,     // transaction active (dev_en)
    input              re,         // read cycle      (dev_re)
    input      [31:0]  addr,       // 32-bit byte address (bits [1:0] ignored)
    output     [31:0]  reg_data,   // raw 32-bit aligned word from ROM
    output             rom_r_ready,

    // i_rom port-A sharing (owned by ram_c; driven by this module
    // whenever rom_r_en=1)
    output     [13:0]  rom_addr,   // 14-bit word address (matches port-A width)
    output             rom_r_en,
    input      [31:0]  rom_data    // 32-bit word read data
);

    localparam [1:0] IDLE  = 2'd0,
                     WAIT1 = 2'd1,
                     WAIT2 = 2'd2;

    reg [1:0] state;
    reg [1:0] n_state;

    // Drive the port-A read whenever we are actively servicing a read.
    // The slave wrapper keeps dev_en/dev_re high from the start of the
    // transaction until dev_ready is sampled, which in turn keeps
    // rom_r_en = 1 long enough for the 2-cycle BRAM pipeline.
    assign rom_r_en = rom_en;
    assign rom_addr = addr[15:2];

    // reg_data is a combinational tap of the BRAM output; the master
    // bridge latches it through the AXI R handshake.
    assign reg_data    = rom_data;
    assign rom_r_ready = (state == WAIT2);

    always @(*) begin
        case (state)
            IDLE:  n_state = (re & rom_en) ? WAIT1 : IDLE;
            WAIT1: n_state = WAIT2;
            // Stay in WAIT2 while the slave wrapper still holds the
            // transaction up.  Once rom_en drops (i.e. the wrapper
            // moved back to S_IDLE after the R handshake) fall through
            // to IDLE and be ready for the next access.
            WAIT2: n_state = (re & rom_en) ? WAIT2 : IDLE;
            default: n_state = IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= n_state;
    end

endmodule
