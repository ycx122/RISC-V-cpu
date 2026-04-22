// -----------------------------------------------------------------------------
// Operand-forwarding muxes for the ID/EX boundary.
//
// `otof1.v` decides *which* pipeline stage's output to forward into each of
// rs1/rs2 (and whether to stall on load-use / CSR-use).  This module just
// performs the two 4-to-1 selections, extracted out of cpu_jh.v so the top
// level doesn't have to spell them out inline.
//
// Encoding of fwd_sel (kept in lock-step with otof1.v):
//
//   2'b00 : regfile read port         (no hazard, or producer has wb_en=0)
//   2'b01 : EX  forward (p_out)       (ALU / mul_div / link value)
//   2'b10 : MEM forward (j2_p_out)    (ALU result, or bus_data_in on loads)
//   2'b11 : WB  forward (csr_reg_wb_data) (CSR-read data + other WB values)
//
// Priority EX > MEM > WB matches the expectation that the closest producer
// always wins.
// -----------------------------------------------------------------------------
module forward_mux (
    input  wire [1:0]  fwd_sel_1,
    input  wire [1:0]  fwd_sel_2,
    input  wire [31:0] regfile_data1,
    input  wire [31:0] regfile_data2,
    input  wire [31:0] ex_fwd,      // p_out
    input  wire [31:0] mem_fwd,     // j2_p_out
    input  wire [31:0] wb_fwd,      // csr_reg_wb_data
    output wire [31:0] rs1_fwd,
    output wire [31:0] rs2_fwd
);

    assign rs1_fwd = (fwd_sel_1 == 2'b01) ? ex_fwd  :
                     (fwd_sel_1 == 2'b10) ? mem_fwd :
                     (fwd_sel_1 == 2'b11) ? wb_fwd  :
                                            regfile_data1;

    assign rs2_fwd = (fwd_sel_2 == 2'b01) ? ex_fwd  :
                     (fwd_sel_2 == 2'b10) ? mem_fwd :
                     (fwd_sel_2 == 2'b11) ? wb_fwd  :
                                            regfile_data2;

endmodule
