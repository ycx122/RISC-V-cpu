`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// icache - direct-mapped instruction cache sitting between the CPU's legacy
//          instruction-fetch port and axil_ifetch_bridge.
//
// Tier 4 / PROCESSOR_IMPROVEMENT_PLAN.md item 4 step B.  Step A moved the
// fetch path onto a read-only AXI4-Lite master so the CPU no longer cares
// what physical memory sits behind it, at the cost of 2 cycles per word in
// steady state (AR + R).  Step B inserts this cache in front of the bridge
// so a steady fetch stream collapses back to 1 cycle per word on hits, and
// future off-chip instruction memory (DDR via MIG's AXI4-Lite facade) can
// be reached without paying round-trip cost on every PC tick.
//
// Organisation
// ------------
// * 2 KB total, direct-mapped, 16 B line (4 words), 128 lines.
//     addr[31:11]  tag    (21 b)
//     addr[10: 4]  index  (7  b)
//     addr[ 3: 2]  wsel   (2  b, word offset within the line)
//     addr[ 1: 0]  byte   (always 00 for fetches; forced aligned anyway)
//
// * Combinational hit path.  In S_IDLE the index + tag + valid form a
//   pure combinational comparator; the selected 32-bit word is driven
//   onto `up_data` and `up_ready` pulses high in the same cycle the CPU
//   presents `up_addr`.  Hit latency = 0 cycle of cache-added delay, so
//   a sequential sustained stream can push 1 fetch / cycle the way the
//   TCM_IFETCH fallback used to.
//
// * Miss path: 4-beat line fill.  On a miss we park in S_FILL for four
//   round trips through axil_ifetch_bridge (each round is AR + R =
//   2 cycles minimum), latching each word into `fill_buf` and then
//   committing tag / valid / data at the edge the 4th beat completes.
//   Subsequent lookups to the same line hit the newly-committed entry on
//   the very next cycle.
//
//   Fill order is always ascending from word 0 of the line, not
//   critical-word-first.  The simple order keeps the logic small and the
//   access pattern pleasantly predictable for future MIG-style bursts;
//   CWF is revisited if the bridge later supports an AXI burst mode.
//
// * fence.i support.  `flush` is a 1-cycle pulse driven by cpu_jh.v
//   when a fence.i instruction first appears in reg_1.  On the flush
//   edge every valid bit is cleared so the next fetch misses and pulls
//   a fresh copy from memory (the ordering versus the drained store
//   queue is provided by cpu_jh's fence_stall, which holds the pipeline
//   until earlier stores have committed through the data bridge before
//   fence.i retires).  If a flush fires while a fill is in flight the
//   commit at the end of the fill is suppressed so we never end up with
//   a valid entry that points at a pre-invalidation memory image.
//
// * Error propagation.  If any of the 4 fill beats returns DECERR /
//   SLVERR on the AXI bus, the line is NOT committed and `up_err` is
//   pulsed together with `up_ready` on the cycle the fill completes,
//   so downstream code can convert the error to an Instruction Access
//   Fault (mcause=1) when that path is added.  cpu_jh.v currently
//   treats `up_err` as a don't-care, matching the behaviour of the
//   standalone axil_ifetch_bridge in step A.
//
// * PC redirects during a fill.  If the CPU's pc_addr changes during
//   S_FILL (e.g. an async interrupt taking a trap while i_wait is
//   asserted, since trap_set_en bypasses pc_en), the in-flight fill is
//   allowed to complete naturally -- the line it would have cached is
//   still legitimate instruction memory, just not the line we now
//   want.  After S_FILL returns to S_IDLE the new pc_addr misses and a
//   fresh fill is kicked off.
//
// Downstream contract (to axil_ifetch_bridge)
// -------------------------------------------
// The downstream port has the same legacy `{en, addr, data, ready, err}`
// shape as the CPU-side port of axil_ifetch_bridge, so the wrap is a
// drop-in insertion:
//
//   cpu_jh.i_bus_{en,ready,err}/pc_addr_out/i_data_in
//       |
//       v  upstream (up_*)
//   icache
//       |
//       v  downstream (dn_*)
//   axil_ifetch_bridge.i_bus_{en,ready,err}/pc_addr/i_data
//       |
//       v  AXI4-Lite master
//    ... slave ...
//
// In TCM_IFETCH / ICACHE_DISABLE builds the cache is bypassed entirely
// (see cpu_soc.v); only the default build instantiates it.
// -----------------------------------------------------------------------------

module icache #(
    parameter LINE_BYTES = 16,
    parameter NUM_LINES  = 128
) (
    input  wire        aclk,
    input  wire        aresetn,

    // ---- Invalidation (fence.i) -------------------------------------------
    input  wire        flush,

    // ---- Upstream: CPU-side instruction fetch port ------------------------
    input  wire        up_en,
    input  wire [31:0] up_addr,
    output wire [31:0] up_data,
    output wire        up_ready,
    output wire        up_err,

    // ---- Downstream: AXI ifetch bridge CPU-side port ----------------------
    output wire        dn_en,
    output wire [31:0] dn_addr,
    input  wire [31:0] dn_data,
    input  wire        dn_ready,
    input  wire        dn_err
);

    // ---------------- Address geometry ----------------------------------------
    localparam WSEL_LSB  = 2;
    localparam WSEL_W    = 2;       // 4 words per line
    localparam IDX_LSB   = 4;       // 16 B lines
    localparam IDX_W     = 7;       // 128 lines
    localparam TAG_LSB   = IDX_LSB + IDX_W;
    localparam TAG_W     = 32 - TAG_LSB;
    localparam LINE_BITS = LINE_BYTES * 8;

    // Lint quietening for unused parameters in certain tool configurations
    wire _unused_line_bits = |(LINE_BITS[0]);

    // ---------------- Storage -------------------------------------------------
    reg [TAG_W-1:0]    tag_mem  [0:NUM_LINES-1];
    reg [NUM_LINES-1:0] valid;
    reg [LINE_BITS-1:0] data_mem [0:NUM_LINES-1];

    // ---------------- Address splits ------------------------------------------
    wire [IDX_W-1:0]  up_idx  = up_addr[IDX_LSB +: IDX_W];
    wire [TAG_W-1:0]  up_tag  = up_addr[TAG_LSB +: TAG_W];
    wire [WSEL_W-1:0] up_wsel = up_addr[WSEL_LSB +: WSEL_W];

    // ---------------- FSM -----------------------------------------------------
    localparam S_IDLE = 1'b0;
    localparam S_FILL = 1'b1;
    reg state;

    // In-flight fill state
    reg [WSEL_W-1:0]  fill_cnt;
    reg [IDX_W-1:0]   fill_idx;
    reg [TAG_W-1:0]   fill_tag;
    reg [WSEL_W-1:0]  fill_wsel;          // the word the CPU is actually asking for
    reg [LINE_BITS-1:0] fill_buf;
    reg               fill_err;           // sticky SLVERR / DECERR across the 4 beats
    reg               fill_flush_seen;    // flush fired while in S_FILL

    // ---------------- Hit evaluation ------------------------------------------
    // Only valid during S_IDLE; S_FILL always forces a miss so the CPU keeps
    // stalling until the line is committed.
    wire hit_idle = valid[up_idx] & (tag_mem[up_idx] == up_tag);
    wire hit      = (state == S_IDLE) & up_en & hit_idle;

    // Word extracted from the stored line.  Using a straightforward right-shift
    // instead of a variable-width part-select keeps Verilator / iverilog happy
    // across their different strictness settings.
    wire [LINE_BITS-1:0] hit_line       = data_mem[up_idx];
    wire [31:0]         hit_line_word   = hit_line[32*up_wsel +: 32];

    // ---------------- Combinational fill-complete outputs ---------------------
    // The cycle the 4th beat returns we commit synchronously at the edge AND
    // answer the CPU combinationally in the same cycle, so reg_1 can latch
    // on the same edge that writes data_mem.  This saves one cycle vs.
    // falling back to a hit on the newly-written entry next cycle.
    wire fill_last_beat = (state == S_FILL) & dn_ready & (fill_cnt == {WSEL_W{1'b1}});

    // Next-state fill_buf, with the just-arrived beat merged in.  Writing it
    // out as a mask avoids relying on a variable-width bit-select assignment
    // on the LHS, which older tools choke on.
    reg [LINE_BITS-1:0] fill_buf_next;
    always @(*) begin
        fill_buf_next = fill_buf;
        case (fill_cnt)
            2'd0: fill_buf_next[ 31: 0] = dn_data;
            2'd1: fill_buf_next[ 63:32] = dn_data;
            2'd2: fill_buf_next[ 95:64] = dn_data;
            2'd3: fill_buf_next[127:96] = dn_data;
        endcase
    end

    // Word the CPU is actually waiting on, extracted out of the merged buffer.
    wire [31:0] fill_cpu_word = fill_buf_next[32*fill_wsel +: 32];

    // ---------------- Downstream drive ----------------------------------------
    // During S_FILL we continuously hold dn_en + dn_addr aimed at the next
    // word to fetch; the bridge consumes the handshake and pulses dn_ready
    // once per completed beat.
    //
    // Address is always the line base + fill_cnt words.  Low two bits are
    // forced to 00 so the address is word aligned.
    wire [31:0] fill_line_base = {fill_tag, fill_idx, {(32-TAG_W-IDX_W){1'b0}}};

    assign dn_en   = (state == S_FILL);
    assign dn_addr = {fill_line_base[31:4], fill_cnt, 2'b00};

    // ---------------- Upstream outputs ----------------------------------------
    // up_ready pulses on:
    //   * a pure cache hit (state == S_IDLE), OR
    //   * the completing fill cycle for the line the CPU is waiting on
    //     (deliver the critical word in the same cycle we commit the line).
    //
    // If the CPU's pc redirects during a fill (trap / misprediction /
    // pending-redirect), the in-flight fill is allowed to finish for its
    // original line, but the critical-word combinational drive back to the
    // CPU must NOT fire when up_addr no longer maps onto this fill: doing
    // so would hand the CPU a word from the WRONG line tagged with the NEW
    // PC (up_data latched alongside pc_addr_reg0=new PC), and that stray
    // instruction would then execute in the shadow of the trap handler.
    // The fill-completes-into-cache commit still happens unconditionally,
    // so a later fetch that comes back to the same line hits normally.
    wire fill_addr_match = (up_addr[IDX_LSB +: IDX_W]  == fill_idx)
                         & (up_addr[TAG_LSB +: TAG_W]  == fill_tag)
                         & (up_addr[WSEL_LSB +: WSEL_W] == fill_wsel);
    wire fill_deliver    = fill_last_beat & fill_addr_match;
    assign up_ready = hit | fill_deliver;
    assign up_data  = (state == S_FILL) ? fill_cpu_word : hit_line_word;

    // up_err is pulsed together with the fill-completion up_ready when any
    // beat of the fill returned SLVERR / DECERR.  A hit can never carry an
    // error because we refuse to commit a faulted line.
    assign up_err   = fill_deliver & (fill_err | dn_err);

    // ---------------- Sequential ----------------------------------------------
    // NOTE: tag_mem / data_mem are deliberately NOT cleared on reset.  Both
    // are large (128 x 21 b tags + 128 x 128 b data = ~19 kbit) and we want
    // Vivado to infer them as distributed RAM / BRAM rather than scatter
    // them across ~19 k FFs; reset-loop writes would force the FF mapping
    // and blow up the Artix-7 100T LUT / FF budget.  Correctness only
    // requires the `valid` bit-vector to be zero at reset, which keeps the
    // garbage contents of the RAMs from ever appearing as a hit.

    always @(posedge aclk) begin
        if (!aresetn) begin
            state           <= S_IDLE;
            valid           <= {NUM_LINES{1'b0}};
            fill_cnt        <= {WSEL_W{1'b0}};
            fill_idx        <= {IDX_W{1'b0}};
            fill_tag        <= {TAG_W{1'b0}};
            fill_wsel       <= {WSEL_W{1'b0}};
            fill_buf        <= {LINE_BITS{1'b0}};
            fill_err        <= 1'b0;
            fill_flush_seen <= 1'b0;
        end else begin
            // Invalidation wins over every other update: we drop valid bits
            // unconditionally on the flush cycle, and also mark the in-flight
            // fill (if any) as poisoned so its eventual commit is skipped.
            if (flush) valid <= {NUM_LINES{1'b0}};
            if (flush & (state == S_FILL)) fill_flush_seen <= 1'b1;

            case (state)
                S_IDLE: begin
                    // Clear any stale "flush seen during fill" bit once we've
                    // returned to IDLE -- the next fill starts clean.
                    fill_flush_seen <= 1'b0;

                    if (up_en & ~hit_idle & ~flush) begin
                        state          <= S_FILL;
                        fill_cnt       <= {WSEL_W{1'b0}};
                        fill_idx       <= up_idx;
                        fill_tag       <= up_tag;
                        fill_wsel      <= up_wsel;
                        fill_buf       <= {LINE_BITS{1'b0}};
                        fill_err       <= 1'b0;
                    end
                end

                S_FILL: begin
                    if (dn_ready) begin
                        fill_buf <= fill_buf_next;
                        if (dn_err) fill_err <= 1'b1;

                        if (fill_cnt == {WSEL_W{1'b1}}) begin
                            // Last beat.  Commit the line iff (a) no beat
                            // returned an error and (b) no flush fired
                            // during the fill window.  Otherwise the line
                            // stays invalid and the CPU will retry on the
                            // next access (which will miss and refill).
                            if (!fill_err & !dn_err & !fill_flush_seen & !flush) begin
                                tag_mem[fill_idx]   <= fill_tag;
                                valid[fill_idx]     <= 1'b1;
                                data_mem[fill_idx]  <= fill_buf_next;
                            end
                            state <= S_IDLE;
                        end else begin
                            fill_cnt <= fill_cnt + {{(WSEL_W-1){1'b0}}, 1'b1};
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
