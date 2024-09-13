module cnn_wrapper(
    input clk,
    input rst_n,
    // Bus signals
    input [6:0] addr,       // 5-bit address for accessing 32 registers plus control/status
    input [31:0] data_in,   // Data bus for writing into registers
    output reg [31:0] data_out, // Data bus for reading from registers
    input wr_en,            // Write enable signal
    input rd_en,            // Read enable signal
    output ready
);

assign ready=wr_en|rd_en;
// Internal signals
reg [31:0] a_buffer[0:15]; // Registers to store 'a' inputs
reg [31:0] b_buffer[0:15]; // Registers to store 'b' inputs
reg computation_start;      // Register to initiate computation
wire [31:0] re;             // Register to store 're' output
wire re_vaild;              // Register to store 're_vaild' output
wire a_ready;
wire b_ready;

// Instantiate the cnn_16x16 module
cnn_16x16 cnn_inst (
    .clk(clk),
    .rst_n(rst_n),
    .a_vaild(computation_start),
    .a_ready(a_ready),
    // Connect the a_buffer inputs
    .in_a0 (a_buffer[0]),
    .in_a1 (a_buffer[1]),
    .in_a2 (a_buffer[2]),
    .in_a3 (a_buffer[3]),
    .in_a4 (a_buffer[4]),
    .in_a5 (a_buffer[5]),
    .in_a6 (a_buffer[6]),
    .in_a7 (a_buffer[7]),
    .in_a8 (a_buffer[8]),
    .in_a9 (a_buffer[9]),
    .in_a10(a_buffer[10]),
    .in_a11(a_buffer[11]),
    .in_a12(a_buffer[12]),
    .in_a13(a_buffer[13]),
    .in_a14(a_buffer[14]),
    .in_a15(a_buffer[15]),
    // Connect the b_buffer inputs
    .b_vaild(computation_start),
    .b_ready(b_ready),
    .in_b0 (b_buffer[0]),
    .in_b1 (b_buffer[1]),
    .in_b2 (b_buffer[2]),
    .in_b3 (b_buffer[3]),
    .in_b4 (b_buffer[4]),
    .in_b5 (b_buffer[5]),
    .in_b6 (b_buffer[6]),
    .in_b7 (b_buffer[7]),
    .in_b8 (b_buffer[8]),
    .in_b9 (b_buffer[9]),
    .in_b10(b_buffer[10]),
    .in_b11(b_buffer[11]),
    .in_b12(b_buffer[12]),
    .in_b13(b_buffer[13]),
    .in_b14(b_buffer[14]),
    .in_b15(b_buffer[15]),
    .re(re), 
    .re_vaild(re_vaild),
    .re_ready(1'b1) // Assume always ready to accept result for simplification
);
reg [4:0] i;
// Write logic with reset
always @(posedge clk) begin
    if (!rst_n) begin
        // Reset logic, clear buffers and control registers
        computation_start <= 1'b0;
        for (i = 0; i < 16; i = i + 1) begin
            a_buffer[i] <= 32'b0;
        end
        for (i = 0; i < 16; i = i + 1) begin
            b_buffer[i] <= 32'b0;
        end
    end else if (wr_en) begin
        case (addr)
            // Address mapping for 'a' buffer
            6'd0 : a_buffer[0] <= data_in;
            6'd1 : a_buffer[1] <= data_in;
            6'd2 : a_buffer[2] <= data_in;
            6'd3 : a_buffer[3] <= data_in;
            6'd4 : a_buffer[4] <= data_in;
            6'd5 : a_buffer[5] <= data_in;
            6'd6 : a_buffer[6] <= data_in;
            6'd7 : a_buffer[7] <= data_in;
            6'd8 : a_buffer[8] <= data_in;
            6'd9 : a_buffer[9] <= data_in;
            6'd10: a_buffer[10] <= data_in;
            6'd11: a_buffer[11] <= data_in;
            6'd12: a_buffer[12] <= data_in;
            6'd13: a_buffer[13] <= data_in;
            6'd14: a_buffer[14] <= data_in;
            6'd15: a_buffer[15] <= data_in;

            // Address mapping for 'b' buffer
            6'd16: b_buffer[0] <= data_in;
            6'd17: b_buffer[1] <= data_in;
            6'd18: b_buffer[2] <= data_in;
            6'd19: b_buffer[3] <= data_in;
            6'd20: b_buffer[4] <= data_in;
            6'd21: b_buffer[5] <= data_in;
            6'd22: b_buffer[6] <= data_in;
            6'd23: b_buffer[7] <= data_in;
            6'd24: b_buffer[8] <= data_in;
            6'd25: b_buffer[9] <= data_in;
            6'd26: b_buffer[10] <= data_in;
            6'd27: b_buffer[11] <= data_in;
            6'd28: b_buffer[12] <= data_in;
            6'd29: b_buffer[13] <= data_in;
            6'd30: b_buffer[14] <= data_in;
            6'd31: b_buffer[15] <= data_in;

            // Start computation
            6'd32: begin
                computation_start <= data_in[29]; // assuming bit 0 is start signal
            end
            default: ; // No operation for other addresses
        endcase
    end
    else if(computation_start==1)
        computation_start=0;
end

reg [31:0]re_r;
reg re_vaild_r;

// Read logic
always @(*) begin
    if (rd_en) begin
        data_out=(addr==34)?re_vaild_r:re_r;
    end else begin
        data_out = 32'b0; // Default value when not enabled
    end
end

always@(posedge clk )
if(rst_n==0)begin
    re_r<=0;
    re_vaild_r<=0;
    end
else if(rd_en==1 & addr==33)begin
    re_r<=0;
    re_vaild_r<=0;
    end
else if(re_vaild==1)begin
    re_r<=re;
    re_vaild_r<=1;
    end

endmodule
