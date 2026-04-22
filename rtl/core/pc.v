// Program counter.
//
// Four writable paths, listed in priority order:
//
//   * trap_set_en / trap_set_addr : highest priority.  Used by csr_reg
//     on traps (ecall, ebreak, mret, machine-timer interrupt).  Bypasses
//     pc_en so a stalled fetch can still redirect to the trap vector.
//
//   * id_mispred_en / id_mispred_target : ID-stage branch-predictor
//     misprediction recovery.  Fired when the architecturally-correct
//     next PC (computed with forwarded rs1/rs2 at ID) differs from the
//     predicted next PC carried in reg_1.  Target is already the true
//     RISC-V spec address; no off-by-4 fudge.  Gated by pc_en so we
//     don't commit a redirect while IF/ID is frozen (load-use, CSR-use,
//     or bus wait) because the forwarded operands driving the branch
//     comparator aren't valid yet.
//
//   * bp_pred_taken / bp_pred_target : IF-stage branch-predictor
//     speculative redirect.  When the BPU predicts taken (BTB hit on a
//     jump, or BTB hit + 2-bit BHT >= 10 on a conditional), the next
//     fetch goes to the predicted target; otherwise we fall through to
//     pc+4.  If the prediction was wrong, the ID-stage mispredict path
//     takes priority next cycle and squashes the wrong-path fetch via
//     data_f_control.
//
//   * default + 4 : normal sequential fetch.
//
// When pc_en is low and nothing else fires, PC holds.
module pc(
    output reg [31:0] pc_addr = 32'd0,
    input             clk,
    input             rst,                // active-low reset
    input             pc_en,              // fetch advance enable
    input             trap_set_en,
    input      [31:0] trap_set_addr,
    input             id_mispred_en,
    input      [31:0] id_mispred_target,
    input             bp_pred_taken,
    input      [31:0] bp_pred_target
);

always @(posedge clk) begin
    if (rst == 1'b0)
        pc_addr <= 32'd0;
    else if (trap_set_en)
        pc_addr <= trap_set_addr;
    else if (pc_en) begin
        if (id_mispred_en)
            pc_addr <= id_mispred_target;
        else if (bp_pred_taken)
            pc_addr <= bp_pred_target;
        else
            pc_addr <= pc_addr + 32'd4;
    end
    // else: hold
end

endmodule
