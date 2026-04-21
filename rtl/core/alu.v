// Combinational ALU.
//
// Unused original outputs `z` (zero flag) and `c` (carry-out of ADD/SUB)
// were removed because no caller consumed them. The single instance in
// cpu_jh.v left both ports dangling, and the `{c, alu_out} = ...` trick
// in the ADD branch created a non-obvious inferred-latch for `c` on
// every other opcode. Dropping the outputs also drops the latch.
module alu (
    output reg [31:0] alu_out,
    input      [2:0]  opcode,
    input      [31:0] op1,
    input      [31:0] op2,
    input             sub
);
    wire [31:0] slt_result, sltu_result, srl_result;

    localparam [2:0] ADD  = 3'b000,
                     SLL  = 3'b001,
                     SLT  = 3'b010,
                     SLTU = 3'b011,
                     XOR  = 3'b100,
                     SRL  = 3'b101,
                     OR   = 3'b110,
                     AND  = 3'b111;

    always @(*) begin
        case (opcode)
            ADD:  alu_out = (sub == 1'b0) ? op1 + op2 : op1 - op2;
            OR:   alu_out = op1 | op2;
            XOR:  alu_out = op1 ^ op2;
            AND:  alu_out = op1 & op2;
            SLL:  alu_out = op1 << op2[4:0];
            SRL:  alu_out = srl_result;
            SLT:  alu_out = slt_result;
            SLTU: alu_out = sltu_result;
            default: alu_out = {32{1'bx}};
        endcase
    end

    // SRL / SRA: `sub` distinguishes arithmetic (1) from logical (0)
    // shift. For arithmetic shift the sign bit is smeared in from the
    // left when op1 is negative.
    assign srl_result = (sub == 1'b0) ? op1 >> op2[4:0]
                      : (op1[31] == 1'b1)
                            ? ({32'hffff_ffff, 32'h0} >> op2[4:0]) | (op1 >> op2[4:0])
                            : op1 >> op2[4:0];

    // SLT: signed less-than.
    assign slt_result = (op2[31] == 1'b0 && op1[31] == 1'b1) ? 32'b1 :
                        (op2[31] == 1'b1 && op1[31] == 1'b0) ? 32'b0 :
                        (op1[31] == 1'b0 && op2[31] == 1'b0) ? (op2 > op1) ? 32'b1 : 32'b0 :
                        (op1[31] == 1'b1 && op2[31] == 1'b1) ? (op1[30:0] < op2[30:0]) ? 32'b1 : 32'b0 : 32'b0;

    // SLTU: unsigned less-than.
    assign sltu_result = (op2 > op1) ? 32'b1 : 32'b0;

endmodule
