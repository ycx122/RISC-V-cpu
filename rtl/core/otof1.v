// Hazard / forwarding unit.
//
// Earlier this module only produced `local_stop`, and `cpu_jh.v` stalled
// the whole pipeline on *any* RAW hazard between the instruction in ID
// and the three following pipeline stages.  That dropped IPC hard on
// ordinary ALU-chain code.
//
// Now:
//   - fwd_sel_1 / fwd_sel_2 pick the newest value of each source operand
//     from one of: regfile, EX (reg_2 output, i.e. p_out), MEM (reg_3
//     output, i.e. j2_p_out) or WB (reg_4 output feeding csr_reg_wb_data).
//     Priority is EX > MEM > WB so the closest producer wins.
//   - local_stop now only asserts on a true load-use hazard: the
//     instruction currently in EX is a load (reg_2_load == 1) whose rd
//     matches one of the sources decoded this cycle in ID.  Everything
//     else is covered by forwarding, so the stall collapses to at most
//     one bubble and only when there is a genuine load-use chain.
//
// Encoding of fwd_sel_{1,2}:
//   2'b00  regfile_dataN   (no hazard, or producer has wb_en=0)
//   2'b01  EX  forward     (p_out from ju.v, includes ALU/mul_div/link)
//   2'b10  MEM forward     (j2_p_out: ALU result or bus_data_in on load)
//   2'b11  WB  forward     (csr_reg_wb_data: includes CSR read data)
module otof1(
    input  [4:0] rs1,
    input  [4:0] rs2,

    // EX stage (reg_2 outputs)
    input  [4:0] rd_ex,
    input        wb_en_ex,
    input        load_ex,
    input        csr_ex,      // EX stage is a CSR read/write

    // MEM stage (reg_3 outputs)
    input  [4:0] rd_mem,
    input        wb_en_mem,
    input        csr_mem,     // MEM stage is a CSR read/write

    // WB stage (reg_4 outputs)
    input  [4:0] rd_wb,
    input        wb_en_wb,

    output [1:0] fwd_sel_1,
    output [1:0] fwd_sel_2,
    output       local_stop
);

    wire rs1_nz = (rs1 != 5'd0);
    wire rs2_nz = (rs2 != 5'd0);

    wire hit_ex_1  = rs1_nz & wb_en_ex  & (rs1 == rd_ex);
    wire hit_ex_2  = rs2_nz & wb_en_ex  & (rs2 == rd_ex);
    wire hit_mem_1 = rs1_nz & wb_en_mem & (rs1 == rd_mem);
    wire hit_mem_2 = rs2_nz & wb_en_mem & (rs2 == rd_mem);
    wire hit_wb_1  = rs1_nz & wb_en_wb  & (rs1 == rd_wb);
    wire hit_wb_2  = rs2_nz & wb_en_wb  & (rs2 == rd_wb);

    assign fwd_sel_1 = hit_ex_1  ? 2'b01 :
                       hit_mem_1 ? 2'b10 :
                       hit_wb_1  ? 2'b11 : 2'b00;

    assign fwd_sel_2 = hit_ex_2  ? 2'b01 :
                       hit_mem_2 ? 2'b10 :
                       hit_wb_2  ? 2'b11 : 2'b00;

    // Stalls we still owe even with forwarding in place:
    //
    //   * load-use   : load result isn't valid until end of MEM.
    //
    //   * CSR-use    : in this pipeline the CSR read data is only folded
    //                  into the write-back value at WB (csr_reg_wb_data);
    //                  EX p_out and MEM j2_p_out both carry the raw rs1
    //                  that flowed through the ALU, which is *not* what
    //                  the CSR instruction is supposed to write back.
    //                  So forwarding from EX/MEM of a CSR producer is
    //                  wrong; stall until it reaches WB (where the WB
    //                  path selects csr_reg_wb_data correctly).
    //
    // Either one drains the bubble via the existing stop_control logic:
    // reg1/reg2_en go low, reg_2 injects zeros, the producer keeps
    // advancing.
    assign local_stop = (load_ex & (hit_ex_1  | hit_ex_2 )) |
                        (csr_ex  & (hit_ex_1  | hit_ex_2 )) |
                        (csr_mem & (hit_mem_1 | hit_mem_2));

endmodule
