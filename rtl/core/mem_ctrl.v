// -----------------------------------------------------------------------------
// EX/MEM stage combinational glue.
//
// Moved out of cpu_jh.v so the top level doesn't need the four inline
// always@(*) blocks it used to carry.  Behaviour is bit-identical; the
// module simply collects the wiring that sits between reg_3 and reg_4:
//
//   * `j_p_out`  : the "ALU/link value -> next stage" path used when the
//                  reg_3 slot is NOT a load/store.  On loads and stores we
//                  zero it out so a later forward from MEM doesn't pick up
//                  a stale ALU result and overwrite the load data.
//
//   * `j2_p_out` : what actually gets written into reg_4.j2_p_out.  On
//                  loads we take the bus read-data; otherwise we take
//                  `j_p_out`.  Named `j2` in the old code because it came
//                  after the j_p_out mux.
//
//   * Data-bus drive: d_bus_en / data_addr_out / d_data_out / ram_we /
//     ram_re / mem_op_out are asserted whenever reg_3 holds a load or a
//     store, mirroring reg_3's store/load/addr/sdata/mem_op fields out to
//     the memory subsystem.
//
//   * `reg_3_rd_masked` / `reg_3_wb_en_masked` : the fast-path mask.  When
//     reg_3_wq is asserted, the fast-path (regfile write port 2 driven by
//     `reg_3_wq & reg_3_wb_en_in` in cpu_jh.v) has already done the write
//     back early, so we must make sure WB does NOT repeat it.  The masked
//     copies feed reg_4, which in turn feeds the csr_reg WB port.
//
// `reg_3_wq` itself comes from `reg_3_wq_out & (~csr_pc_en)`: if csr_reg is
// about to redirect the PC on a trap, we squash the early fast-path write
// so the trapping instruction does not also commit its dest register.
// That formula stays in cpu_jh.v because `csr_pc_en` is a WB-stage signal.
// -----------------------------------------------------------------------------
module mem_ctrl (
    // Inputs from reg_3 (EX/MEM boundary).
    input  wire         reg_3_store,
    input  wire         reg_3_load,
    input  wire [31:0]  reg_3_sdata,
    input  wire [31:0]  reg_3_p_out,
    input  wire [4:0]   reg_3_rd,
    input  wire         reg_3_wb_en_in,
    input  wire [2:0]   reg_3_mem_op,
    input  wire         reg_3_wq,       // already ANDed with ~csr_pc_en in cpu_jh.v

    // Data returning from the bus on loads.
    input  wire [31:0]  bus_data_in,

    // Path into reg_4.
    output wire [31:0]  j2_p_out,
    output wire [4:0]   reg_3_rd_masked,
    output wire         reg_3_wb_en_masked,

    // Drive onto the data-memory bus.
    output reg          d_bus_en,
    output reg  [31:0]  data_addr_out,
    output reg  [31:0]  d_data_out,
    output reg          ram_we,
    output reg          ram_re,
    output reg  [2:0]   mem_op_out
);

    // Bypass ALU/link result around load/store slots so forwarding never
    // accidentally exposes the raw address.
    reg [31:0] j_p_out;
    always @(*) begin
        if (reg_3_load == 1'b1 || reg_3_store == 1'b1)
            j_p_out = 32'd0;
        else
            j_p_out = reg_3_p_out;
    end

    // Data-bus drive.
    always @(*) begin
        if (reg_3_load == 1'b1 || reg_3_store == 1'b1) begin
            d_bus_en      = 1'b1;
            data_addr_out = reg_3_p_out;
            d_data_out    = reg_3_sdata;
            ram_we        = reg_3_store;
            ram_re        = reg_3_load;
            mem_op_out    = reg_3_mem_op;
        end
        else begin
            d_bus_en      = 1'b0;
            data_addr_out = 32'd0;
            d_data_out    = 32'd0;
            ram_we        = 1'b0;
            ram_re        = 1'b0;
            mem_op_out    = 3'd0;
        end
    end

    // Load return value vs ALU/link result.
    assign j2_p_out = (reg_3_load == 1'b1) ? bus_data_in : j_p_out;

    // Fast-path mask: if reg_3_wq already committed an early WB through the
    // regfile's second write port, suppress the architectural WB-port write
    // at WB so we don't double-book the same destination.
    assign reg_3_rd_masked    = (reg_3_wq == 1'b1) ? 5'd0 : reg_3_rd;
    assign reg_3_wb_en_masked = (reg_3_wq == 1'b1) ? 1'b0 : reg_3_wb_en_in;

endmodule
