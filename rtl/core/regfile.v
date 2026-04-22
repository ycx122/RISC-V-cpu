// 32x32 RISC-V integer register file.
//
// Rewritten to use an array-indexed read/write pattern instead of the
// original 32-case combinational MUX.  Behavioural consequences:
//
//   * x0 is hard-wired to zero on both read ports, regardless of any
//     write that targets write_addr==0 or w_addr_2==0.  The original
//     file also achieved this (read index 0 returned `reg_0`, which
//     was never written) but only as a side-effect of the case
//     statement layout; the new form states it explicitly.
//
//   * Two simultaneous writes that target the same rd (port 1 = WB
//     path via csr_reg, port 2 = early write-back from EX via the
//     reg_3 fast-path) collide when a pair of back-to-back instructions
//     writes the same rd: cycle K has the older producer's WB AND the
//     younger producer's fast-path both targeting that rd.  The fast
//     path carries the newer value, so it must win.  We enforce that
//     explicitly by ordering the two non-blocking assignments (write_ce
//     first, w_en_2 second) instead of relying on a one-case MUX so the
//     priority is obvious when reading the source.
//
//   * Read-during-write semantics are "read old value" (classic write
//     port → regs array → combinational read), unchanged from before.
//     That matches the forwarding assumptions baked into otof1.v:
//     the WB stage's value is forwarded explicitly through the MUX in
//     cpu_jh.v rather than via a read-new-write bypass here.
// Port order kept bit-compatible with the old 32-case implementation
// so cpu_jh.v's positional instantiation continues to work unchanged.
module regfile (
    output [31:0] data1,
    output [31:0] data2,
    input         clk,

    // Architectural write-back (csr_reg → regfile_data1 destination).
    input  [31:0] write_data,
    input  [4:0]  write_addr,

    // Read ports.
    input  [4:0]  read_1_addr,
    input  [4:0]  read_2_addr,

    input         write_ce,

    // Early write-back from EX (reg_3 fast-path: `w_en_2 & reg_3_wq`).
    input         w_en_2,
    input  [4:0]  w_addr_2,
    input  [31:0] w_data_2
);

reg [31:0] regs [1:31];
integer init_i;

initial begin
    for (init_i = 1; init_i < 32; init_i = init_i + 1)
        regs[init_i] = 32'h0;
end

always @(posedge clk) begin
    // WB first; fast-path second so it wins a same-rd collision.
    if (write_ce && (write_addr != 5'd0))
        regs[write_addr] <= write_data;
    if (w_en_2 && (w_addr_2 != 5'd0))
        regs[w_addr_2] <= w_data_2;
end

// x0 stays zero; x1..x31 come from the array.
assign data1 = (read_1_addr == 5'd0) ? 32'h0 : regs[read_1_addr];
assign data2 = (read_2_addr == 5'd0) ? 32'h0 : regs[read_2_addr];

endmodule
