// -----------------------------------------------------------------------------
// Pipeline-boundary registers for the 5-stage integer pipe.
//
// These four modules were inlined at the bottom of cpu_jh.v for the longest
// time; they are pulled out here so cpu_jh.v can focus on top-level wiring
// and each stage boundary can be read in isolation.  Behaviour is identical
// to the pre-refactor version (same reset, same enable, same bubble
// injection on stall, same divider-stall clear in reg_3, same reg_2 mirror
// register pattern).
//
//   reg_1  (IF/ID)  : holds the fetched instruction word + its PC + the
//                     IF-stage BPU prediction metadata so cpu_jh.v can
//                     compare against ID-resolved branches next cycle.
//
//   reg_2  (ID/EX)  : holds decoded control signals, rs1/op2 + store data
//                     for the EX and MEM stages.  Implemented with an
//                     intermediate register pair (`_r` shadow + combinational
//                     output) so a `local_stop` injects a zero bubble on the
//                     enable-gated path without disturbing the cycle-0 reset
//                     behaviour used by stop_control.
//
//   reg_3  (EX/MEM) : holds the EX-stage outputs for the memory-access /
//                     WB dispatch stage.  Has a second clear path triggered
//                     by `div_wait_d1` so a stalled iterative-divider EX
//                     cannot push stale results into MEM.
//
//   reg_4  (MEM/WB) : holds the final write-back payload + CSR access + PC
//                     for csr_reg.v to arbitrate traps against.
//
// None of the resets here have polarity changes from the original code:
// every clear is active-low on `rst`, which matches what cpu_jh.v's
// flush_ctrl produces.
// -----------------------------------------------------------------------------

