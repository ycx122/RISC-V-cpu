`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// plic - SiFive-compatible Platform-Level Interrupt Controller (subset).
//
// Tier 4 item 3 of PROCESSOR_IMPROVEMENT_PLAN.md.  This is a deliberately
// small PLIC matching the RISC-V PLIC specification (a.k.a. the SiFive
// PLIC layout used by Linux, FreeRTOS+PLIC and OpenSBI generic drivers),
// parametrised only on the number of sources and the width of the
// priority field.
//
// Features
//   * N_SRC interrupt sources.  Source 0 is reserved (spec-mandated);
//     real sources are 1..N_SRC-1 and driven by irq_sources[N_SRC-1:1].
//   * 1 context: hart 0, M-mode.  (S-mode context would add one more
//     claim/threshold block at +0x2000 on a real SiFive PLIC.)
//   * PRIORITY_WIDTH-bit per-source priority register; 0 = never
//     interrupt.  Ties are broken by source-id (lowest id wins), the
//     same rule used by Linux's plic.c.
//   * Level-sensitive sources.  Pending bit is set as long as the
//     source is asserted and the source has not been claimed; an
//     in-flight bit prevents the handler from re-claiming the same
//     source until it writes the complete register.
//
// Memory map (byte offsets from the PLIC base; unmapped offsets read 0 /
// ignore writes):
//
//   0x000000 + 4*i  priority[i]                (0 <= i < N_SRC, i=0 WIRI)
//   0x001000        pending[31:0]              (read-only; bit0 WIRI)
//   0x002000        enable[31:0] context 0     (hart 0 M-mode)
//   0x200000        threshold context 0        (R/W)
//   0x200004        claim/complete context 0   (read = claim, write = complete)
//
// (A real SiFive PLIC has up to 1024 sources and 15872 contexts; the
//  register stride and offsets above are a strict subset of that layout,
//  so a driver written for the full PLIC works unchanged -- it just
//  sees the high-id sources perpetually untriggered.)
//
// Claim/complete protocol
//   * Read of claim/complete returns the id of the highest-priority
//     enabled pending source whose priority is strictly greater than
//     the threshold, or 0 if none.  In the same clock the pending bit
//     of that source is masked (in_flight[id] <= 1'b1) so re-reading
//     while the handler is running will not return the same id again.
//   * Write of claim/complete clears in_flight[wdata[5:0]] so the
//     source can be re-taken once it asserts again.
//
// -----------------------------------------------------------------------------
module plic #(
    parameter integer N_SRC          = 8,    // total sources including reserved id 0; must be <=32
    parameter integer PRIORITY_WIDTH = 3     // bits of per-source priority (SiFive: 3)
) (
    input              clk,
    input              rst_n,

    // Simple device-side handshake from axil_slave_wrapper.  `plic_addr`
    // is the byte address within the PLIC slave window (at least low
    // 22 bits are significant to reach the per-context block at
    // 0x0020_0000 / 0x0020_0004).
    input              plic_en,
    input              re,
    input              we,
    input  [23:0]      plic_addr,
    input  [31:0]      din,
    input  [3:0]       wstrb,
    output reg [31:0]  dout,
    output             plic_ready,

    // Level-sensitive interrupt sources.  bit 0 is tied off and ignored
    // (reserved by the PLIC spec).  Inputs are assumed synchronous to
    // clk; callers should two-flop external async signals first.
    input  [N_SRC-1:0] irq_sources,

    // Level-sensitive external-interrupt output to the hart 0 M-mode
    // context.  Feeds CSR mip.MEIP via the SoC.
    output             meip
);

    // ---- local parameters --------------------------------------------------
    localparam integer ID_WIDTH   = $clog2(N_SRC);
    localparam [23:0] OFF_PENDING = 24'h001000;
    localparam [23:0] OFF_ENABLE  = 24'h002000;
    localparam [23:0] OFF_THRESH  = 24'h200000;
    localparam [23:0] OFF_CLAIM   = 24'h200004;

    // ---- architectural state ----------------------------------------------
    // priority[0] is WIRI; bit 0 of enable / pending / in_flight is
    // likewise WIRI per the spec, we just leave them 0 at reset.
    reg [PRIORITY_WIDTH-1:0] priority_r [0:N_SRC-1];
    reg [N_SRC-1:0]          enable_r;            // context 0 enables
    reg [PRIORITY_WIDTH-1:0] threshold_r;
    reg [N_SRC-1:0]          in_flight_r;         // claimed-but-not-completed

    // Pending bit for each source.  The spec calls for a gateway per
    // source; for level-sensitive sources (what we have) the simplest
    // faithful gateway is "pending = asserted & ~in_flight".
    wire [N_SRC-1:0] pending;
    genvar g;
    generate
        for (g = 0; g < N_SRC; g = g + 1) begin : g_pending
            if (g == 0)
                assign pending[g] = 1'b0;        // source 0 always WIRI
            else
                assign pending[g] = irq_sources[g] & ~in_flight_r[g];
        end
    endgenerate

    // ---- address decode ---------------------------------------------------
    //
    // Priority window occupies the first N_SRC*4 bytes; we decode it by
    // checking the upper bits of `plic_addr` are zero and the low bits
    // are a word-aligned index in range.
    wire sel_priority = plic_en &
                        (plic_addr[23:12] == 12'h000) &
                        (plic_addr[1:0]   == 2'b00)   &
                        (plic_addr[11:2] < N_SRC[9:0]);
    wire [ID_WIDTH-1:0] prio_idx = plic_addr[2 +: ID_WIDTH];

    wire sel_pending  = plic_en & (plic_addr == OFF_PENDING);
    wire sel_enable   = plic_en & (plic_addr == OFF_ENABLE);
    wire sel_thresh   = plic_en & (plic_addr == OFF_THRESH);
    wire sel_claim    = plic_en & (plic_addr == OFF_CLAIM);

    assign plic_ready = plic_en;

    // Byte-wise write helper -- same shape as the one in clnt.v; PLIC
    // accesses are meant to be 32-bit aligned but we honour wstrb for
    // robustness.
    function [31:0] apply_wstrb;
        input [31:0] cur;
        input [31:0] nd;
        input [3:0]  s;
        begin
            apply_wstrb = { s[3] ? nd[31:24] : cur[31:24],
                            s[2] ? nd[23:16] : cur[23:16],
                            s[1] ? nd[15:8]  : cur[15:8],
                            s[0] ? nd[7:0]   : cur[7:0] };
        end
    endfunction

    // ---- priority encoder over pending sources ----------------------------
    //
    // Returns the lowest-id source that is enabled, pending, and has
    // priority strictly greater than the threshold.  `best_id` is 0 if no
    // such source exists (claim returning 0 means "spurious / none"
    // which matches the PLIC spec).
    integer             i_idx;
    reg [ID_WIDTH-1:0]  best_id_c;
    reg [PRIORITY_WIDTH-1:0] best_pri_c;
    reg                 best_any_c;
    always @(*) begin
        best_id_c  = {ID_WIDTH{1'b0}};
        best_pri_c = {PRIORITY_WIDTH{1'b0}};
        best_any_c = 1'b0;
        for (i_idx = 1; i_idx < N_SRC; i_idx = i_idx + 1) begin
            if (enable_r[i_idx] & pending[i_idx] &
                (priority_r[i_idx] > threshold_r) &
                (priority_r[i_idx] > best_pri_c)) begin
                // Strictly greater: SiFive tie-break picks the smallest
                // id on equal priority, which is what keeping the `>`
                // comparison achieves when iterating low->high.
                best_id_c  = i_idx[ID_WIDTH-1:0];
                best_pri_c = priority_r[i_idx];
                best_any_c = 1'b1;
            end
        end
    end

    assign meip = best_any_c;

    // ---- read side --------------------------------------------------------
    always @(*) begin
        dout = 32'h0;
        if (plic_en & re) begin
            if (sel_priority) begin
                dout = { {(32-PRIORITY_WIDTH){1'b0}}, priority_r[prio_idx] };
            end else if (sel_pending) begin
                dout = { {(32-N_SRC){1'b0}}, pending };
            end else if (sel_enable) begin
                dout = { {(32-N_SRC){1'b0}}, enable_r };
            end else if (sel_thresh) begin
                dout = { {(32-PRIORITY_WIDTH){1'b0}}, threshold_r };
            end else if (sel_claim) begin
                dout = { {(32-ID_WIDTH){1'b0}}, best_id_c };
            end
        end
    end

    // ---- write / state updates --------------------------------------------
    //
    // Icarus Verilog does not accept part-select-on-function-call, so we
    // materialise the wstrb-merged 32-bit values into named wires first
    // and then truncate.  This is also easier for humans to read.

    wire [31:0] prio_merged =
        apply_wstrb({{(32-PRIORITY_WIDTH){1'b0}}, priority_r[prio_idx]},
                    din, wstrb);

    wire [31:0] enable_merged =
        apply_wstrb({{(32-N_SRC){1'b0}}, enable_r}, din, wstrb);

    wire [31:0] thresh_merged =
        apply_wstrb({{(32-PRIORITY_WIDTH){1'b0}}, threshold_r}, din, wstrb);

    wire [N_SRC-1:0] enable_mask = {{(N_SRC-1){1'b1}}, 1'b0};

    wire [ID_WIDTH-1:0] complete_id = din[ID_WIDTH-1:0];
    wire complete_in_range = (complete_id != {ID_WIDTH{1'b0}}) &&
                             (din[31:ID_WIDTH] == {(32-ID_WIDTH){1'b0}});

    integer i_prio;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i_prio = 0; i_prio < N_SRC; i_prio = i_prio + 1)
                priority_r[i_prio] <= {PRIORITY_WIDTH{1'b0}};
            enable_r    <= {N_SRC{1'b0}};
            threshold_r <= {PRIORITY_WIDTH{1'b0}};
            in_flight_r <= {N_SRC{1'b0}};
        end else begin
            // Priority register writes.  prio[0] stays 0 per spec.
            if (sel_priority & we & (prio_idx != {ID_WIDTH{1'b0}}))
                priority_r[prio_idx] <= prio_merged[PRIORITY_WIDTH-1:0];

            if (sel_enable & we)
                enable_r <= enable_merged[N_SRC-1:0] & enable_mask;

            if (sel_thresh & we)
                threshold_r <= thresh_merged[PRIORITY_WIDTH-1:0];

            // Claim: on a read of the claim register we mask the winner.
            // A simultaneous complete-write of the same register is
            // illegal (spec) so we don't worry about reconciling them.
            if (sel_claim & re & best_any_c)
                in_flight_r[best_id_c] <= 1'b1;

            // Complete: write any non-reserved id to clear its in_flight.
            if (sel_claim & we & complete_in_range)
                in_flight_r[complete_id] <= 1'b0;
        end
    end

endmodule
