// -----------------------------------------------------------------------------
// ID-stage branch / JAL / JALR resolution unit.
//
// History (see the comment that used to live inline in cpu_jh.v):
//   * jumps used to resolve in EX (ju.v), costing ~3 bubbles per taken
//     branch;
//   * we pulled resolution forward to ID for a 1-cycle taken penalty;
//   * the IF-stage BPU then started speculatively redirecting, so a
//     correct prediction pays zero bubbles and a mispredict falls back to
//     the same 1-cycle flush-reg_1 path.
//
// This module concentrates all of the comb logic that:
//   (a) computes the architecturally-correct branch-taken flag and target
//       for the instruction sitting in ID;
//   (b) compares that against the IF-stage prediction latched in reg_1;
//   (c) emits the mispredict redirect signal into pc.v;
//   (d) emits the flush selector (c_pc) into flush_ctrl; and
//   (e) derives the RAS-hint bits (call/ret) and the valid-update strobe
//       for branch_pred.v's training port.
//
// The rules for what counts as a "valid" ID slot are shared with the
// int_window logic in cpu_jh.v: pc_en must be high (pipeline advancing),
// reg_1_pcaddr must be non-zero (reg_1 is not a bubble / reset state), and
// csr_data_c must be low (csr_reg is not already committing a trap flush
// this cycle, since that would otherwise produce two competing redirects).
//
// id.v encoding recap:
//   id_b_en == 2'd1 : conditional branch
//   id_b_en == 2'd2 : jal or jalr; id_pc_im_f == 1 picks jalr.
//
// id.v packs immediates as:
//   id_pc_im = {inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}  (JAL,  21-bit)
//   id_pc_im = {20'bx,    inst[31:20]}                              (JALR, 12-bit in low bits)
//   id_b_im  = {inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}   (branch, 13-bit)
//
// The original behavioural `reg id_branch_take` + combinational case are
// preserved verbatim so simulation matches cycle-for-cycle.
// -----------------------------------------------------------------------------
module branch_unit (
    // ID-stage decode signals.
    input  wire [1:0]  id_b_en,
    input  wire        id_pc_im_f,        // 1 -> JALR, 0 -> JAL (for id_b_en==2)
    input  wire [2:0]  id_mem_op,         // branch funct3 (beq/bne/blt/bge/bltu/bgeu)
    input  wire [20:0] id_pc_im,          // JAL 21-bit / JALR 12-bit-in-low
    input  wire [12:0] id_b_im,           // conditional-branch 13-bit
    input  wire [4:0]  id_rs1,
    input  wire [4:0]  id_rd,

    // Pipeline register state.
    input  wire [31:0] reg_1_pcaddr,      // PC of the instruction currently in ID
    input  wire        reg_1_pred_taken,  // IF-stage BPU prediction that was latched
    input  wire [31:0] reg_1_pred_target, // BPU-predicted target for that PC

    // Forwarded rs1/rs2 values (already merged with regfile / EX / MEM / WB).
    input  wire [31:0] rs1_fwd,
    input  wire [31:0] rs2_fwd,

    // Pipeline gating flags.
    input  wire        pc_en,             // pipeline is advancing this cycle
    input  wire        csr_data_c,        // csr_reg is committing a trap flush

    // Comparator + redirect outputs back to pc.v / flush_ctrl.
    output wire        id_actual_taken,
    output wire [31:0] id_actual_target,
    output wire [31:0] id_actual_next_pc,
    output wire        id_mispred_en,
    output wire [31:0] id_mispred_target,
    output wire [1:0]  c_pc,

    // Classification / training outputs for branch_pred.v.
    output wire        id_is_branch,
    output wire        id_is_jal,
    output wire        id_is_jalr,
    output wire        id_upd_is_call,
    output wire        id_upd_is_ret,
    output wire        id_upd_valid,
    output wire        id_valid_slot
);

    // ---- Branch condition evaluation ---------------------------------------
    wire beq_eq  = (rs1_fwd == rs2_fwd);
    wire blt_lt  = ($signed(rs1_fwd) < $signed(rs2_fwd));
    wire bltu_lt = (rs1_fwd < rs2_fwd);

    reg id_branch_take;
    always @(*) begin
        case (id_mem_op)                 // branch funct3 (see id.v)
            3'd0:    id_branch_take =  beq_eq;     // beq
            3'd1:    id_branch_take = !beq_eq;     // bne
            3'd4:    id_branch_take =  blt_lt;     // blt
            3'd5:    id_branch_take = !blt_lt;     // bge
            3'd6:    id_branch_take =  bltu_lt;    // bltu
            3'd7:    id_branch_take = !bltu_lt;    // bgeu
            default: id_branch_take =  1'b0;
        endcase
    end

    // ---- Instruction-class decode ------------------------------------------
    assign id_is_branch = (id_b_en == 2'd1);
    assign id_is_jalr   = (id_b_en == 2'd2) &  id_pc_im_f;
    assign id_is_jal    = (id_b_en == 2'd2) & ~id_pc_im_f;

    // ---- Sign-extended immediates ------------------------------------------
    wire [31:0] jal_offset  = {{11{id_pc_im[20]}}, id_pc_im};
    wire [31:0] jalr_offset = {{20{id_pc_im[11]}}, id_pc_im[11:0]};
    wire [31:0] br_offset   = {{19{id_b_im[12]}},  id_b_im};

    // ---- Architecturally-correct next-PC -----------------------------------
    assign id_actual_taken  = (id_is_branch & id_branch_take) | id_is_jal | id_is_jalr;
    assign id_actual_target = id_is_jalr ? (rs1_fwd      + jalr_offset)
                            : id_is_jal  ? (reg_1_pcaddr + jal_offset)
                                         : (reg_1_pcaddr + br_offset);
    assign id_actual_next_pc = id_actual_taken ? id_actual_target
                                               : (reg_1_pcaddr + 32'd4);

    // Predicted next PC carried through reg_1.
    wire [31:0] reg_1_pred_next_pc = reg_1_pred_taken ? reg_1_pred_target
                                                      : (reg_1_pcaddr + 32'd4);

    // reg_1_pcaddr != 0 is the "is this ID slot real?" heuristic shared with
    // int_window: flushed / reset reg_1 reads as pcaddr==0 and is treated as
    // a bubble so we never train the predictor or emit a spurious redirect.
    assign id_valid_slot = (reg_1_pcaddr != 32'd0);

    // Misprediction: fetched path disagrees with ID resolution.  Gated by
    // pc_en so a stalled branch with stale forwarded operands doesn't look
    // like a control-flow event, and by csr_data_c so a trap commit's bigger
    // flush always wins.
    assign id_mispred_en     = pc_en & id_valid_slot & ~csr_data_c
                             & (id_actual_next_pc != reg_1_pred_next_pc);
    assign id_mispred_target = id_actual_next_pc;

    // Flush selector kept in the legacy 2'd0 / 2'd1 encoding that flush_ctrl
    // understands.  c_pc != 0 -> flush reg_1.
    assign c_pc = id_mispred_en ? 2'd1 : 2'd0;

    // ---- BPU training hints -------------------------------------------------
    wire id_rd_is_link  = (id_rd  == 5'd1) | (id_rd  == 5'd5);
    wire id_rs1_is_link = (id_rs1 == 5'd1) | (id_rs1 == 5'd5);

    assign id_upd_is_call = (id_is_jal | id_is_jalr) & id_rd_is_link;
    assign id_upd_is_ret  = id_is_jalr & id_rs1_is_link & ~id_rd_is_link;

    // Commit an update for every real instruction leaving ID.  The predictor
    // decides internally whether the instruction is a branch/jump (train) or
    // whether a stale BTB alias needs to be cleared on a non-branch.
    assign id_upd_valid = pc_en & id_valid_slot & ~csr_data_c;

endmodule
