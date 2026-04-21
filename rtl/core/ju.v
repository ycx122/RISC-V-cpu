// Jump / branch unit.
//
// Consumes the ALU result together with `ju_c` (what kind of ju op) and
// `mem_op` (which exact branch, reusing the mem_op field from decode)
// and drives three things:
//   ju_out   : the value written back to the destination register
//              (ALU or mul_div result for normal ops, pc_addr for JAL/JALR)
//   pc_c     : PC update selector into pc.v. 0 = pc+4, 2 = branch taken
//   b_im_out : branch offset when pc_c == 2
//
// The mem_op encoding for branch ops comes straight from id.v / RISC-V
// funct3. Here it only has to tell the six branch flavors apart:
//   0 : beq       (alu_out ==  0)
//   1 : bne       (alu_out !=  0)
//   4 : blt       (alu_out[0] == 1)  -- ALU did signed less-than
//   5 : bge       (alu_out[0] == 0)
//   6 : bltu      (alu_out[0] == 1)  -- ALU did unsigned less-than
//   7 : bgeu      (alu_out[0] == 0)
// Any other mem_op value while ju_c == 1 is illegal and yields X on all
// outputs, which in turn lets simulation catch a mis-decoded branch.
module ju (
output reg [31:0] ju_out,
output reg [1:0]  pc_c = 0,
output reg [12:0] b_im_out,
input      [1:0]  ju_c,
input      [12:0] im_in,
input      [31:0] pc_addr,
input      [31:0] alu_out,
input      [2:0]  mem_op,

input      [31:0] mul_div_out,
input             mul_div_ready
);

reg branch_taken;
reg branch_valid;

always @(*) begin
    branch_taken = 1'bx;
    branch_valid = 1'b1;

    case (mem_op)
        3'd0:        branch_taken =  (alu_out == 0);    // beq
        3'd1:        branch_taken =  (alu_out != 0);    // bne
        3'd4, 3'd6:  branch_taken =  alu_out[0];        // blt / bltu
        3'd5, 3'd7:  branch_taken = ~alu_out[0];        // bge / bgeu
        default:     branch_valid = 1'b0;
    endcase
end

always @(*) begin
    if (ju_c == 2'd0) begin
        // Normal ALU / mul_div result flowing to write-back.
        ju_out   = (mul_div_ready == 1'b1) ? mul_div_out : alu_out;
        pc_c     = 2'd0;
        b_im_out = 13'd0;
    end
    else if (ju_c == 2'd1) begin
        // Conditional branch.
        if (branch_valid == 1'b1) begin
            ju_out   = 32'd0;
            pc_c     = branch_taken ? 2'd2 : 2'd0;
            b_im_out = branch_taken ? im_in : 13'd0;
        end
        else begin
            ju_out   = {32{1'bx}};
            pc_c     = 2'bxx;
            b_im_out = {13{1'bx}};
        end
    end
    else if (ju_c == 2'd2) begin
        // JAL / JALR link-register value (return address).
        // `pc_addr` here is reg_2_pcaddr, i.e. the PC of the jump
        // itself, so the RISC-V spec "rd <- PC_of_jump + 4" becomes
        // `pc_addr + 4`.  The PC redirect itself is handled in pc.v
        // by id_pc_c, so this module only provides the write-back
        // value.  The +4 is paired with id.v auipc (addr + imm, no
        // -4) and pc.v JALR target (rs1 + imm - 4 for the fetch
        // bubble); all three changed in lockstep.
        ju_out   = pc_addr + 32'd4;
        pc_c     = 2'd0;
        b_im_out = 13'd0;
    end
    else begin
        // ju_c == 3 is not used by decode today; leave it as X so a
        // regression flips it into a simulation-visible state.
        ju_out   = {32{1'bx}};
        pc_c     = 2'd0;
        b_im_out = {13{1'bx}};
    end
end

endmodule
