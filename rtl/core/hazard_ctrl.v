// -----------------------------------------------------------------------------
// Pipeline stall / enable controller.
//
// Formerly named `stop_control` and embedded inside cpu_jh.v.  The module
// name and layout were pulled out so cpu_jh.v could read as a thin
// top-level; the behaviour was then upgraded in Tier-4.2.2 so the I-Cache
// miss window no longer stalls already-fetched work sitting in EX/MEM/WB.
//
// Stall sources in priority order (any one forces the relevant stage to
// freeze by dropping its enable low):
//
//   cpu_rst (active-low)   : reset window - all enables forced high so the
//                            internal pipeline registers can re-sample their
//                            async clears cleanly.  This matches the prior
//                            behaviour where stop_control pulled everything
//                            high while rst was asserted.
//
//   d_wait = d_bus_en & !d_bus_ready : data-bus stall on a load/store whose
//                            addressed slave hasn't come back yet.  Freezes
//                            EVERY stage because the WB producer is parked
//                            on the bus and cannot retire.  This has not
//                            changed from the pre-I-Cache behaviour.
//
//   i_wait = i_bus_en & !i_bus_ready : instruction-bus stall.  Only freezes
//                            the PC: cpu_jh.v injects a NOP bubble into
//                            reg_1 whenever i_bus_ready is low (see the
//                            stop_cache_reg1 mux in that file), so reg_2..
//                            reg_4 can drain the already-fetched in-flight
//                            instructions during an I-Cache line fill.
//                            Without this, a miss on the line containing a
//                            test's pass / fail epilogue could stall for
//                            more wall-clock time than the testbench's
//                            `#100 wait` after x26 hits 1, leaving x27 at
//                            zero when cpu_test samples it.  id_mispred_en
//                            is still gated by pc_en, so any mispredict
//                            that fires while pc is frozen is captured by
//                            the pending_redirect register in cpu_jh.v and
//                            replayed when pc_en rises.
//
//   local_stop              : injected by the caller.  Folds in load-use and
//                            CSR-use hazards (otof1), fence drain, and the
//                            WFI halt gate.  Stops IF/ID and EX-input (reg1,
//                            reg2, pc) but lets reg_3 and reg_4 keep draining
//                            so the hazard-producing instruction can retire.
//
//   div_wait                : iterative divider busy.  Holds reg_1/reg_2 and
//                            reg_3 (the ALU result isn't ready yet) but
//                            still retires anything already in WB.
//
// reg_X_en == 0 causes the associated pipeline register to re-latch its
// current value on the next clock edge (behavioural bubble / hold).
// pc_en == 0 holds the program counter.
// -----------------------------------------------------------------------------
module hazard_ctrl (
    input  wire d_bus_en,
    input  wire d_bus_ready,
    input  wire i_bus_en,
    input  wire i_bus_ready,
    input  wire cpu_rst,
    input  wire local_stop,
    input  wire div_wait,
    output wire reg1_en,
    output wire reg2_en,
    output wire reg3_en,
    output wire reg4_en,
    output wire pc_en
);

    wire d_wait         = d_bus_en & (~d_bus_ready);
    wire i_wait         = i_bus_en & (~i_bus_ready);
    // Drain gate: d_wait still freezes every stage (MEM producer parked on
    // the bus).  i_wait no longer stops reg_1..reg_4 - instead cpu_jh.v
    // hands reg_1 a NOP bubble while fetch is pending, so the EX/MEM/WB
    // instructions already in flight can still retire during an I-Cache
    // miss window.
    wire drain_wait_f   = ~d_wait;
    // PC gate: both d_wait and i_wait have to hold the PC (no fresh fetch
    // can be launched while the current one is still in flight).
    wire fetch_wait_f   = ~(d_wait | i_wait);
    wire local_stop_nor = ~local_stop;
    wire div_wait_nor   = ~div_wait;

    assign reg1_en = (cpu_rst == 1'b0) ? 1'b1 : (drain_wait_f & local_stop_nor & div_wait_nor);
    assign reg2_en = (cpu_rst == 1'b0) ? 1'b1 : (drain_wait_f & local_stop_nor & div_wait_nor);
    assign reg3_en = (cpu_rst == 1'b0) ? 1'b1 : (drain_wait_f                  & div_wait_nor);
    assign reg4_en = (cpu_rst == 1'b0) ? 1'b1 :  drain_wait_f;
    assign pc_en   = (cpu_rst == 1'b0) ? 1'b1 : (fetch_wait_f & local_stop_nor & div_wait_nor);

endmodule
