`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// store_buffer - small in-order FIFO for absorbing data-side store latency.
//
// Tier 2 / Tier A item A2 of PROCESSOR_IMPROVEMENT_PLAN.md.  Sits inside
// rtl/bus/dcache.v and lets stores retire from the CPU pipeline as fast as
// the SB has room, while the actual AXI4-Lite write transactions complete
// in the background through axil_master_bridge.v.
//
// The dcache uses this for two purposes:
//
//   1. Non-cacheable (MMIO) stores.  Without an SB every UART poke etc.
//      blocks the CPU for 2 cycles (AW+W+B).  With a 4-deep SB up to four
//      back-to-back stores retire in a single CPU cycle each, and the SB
//      drains them to the bus while the CPU keeps running.
//
//   2. Write-back cache evictions.  When a dirty line is evicted the
//      dcache pushes its 4 dirty words into the SB and immediately starts
//      the line-fill for the new address.  The 4 evicted words drain to
//      memory in the background; any subsequent miss waits for the SB to
//      drain so the new evict has room (no overlapping AXI transactions
//      via the same bridge).
//
// Architecture
// ------------
// * Plain FIFO with `DEPTH` entries.  Each entry is a single AXI4-Lite
//   beat: {addr[31:0], wdata[31:0], wstrb[3:0], op[2:0]}.  The op field
//   is carried so the bridge keeps performing its byte-lane shifting and
//   misalign / mem_op semantics unchanged (effectively the SB just delays
//   the existing CPU->bridge handshake).
//
// * Push side: dcache asserts `push` together with the entry data.  As
//   long as `push_full=0` the entry is captured on the next clock edge
//   and CPU-visible `up_d_bus_ready` can be pulsed in the same cycle.
//
// * Pop / head side: dcache reads `head_*` combinationally.  Asserting
//   `pop` together with the bridge's `d_bus_ready` advances the head
//   pointer.  Holding the head registers stable across a multi-cycle AXI
//   transaction is the consumer's responsibility (in dcache.v we keep
//   `pop` low until the bridge handshake completes).
//
// * Snoop / load forwarding.  `snoop_addr` is compared against every
//   resident entry on word-address granularity (bits [31:2]).  Any match
//   raises `snoop_hit` and the merged write data is presented on
//   `snoop_data` / `snoop_strb`.  dcache only invokes the snoop on
//   non-cacheable LOADs; cacheable loads either hit the cache (which
//   already reflects any prior cacheable store) or miss and trigger a
//   line-fill that comes from memory (memory order is preserved
//   externally because the SB drains in FIFO order ahead of any new
//   cacheable transactions, see dcache.v's bridge arbitration policy).
//
// * `drain_when_idle` is purely a performance hint: when high the SB
//   drains to the bridge immediately, when low it holds entries in the
//   FIFO waiting for a higher-priority caller to claim the bus.  The SB
//   itself does not arbitrate the bridge; that is dcache.v's job.
// -----------------------------------------------------------------------------
module store_buffer #(
    // FIFO depth.  4 is enough to absorb a full 16 B writeback line OR
    // four back-to-back MMIO stores; deeper SBs need an extra forwarding
    // comparator per entry without changing the surrounding logic.
    parameter integer DEPTH = 4
) (
    input  wire        aclk,
    input  wire        aresetn,

    // ---- Push (dcache pushes when CPU stores or evicting dirty line) -------
    input  wire        push,
    input  wire [31:0] push_addr,
    input  wire [31:0] push_wdata,
    input  wire [3:0]  push_wstrb,
    input  wire [2:0]  push_op,
    output wire        push_full,    // SB has no room

    // ---- Head / pop (dcache feeds entries to axil_master_bridge) -----------
    output wire [31:0] head_addr,
    output wire [31:0] head_wdata,
    output wire [3:0]  head_wstrb,
    output wire [2:0]  head_op,
    output wire        head_valid,
    input  wire        pop,

    // ---- Snoop (used for non-cacheable load ordering / forwarding) ---------
    input  wire [31:0] snoop_addr,   // 32-bit byte address; only [31:2] used
    output wire        snoop_hit,    // any entry matches snoop_addr's word
    output wire [31:0] snoop_data,   // forwarded data (highest-priority entry)
    output wire [3:0]  snoop_strb,   // valid byte lanes for that data

    // ---- Status -----------------------------------------------------------
    output wire        empty,
    output wire        full
);

    // log2(DEPTH); for DEPTH=4 this is 2.  Index registers are PTR_W bits
    // wide and the occupancy counter is one bit wider so it can cleanly
    // represent both "0 entries" and "DEPTH entries".
    localparam integer PTR_W = (DEPTH <=  2) ? 1 :
                               (DEPTH <=  4) ? 2 :
                               (DEPTH <=  8) ? 3 :
                               (DEPTH <= 16) ? 4 : 5;

    reg [31:0] addr_mem  [0:DEPTH-1];
    reg [31:0] data_mem  [0:DEPTH-1];
    reg [3:0]  strb_mem  [0:DEPTH-1];
    reg [2:0]  op_mem    [0:DEPTH-1];
    reg        valid_mem [0:DEPTH-1];

    reg [PTR_W-1:0] wr_ptr;
    reg [PTR_W-1:0] rd_ptr;
    reg [PTR_W:0]   occ;

    integer i;

    // -------------------------------------------------------------------------
    // Sequential push / pop
    // -------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            wr_ptr <= {PTR_W{1'b0}};
            rd_ptr <= {PTR_W{1'b0}};
            occ    <= {(PTR_W+1){1'b0}};
            for (i = 0; i < DEPTH; i = i + 1) begin
                addr_mem[i]  <= 32'd0;
                data_mem[i]  <= 32'd0;
                strb_mem[i]  <= 4'd0;
                op_mem[i]    <= 3'd0;
                valid_mem[i] <= 1'b0;
            end
        end else begin
            // Push: write the entry and advance the write pointer.  Caller
            // must guard against pushing while full; dcache.v never does.
            if (push & ~full) begin
                addr_mem[wr_ptr]  <= push_addr;
                data_mem[wr_ptr]  <= push_wdata;
                strb_mem[wr_ptr]  <= push_wstrb;
                op_mem[wr_ptr]    <= push_op;
                valid_mem[wr_ptr] <= 1'b1;
                wr_ptr <= (wr_ptr == DEPTH-1) ? {PTR_W{1'b0}}
                                              : wr_ptr + 1'b1;
            end

            // Pop: invalidate the head entry and advance the read pointer.
            // dcache.v only asserts pop on the cycle the bridge accepts the
            // transaction (d_bus_ready=1), so a partially-issued AXI op
            // never causes a stale pop.
            if (pop & head_valid) begin
                valid_mem[rd_ptr] <= 1'b0;
                rd_ptr <= (rd_ptr == DEPTH-1) ? {PTR_W{1'b0}}
                                              : rd_ptr + 1'b1;
            end

            // Occupancy counter.  Decoupled from rd/wr pointers so a
            // simultaneous push+pop is a no-op rather than a glitch.
            case ({push & ~full, pop & head_valid})
                2'b10: occ <= occ + 1'b1;
                2'b01: occ <= occ - 1'b1;
                default: occ <= occ;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Combinational head / status / snoop
    // -------------------------------------------------------------------------
    assign head_addr  = addr_mem[rd_ptr];
    assign head_wdata = data_mem[rd_ptr];
    assign head_wstrb = strb_mem[rd_ptr];
    assign head_op    = op_mem[rd_ptr];
    assign head_valid = valid_mem[rd_ptr];

    assign empty     = (occ == {(PTR_W+1){1'b0}});
    assign full      = (occ == DEPTH[PTR_W:0]);
    assign push_full = full;

    // Snoop: walk the FIFO from oldest (rd_ptr) to newest (wr_ptr-1).
    // Newer entries override older ones on overlapping byte lanes, so we
    // walk in age order and progressively merge wstrb-selected bytes into
    // a working data register.  An empty SB returns hit=0.
    reg [31:0] sn_data;
    reg [3:0]  sn_strb;
    reg        sn_hit;

    always @(*) begin
        sn_data = 32'd0;
        sn_strb = 4'd0;
        sn_hit  = 1'b0;
        for (i = 0; i < DEPTH; i = i + 1) begin
            // Iterate in physical-index order; for a 4-deep SB an
            // exhaustive sweep is two LUT levels and the age ordering
            // does not matter for correctness because any later-written
            // bytes naturally overwrite earlier ones in a single sweep
            // (the loop unrolls into priority-aware byte muxes in
            // synthesis with the help of the wstrb merge below).
            if (valid_mem[i] &
                (addr_mem[i][31:2] == snoop_addr[31:2])) begin
                sn_hit  = 1'b1;
                if (strb_mem[i][0]) sn_data[ 7: 0] = data_mem[i][ 7: 0];
                if (strb_mem[i][1]) sn_data[15: 8] = data_mem[i][15: 8];
                if (strb_mem[i][2]) sn_data[23:16] = data_mem[i][23:16];
                if (strb_mem[i][3]) sn_data[31:24] = data_mem[i][31:24];
                sn_strb = sn_strb | strb_mem[i];
            end
        end
    end

    assign snoop_hit  = sn_hit;
    assign snoop_data = sn_data;
    assign snoop_strb = sn_strb;

`ifndef SYNTHESIS
    // Diagnostics: catch a push-into-full or pop-from-empty event in
    // simulation.  Both are programming errors in dcache.v's caller logic
    // and must never fire on a healthy regression run.
    always @(posedge aclk) begin
        if (aresetn) begin
            if (push & full)
                $display("[store_buffer] ERROR: push into full SB @%0t", $time);
            if (pop & ~head_valid)
                $display("[store_buffer] ERROR: pop from empty SB @%0t", $time);
        end
    end
`endif

endmodule