module reg_1 (
    input            reg1_en,
    input     [31:0] rom_out,
    input     [31:0] pc_out,
    input            clk,
    input            rst,
    output reg [31:0] id_in,
    output reg [31:0] reg_2_in,
    // IF-stage branch-predictor metadata forwarded to ID so cpu_jh.v can
    // spot mispredictions when the branch resolves.  On a reset or flush
    // these fall back to 0 (pred_taken=0 => predicted fall-through), which
    // combined with reg_1_pcaddr=0 marks the slot as a bubble.
    input            bp_taken_in,
    input     [31:0] bp_target_in,
    output reg       pred_taken,
    output reg [31:0] pred_target
);
always @(posedge clk) begin
    if (rst == 1'b0) begin
        id_in       <= 32'd0;
        reg_2_in    <= 32'd0;
        pred_taken  <= 1'b0;
        pred_target <= 32'd0;
    end
    else if (reg1_en == 1'b1) begin
        id_in       <= rom_out;
        reg_2_in    <= pc_out;
        pred_taken  <= bp_taken_in;
        pred_target <= bp_target_in;
    end
end
endmodule


module reg_2 (
    input              reg2_en,
    input              clk,
    input              rst,
    input              store,
    input              load,
    input      [31:0]  sdata,
    input      [31:0]  op2,
    input      [31:0]  op1,
    input      [12:0]  b_im,
    input      [1:0]   b_en,
    input      [2:0]   op,
    input      [4:0]   rd,
    input              wb_en_in,
    input      [31:0]  pc_rd,
    input      [2:0]   mem_op,
    input      [14:0]  csr,
    input              mul_div,
    input              wq,
    input              illegal,

    output reg         reg_2_store,
    output reg         reg_2_load,
    output reg [31:0]  reg_2_sdata,
    output reg [31:0]  reg_2_op2,
    output reg [31:0]  reg_2_op1,
    output reg [12:0]  reg_2_b_im,
    output reg [1:0]   reg_2_b_en,
    output reg [2:0]   reg_2_op,
    output reg [4:0]   reg_2_rd,
    output reg         reg_2_wb_en_in,
    output reg [31:0]  reg_2_pcaddr,
    input              id_sub,
    output reg         reg_2_id_sub,
    output reg [2:0]   reg_2_mem_op,
    output reg [14:0]  reg_2_csr,
    output reg         reg_2_mul_div,
    output reg         reg_2_wq,
    output reg         reg_2_illegal,
    input              local_stop
);

    reg        reg_2_store_r;
    reg        reg_2_load_r;
    reg [31:0] reg_2_sdata_r;
    reg [31:0] reg_2_op2_r;
    reg [31:0] reg_2_op1_r;
    reg [12:0] reg_2_b_im_r;
    reg [1:0]  reg_2_b_en_r;
    reg [2:0]  reg_2_op_r;
    reg [4:0]  reg_2_rd_r;
    reg        reg_2_wb_en_in_r;
    reg [31:0] reg_2_pcaddr_r;
    reg        reg_2_id_sub_r;
    reg [2:0]  reg_2_mem_op_r;
    reg [14:0] reg_2_csr_r;
    reg        reg_2_mul_div_r;
    reg        reg_2_wq_r;
    reg        reg_2_illegal_r;

    // Intermediate -> visible output.  The shadow ladder used to hold a
    // commented-out local_stop clear here; keeping the passthrough version
    // preserves the original cycle accounting.
    always @(*) begin
        reg_2_store    = reg_2_store_r;
        reg_2_load     = reg_2_load_r;
        reg_2_sdata    = reg_2_sdata_r;
        reg_2_op2      = reg_2_op2_r;
        reg_2_op1      = reg_2_op1_r;
        reg_2_b_im     = reg_2_b_im_r;
        reg_2_b_en     = reg_2_b_en_r;
        reg_2_op       = reg_2_op_r;
        reg_2_rd       = reg_2_rd_r;
        reg_2_wb_en_in = reg_2_wb_en_in_r;
        reg_2_pcaddr   = reg_2_pcaddr_r;
        reg_2_id_sub   = reg_2_id_sub_r;
        reg_2_mem_op   = reg_2_mem_op_r;
        reg_2_csr      = reg_2_csr_r;
        reg_2_mul_div  = reg_2_mul_div_r;
        reg_2_wq       = reg_2_wq_r;
        reg_2_illegal  = reg_2_illegal_r;
    end

    always @(posedge clk) begin
        if (rst == 1'b0) begin
            reg_2_store_r    <= 1'b0;
            reg_2_load_r     <= 1'b0;
            reg_2_sdata_r    <= 32'd0;
            reg_2_op2_r      <= 32'd0;
            reg_2_op1_r      <= 32'd0;
            reg_2_b_im_r     <= 13'd0;
            reg_2_b_en_r     <= 2'd0;
            reg_2_op_r       <= 3'd0;
            reg_2_rd_r       <= 5'd0;
            reg_2_wb_en_in_r <= 1'b1; // preserved from original (note: was flagged "?")
            reg_2_pcaddr_r   <= 32'd0;
            reg_2_id_sub_r   <= 1'b0;
            reg_2_mem_op_r   <= 3'd0;
            reg_2_csr_r      <= 15'd0;
            reg_2_mul_div_r  <= 1'b0;
            reg_2_wq_r       <= 1'b0;
            reg_2_illegal_r  <= 1'b0;
        end
        else if (reg2_en == 1'b1) begin
            reg_2_store_r    <= store;
            reg_2_load_r     <= load;
            reg_2_sdata_r    <= sdata;
            reg_2_op2_r      <= op2;
            reg_2_op1_r      <= op1;
            reg_2_b_im_r     <= b_im;
            reg_2_b_en_r     <= b_en;
            reg_2_op_r       <= op;
            reg_2_rd_r       <= rd;
            reg_2_wb_en_in_r <= wb_en_in;
            reg_2_pcaddr_r   <= pc_rd;
            reg_2_id_sub_r   <= id_sub;
            reg_2_mem_op_r   <= mem_op;
            reg_2_csr_r      <= csr;
            reg_2_mul_div_r  <= mul_div;
            reg_2_wq_r       <= wq;
            reg_2_illegal_r  <= illegal;
        end
        else if (local_stop == 1'b1) begin
            reg_2_store_r    <= 1'b0;
            reg_2_load_r     <= 1'b0;
            reg_2_sdata_r    <= 32'd0;
            reg_2_op2_r      <= 32'd0;
            reg_2_op1_r      <= 32'd0;
            reg_2_b_im_r     <= 13'd0;
            reg_2_b_en_r     <= 2'd0;
            reg_2_op_r       <= 3'd0;
            reg_2_rd_r       <= 5'd0;
            reg_2_wb_en_in_r <= 1'b1;
            reg_2_pcaddr_r   <= 32'd0;
            reg_2_id_sub_r   <= 1'b0;
            reg_2_mem_op_r   <= 3'd0;
            reg_2_csr_r      <= 15'd0;
            reg_2_mul_div_r  <= 1'b0;
            reg_2_wq_r       <= 1'b0;
            reg_2_illegal_r  <= 1'b0;
        end
    end
endmodule


module reg_3 (
    input            reg3_en,
    input            clk,
    input            rst,
    input            store,
    input            load,
    input     [31:0] sdata,
    input     [31:0] p_out,
    input     [4:0]  rd,
    input            wb_en_in,
    input     [2:0]  mem_op,
    input     [14:0] csr,
    input     [31:0] pcaddr,
    input            wq,
    input            illegal,

    output reg         reg_3_store = 1'b0,
    output reg         reg_3_load  = 1'b0,
    output reg [31:0]  reg_3_sdata,
    output reg [31:0]  reg_3_p_out,
    output reg [4:0]   reg_3_rd,
    output reg         reg_3_wb_en_in,
    output reg [2:0]   reg_3_mem_op,
    output reg [14:0]  reg_3_csr,
    output reg [31:0]  reg_3_pcaddr,
    output reg         reg_3_wq,
    output reg         reg_3_illegal,

    input              div_wait_d1
);
always @(posedge clk) begin
    if (rst == 1'b0) begin
        reg_3_store    <= 1'b0;
        reg_3_load     <= 1'b0;
        reg_3_sdata    <= 32'd0;
        reg_3_p_out    <= 32'd0;
        reg_3_rd       <= 5'd0;
        reg_3_wb_en_in <= 1'b0;
        reg_3_mem_op   <= 3'd0;
        reg_3_csr      <= 15'd0;
        reg_3_pcaddr   <= 32'd0;
        reg_3_wq       <= 1'b0;
        reg_3_illegal  <= 1'b0;
    end
    else if (reg3_en == 1'b1) begin
        reg_3_store    <= store;
        reg_3_load     <= load;
        reg_3_sdata    <= sdata;
        reg_3_p_out    <= p_out;
        reg_3_rd       <= rd;
        reg_3_wb_en_in <= wb_en_in;
        reg_3_mem_op   <= mem_op;
        reg_3_csr      <= csr;
        reg_3_pcaddr   <= pcaddr;
        reg_3_wq       <= wq;
        reg_3_illegal  <= illegal;
    end
    else if (div_wait_d1 == 1'b1) begin
        reg_3_store    <= 1'b0;
        reg_3_load     <= 1'b0;
        reg_3_sdata    <= 32'd0;
        reg_3_p_out    <= 32'd0;
        reg_3_rd       <= 5'd0;
        reg_3_wb_en_in <= 1'b0;
        reg_3_mem_op   <= 3'd0;
        reg_3_csr      <= 15'd0;
        reg_3_pcaddr   <= 32'd0;
        reg_3_wq       <= 1'b0;
        reg_3_illegal  <= 1'b0;
    end
end
endmodule


module reg_4 (
    input              reg4_en,
    input              clk,
    input              rst,
    input     [31:0]   j2_p_out,
    input     [4:0]    rd,
    input              wb_en,
    input     [14:0]   csr,
    input     [31:0]   pcaddr,
    input              illegal,
    // MEM-stage access-fault handoff (Tier 4.2, Tier A #3):
    //   load_fault  : the load completing this cycle came back with
    //                 AXI RRESP[1]=1 (SLVERR/DECERR).  WB raises
    //                 mcause=5 at csr_reg.
    //   store_fault : the store completing this cycle came back with
    //                 AXI BRESP[1]=1.  WB raises mcause=7 at csr_reg.
    //   fault_addr  : the failing virtual address (reg_3_p_out).  Used
    //                 for mtval.
    input              load_fault,
    input              store_fault,
    input     [31:0]   fault_addr,

    output reg [31:0]  r4_j2_p_out,
    output reg [4:0]   r4_rd,
    output reg         r4_wb_en,
    output reg [14:0]  r4_csr,
    output reg [31:0]  r4_pcaddr,
    output reg         r4_illegal,
    output reg         r4_load_fault,
    output reg         r4_store_fault,
    output reg [31:0]  r4_fault_addr
);
always @(posedge clk) begin
    if (reg4_en == 1'b1) begin
        if (rst == 1'b0) begin
            r4_j2_p_out    <= 32'd0;
            r4_rd          <= 5'd0;
            r4_wb_en       <= 1'b0;
            r4_csr         <= 15'd0;
            r4_pcaddr      <= 32'd0;
            r4_illegal     <= 1'b0;
            r4_load_fault  <= 1'b0;
            r4_store_fault <= 1'b0;
            r4_fault_addr  <= 32'd0;
        end
        else begin
            r4_j2_p_out    <= j2_p_out;
            r4_rd          <= rd;
            r4_wb_en       <= wb_en;
            r4_csr         <= csr;
            r4_pcaddr      <= pcaddr;
            r4_illegal     <= illegal;
            r4_load_fault  <= load_fault;
            r4_store_fault <= store_fault;
            r4_fault_addr  <= fault_addr;
        end
    end
end
endmodule
