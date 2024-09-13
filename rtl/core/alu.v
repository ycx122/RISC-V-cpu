module alu (
    output reg [31:0] alu_out,
    output z,
    output reg c,
    input [2:0] opcode,
    input [31:0] op1,
    input [31:0] op2,
    input sub
);
    wire [31:0] slt_result, sltu_result, srl_result;
    wire [31:0] shifted_op1;

    // Assign zero flag
    assign z = ~|alu_out;

    // Parameters for opcode
    parameter ADD = 3'b000,
               SLL = 3'b001,
               SLT = 3'b010,
               SLTU = 3'b011,
               XOR = 3'b100,
               SRL = 3'b101,
               OR = 3'b110,
               AND = 3'b111;

    // Main ALU operation selection
    always @(*) begin
        case (opcode)
            ADD: {c, alu_out} = (sub == 0) ? op1 + op2 : op1 - op2;
            OR: alu_out = op1 | op2;
            XOR: alu_out = op1 ^ op2;
            AND: alu_out = op1 & op2;
            SLL: alu_out = op1 << op2[4:0];
            SRL: alu_out = srl_result;
            SLT: alu_out = slt_result;
            SLTU: alu_out = sltu_result;
            default: alu_out = {32{1'bx}};
        endcase
    end

    // Calculate SRL result
    assign srl_result = (sub == 0) ? op1 >> op2[4:0] : (op1[31] == 1'b1) ? ({32'hffff_ffff,32'h0}>>op2[4:0]) | (op1 >> op2[4:0]) : op1 >> op2[4:0];

    // Calculate SLT and SLTU results
    assign slt_result = (op2[31] == 1'b0 && op1[31] == 1'b1) ? 32'b1 :
                        (op2[31] == 1'b1 && op1[31] == 1'b0) ? 32'b0 :
                        (op1[31] == 1'b0 && op2[31] == 1'b0) ? (op2 > op1) ? 32'b1 : 32'b0 :
                        (op1[31] == 1'b1 && op2[31] == 1'b1) ? (op1[30:0] < op2[30:0]) ? 32'b1 : 32'b0 : 32'b0;

    assign sltu_result = (op2 > op1) ? 32'b1 : 32'b0;

endmodule
