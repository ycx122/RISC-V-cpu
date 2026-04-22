// -----------------------------------------------------------------------------
// Pipeline stall / enable controller.
//
// Formerly named `stop_control` and embedded inside cpu_jh.v.  Behaviour is
// bit-for-bit identical; only the file layout and the module name have
// changed so cpu_jh.v can read as a thin top-level.
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
//                            on the bus and cannot retire.
//
//   i_wait = i_bus_en & !i_bus_ready : instruction-bus stall.  Same fate.
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
    wire read_wait_f    = ~(d_wait | i_wait);
    wire local_stop_nor = ~local_stop;
    wire div_wait_nor   = ~div_wait;

    assign reg1_en = (cpu_rst == 1'b0) ? 1'b1 : (read_wait_f & local_stop_nor & div_wait_nor);
    assign reg2_en = (cpu_rst == 1'b0) ? 1'b1 : (read_wait_f & local_stop_nor & div_wait_nor);
    assign reg3_en = (cpu_rst == 1'b0) ? 1'b1 : (read_wait_f                  & div_wait_nor);
    assign reg4_en = (cpu_rst == 1'b0) ? 1'b1 :  read_wait_f;
    assign pc_en   = (cpu_rst == 1'b0) ? 1'b1 : (read_wait_f & local_stop_nor & div_wait_nor);

endmodule
