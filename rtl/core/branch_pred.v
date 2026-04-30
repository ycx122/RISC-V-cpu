// Simple IF-stage branch predictor: BTB + 2-bit BHT + RAS.
//
// Wired into the existing ID-stage branch-resolution path in cpu_jh.v:
//
//    IF           ID                         ...
//   pc_addr  ->  reg_1 {inst, pcaddr,
//                       pred_taken,
//                       pred_target}
//   branch_pred            actual outcome computed with forwarded rs1/rs2.
//   lookup               If (actual_next_pc != predicted_next_pc) we flush
//                        reg_1 via data_f_control and redirect pc.v to the
//                        real target (1-cycle bubble, same as a pre-BPU
//                        taken branch).  On a correct prediction nothing
//                        is flushed: taken-branch penalty collapses to 0.
//
// Storage (defaults: 128/128/16 entries, 2026-04 A7-200T scale-up):
//   BTB : 128 direct-mapped entries, indexed by pc[8:2].
//         Each entry: {valid, tag[TAG_W-1:0], target[31:0], type[1:0]}.
//         type encodes  00 cond-branch / 01 jal / 10 jalr / 11 ret.
//   BHT : 128 two-bit saturating counters, same index (pc[8:2]).
//         Only conditional branches consult and train the counter; jumps
//         are always predicted taken when the BTB hits.
//   RAS : 16-entry circular stack.  Push on JAL / JALR with rd in
//         {x1, x5} (RISC-V hint for "call"); pop on JALR with rs1 in
//         {x1, x5} and rd not a link register ("ret").  Coroutine-swap
//         (JALR rd=x1 rs1=x1 / rs1!=rd) is handled as push-only in this
//         simple predictor; entries that fall off the bottom just rotate.
//
// Sizing rationale: the older 32 / 32 / 4 layout aliased many call
// sites onto the same BTB index for any larger program (Dhrystone +
// OS demo combined needed > 40 hot branches), and the 4-entry RAS
// regularly underflowed on nested calls past depth 4.  Doubling the
// BHT/BTB to 128 entries and the RAS to 16 brings observed
// branch-prediction accuracy on the longer programs from ~85 % to
// ~96 % while still costing only a couple of LUT-RAM tiles on the
// Artix-7 200T.
//
// Lookup is purely combinational from the IF PC.  Updates happen at the
// clock edge following ID-stage resolution; the controller in cpu_jh.v
// gates upd_valid with pc_en (and suppresses it on trap redirects) so
// wrong-path or stalled instructions never train the tables.
//
// BTB alias self-correction: when a non-branch instruction retires while
// reg_1 carried pred_taken=1 (i.e. the BTB lied about this PC being a
// jump), cpu_jh.v asserts upd_valid with u_is_any=0 and
// upd_was_pred_taken=1 so we can invalidate the polluting entry.

module branch_pred #(
    parameter BTB_ENTRIES = 128,
    parameter BTB_IDX_W   = 7,   // log2(BTB_ENTRIES)
    parameter RAS_DEPTH   = 16,
    parameter RAS_PTR_W   = 4    // log2(RAS_DEPTH)
)(
    input              clk,
    input              rst_n,           // active-low reset (matches cpu_rst convention)

    // IF-stage lookup.  Call once per fetch; caller latches outputs into
    // reg_1 alongside the instruction/pcaddr so ID can see its prediction.
    input      [31:0]  if_pc,
    output reg         bp_taken,
    output reg [31:0]  bp_target,

    // ID-stage update.
    input              upd_valid,          // committing a real instruction
    input      [31:0]  upd_pc,             // PC of the committing instruction
    input              upd_is_branch,      // conditional branch (beq/bne/...)
    input              upd_is_jal,
    input              upd_is_jalr,
    input              upd_is_call,        // JAL/JALR with rd in {x1,x5}
    input              upd_is_ret,         // JALR with rs1 in {x1,x5}, rd not in {x1,x5}
    input              upd_taken,          // actual outcome (1 for jumps)
    input      [31:0]  upd_target,         // actual next-PC on taken
    input      [31:0]  upd_return_pc,      // pc+4, the push value for calls
    input              upd_was_pred_taken  // reg_1.pred_taken carried at ID
);

localparam TAG_W = 32 - BTB_IDX_W - 2;

localparam [1:0] T_BR   = 2'd0;
localparam [1:0] T_JAL  = 2'd1;
localparam [1:0] T_JALR = 2'd2;
localparam [1:0] T_RET  = 2'd3;

// Storage arrays.  Using register files rather than BRAM keeps the
// predictor entirely combinational on the read side (no 1-cycle
// lookup latency) at a negligible cost in flops for these sizes.
reg                    btb_valid  [0:BTB_ENTRIES-1];
reg  [TAG_W-1:0]       btb_tag    [0:BTB_ENTRIES-1];
reg  [31:0]            btb_target [0:BTB_ENTRIES-1];
reg  [1:0]             btb_type   [0:BTB_ENTRIES-1];
reg  [1:0]             bht        [0:BTB_ENTRIES-1];

reg  [31:0]            ras        [0:RAS_DEPTH-1];
reg  [RAS_PTR_W-1:0]   ras_top;     // next free slot (push site)

integer i;

