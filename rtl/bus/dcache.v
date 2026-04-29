`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// dcache - data-side L1 cache with integrated store buffer.
//
// Tier 2 / Tier A items A1 + A2 of PROCESSOR_IMPROVEMENT_PLAN.md.  Sits
// between rtl/core/mem_ctrl.v's bus drive and rtl/bus/axil_master_bridge.v
// on the data side, presenting the same legacy {d_bus_en, ram_we, ram_re,
// d_addr, d_data_out, mem_op, d_bus_ready, bus_data_in, d_bus_err,
// d_bus_misalign} handshake on both ports so neither the CPU nor the
// bridge needs to know the cache is there.
//
// Organisation
// ------------
// * 8 KB direct-mapped, 16 B line (4 words), 512 lines.
//     addr[31:13]  tag    (19 b)
//     addr[12: 4]  index  ( 9 b)
//     addr[ 3: 2]  wsel   ( 2 b)
//     addr[ 1: 0]  byte   (always 00 after misalign filtering)
//
// * Write-back, write-allocate.  Cacheable hits retire in 1 cycle of
//   added latency (combinational up_d_bus_ready + 1 BRAM read).  Misses
//   pull a full 16 B line through the bridge with the existing 4-beat
//   AXI4-Lite read pattern (4 x AR+R).  Evicting a dirty line pushes
//   its 4 words into the integrated store buffer (rtl/bus/store_buffer.v);
//   the SB then drains them to memory while the cache continues
//   servicing further hits.
//
// * Cacheable region.  Currently the SoC's data RAM window only:
//     0x2000_0000 .. 0x2FFF_FFFF
//   Boot ROM (0x0xxx_xxxx) and MMIO (0x4xxx_xxxx) bypass the cache; for
//   stores those still go through the SB so MMIO pokes retire fast (4
//   back-to-back UART transmits become 1-cycle each as long as the SB
//   has room).  Widening the cacheable predicate to cover read-only
//   ROM is a follow-up; today the cache treats every allocated line as
//   potentially dirty, which is wrong for a read-only region.
//
// * Misalignment.  Misaligned requests (LH/LW at non-aligned addr, SH/SW
//   likewise) are filtered out before the cache lookup with the same
//   semantics axil_master_bridge already implements: short-circuit with
//   d_bus_misalign=1 and never issue an AXI transaction.  The bridge
//   keeps its own check too so DCACHE_DISABLE / non-cacheable paths
//   still cover the case.
//
// * Access faults.  A bridge d_bus_err on a non-cacheable bypass
//   propagates straight to the CPU.  d_bus_err during a line fill is
//   captured and replayed alongside the load/store completion pulse
//   (the line stays invalid so the next access retries).  Errors on a
//   writeback drain are imprecise w.r.t. the CPU pipeline (the original
//   store has long retired by the time the SB hits memory), matching
//   the behaviour of every commercial write-back cache.  In practice
//   the writeback target is always RAM in this SoC, which never DECERRs,
//   so the imprecise window only fires under fault injection testing.
//
// FSM and bridge arbitration
// --------------------------
// Two clients want the bridge: the cache miss FSM (line fill) and the
// SB drain.  Because axil_master_bridge.v handles only one outstanding
// transaction at a time, dcache muxes the bridge drive between them as
// follows:
//
//   * S_BYPASS owns the bridge for the original CPU request.
//   * S_FILL  owns the bridge for the 4-beat line read.
//   * S_IDLE / S_WB_PUSH let the SB drain opportunistically.
//   * S_FILL_WAIT explicitly waits for the SB to empty before kicking
//     off the line fill, which keeps the bridge serialised w.r.t. the
//     write-then-read of the same physical line we just evicted.
//
// In a hit-after-miss steady state this overlaps SB drain with CPU
// progress: the miss returns the critical word on the very first beat,
// the CPU resumes mid-fill while the remaining three words finish
// streaming into the data SRAM, and the SB continues draining the 4
// evicted words while the CPU runs ahead on cache hits.  Two misses
// in a row serialise (the second waits for the first to commit and
// the SB to empty before evicting), so the SB never overflows.
//
// Critical-word-first
// -------------------
// PROCESSOR_IMPROVEMENT_PLAN.md Tier 4.2 follow-up: instead of waiting
// for all four beats to land before acking the CPU, we kick off the
// line fill at `fill_cnt = miss_addr[3:2]` and pulse `up_d_bus_ready`
// the cycle that very first beat returns.  The CPU samples the
// requested word combinationally from the AXI R channel and resumes
// on the next clock edge, while S_FILL stays put draining the
// remaining three beats into `fill_buf` (still wrapping `fill_cnt`
// modulo 4 so each beat lands in its correct line slot).  Once the
// fourth beat lands the line is committed and we drop back to S_IDLE
// in the same cycle - there is no separate S_FILL_ACK any more.  CPU
// requests that arrive during the background-fill window see
// state != S_IDLE and stall on `up_d_bus_ready=0` until the line is
// committed; that's the simplest "fill_pending" semantics and is
// strictly correct because we cannot service a partial-line lookup
// without snooping fill_buf.  Hit-under-miss is left as a future
// optimisation.
//
// `flush` is a 1-cycle pulse that asks the cache to drop ALL valid /
// dirty bits.  It does NOT scrub dirty lines back to memory: dirty
// state is silently lost.  cpu_soc.v ties `flush` to 1'b0 by default;
// fence.i ordering is handled by cpu_jh.v's fence_stall, which drains
// pending stores through the data bus (and therefore the SB) before
// fence.i retires.
// -----------------------------------------------------------------------------
module dcache #(
    parameter integer LINE_BYTES = 16,
    parameter integer NUM_LINES  = 512,
    parameter [31:0]  CACHE_BASE = 32'h2000_0000,
    parameter [31:0]  CACHE_MASK = 32'hF000_0000,
    parameter integer SB_DEPTH   = 4
) (
    input  wire        aclk,
    input  wire        aresetn,

    input  wire        flush,

    // ---- Upstream: CPU-side bus handshake (mem_ctrl <-> dcache) ----------
    input  wire        up_d_bus_en,
    input  wire        up_ram_we,
    input  wire        up_ram_re,
    input  wire [31:0] up_d_addr,
    input  wire [31:0] up_d_data_out,
    input  wire [2:0]  up_mem_op,
    output reg  [31:0] up_bus_data_in,
    output reg         up_d_bus_ready,
    output reg         up_d_bus_err,
    output reg         up_d_bus_misalign,

    // ---- Downstream: bridge-side bus handshake (dcache <-> bridge) -------
    output reg         dn_d_bus_en,
    output reg         dn_ram_we,
    output reg         dn_ram_re,
    output reg  [31:0] dn_d_addr,
    output reg  [31:0] dn_d_data_out,
    output reg  [2:0]  dn_mem_op,
    input  wire [31:0] dn_bus_data_in,
    input  wire        dn_d_bus_ready,
    input  wire        dn_d_bus_err,
    input  wire        dn_d_bus_misalign
);

    // -------------------------------------------------------------------------
    // Address geometry
    // -------------------------------------------------------------------------
    localparam integer WSEL_LSB  = 2;
    localparam integer WSEL_W    = 2;
    localparam integer IDX_LSB   = 4;
    localparam integer IDX_W     = (NUM_LINES <= 32  ) ? 5 :
                                   (NUM_LINES <= 64  ) ? 6 :
                                   (NUM_LINES <= 128 ) ? 7 :
                                   (NUM_LINES <= 256 ) ? 8 :
                                   (NUM_LINES <= 512 ) ? 9 :
                                   (NUM_LINES <= 1024) ?10 : 11;
    localparam integer TAG_LSB   = IDX_LSB + IDX_W;
    localparam integer TAG_W     = 32 - TAG_LSB;
    localparam integer LINE_BITS = LINE_BYTES * 8;

    // -------------------------------------------------------------------------
    // Storage.  tag_mem / data_mem are NOT reset (large arrays, want
    // BRAM/distRAM inference); correctness only needs `valid` zeroed.
    // -------------------------------------------------------------------------
    reg [TAG_W-1:0]    tag_mem  [0:NUM_LINES-1];
    reg [LINE_BITS-1:0] data_mem [0:NUM_LINES-1];
    reg [NUM_LINES-1:0] valid;
    reg [NUM_LINES-1:0] dirty;

    // -------------------------------------------------------------------------
    // Misalignment classifier (mirrors axil_master_bridge.v::misaligned_req)
    // -------------------------------------------------------------------------
    function automatic misaligned_req;
        input [2:0]  op;
        input [1:0]  byte_off;
        begin
            case (op[1:0])
                2'b00:   misaligned_req = 1'b0;        // SB / LB / LBU
                2'b01:   misaligned_req = byte_off[0]; // SH / LH / LHU
                2'b10:   misaligned_req = |byte_off;   // SW / LW
                default: misaligned_req = 1'b0;
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // Address splits and cacheable predicate
    // -------------------------------------------------------------------------
    wire [IDX_W-1:0]  up_idx  = up_d_addr[IDX_LSB +: IDX_W];
    wire [TAG_W-1:0]  up_tag  = up_d_addr[TAG_LSB +: TAG_W];
    wire [WSEL_W-1:0] up_wsel = up_d_addr[WSEL_LSB +: WSEL_W];
    wire [1:0]        up_boff = up_d_addr[1:0];

    function automatic cacheable;
        input [31:0] addr;
        begin
            cacheable = ((addr & CACHE_MASK) == (CACHE_BASE & CACHE_MASK));
        end
    endfunction

    wire up_cacheable = cacheable(up_d_addr);
    wire up_misalign  = misaligned_req(up_mem_op, up_boff);
    wire up_req       = up_d_bus_en & (up_ram_we | up_ram_re);

    // -------------------------------------------------------------------------
    // Hit logic (combinational over the IDLE state path)
    // -------------------------------------------------------------------------
    wire hit_match  = valid[up_idx] & (tag_mem[up_idx] == up_tag);

    wire [LINE_BITS-1:0] hit_line     = data_mem[up_idx];
    wire [31:0]          hit_word_raw = hit_line[32*up_wsel +: 32];

    // -------------------------------------------------------------------------
    // Sub-word load extraction (mirrors axil_master_bridge.v)
    // -------------------------------------------------------------------------
    function automatic [31:0] extract_load;
        input [31:0] word;
        input [2:0]  op;
        input [1:0]  boff;
        reg   [7:0]  rb_sel;
        reg   [15:0] rh_sel;
        begin
            case (boff)
                2'b00: rb_sel = word[ 7: 0];
                2'b01: rb_sel = word[15: 8];
                2'b10: rb_sel = word[23:16];
                2'b11: rb_sel = word[31:24];
            endcase
            case (boff[1])
                1'b0:  rh_sel = word[15: 0];
                1'b1:  rh_sel = word[31:16];
            endcase
            case (op)
                3'b000:  extract_load = {{24{rb_sel[7]}},  rb_sel};
                3'b001:  extract_load = {{16{rh_sel[15]}}, rh_sel};
                3'b010:  extract_load = word;
                3'b100:  extract_load = {24'd0, rb_sel};
                3'b101:  extract_load = {16'd0, rh_sel};
                default: extract_load = word;
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // Store-side word merge: build the next 32-bit word given an existing
    // line word, the CPU's store data and mem_op + byte offset.
    // -------------------------------------------------------------------------
    function automatic [31:0] merge_store;
        input [31:0] old_word;
        input [31:0] sdata;
        input [2:0]  op;
        input [1:0]  boff;
        reg   [31:0] result;
        begin
            result = old_word;
            case (op[1:0])
                2'b00: begin // SB
                    case (boff)
                        2'b00: result[ 7: 0] = sdata[7:0];
                        2'b01: result[15: 8] = sdata[7:0];
                        2'b10: result[23:16] = sdata[7:0];
                        2'b11: result[31:24] = sdata[7:0];
                    endcase
                end
                2'b01: begin // SH
                    if (boff[1] == 1'b0) result[15: 0] = sdata[15:0];
                    else                 result[31:16] = sdata[15:0];
                end
                2'b10: result = sdata;
                default: result = old_word;
            endcase
            merge_store = result;
        end
    endfunction

    // wstrb / wdata shift for non-cacheable SB pushes (mirrors
    // axil_master_bridge.v's wdata_shift / wstrb_shift)
    function automatic [3:0] strb_for;
        input [2:0] op;
        input [1:0] boff;
        begin
            case (op[1:0])
                2'b00:   strb_for = 4'b0001 << boff;
                2'b01:   strb_for = 4'b0011 << {boff[1], 1'b0};
                2'b10:   strb_for = 4'b1111;
                default: strb_for = 4'b0000;
            endcase
        end
    endfunction

    function automatic [31:0] wdata_shift;
        input [31:0] sdata;
        input [2:0]  op;
        input [1:0]  boff;
        reg   [31:0] r;
        begin
            r = 32'd0;
            case (op[1:0])
                2'b00: begin
                    case (boff)
                        2'b00: r = {24'd0,            sdata[7:0]};
                        2'b01: r = {16'd0, sdata[7:0],  8'd0};
                        2'b10: r = { 8'd0, sdata[7:0], 16'd0};
                        2'b11: r = {       sdata[7:0], 24'd0};
                    endcase
                end
                2'b01: begin
                    if (boff[1] == 1'b0) r = {16'd0, sdata[15:0]};
                    else                 r = {sdata[15:0], 16'd0};
                end
                2'b10: r = sdata;
                default: r = 32'd0;
            endcase
            wdata_shift = r;
        end
    endfunction

    // -------------------------------------------------------------------------
    // Store buffer instantiation
    // -------------------------------------------------------------------------
    reg         sb_push;
    reg  [31:0] sb_push_addr;
    reg  [31:0] sb_push_wdata;
    reg  [3:0]  sb_push_wstrb;
    reg  [2:0]  sb_push_op;
    wire        sb_push_full;

    wire [31:0] sb_head_addr;
    wire [31:0] sb_head_wdata;
    wire [3:0]  sb_head_wstrb;
    wire [2:0]  sb_head_op;
    wire        sb_head_valid;
    wire        sb_pop;

    wire        sb_snoop_hit;
    wire [31:0] sb_snoop_data;
    wire [3:0]  sb_snoop_strb;

    wire        sb_empty;
    wire        sb_full;

    store_buffer #(
        .DEPTH (SB_DEPTH)
    ) u_sb (
        .aclk        (aclk),
        .aresetn     (aresetn),
        .push        (sb_push),
        .push_addr   (sb_push_addr),
        .push_wdata  (sb_push_wdata),
        .push_wstrb  (sb_push_wstrb),
        .push_op     (sb_push_op),
        .push_full   (sb_push_full),
        .head_addr   (sb_head_addr),
        .head_wdata  (sb_head_wdata),
        .head_wstrb  (sb_head_wstrb),
        .head_op     (sb_head_op),
        .head_valid  (sb_head_valid),
        .pop         (sb_pop),
        .snoop_addr  (up_d_addr),
        .snoop_hit   (sb_snoop_hit),
        .snoop_data  (sb_snoop_data),
        .snoop_strb  (sb_snoop_strb),
        .empty       (sb_empty),
        .full        (sb_full)
    );

    // SB snoop is currently informational (forwarding is unnecessary
    // because cacheable loads go through the cache and non-cacheable
    // loads gate on sb_empty).  Mark used so lint stays quiet.
    wire _unused_sb_snoop = sb_snoop_hit ^ (|sb_snoop_data) ^ (|sb_snoop_strb);

    // -------------------------------------------------------------------------
    // FSM
    //
    // Note: S_FILL_ACK is gone vs the pre-CWF revision -- the critical
    // word ack is now delivered combinationally on the first beat of
    // S_FILL (see `fill_first_beat` below), and the line commit happens
    // directly on the last beat with state going straight to S_IDLE.
    // -------------------------------------------------------------------------
    localparam [2:0] S_IDLE      = 3'd0;
    localparam [2:0] S_WB_PUSH   = 3'd1;
    localparam [2:0] S_FILL_WAIT = 3'd2;
    localparam [2:0] S_FILL      = 3'd3;
    localparam [2:0] S_BYPASS    = 3'd4;

    reg [2:0]            state;
    reg [WSEL_W-1:0]     fill_cnt;       // current beat's word slot (CWF: starts at miss_addr[3:2], wraps mod 4)
    reg [WSEL_W-1:0]     beats_rcv;      // number of beats received so far in this fill (0..3); 0 => next R is critical beat
    reg [WSEL_W-1:0]     wb_cnt;
    reg [IDX_W-1:0]      miss_idx;
    reg [TAG_W-1:0]      miss_tag;
    reg [TAG_W-1:0]      evict_tag;
    reg                  miss_was_store;
    reg                  miss_was_load;
    reg [31:0]           miss_addr;
    reg [2:0]            miss_op;
    reg [31:0]           miss_sdata;
    reg [LINE_BITS-1:0]  fill_buf;
    reg                  fill_err;
    reg [LINE_BITS-1:0]  evict_buf;

    wire victim_dirty = valid[up_idx] & dirty[up_idx];

    // SB drains opportunistically when neither cache miss FSM (S_FILL)
    // nor bypass FSM (S_BYPASS) wants the bridge.  S_FILL_WAIT keeps SB
    // drain enabled because that's the state's whole purpose.
    wire sb_drain_active = sb_head_valid &
                           ((state == S_IDLE) |
                            (state == S_WB_PUSH) |
                            (state == S_FILL_WAIT));

    // Pop the SB the same cycle the bridge accepts the head entry.  Making
    // pop combinational (rather than registering it for one extra cycle)
    // ensures head_valid drops on the very next clock edge so the comb
    // bridge-drive logic does NOT re-issue the same entry while the bridge
    // sits in S_DONE -> S_IDLE.  Otherwise dcache would speculatively
    // launch a second AW for the just-popped entry, then S_BYPASS would
    // mistake that phantom write's d_bus_ready for its own read ack.
    assign sb_pop = sb_drain_active & dn_d_bus_ready;

    wire [31:0] fill_addr = {miss_tag, miss_idx, fill_cnt, 2'b00};

    // Combinational classification of an S_IDLE request.  Each `*_now`
    // is mutually exclusive with the others so they can drive separate
    // up_ack paths.
    wire idle_misalign     = (state == S_IDLE) & up_req & up_misalign;
    wire idle_hit          = (state == S_IDLE) & up_req & ~up_misalign
                           & up_cacheable & hit_match;
    wire idle_nc_store_ok  = (state == S_IDLE) & up_req & ~up_misalign
                           & ~up_cacheable & up_ram_we & ~sb_full;

    // S_BYPASS ack pulse: high for exactly one clock cycle by virtue
    // of the FSM transitioning to S_IDLE on the next edge.
    wire bypass_ack = (state == S_BYPASS) & dn_d_bus_ready;

    // Explicit background-fill semantics (PROCESSOR_IMPROVEMENT_PLAN):
    // While fill_pending is set, upstream hit / NC-store / bypass paths do
    // not arm (state!=S_IDLE), so accesses to other words on the same line
    // stall until commit — no hit-under-fill.
    wire fill_pending = (state == S_FILL);

    // Critical-word-first ack pulse: same cycle as the FIRST returning beat
    // (beats_rcv==0) after fill_cnt was initialised to miss_addr[3:2].
    wire fill_first_beat = fill_pending & dn_d_bus_ready
                         & (beats_rcv == {WSEL_W{1'b0}});

    // -------------------------------------------------------------------------
    // CPU-visible ready / data / err / misalign (combinational).
    //
    // Combinational ack matches icache.v's pattern: the CPU sees
    // up_d_bus_ready in the same cycle the FSM decides we have an
    // answer, advances reg_3 at the next posedge, and the dcache state
    // automatically transitions to S_IDLE so the next cycle's request
    // is judged on its own merit.  This avoids a registered-pulse hazard
    // where a stale ack carries forward across a request boundary.
    // -------------------------------------------------------------------------
    always @(*) begin
        up_bus_data_in    = 32'd0;
        up_d_bus_ready    = 1'b0;
        up_d_bus_err      = 1'b0;
        up_d_bus_misalign = 1'b0;

        if (idle_misalign) begin
            up_d_bus_ready    = 1'b1;
            up_d_bus_misalign = 1'b1;
        end
        else if (idle_hit) begin
            up_d_bus_ready = 1'b1;
            if (up_ram_re) begin
                up_bus_data_in = extract_load(hit_word_raw,
                                              up_mem_op,
                                              up_boff);
            end
        end
        else if (idle_nc_store_ok) begin
            up_d_bus_ready = 1'b1;
        end
        else if (fill_first_beat) begin
            // CWF ack: the very first fill beat IS the critical word
            // because we initialise fill_cnt = miss_addr[3:2].  Drive
            // the load result combinationally from the AXI R channel
            // (`dn_bus_data_in`) so the CPU sees its word the same
            // cycle the AXI bus delivers it; no detour through
            // fill_buf or the data SRAM.
            up_d_bus_ready = 1'b1;
            up_d_bus_err   = dn_d_bus_err;
            if (miss_was_load) begin
                up_bus_data_in = extract_load(dn_bus_data_in,
                                              miss_op,
                                              miss_addr[1:0]);
            end
        end
        else if (bypass_ack) begin
            up_d_bus_ready    = 1'b1;
            up_d_bus_err      = dn_d_bus_err;
            up_d_bus_misalign = dn_d_bus_misalign;
            if (miss_was_load) up_bus_data_in = dn_bus_data_in;
        end
    end

    // -------------------------------------------------------------------------
    // Bridge drive (combinational)
    // -------------------------------------------------------------------------
    always @(*) begin
        dn_d_bus_en   = 1'b0;
        dn_ram_we     = 1'b0;
        dn_ram_re     = 1'b0;
        dn_d_addr     = 32'd0;
        dn_d_data_out = 32'd0;
        dn_mem_op     = 3'd0;

        if (state == S_FILL) begin
            dn_d_bus_en = 1'b1;
            dn_ram_re   = 1'b1;
            dn_d_addr   = fill_addr;
            dn_mem_op   = 3'b010;            // LW (full-word read)
        end
        else if (state == S_BYPASS) begin
            dn_d_bus_en   = 1'b1;
            dn_ram_we     = miss_was_store;
            dn_ram_re     = miss_was_load;
            dn_d_addr     = miss_addr;
            dn_d_data_out = miss_sdata;
            dn_mem_op     = miss_op;
        end
        else if (sb_drain_active) begin
            dn_d_bus_en   = 1'b1;
            dn_ram_we     = 1'b1;
            dn_d_addr     = sb_head_addr;
            dn_d_data_out = sb_head_wdata;
            dn_mem_op     = sb_head_op;
        end
    end

    // -------------------------------------------------------------------------
    // Sequential FSM + cache update + SB control
    // -------------------------------------------------------------------------
    reg [LINE_BITS-1:0] fill_buf_next;
    reg [31:0]          merged_word_hit;
    reg [31:0]          merged_word_fill;
    reg [LINE_BITS-1:0] commit_line;

    always @(*) begin
        fill_buf_next = fill_buf;
        case (fill_cnt)
            2'd0: fill_buf_next[ 31: 0] = dn_bus_data_in;
            2'd1: fill_buf_next[ 63:32] = dn_bus_data_in;
            2'd2: fill_buf_next[ 95:64] = dn_bus_data_in;
            2'd3: fill_buf_next[127:96] = dn_bus_data_in;
        endcase
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            state           <= S_IDLE;
            fill_cnt        <= {WSEL_W{1'b0}};
            beats_rcv       <= {WSEL_W{1'b0}};
            wb_cnt          <= {WSEL_W{1'b0}};
            miss_idx        <= {IDX_W{1'b0}};
            miss_tag        <= {TAG_W{1'b0}};
            evict_tag       <= {TAG_W{1'b0}};
            miss_was_store  <= 1'b0;
            miss_was_load   <= 1'b0;
            miss_addr       <= 32'd0;
            miss_op         <= 3'd0;
            miss_sdata      <= 32'd0;
            fill_buf        <= {LINE_BITS{1'b0}};
            fill_err        <= 1'b0;
            evict_buf       <= {LINE_BITS{1'b0}};
            valid           <= {NUM_LINES{1'b0}};
            dirty           <= {NUM_LINES{1'b0}};

            sb_push         <= 1'b0;
            sb_push_addr    <= 32'd0;
            sb_push_wdata   <= 32'd0;
            sb_push_wstrb   <= 4'd0;
            sb_push_op      <= 3'd0;
        end else begin
            // Default: push pulse goes low each cycle (pop is combinational
            // and handled outside this seq block - see assign sb_pop above).
            sb_push <= 1'b0;

            // Top-level invalidate (currently tied off in cpu_soc.v).
            if (flush) begin
                valid <= {NUM_LINES{1'b0}};
                dirty <= {NUM_LINES{1'b0}};
            end

            case (state)
                // ------------------------------------------------------
                // S_IDLE: combinational hit / misalign / nc-store ack
                // already happen via the comb up_d_bus_ready above.  All
                // we do here is the side-effect work (cache write on
                // hit, SB push on nc-store) and dispatch into the miss
                // path.
                // ------------------------------------------------------
                S_IDLE: begin
                    if (idle_hit & up_ram_we) begin
                        merged_word_hit = merge_store(hit_word_raw,
                                                      up_d_data_out,
                                                      up_mem_op,
                                                      up_boff);
                        case (up_wsel)
                            2'd0: data_mem[up_idx][ 31: 0] <= merged_word_hit;
                            2'd1: data_mem[up_idx][ 63:32] <= merged_word_hit;
                            2'd2: data_mem[up_idx][ 95:64] <= merged_word_hit;
                            2'd3: data_mem[up_idx][127:96] <= merged_word_hit;
                        endcase
                        dirty[up_idx] <= 1'b1;
                    end
                    else if (idle_nc_store_ok) begin
                        // Push the *original* request shape (address with
                        // byte offset preserved, raw d_data_out, original
                        // mem_op) so axil_master_bridge.v can apply its
                        // own (mem_op,boff)->wdata/wstrb shift at drain
                        // time.  The wstrb stored on the SB is purely for
                        // forwarding/snoop bookkeeping.
                        sb_push       <= 1'b1;
                        sb_push_addr  <= up_d_addr;
                        sb_push_wdata <= up_d_data_out;
                        sb_push_wstrb <= strb_for(up_mem_op,
                                                  up_boff);
                        sb_push_op    <= up_mem_op;
                    end
                    else if (up_req & ~up_misalign & up_cacheable
                             & ~hit_match) begin
                        // Cacheable miss.  If the victim is dirty AND
                        // the SB isn't empty, spin one cycle so the SB
                        // can drain to make room for the writeback.
                        if (~victim_dirty | sb_empty) begin
                            miss_idx       <= up_idx;
                            miss_tag       <= up_tag;
                            miss_addr      <= up_d_addr;
                            miss_op        <= up_mem_op;
                            miss_was_load  <= up_ram_re;
                            miss_was_store <= up_ram_we;
                            miss_sdata     <= up_d_data_out;
                            // CWF: start the line read at the word the
                            // CPU is actually waiting on.  fill_cnt
                            // wraps modulo 4 each beat and beats_rcv
                            // tracks how many of the four beats have
                            // landed so we know when to commit.
                            fill_cnt        <= up_wsel;
                            beats_rcv       <= {WSEL_W{1'b0}};
                            fill_buf        <= {LINE_BITS{1'b0}};
                            fill_err        <= 1'b0;
                            if (victim_dirty) begin
                                evict_buf <= data_mem[up_idx];
                                evict_tag <= tag_mem[up_idx];
                                wb_cnt    <= {WSEL_W{1'b0}};
                                state     <= S_WB_PUSH;
                            end else begin
                                state <= S_FILL_WAIT;
                            end
                        end
                    end
                    else if (up_req & ~up_misalign & ~up_cacheable
                             & ~idle_nc_store_ok) begin
                        // Non-cacheable load OR non-cacheable store
                        // blocked by full SB.  For loads we additionally
                        // require sb_empty so the bridge sees prior
                        // MMIO stores in program order.
                        if (up_ram_re & sb_empty) begin
                            miss_idx       <= up_idx;
                            miss_tag       <= up_tag;
                            miss_addr      <= up_d_addr;
                            miss_op        <= up_mem_op;
                            miss_was_load  <= 1'b1;
                            miss_was_store <= 1'b0;
                            miss_sdata     <= 32'd0;
                            state          <= S_BYPASS;
                        end
                        else if (up_ram_we & ~up_ram_re) begin
                            // Store that found SB full -- spin until SB
                            // drains a slot.  No state change.
                        end
                        // else: load with SB non-empty, spin.
                    end
                end

                // ------------------------------------------------------
                // S_WB_PUSH: enqueue 4 dirty words from evict_buf into
                // the SB, one per cycle.  S_IDLE guaranteed sb_empty
                // before entering, so push_full never fires here for
                // a 4-deep SB.
                // ------------------------------------------------------
                S_WB_PUSH: begin
                    sb_push       <= 1'b1;
                    sb_push_addr  <= {evict_tag, miss_idx, wb_cnt, 2'b00};
                    sb_push_wdata <= evict_buf[32*wb_cnt +: 32];
                    sb_push_wstrb <= 4'b1111;
                    sb_push_op    <= 3'b010;
                    if (wb_cnt == {WSEL_W{1'b1}}) begin
                        dirty[miss_idx] <= 1'b0;
                        valid[miss_idx] <= 1'b0;
                        state           <= S_FILL_WAIT;
                    end else begin
                        wb_cnt <= wb_cnt + 1'b1;
                    end
                end

                // ------------------------------------------------------
                // S_FILL_WAIT: serialise bridge usage by waiting for SB
                // to fully drain before the line fill begins.
                // ------------------------------------------------------
                S_FILL_WAIT: begin
                    if (sb_empty) state <= S_FILL;
                end

                // ------------------------------------------------------
                // S_FILL: 4-beat line read with critical-word-first.
                //
                // Beat 0 (when beats_rcv==0) carries the critical word
                // because fill_cnt was initialised to miss_addr[3:2].
                // The combinational up_d_bus_ready path above pulses
                // ack THIS cycle so the CPU resumes immediately.
                // `beats_rcv==0` ensures that pulse is exactly once per
                // fill (subsequent beats have beats_rcv!=0). Subsequent
                // beats stream in with their own
                // dn_d_bus_ready handshakes, fill_cnt wraps mod 4 so
                // each word lands in its correct slot, and beats_rcv
                // increments to track when we have all four.
                //
                // Last beat (beats_rcv==3) commits the line and goes
                // straight to S_IDLE -- the old S_FILL_ACK parking
                // cycle is gone because the CWF ack has already
                // happened.  Any new CPU request that arrives between
                // the CWF ack and the line commit stalls on
                // up_d_bus_ready=0 (state != S_IDLE blocks every
                // idle_*).
                // ------------------------------------------------------
                S_FILL: begin
                    if (dn_d_bus_ready) begin
                        fill_buf <= fill_buf_next;
                        if (dn_d_bus_err) fill_err <= 1'b1;

                        if (beats_rcv == {WSEL_W{1'b1}}) begin
                            // Build the post-fill, post-merge line in
                            // one combinational shot.
                            commit_line = fill_buf_next;
                            if (miss_was_store) begin
                                merged_word_fill = merge_store(
                                    fill_buf_next[32*miss_addr[3:2] +: 32],
                                    miss_sdata,
                                    miss_op,
                                    miss_addr[1:0]);
                                case (miss_addr[3:2])
                                    2'd0: commit_line[ 31: 0] = merged_word_fill;
                                    2'd1: commit_line[ 63:32] = merged_word_fill;
                                    2'd2: commit_line[ 95:64] = merged_word_fill;
                                    2'd3: commit_line[127:96] = merged_word_fill;
                                endcase
                            end

                            if (~fill_err & ~dn_d_bus_err & ~flush) begin
                                tag_mem[miss_idx]  <= miss_tag;
                                data_mem[miss_idx] <= commit_line;
                                valid[miss_idx]    <= 1'b1;
                                dirty[miss_idx]    <= miss_was_store;
                            end
                            state <= S_IDLE;
                        end else begin
                            // 2-bit fill_cnt naturally wraps mod 4, no
                            // explicit modular logic needed.
                            fill_cnt  <= fill_cnt  + 1'b1;
                            beats_rcv <= beats_rcv + 1'b1;
                        end
                    end
                end

                // ------------------------------------------------------
                // S_BYPASS: forward the CPU's request to the bridge
                // until the bridge acks; ack pulse is combinational.
                // ------------------------------------------------------
                S_BYPASS: begin
                    if (dn_d_bus_ready) state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    always @(posedge aclk) begin
        if (aresetn) begin
            if (sb_push & sb_push_full) begin
                $display("[dcache] ERROR: SB push while full @%0t (state=%0d)",
                         $time, state);
            end
        end
    end
`ifdef DCACHE_TRACE
    always @(posedge aclk) begin
        if (aresetn) begin
            if (idle_nc_store_ok || bypass_ack || fill_first_beat ||
                (sb_drain_active && dn_d_bus_ready)) begin
                $display("[dcache] t=%0t st=%0d up_addr=%h up_we=%b up_re=%b up_data=%h up_din=%h dn_addr=%h dn_we=%b dn_din=%h dn_rdy=%b nc_st=%b bypass=%b cwf_ack=%b sb_dr=%b head_a=%h head_d=%h",
                    $time, state, up_d_addr, up_ram_we, up_ram_re, up_d_data_out, up_bus_data_in,
                    dn_d_addr, dn_ram_we, dn_bus_data_in, dn_d_bus_ready,
                    idle_nc_store_ok, bypass_ack, fill_first_beat, sb_drain_active,
                    sb_head_addr, sb_head_wdata);
            end
        end
    end
`endif
`endif

endmodule
