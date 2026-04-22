// -----------------------------------------------------------------------------
// Pipeline flush (squash) controller.
//
// Formerly `data_f_control` inside cpu_jh.v.  Drives the active-low resets
// of the four pipeline-register modules so that the correct subset of the
// pipeline is squashed on a control-flow event.
//
// Inputs:
//   c_pc            - driven by branch_unit.  2'd0 means "no redirect",
//                     any non-zero value means "flush the IF/ID slot"
//                     (wrong-path fetch that was latched the same cycle
//                     as an ID-stage redirect).  With BPU on top, this
//                     fires only on a real misprediction; a correct
//                     prediction leaves reg_1 alone.
//
//   pending_redirect_apply - driven by cpu_jh.v.  High for exactly one
//                     cycle when the pending-redirect register (latched
//                     during an I-Cache miss drain) is being replayed
//                     into pc.  Whatever just got latched into reg_1
//                     this cycle came from the unfrozen fetch path
//                     which may be the wrong-path word (e.g. the last
//                     beat of the fill that caused the stall), so we
//                     squash reg_1 alongside the pc redirect.  reg_2..
//                     reg_4 are NOT squashed because they contain the
//                     drained in-flight instructions that have been
//                     retiring normally throughout the stall.
//
//   csr_data_c      - trap commit pulse from csr_reg.  The instruction
//                     that caused the trap lives in WB (reg_4) and must
//                     retire with the trap entry written into the M-
//                     mode CSRs; everything younger (reg_1, reg_2,
//                     reg_3) must be squashed.
//
// Output encoding:
//   rst[i] == 0 squashes pipeline register i (active-low, matches the
//               `rst` port on reg_1..reg_4 modules).
//
//   rst[0] : IF/ID (reg_1)
//   rst[1] : ID/EX (reg_2)
//   rst[2] : EX/MEM (reg_3)
//   rst[3] : MEM/WB (reg_4) -- never flushed, WB must retire.
// -----------------------------------------------------------------------------
module flush_ctrl (
    input  wire [1:0] c_pc,
    input  wire       pending_redirect_apply,
    input  wire       csr_data_c,
    output wire [3:0] rst
);

    assign rst[0] = ((c_pc != 2'b00) || csr_data_c || pending_redirect_apply)
                  ? 1'b0 : 1'b1;
    assign rst[1] = (csr_data_c == 1'b1)            ? 1'b0 : 1'b1;
    assign rst[2] = (csr_data_c == 1'b1)            ? 1'b0 : 1'b1;
    assign rst[3] = 1'b1;

endmodule