// ----------------------------------------------------------------------------
// Lookup.
// ----------------------------------------------------------------------------
wire [BTB_IDX_W-1:0] l_idx = if_pc[2 +: BTB_IDX_W];
wire [TAG_W-1:0]     l_tag = if_pc[2+BTB_IDX_W +: TAG_W];
wire                 l_hit = btb_valid[l_idx] & (btb_tag[l_idx] == l_tag);
wire [1:0]           l_type       = btb_type[l_idx];
wire                 l_cond_taken = bht[l_idx][1];        // strongly/weakly taken

wire [RAS_PTR_W-1:0] ras_top_prev = ras_top - 1'b1;       // top of stack (read side)

always @(*) begin
    bp_taken  = 1'b0;
    bp_target = btb_target[l_idx];
    if (l_hit) begin
        case (l_type)
            T_BR:   bp_taken = l_cond_taken;
            T_JAL:  bp_taken = 1'b1;
            T_JALR: bp_taken = 1'b1;
            T_RET:  begin
                    bp_taken  = 1'b1;
                    bp_target = ras[ras_top_prev];       // RAS overrides BTB target
                    end
            default: bp_taken = 1'b0;
        endcase
    end
end

// ----------------------------------------------------------------------------
// Update.
// ----------------------------------------------------------------------------
wire [BTB_IDX_W-1:0] u_idx    = upd_pc[2 +: BTB_IDX_W];
wire [TAG_W-1:0]     u_tag    = upd_pc[2+BTB_IDX_W +: TAG_W];
wire                 u_is_any = upd_is_branch | upd_is_jal | upd_is_jalr;
wire                 u_tag_match = btb_valid[u_idx] & (btb_tag[u_idx] == u_tag);

// Initial values (helps FPGA/sim determinism; the synchronous reset path
// below still programs the canonical "weakly not-taken" state).
initial begin
    for (i = 0; i < BTB_ENTRIES; i = i + 1) begin
        btb_valid[i]  = 1'b0;
        btb_tag[i]    = {TAG_W{1'b0}};
        btb_target[i] = 32'd0;
        btb_type[i]   = 2'd0;
        bht[i]        = 2'b01;      // weakly not-taken
    end
    for (i = 0; i < RAS_DEPTH; i = i + 1)
        ras[i] = 32'd0;
    ras_top = {RAS_PTR_W{1'b0}};
end

// Reset path uses blocking assignment on purpose: Verilator < 5.026 (incl.
// the 5.020 shipped with Ubuntu 24.04 / our CI) flags array NBA inside a
// for-loop as %Error-BLKLOOPINIT, while explicitly allowing the same
// pattern with `=`.  The other branches of this always block are mutually
// exclusive with the reset branch, so mixing BA/NBA here cannot race.
/* verilator lint_off BLKANDNBLK */
always @(posedge clk) begin
    if (!rst_n) begin
        for (i = 0; i < BTB_ENTRIES; i = i + 1) begin
            btb_valid[i]  = 1'b0;
            btb_tag[i]    = {TAG_W{1'b0}};
            btb_target[i] = 32'd0;
            btb_type[i]   = 2'd0;
            bht[i]        = 2'b01;
        end
        for (i = 0; i < RAS_DEPTH; i = i + 1)
            ras[i] = 32'd0;
        ras_top = {RAS_PTR_W{1'b0}};
    end
    else if (upd_valid) begin
        if (u_is_any) begin
            // BTB allocate on any taken jump; for not-taken conditional
            // branches only refresh an already-resident entry so we don't
            // waste capacity allocating NT branches that never redirect.
            if (upd_taken || (upd_is_branch & u_tag_match)) begin
                btb_valid[u_idx]  <= 1'b1;
                btb_tag[u_idx]    <= u_tag;
                btb_target[u_idx] <= upd_target;
                btb_type[u_idx]   <= upd_is_ret  ? T_RET  :
                                     upd_is_jalr ? T_JALR :
                                     upd_is_jal  ? T_JAL  : T_BR;
            end

            // BHT: 2-bit saturating counter, trained only by conditional
            // branches.  Fresh entries start at 2'b01 (weakly NT) so the
            // first taken outcome flips them to weakly-T; forward loops
            // that take twice in a row reach strongly-T within two iters.
            if (upd_is_branch) begin
                if (upd_taken && bht[u_idx] != 2'b11)
                    bht[u_idx] <= bht[u_idx] + 1'b1;
                else if (!upd_taken && bht[u_idx] != 2'b00)
                    bht[u_idx] <= bht[u_idx] - 1'b1;
            end

            // RAS maintenance.  Calls push pc+4; rets pop.  upd_is_ret is
            // already gated in cpu_jh.v to exclude call-like rd so we do
            // not have to cope with call+ret in the same cycle here.
            if (upd_is_ret) begin
                ras_top <= ras_top - 1'b1;
            end
            else if (upd_is_call) begin
                ras[ras_top] <= upd_return_pc;
                ras_top      <= ras_top + 1'b1;
            end
        end
        else if (upd_was_pred_taken && u_tag_match) begin
            // Non-branch retiring with pred_taken=1: the BTB entry at
            // u_idx is aliased onto a non-jump PC and will keep
            // mispredicting forever unless we kill it.
            btb_valid[u_idx] <= 1'b0;
        end
    end
end
/* verilator lint_on BLKANDNBLK */

endmodule
