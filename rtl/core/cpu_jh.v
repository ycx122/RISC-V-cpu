// -----------------------------------------------------------------------------
// cpu_jh - top-level integer pipeline.
//
// History:
//   21/07/15          initial single-cycle skeleton
//   21/10/19          full RV32I decode
//   23/11/20          v2: five-stage pipeline
//   (refactor, 2026)  pulled reg_1..reg_4, stop_control, data_f_control,
//                     stop_cache, the ID-stage branch resolver, the
//                     operand-forwarding muxes and the EX/MEM combinational
//                     glue into their own modules so this file reads as a
//                     thin top-level instantiator.  No timing changes - the
//                     original stall/flush/forward/early-WB scheme is
//                     preserved bit-for-bit.  See:
//                       - rtl/core/pipeline_regs.v  (reg_1 / reg_2 / reg_3 / reg_4)
//                       - rtl/core/stop_cache.v     (IF-stage instr latch)
//                       - rtl/core/hazard_ctrl.v    (stall enable net)
//                       - rtl/core/flush_ctrl.v     (per-stage squash net)
//                       - rtl/core/branch_unit.v    (ID-stage branch resolver)
//                       - rtl/core/forward_mux.v    (4-to-1 rs1/rs2 muxes)
//                       - rtl/core/mem_ctrl.v       (EX/MEM data-bus drive)
//
// Reset-active-high assumed throughout this file (cpu_rst == 1'b0 means
// "in reset"; most submodule `rst` ports are also active-low but named
// `rst` rather than `rst_n` for historical reasons).
// -----------------------------------------------------------------------------
module cpu_jh (
    input             clk,
    input             cpu_rst,
    input      [31:0] bus_data_in,
    input             d_bus_ready,
    // 1-cycle pulse coincident with d_bus_ready:  1 => the completing
    // load/store saw an AXI SLVERR/DECERR response and has to raise a
    // Load/Store Access Fault at WB (Tier 4.2, Tier A #3).
    input             d_bus_err,
    input             i_bus_ready,
    input      [31:0] i_data_in,
    input             pc_set_en,
    input      [31:0] pc_set_data,

    // Level-sensitive interrupt pins (driven by the SoC / CLINT / PLIC stub):
    //   mtip - mtime >= mtime_cmp while clnt_flag is set
    //   meip - external interrupt line (high = request pending)
    // Both are expected to be synchronised onto `clk` upstream.
    input             mtip,
    input             meip,

    output     [31:0] data_addr_out,
    output     [31:0] d_data_out,
    output            d_bus_en,
    output reg        i_bus_en,
    output     [31:0] pc_addr_out,
    output            ram_we,
    output            ram_re,
    output     [2:0]  mem_op_out,

    // fence.i invalidate pulse, 1-cycle wide, asserted on the clock edge
    // the CPU-visible i-stream loses ordering with older stores (see the
    // flush_icache block further down).  Routed by cpu_soc.v into the
    // I-Cache's `flush` input; tied off harmlessly when the cache is
    // bypassed (TCM_IFETCH / ICACHE_DISABLE).
    output            flush_icache
);

    // -------------------------------------------------------------------------
    // Pipeline enables / stall / flush / misc
    // -------------------------------------------------------------------------
    wire reg1_en, reg2_en, reg3_en, reg4_en;
    wire pc_en;
    wire local_stop;
    wire div_wait;
    wire wfi_halt;                  // csr_reg: 1 while a committed WFI waits for mip & mie
    wire [3:0] rst;                 // per-stage active-low flush from flush_ctrl

    initial begin
        i_bus_en = 1'b1;
    end

    // Fence / fence.i stall: keep ID (and therefore IF) frozen while any
    // older store is still in EX / MEM or still owning the d-bus.  Once
    // reg_2_store, reg_3_store and the bus transaction have all drained,
    // fence.i itself is allowed to flow through as a plain NOP and the
    // next fetch sees the post-store memory image.  ORed into hazard_ctrl's
    // `local_stop` input; reg_3/reg_4 keep advancing independently so the
    // drain actually makes progress.
    wire id_is_fence_i;
    wire fence_stall = id_is_fence_i &
                       (reg_2_store | reg_3_store |
                        (d_bus_en & ~d_bus_ready));

    hazard_ctrl ca1 (
        .d_bus_en    (d_bus_en),
        .d_bus_ready (d_bus_ready),
        .i_bus_en    (i_bus_en),
        .i_bus_ready (i_bus_ready),
        .cpu_rst     (cpu_rst),
        .local_stop  (local_stop | fence_stall | wfi_halt),
        .div_wait    (div_wait),
        .reg1_en     (reg1_en),
        .reg2_en     (reg2_en),
        .reg3_en     (reg3_en),
        .reg4_en     (reg4_en),
        .pc_en       (pc_en)
    );

    // -------------------------------------------------------------------------
    // IF: PC + branch predictor + instruction latch + reg_1
    // -------------------------------------------------------------------------
    wire [31:0] pc_addr;
    assign pc_addr_out = pc_addr;

    wire        csr_pc_en;
    wire [31:0] csr_pc_data;
    wire        csr_data_c;
    wire        pc_set_en_pc   = csr_pc_en | pc_set_en;
    wire [31:0] pc_set_data_pc = csr_pc_en ? csr_pc_data
                                : pc_set_en ? pc_set_data
                                            : 32'd0;

    wire        bp_taken_raw;
    wire [31:0] bp_target;
    // Compile-time BPU bypass switch.  Passing `+define+BPU_DISABLE` (iverilog
    // -DBPU_DISABLE, or Verilator -DBPU_DISABLE) forces every IF-stage
    // prediction to "not taken" while leaving the predictor's update path
    // intact.  The pipeline then falls back to the pre-BPU behaviour (every
    // taken branch eats one bubble at ID) and sim/bpu_bench.sh can be used
    // to produce an A/B cycle comparison without a real git revert.
`ifdef BPU_DISABLE
    wire bp_taken = 1'b0;
`else
    wire bp_taken = bp_taken_raw;
`endif

    wire        id_mispred_en;
    wire        id_mispred_en_raw;
    wire [31:0] id_mispred_target;
    wire [1:0]  c_pc;

    // Pending-redirect latch.
    //
    // When an I-Cache miss occurs on the instruction after a taken
    // branch / JAL / JALR, the whole pipeline used to freeze until the
    // fill completed.  With the Tier-4.2.2 drain policy (hazard_ctrl
    // leaves reg_1..reg_4 enabled during i_wait), reg_2..reg_4 keep
    // draining through the NOP bubbles cpu_jh injects into reg_1, so
    // the branch itself retires normally.  The redirect, however,
    // still depends on pc_en (to avoid fake redirects during load-use
    // / CSR-use stalls), which is low during the fill.  This register
    // captures the raw mispredict pulse the cycle it fires (branch in
    // reg_1) and replays it into pc.v the first cycle pc_en goes
    // high, which is also the cycle fetch returns a word we have to
    // squash (the wrong-path word that happened to sit at the fall-
    // through PC).  flush_ctrl therefore uses the apply pulse to
    // squash reg_1 alongside the pc redirect.
    reg        pending_redirect_r;
    reg [31:0] pending_redirect_target_r;
    wire       pending_redirect_apply = pending_redirect_r & pc_en;
    // Only real control-transfer instructions latch a pending
    // redirect; a NOP bubble sitting in reg_1 during drain could
    // otherwise hit a stale BTB alias and fire id_mispred_en_raw even
    // though the architectural next PC is simply pcaddr+4.
    wire       reg_1_is_ctrl  = (id_b_en != 2'd0);
    // Restrict pending-redirect latch to the single stall class the
    // drain policy is trying to fix: i_wait with no other pipeline
    // hazard active.  During d_wait, local_stop (load-use / CSR-use),
    // or div_wait the forwarded operands feeding branch_unit can be
    // stale (see branch_unit.v's pc_en-gate rationale), so we mustn't
    // trust id_mispred_en_raw as a genuine control-flow event.
    wire       pending_trigger = id_mispred_en_raw & reg_1_is_ctrl
                               & i_wait & ~d_wait & ~local_stop & ~div_wait
                               & ~pending_redirect_r;
    always @(posedge clk) begin
        if (cpu_rst == 1'b0) begin
            pending_redirect_r        <= 1'b0;
            pending_redirect_target_r <= 32'd0;
        end
        // Trap always wins - csr_reg's trap_set_en bypasses pc_en so
        // any pending redirect is stale by the time pc jumps to the
        // trap vector.
        else if (pc_set_en_pc) begin
            pending_redirect_r <= 1'b0;
        end
        else if (pending_redirect_apply) begin
            pending_redirect_r <= 1'b0;
        end
        else if (pending_trigger) begin
            pending_redirect_r        <= 1'b1;
            pending_redirect_target_r <= id_mispred_target;
        end
    end

    pc a1 (
        .pc_addr                 (pc_addr),
        .clk                     (clk),
        .rst                     (cpu_rst),
        .pc_en                   (pc_en),
        .trap_set_en             (pc_set_en_pc),
        .trap_set_addr           (pc_set_data_pc),
        .pending_redirect_en     (pending_redirect_r),
        .pending_redirect_target (pending_redirect_target_r),
        .id_mispred_en           (id_mispred_en),
        .id_mispred_target       (id_mispred_target),
        .bp_pred_taken           (bp_taken),
        .bp_pred_target          (bp_target)
    );

    // Level-0 PC snapshot (kept for historical reasons -- matches the old
    // combinational path from the pc module into reg_1's pc_out input).
    reg [31:0] pc_addr_reg0;
    always @(*) pc_addr_reg0 = pc_addr;

    wire [31:0] stop_cache_reg1;
    wire        d_wait = d_bus_en    & (~d_bus_ready);
    wire        i_wait = i_bus_en    & (~i_bus_ready);

    // Valid-gated instruction word feed to reg_1.
    //
    // With the AXI ifetch path (rtl/bus/axil_ifetch_bridge.v + I-Cache)
    // `i_data_in` only carries a valid instruction on cycles where
    // `i_bus_ready` pulses high; in between transactions the bus master
    // may drive zeros or stale bytes on the R channel.
    //
    // The Tier-4.2.2 drain model leaves reg1_en high during an i_wait
    // window so reg_2..reg_4 can retire already-fetched in-flight work;
    // that means reg_1 samples stop_cache_reg1 every cycle, including
    // inside a miss fill.  To keep that re-sampling harmless we inject
    // an architectural NOP (addi x0, x0, 0 == 32'h0000_0013) whenever
    // i_bus_ready is low, which is exactly the correct bubble shape for
    // the integer pipeline: rd=0 => no regfile write, wb_en=0 after
    // id.v decodes it, so reg_2..reg_4 see a harmless slot.
    //
    // In the TCM_IFETCH fallback i_bus_ready is tied high and this mux
    // degenerates to a pure combinational pass-through of i_data_in, so
    // the pre-AXI behaviour is preserved bit-for-bit.
    localparam [31:0] IFETCH_BUBBLE_NOP = 32'h0000_0013;
    assign stop_cache_reg1 = i_bus_ready ? i_data_in : IFETCH_BUBBLE_NOP;

    // fence.i invalidate pulse.
    //
    // The I-Cache (rtl/bus/icache.v) snoops `flush_icache` and clears all
    // valid bits on the rising edge.  We need the flush to land on the
    // *same* clock edge reg_1 first latches the fence.i instruction word,
    // so that the very next cycle's cache lookup (aimed at fence.i's
    // successor PC, since pc_en fired together with reg1_en on that
    // edge) cannot get a pre-invalidation hit.  Asserting the pulse one
    // cycle later -- after reg_1 already contains fence.i -- is too late
    // because the successor-PC lookup is combinational and would have
    // observed a stale valid entry before the flush edge.
    //
    // The trigger is therefore a decode of the instruction word that is
    // about to enter reg_1 (stop_cache_reg1), gated by `reg1_en` so we
    // only pulse on cycles the register actually moves.  The decode
    // matches id.v's fence_i recognition (opcode == 5'b00011, low two
    // bits == 2'b11).  While i_bus_ready is low stop_cache_reg1 presents
    // the IFETCH_BUBBLE_NOP encoding (addi x0, x0, 0 == 32'h13) whose
    // [6:2]=00100 does NOT match fence.i's 00011, so a replayed bubble
    // cannot spuriously re-assert flush_icache mid-stall.
    wire incoming_is_fence_i = (stop_cache_reg1[1:0] == 2'b11) &
                               (stop_cache_reg1[6:2] == 5'b00011);
    assign flush_icache = reg1_en & incoming_is_fence_i;

    wire [31:0] reg_1_inst, reg_1_pcaddr;
    wire        reg_1_pred_taken;
    wire [31:0] reg_1_pred_target;

    reg_1 a1_2 (
        .reg1_en      (reg1_en),
        .rom_out      (stop_cache_reg1),
        .pc_out       (pc_addr_reg0),
        .clk          (clk),
        .rst          (rst[0] & cpu_rst),
        .id_in        (reg_1_inst),
        .reg_2_in     (reg_1_pcaddr),
        .bp_taken_in  (bp_taken),
        .bp_target_in (bp_target),
        .pred_taken   (reg_1_pred_taken),
        .pred_target  (reg_1_pred_target)
    );

    // -------------------------------------------------------------------------
    // ID: decode + regfile + forwarding + branch resolution
    // -------------------------------------------------------------------------
    wire        id_s, id_l, id_im_c, id_wb_en, id_mul_div, id_wq;
    wire [4:0]  id_rs1, id_rs2, id_rd;
    wire [31:0] id_im;
    wire [2:0]  id_alu_op;
    wire [1:0]  id_b_en, id_pc_c;
    wire [12:0] id_b_im;
    wire [20:0] id_pc_im;
    wire        id_sub;
    wire [2:0]  id_mem_op;
    wire [14:0] id_csr;
    wire        id_illegal;
    // jalr discriminator (id.v opcode 11001 == JALR); kept here because
    // branch_unit uses it to select between the two id_pc_im encodings.
    wire        id_pc_im_f = (reg_1_inst[6:2] == 5'b11001) ? 1'b1 : 1'b0;

    id a2 (
        reg_1_inst,
        reg_1_pcaddr,
        id_s,
        id_l,
        id_rs1,
        id_rs2,
        id_rd,
        id_alu_op,
        id_im,
        id_im_c,
        id_pc_im,
        id_pc_c,
        id_wb_en,
        id_b_im,
        id_b_en,
        id_sub,
        id_mem_op,
        id_csr,
        id_mul_div,
        id_wq,
        id_is_fence_i,
        id_illegal
    );

    wire [31:0] regfile_data1, regfile_data2;
    wire [31:0] csr_reg_wb_data;

    // WB / MEM retire-pulse gates.
    //
    // When the IF or MEM bus stalls (i_wait / d_wait), reg_3 and reg_4
    // are held by hazard_ctrl: reg3_en / reg4_en drop low so the
    // registers keep their current contents and the pipeline does not
    // lose work-in-flight.  Their *outputs* therefore keep presenting
    // the same instruction for the duration of the stall, which in turn
    // would drive csr_reg's side-effect logic (CSR write, mepc/mcause
    // latch, minstret tick) and the regfile's WB/fast-path write ports
    // every clock cycle.  That double-retires the instruction -- most
    // visibly `csrrs rd, csr, rs1` ends up returning the POST-update
    // value in rd instead of the OLD value the spec mandates.
    //
    // Under the legacy TCM_IFETCH path this was latent: i_wait was
    // hardwired 0 and the handful of AXI slaves we ship complete in
    // one cycle, so d_wait never lasted long enough to be observed.
    // The new AXI ifetch path, however, imposes a one-cycle bubble
    // between every instruction (2-cycle read handshake) so the first
    // csrrs in sim/tests/mi_smoke.S immediately double-fires.
    //
    // Fix: gate the WB-stage side-effects and the EX fast-path write
    // with a "fresh" pulse that is only high on the cycle right after
    // reg_3 / reg_4 were actually written (= reg*_en was high the
    // previous cycle).  During a stall the pulse falls low, so the
    // held instruction contributes exactly one retire.
    reg reg3_en_d1, reg4_en_d1;
    always @(posedge clk) begin
        if (cpu_rst == 1'b0) begin
            reg3_en_d1 <= 1'b0;
            reg4_en_d1 <= 1'b0;
        end else begin
            reg3_en_d1 <= reg3_en;
            reg4_en_d1 <= reg4_en;
        end
    end
    wire wb_fresh  = reg4_en_d1;
    wire mem_fresh = reg3_en_d1;

    regfile b2 (
        regfile_data1,
        regfile_data2,
        clk,
        csr_reg_wb_data,
        reg_4_rd,
        id_rs1, id_rs2,
        reg_4_wb_en & wb_fresh,
        reg_3_wq & reg_3_wb_en_in & mem_fresh,
        reg_3_rd,
        reg_3_p_out
    );

    // Hazard + forwarding select.
    //   fwd_sel_{1,2} encoding (see otof1.v / forward_mux.v):
    //     00 regfile, 01 EX (p_out), 10 MEM (j2_p_out), 11 WB (csr_reg_wb_data)
    //   reg_*_csr[2] is the "this is a CSR instruction" bit set in id.v.  The
    //   whole 15-bit csr field is zero for non-CSR decodes, and CSRRW/CSRRS/
    //   CSRRC set csr[2]=1.  ecall/ebreak/mret also set csr[2] but decode
    //   with rd=0, so the rs==rd && rs!=0 check in otof1 never fires for
    //   them and no spurious stall is injected.
    wire [1:0] fwd_sel_1, fwd_sel_2;
    otof1 d2 (
        .rs1       (id_rs1),
        .rs2       (id_rs2),
        .rd_ex     (reg_2_rd),
        .wb_en_ex  (reg_2_wb_en_in),
        .load_ex   (reg_2_load),
        .csr_ex    (reg_2_csr[2]),
        .rd_mem    (reg_3_rd),
        .wb_en_mem (reg_3_wb_en_in),
        .csr_mem   (reg_3_csr[2]),
        .rd_wb     (reg_4_rd),
        // wb_en_wb is gated by wb_fresh so that once the retiring
        // instruction's regfile write has already landed (which
        // happens on the posedge at the end of the wb_fresh cycle),
        // consumers fall back to the freshly-written regfile value
        // instead of re-reading csr_reg_wb_data.  For CSR instructions
        // the latter is a live combinational read of the destination
        // CSR, which after the sync update in csr_reg now carries the
        // POST-update value -- exactly what the architectural rd is
        // NOT supposed to be.  Non-CSR ops see the same byte either
        // way (reg_4_j2_p_out doesn't change across stall cycles), so
        // masking this is safe.
        .wb_en_wb  (reg_4_wb_en & wb_fresh),
        .fwd_sel_1 (fwd_sel_1),
        .fwd_sel_2 (fwd_sel_2),
        .local_stop(local_stop)
    );

    wire [31:0] rs1_fwd, rs2_fwd;
    forward_mux d2_mux (
        .fwd_sel_1     (fwd_sel_1),
        .fwd_sel_2     (fwd_sel_2),
        .regfile_data1 (regfile_data1),
        .regfile_data2 (regfile_data2),
        .ex_fwd        (p_out),
        .mem_fwd       (j2_p_out),
        .wb_fwd        (csr_reg_wb_data),
        .rs1_fwd       (rs1_fwd),
        .rs2_fwd       (rs2_fwd)
    );

    // ID-stage branch/jump resolver + BPU training signals.
    wire        id_actual_taken;
    wire [31:0] id_actual_target;
    wire [31:0] id_actual_next_pc;
    wire        id_is_branch, id_is_jal, id_is_jalr;
    wire        id_upd_is_call, id_upd_is_ret;
    wire        id_upd_valid;
    wire        id_valid_slot;

    branch_unit bu_id (
        .id_b_en            (id_b_en),
        .id_pc_im_f         (id_pc_im_f),
        .id_mem_op          (id_mem_op),
        .id_pc_im           (id_pc_im),
        .id_b_im            (id_b_im),
        .id_rs1             (id_rs1),
        .id_rd              (id_rd),
        .reg_1_pcaddr       (reg_1_pcaddr),
        .reg_1_pred_taken   (reg_1_pred_taken),
        .reg_1_pred_target  (reg_1_pred_target),
        .rs1_fwd            (rs1_fwd),
        .rs2_fwd            (rs2_fwd),
        .pc_en              (pc_en),
        .csr_data_c         (csr_data_c),
        .id_actual_taken    (id_actual_taken),
        .id_actual_target   (id_actual_target),
        .id_actual_next_pc  (id_actual_next_pc),
        .id_mispred_en      (id_mispred_en),
        .id_mispred_en_raw  (id_mispred_en_raw),
        .id_mispred_target  (id_mispred_target),
        .c_pc               (c_pc),
        .id_is_branch       (id_is_branch),
        .id_is_jal          (id_is_jal),
        .id_is_jalr         (id_is_jalr),
        .id_upd_is_call     (id_upd_is_call),
        .id_upd_is_ret      (id_upd_is_ret),
        .id_upd_valid       (id_upd_valid),
        .id_valid_slot      (id_valid_slot)
    );

    branch_pred bp_u (
        .clk                (clk),
        .rst_n              (cpu_rst),
        .if_pc              (pc_addr),
        .bp_taken           (bp_taken_raw),
        .bp_target          (bp_target),
        .upd_valid          (id_upd_valid),
        .upd_pc             (reg_1_pcaddr),
        .upd_is_branch      (id_is_branch),
        .upd_is_jal         (id_is_jal),
        .upd_is_jalr        (id_is_jalr),
        .upd_is_call        (id_upd_is_call),
        .upd_is_ret         (id_upd_is_ret),
        .upd_taken          (id_actual_taken),
        .upd_target         (id_actual_target),
        .upd_return_pc      (reg_1_pcaddr + 32'd4),
        .upd_was_pred_taken (reg_1_pred_taken)
    );

    // Immediate-or-operand + store-data MUX (im2op).
    wire [31:0] im2op_s_data, im2op_op2_out;
    im2op c2 (
        im2op_s_data,
        im2op_op2_out,
        rs2_fwd,
        id_im,
        id_im_c
    );

    // -------------------------------------------------------------------------
    // ID/EX boundary: reg_2
    // -------------------------------------------------------------------------
    wire         reg_2_store, reg_2_load;
    wire [31:0]  reg_2_sdata, reg_2_op2, reg_2_op1;
    wire [12:0]  reg_2_b_im;
    wire [1:0]   reg_2_b_en;
    wire [2:0]   reg_2_op;
    wire [4:0]   reg_2_rd;
    wire         reg_2_wb_en_in;
    wire [31:0]  reg_2_pcaddr;
    wire         reg_2_id_sub;
    wire [2:0]   reg_2_mem_op;
    wire [14:0]  reg_2_csr;
    wire         reg_2_mul_div, reg_2_wq, reg_2_illegal;

    // local_stop_d1: sampled-high pulse used by reg_2's bubble-injection
    // branch.  Kept as a `reg` updated in an always@(*) to match the
    // original semantics exactly.
    reg  local_stop_d1;
    always @(*) begin
        if (cpu_rst == 1'b0)
            local_stop_d1 = 1'b0;
        else
            local_stop_d1 = local_stop & (reg1_en | reg2_en | reg3_en | reg4_en) & (~div_wait);
    end

    reg_2 a2_3 (
        reg2_en,
        clk,
        rst[1] & cpu_rst,
        id_s,
        id_l,
        im2op_s_data,
        im2op_op2_out,
        rs1_fwd,
        id_b_im,
        id_b_en,
        id_alu_op,
        id_rd,
        id_wb_en,
        reg_1_pcaddr,
        id_mem_op,
        id_csr,
        id_mul_div,
        id_wq,
        id_illegal,

        reg_2_store,
        reg_2_load,
        reg_2_sdata,
        reg_2_op2,
        reg_2_op1,
        reg_2_b_im,
        reg_2_b_en,
        reg_2_op,
        reg_2_rd,
        reg_2_wb_en_in,
        reg_2_pcaddr,
        id_sub,
        reg_2_id_sub,
        reg_2_mem_op,
        reg_2_csr,
        reg_2_mul_div,
        reg_2_wq,
        reg_2_illegal,
        local_stop_d1
    );

    // -------------------------------------------------------------------------
    // EX: ALU, mul/div, and the legacy jump unit (kept for its wb-value MUX)
    // -------------------------------------------------------------------------
    wire [31:0] alu_outdata;
    alu a3 (
        .alu_out (alu_outdata),
        .opcode  (reg_2_op),
        .op1     (reg_2_op1),
        .op2     (reg_2_op2),
        .sub     (reg_2_id_sub)
    );

    wire [31:0] mul_div_output;
    wire        mul_div_ready;
    mul_div mul_div3 (
        .op1           (reg_2_op1),
        .op2           (reg_2_op2),
        .opcode        (reg_2_op),
        .en            (reg_2_mul_div),
        .mul_div_output(mul_div_output),
        .ready         (mul_div_ready),
        .clk           (clk),
        .rst_n         (cpu_rst)
    );

    assign div_wait = (~mul_div_ready) & reg_2_mul_div;

    wire [31:0] p_out;
    wire [1:0]  ju_pc_c;
    wire [12:0] ju_im;
    ju b3 (
        p_out,
        ju_pc_c,
        ju_im,
        reg_2_b_en,
        reg_2_b_im,
        reg_2_pcaddr,
        alu_outdata,
        reg_2_mem_op,
        mul_div_output,
        mul_div_ready
    );

    // -------------------------------------------------------------------------
    // EX/MEM boundary: reg_3
    // -------------------------------------------------------------------------
    wire         reg_3_store, reg_3_load;
    wire [31:0]  reg_3_sdata;
    wire [31:0]  reg_3_p_out;
    wire [4:0]   reg_3_rd;
    wire         reg_3_wb_en_in;
    wire [2:0]   reg_3_mem_op;
    wire [14:0]  reg_3_csr;
    wire [31:0]  reg_3_pcaddr;
    wire         reg_3_wq_out;
    wire         reg_3_illegal;

    reg div_wait_d1;
    always @(*) begin
        if (cpu_rst == 1'b0)
            div_wait_d1 = 1'b0;
        else
            div_wait_d1 = div_wait & (reg1_en | reg2_en | reg3_en | reg4_en);
    end

    reg_3 a3_4 (
        reg3_en,
        clk,
        rst[2] & cpu_rst,
        reg_2_store,
        reg_2_load,
        reg_2_sdata,
        p_out,
        reg_2_rd,
        reg_2_wb_en_in,
        reg_2_mem_op,
        reg_2_csr,
        reg_2_pcaddr,
        reg_2_wq,
        reg_2_illegal,

        reg_3_store,
        reg_3_load,
        reg_3_sdata,
        reg_3_p_out,
        reg_3_rd,
        reg_3_wb_en_in,
        reg_3_mem_op,
        reg_3_csr,
        reg_3_pcaddr,
        reg_3_wq_out,
        reg_3_illegal,
        div_wait_d1
    );

    // csr_pc_en comes from WB -- folds into reg_3_wq so a trap commit
    // squashes the fast-path early-WB that would otherwise run alongside
    // the trapping instruction's ordinary retirement.
    wire reg_3_wq = reg_3_wq_out & (~csr_pc_en);

    // -------------------------------------------------------------------------
    // MEM: data-bus drive + load-return MUX + fast-path mask -> reg_4
    // -------------------------------------------------------------------------
    wire [31:0] j2_p_out;
    wire [4:0]  reg_3_rd_masked;
    wire        reg_3_wb_en_masked;

    mem_ctrl b4 (
        .reg_3_store        (reg_3_store),
        .reg_3_load         (reg_3_load),
        .reg_3_sdata        (reg_3_sdata),
        .reg_3_p_out        (reg_3_p_out),
        .reg_3_rd           (reg_3_rd),
        .reg_3_wb_en_in     (reg_3_wb_en_in),
        .reg_3_mem_op       (reg_3_mem_op),
        .reg_3_wq           (reg_3_wq),
        .bus_data_in        (bus_data_in),
        .j2_p_out           (j2_p_out),
        .reg_3_rd_masked    (reg_3_rd_masked),
        .reg_3_wb_en_masked (reg_3_wb_en_masked),
        .d_bus_en           (d_bus_en),
        .data_addr_out      (data_addr_out),
        .d_data_out         (d_data_out),
        .ram_we             (ram_we),
        .ram_re             (ram_re),
        .mem_op_out         (mem_op_out)
    );

    // -------------------------------------------------------------------------
    // Access-fault handoff to WB (Tier 4.2, Tier A #3).
    //
    // d_bus_err pulses 1 the same cycle d_bus_ready pulses, so the fault
    // only belongs to whatever load / store currently sits in reg_3.  We
    // compute the load/store split and the faulting address here and hand
    // all three through reg_4 so csr_reg can raise mcause=5/7 at WB
    // (retired=0 for the faulting slot, so nothing commits to rd).
    //
    // On a faulting load we also force reg_4.rd=0 / wb_en=0: the
    // rdata latched by the bridge is garbage (DECERR path clamps m_rdata
    // to 0) and we don't want the regfile WB port to scribble it onto
    // the architectural rd the trap handler is about to inspect.  For a
    // faulting store there is no rd to worry about.  The early fast-path
    // (reg_3_wq) isn't used by loads, so it needs no extra gating here -
    // csr_pc_en's existing squash already kills the ALU wq paths.
    // -------------------------------------------------------------------------
    wire r3_load_fault  = d_bus_ready & d_bus_err & reg_3_load;
    wire r3_store_fault = d_bus_ready & d_bus_err & reg_3_store;
    wire [31:0] r3_fault_addr = reg_3_p_out;

    wire [4:0] reg_3_rd_to_r4    = r3_load_fault ? 5'd0 : reg_3_rd_masked;
    wire       reg_3_wb_en_to_r4 = reg_3_wb_en_masked & ~r3_load_fault;

    // -------------------------------------------------------------------------
    // MEM/WB boundary: reg_4
    // -------------------------------------------------------------------------
    wire [31:0] reg_4_j2_p_out;
    wire [4:0]  reg_4_rd;
    wire        reg_4_wb_en;
    wire [14:0] reg_4_csr;
    wire [31:0] reg_4_pcaddr;
    wire        reg_4_illegal;
    wire        reg_4_load_fault;
    wire        reg_4_store_fault;
    wire [31:0] reg_4_fault_addr;

    reg_4 a4_5 (
        .reg4_en        (reg4_en),
        .clk            (clk),
        .rst            (rst[3] & cpu_rst),
        .j2_p_out       (j2_p_out),
        .rd             (reg_3_rd_to_r4),
        .wb_en          (reg_3_wb_en_to_r4),
        .csr            (reg_3_csr),
        .pcaddr         (reg_3_pcaddr),
        .illegal        (reg_3_illegal),
        .load_fault     (r3_load_fault),
        .store_fault    (r3_store_fault),
        .fault_addr     (r3_fault_addr),
        .r4_j2_p_out    (reg_4_j2_p_out),
        .r4_rd          (reg_4_rd),
        .r4_wb_en       (reg_4_wb_en),
        .r4_csr         (reg_4_csr),
        .r4_pcaddr      (reg_4_pcaddr),
        .r4_illegal     (reg_4_illegal),
        .r4_load_fault  (reg_4_load_fault),
        .r4_store_fault (reg_4_store_fault),
        .r4_fault_addr  (reg_4_fault_addr)
    );

    // -------------------------------------------------------------------------
    // WB: csr_reg observes WB and arbitrates traps / mret / WFI wake
    // -------------------------------------------------------------------------
    // WB-stage observability gate for csr_reg's async-interrupt arbitration.
    // The old scheme latched a one-cycle e_inter pulse in e_inter_reg and
    // used an int_ack handshake to drain it; that was specific to the
    // legacy pulse-based SoC wiring.  With level-sensitive mtip/meip the
    // interrupt source clears itself (e.g. timer handler bumps mtime_cmp)
    // so all csr_reg really needs from here is a "is WB observable right
    // now?" strobe:
    //   * pipeline is actually advancing (pc_en), so we are not in the
    //     middle of a memory stall or load-use stall;
    //   * WB holds a real (non-zero) instruction committing this cycle;
    //   * reg_3 also holds a non-zero PC so csr_reg has a valid pc_next
    //     for mepc.  If reg_3 is a bubble (one cycle after a taken branch
    //     flushed reg_2/reg_3), we wait one more cycle until the
    //     post-redirect fetch fills reg_3.
    //
    // WFI halt is handled separately inside csr_reg: it ORs wfi_active into
    // its own int_window, and captures pc_next at WFI retire to use as mepc
    // when the wake finally fires.
    wire int_window = pc_en &
                      (reg_4_pcaddr != 32'd0) &
                      (reg_3_pcaddr != 32'd0);

    // csr_reg inputs are NOT gated combinationally by wb_fresh -- csr_data_out
    // still needs to track reg_4 across i_wait cycles so that the WB->ID
    // forwarding of CSR reads (csrr in WB, bne/addi in ID on the next slot)
    // stays correct.  Instead, we pass `retire_pulse` so that the
    // *synchronous* side effects inside csr_reg fire exactly once per WB
    // retirement:
    //   * mstatus_mret (MIE<=MPIE, MPIE<=1) is not idempotent; a stalled mret
    //     otherwise re-opens MIE after the handler masked it (mi_smoke.S
    //     test 6 on the AXI ifetch path).
    //   * mstatus_trap_entry (MPIE<=MIE, MIE<=0) likewise loses the original
    //     MIE bit on a second fire.
    //   * csr_rw `mstatus <= write_val` re-samples csr_data_out on every
    //     cycle, and csr_data_out reflects the already-updated mstatus on
    //     the next cycle, so a stalled csrrs/csrrc double-applies the
    //     set/clear mask.
    //   * minstret would otherwise double-count for any instruction held
    //     in WB longer than one cycle.
    //
    // set_pc_en / set_pc_addr stay combinational: asserting the same
    // redirect twice is a pc.v no-op because it just re-latches the same
    // target on each clock edge.
    csr_reg a5 (
        .clk          (clk),
        .rst_n        (cpu_rst),
        .csr          (reg_4_csr[14:3]),
        .csr_data     (reg_4_j2_p_out),
        .csr_op       (reg_4_csr[2:0]),

        .mtip         (mtip),
        .meip         (meip),
        .int_window   (int_window),

        .pc_addr      (reg_4_pcaddr),
        .pc_next      (reg_3_pcaddr),
        .illegal      (reg_4_illegal),
        .load_fault   (reg_4_load_fault),
        .store_fault  (reg_4_store_fault),
        .fault_addr   (reg_4_fault_addr),

        .retire_pulse (wb_fresh),

        .wb_data_out  (csr_reg_wb_data),
        .set_pc_en    (csr_pc_en),
        .set_pc_addr  (csr_pc_data),
        .data_c       (csr_data_c),
        .int_taken    (/* unused at this level; WFI halt handled inside csr_reg */),
        .wfi_halt     (wfi_halt)
    );

    // -------------------------------------------------------------------------
    // Pipeline flush controller.
    //
    // c_pc reflects mispredict-only flushes (zero when the BPU predicts
    // correctly), so a stalled branch or a matching prediction leaves
    // reg_1 intact.  The mispred signal is already pc_en-gated so
    // stall-frozen resolutions don't flush the ID slot either.
    // -------------------------------------------------------------------------
    flush_ctrl b5 (
        .c_pc                   (c_pc),
        .pending_redirect_apply (pending_redirect_apply),
        .csr_data_c             (csr_data_c),
        .rst                    (rst)
    );

endmodule
