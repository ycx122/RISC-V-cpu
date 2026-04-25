// -----------------------------------------------------------------------------
// axil_master_bridge
//
// Bridges the CPU's legacy one-beat {d_bus_en, ram_we, ram_re, d_addr,
// d_data_out, mem_op, d_bus_ready, bus_data_in} handshake onto an
// AXI4-Lite master port (AW / W / B / AR / R).
//
// Responsibilities
// ----------------
// 1. Issue aligned AXI4-Lite transactions
//    - All AW/AR transactions are issued on naturally word-aligned
//      addresses (lowest two bits of AWADDR/ARADDR forced to 2'b00).
//    - Slaves never see a misaligned access on AXI, so they only ever
//      need to handle the standard "32b word + wstrb" shape.  That is
//      exactly what Xilinx MIG / AXI UART16550 / AXI QSPI / AXI DMA all
//      expect as AXI4-Lite masters, so the RAM / ROM / CLINT / UART
//      slaves behind this bridge are drop-in compatible with those real
//      AXI IPs.
//
// 2. Byte-lane steering
//    - On writes (SB / SH / SW):
//        * Replicate the CPU's store data into the correct byte lane(s)
//          of AXI WDATA.
//        * Generate WSTRB from (mem_op + d_addr[1:0]) so the slave only
//          writes the requested byte(s).  A byte write at byte-address 2
//          becomes {awaddr=addr&~3, wdata[23:16]=reg[7:0], wstrb=4'b0100}.
//    - On reads (LB / LH / LW / LBU / LHU):
//        * Always fetch the full 32-bit aligned word back from the slave.
//        * Extract the requested byte / half-word from the returned word
//          based on d_addr[1:0] and sign- or zero-extend it per mem_op.
//          The slave therefore never has to look at mem_op, which is a
//          CPU-private concept.
//
// 3. Completion handshake back to the CPU
//    - `d_bus_ready` is a one-cycle pulse synchronous to `aclk`; matches
//      the semantics the CPU (hazard_ctrl / mem_ctrl) already expects
//      from the previous custom bus.  `bus_data_in` carries the
//      post-extraction load value in the same cycle `d_bus_ready=1`.
//
// Protocol assumptions
// --------------------
// * The CPU only issues one outstanding transaction at a time, and keeps
//   {d_addr, d_data_out, mem_op, ram_we, ram_re} stable from the cycle
//   `d_bus_en=1` is first seen until `d_bus_ready=1`.  This matches the
//   current `mem_ctrl.v` drive pattern.
// * `ram_we` and `ram_re` are mutually exclusive and at most one of them
//   is asserted together with `d_bus_en`.
// * `aresetn` is active-low.
// -----------------------------------------------------------------------------
module axil_master_bridge (
    input  wire        aclk,
    input  wire        aresetn,

    // --- CPU legacy handshake ------------------------------------------------
    input  wire        d_bus_en,
    input  wire        ram_we,
    input  wire        ram_re,
    input  wire [31:0] d_addr,
    input  wire [31:0] d_data_out,
    input  wire [2:0]  mem_op,

    output wire [31:0] bus_data_in,
    output wire        d_bus_ready,
    // 1-cycle pulse coincident with d_bus_ready: set if the AXI response for
    // the completing transaction was SLVERR (2'b10) or DECERR (2'b11).  The
    // CPU pipes this into reg_4 alongside the load/store's rd/wb_en to raise
    // a Load/Store Access Fault (mcause=5/7) at WB.
    output wire        d_bus_err,
    // 1-cycle pulse coincident with d_bus_ready: set if the CPU requested a
    // naturally-misaligned load/store (LH/LW at a non-aligned byte, SH/SW
    // likewise) and the bridge short-circuited the request without issuing
    // any AXI transaction.  The CPU pipes this into reg_4 so csr_reg can
    // raise mcause=4 (Load Address Misaligned) / mcause=6 (Store Address
    // Misaligned) at WB with mtval=d_addr.  Mutually exclusive with
    // d_bus_err - a misaligned access never reaches AXI, so it never gets a
    // SLVERR/DECERR.  See Tier A #2.
    output wire        d_bus_misalign,

    // --- AXI4-Lite master ----------------------------------------------------
    output reg         m_awvalid,
    input  wire        m_awready,
    output reg  [31:0] m_awaddr,
    output wire [2:0]  m_awprot,

    output reg         m_wvalid,
    input  wire        m_wready,
    output reg  [31:0] m_wdata,
    output reg  [3:0]  m_wstrb,

    input  wire        m_bvalid,
    output reg         m_bready,
    input  wire [1:0]  m_bresp,

    output reg         m_arvalid,
    input  wire        m_arready,
    output reg  [31:0] m_araddr,
    output wire [2:0]  m_arprot,

    input  wire        m_rvalid,
    output reg         m_rready,
    input  wire [31:0] m_rdata,
    input  wire [1:0]  m_rresp
);

    // AXI protection signals are fixed: unprivileged / secure / data.
    assign m_awprot = 3'b000;
    assign m_arprot = 3'b000;

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    // S_DONE exists purely to absorb the one cycle where d_bus_ready=1 is
    // pulsed to the CPU.  Without it, the bridge would transition back to
    // S_IDLE on the same cycle the CPU first observes d_bus_ready=1, and
    // would then observe the *old* (not-yet-advanced) d_bus_en / ram_re /
    // d_addr from the pipeline and fire a duplicate transaction.  Sitting
    // in S_DONE for exactly one cycle mirrors the old riscv_bus TRANS
    // state and gives the pipeline the posedge it needs to retire the
    // load/store before we sample its signals again.
    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_W    = 2'd1;  // write: AW + W issued, waiting for B
    localparam [1:0] S_R    = 2'd2;  // read : AR issued, waiting for R
    localparam [1:0] S_DONE = 2'd3;

    reg [1:0] state;

    // Latched copy of the CPU request so byte-lane extraction on reads
    // still sees the correct offset after the CPU pipeline advances past
    // the load.
    reg [31:0] addr_latch;
    reg [2:0]  op_latch;
    reg [31:0] rdata_latch;
    reg        d_bus_ready_r;
    reg        d_bus_err_r;
    reg        d_bus_misalign_r;

    // -------------------------------------------------------------------------
    // Natural-alignment check for the incoming request.  SB / LB / LBU
    // (mem_op[1:0]=00) are always aligned.  SH / LH / LHU (=01) require
    // d_addr[0]=0.  SW / LW (=10) require d_addr[1:0]=00.  The MSB of
    // mem_op distinguishes load-vs-store sign-/zero-extension shape on
    // loads but does not affect alignment.  Width-0 reserved encodings are
    // treated as aligned here - they cannot be generated by id.v under
    // RV32I.
    // -------------------------------------------------------------------------
    function misaligned_req;
        input [2:0]  op;
        input [1:0]  byte_off;
        begin
            case (op[1:0])
                2'b00:   misaligned_req = 1'b0;                 // byte
                2'b01:   misaligned_req = byte_off[0];          // half-word
                2'b10:   misaligned_req = |byte_off;            // word
                default: misaligned_req = 1'b0;
            endcase
        end
    endfunction

    wire req_misaligned = misaligned_req(mem_op, d_addr[1:0]);

    // -------------------------------------------------------------------------
    // Write-side data / strobe shaping
    // -------------------------------------------------------------------------
    // mem_op encoding (unchanged from the CPU):
    //   3'b000 : SB  (byte)
    //   3'b001 : SH  (half-word)
    //   3'b010 : SW  (word)
    // For stores the top bit of mem_op is always 0.
    reg [31:0] wdata_shift;
    reg [3:0]  wstrb_shift;

    wire [1:0] byte_off_now = d_addr[1:0];

    always @(*) begin
        case (mem_op[1:0])
            2'b00: begin // SB
                wstrb_shift = 4'b0001 << byte_off_now;
                case (byte_off_now)
                    2'b00: wdata_shift = {24'd0,            d_data_out[7:0]};
                    2'b01: wdata_shift = {16'd0, d_data_out[7:0],  8'd0};
                    2'b10: wdata_shift = { 8'd0, d_data_out[7:0], 16'd0};
                    2'b11: wdata_shift = {       d_data_out[7:0], 24'd0};
                endcase
            end
            2'b01: begin // SH
                // Aligned SH: byte_off is 00 or 10.  For 2'b11 the spec
                // calls for a misaligned-access exception; we fall back
                // to a single-word transaction here (the ISA regression
                // suite never exercises this path).
                wstrb_shift = 4'b0011 << {byte_off_now[1], 1'b0};
                if (byte_off_now[1] == 1'b0)
                    wdata_shift = {16'd0, d_data_out[15:0]};
                else
                    wdata_shift = {d_data_out[15:0], 16'd0};
            end
            2'b10: begin // SW
                wstrb_shift = 4'b1111;
                wdata_shift = d_data_out;
            end
            default: begin
                wstrb_shift = 4'b0000;
                wdata_shift = 32'd0;
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // Read-side extraction (uses the latched request so the CPU can have
    // moved on by the cycle this mux fires).
    // -------------------------------------------------------------------------
    wire [1:0] byte_off_latched = addr_latch[1:0];

    reg  [7:0]  rb_sel;
    reg  [15:0] rh_sel;
    reg  [31:0] rdata_extracted;

    always @(*) begin
        case (byte_off_latched)
            2'b00: rb_sel = rdata_latch[7:0];
            2'b01: rb_sel = rdata_latch[15:8];
            2'b10: rb_sel = rdata_latch[23:16];
            2'b11: rb_sel = rdata_latch[31:24];
        endcase

        case (byte_off_latched[1])
            1'b0: rh_sel = rdata_latch[15:0];
            1'b1: rh_sel = rdata_latch[31:16];
        endcase

        case (op_latch)
            3'b000:  rdata_extracted = {{24{rb_sel[7]}},  rb_sel};   // LB
            3'b001:  rdata_extracted = {{16{rh_sel[15]}}, rh_sel};   // LH
            3'b010:  rdata_extracted = rdata_latch;                  // LW
            3'b100:  rdata_extracted = {24'd0, rb_sel};              // LBU
            3'b101:  rdata_extracted = {16'd0, rh_sel};              // LHU
            default: rdata_extracted = rdata_latch;
        endcase
    end

    assign bus_data_in    = rdata_extracted;
    assign d_bus_ready    = d_bus_ready_r;
    assign d_bus_err      = d_bus_err_r;
    assign d_bus_misalign = d_bus_misalign_r;

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            state         <= S_IDLE;
            m_awvalid     <= 1'b0;
            m_awaddr      <= 32'd0;
            m_wvalid      <= 1'b0;
            m_wdata       <= 32'd0;
            m_wstrb       <= 4'd0;
            m_bready      <= 1'b0;
            m_arvalid     <= 1'b0;
            m_araddr      <= 32'd0;
            m_rready      <= 1'b0;
            addr_latch       <= 32'd0;
            op_latch         <= 3'd0;
            rdata_latch      <= 32'd0;
            d_bus_ready_r    <= 1'b0;
            d_bus_err_r      <= 1'b0;
            d_bus_misalign_r <= 1'b0;
        end else begin
            // d_bus_ready / d_bus_err / d_bus_misalign default to a
            // one-cycle pulse.
            d_bus_ready_r    <= 1'b0;
            d_bus_err_r      <= 1'b0;
            d_bus_misalign_r <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (d_bus_en & (ram_we | ram_re) & req_misaligned) begin
                        // Misaligned load/store: short-circuit.  No AXI
                        // transaction is issued; instead we emit a
                        // single-cycle completion pulse carrying
                        // d_bus_misalign=1 and park in S_DONE for one
                        // cycle to mirror the regular transaction timing
                        // (so the CPU pipeline retires reg_3 exactly once
                        // and does not re-issue the same request).  The
                        // original (misaligned) address still needs to
                        // end up in mtval, so we latch d_addr without
                        // forcing the bottom two bits to zero.
                        addr_latch       <= d_addr;
                        op_latch         <= mem_op;
                        d_bus_ready_r    <= 1'b1;
                        d_bus_misalign_r <= 1'b1;
                        state            <= S_DONE;
                    end else if (d_bus_en & ram_we) begin
                        addr_latch <= d_addr;
                        op_latch   <= mem_op;
                        m_awvalid  <= 1'b1;
                        m_awaddr   <= {d_addr[31:2], 2'b00};
                        m_wvalid   <= 1'b1;
                        m_wdata    <= wdata_shift;
                        m_wstrb    <= wstrb_shift;
                        m_bready   <= 1'b1;
                        state      <= S_W;
                    end else if (d_bus_en & ram_re) begin
                        addr_latch <= d_addr;
                        op_latch   <= mem_op;
                        m_arvalid  <= 1'b1;
                        m_araddr   <= {d_addr[31:2], 2'b00};
                        m_rready   <= 1'b1;
                        state      <= S_R;
                    end
                end

                S_W: begin
                    if (m_awvalid & m_awready) m_awvalid <= 1'b0;
                    if (m_wvalid  & m_wready ) m_wvalid  <= 1'b0;

                    if (m_bvalid & m_bready) begin
                        m_bready      <= 1'b0;
                        d_bus_ready_r <= 1'b1;
                        // Bit 1 of AXI BRESP distinguishes SLVERR (2'b10)
                        // and DECERR (2'b11) from OKAY (2'b00) / EXOKAY
                        // (2'b01); either error maps to a Store Access
                        // Fault once it reaches WB.
                        d_bus_err_r   <= m_bresp[1];
                        state         <= S_DONE;
                    end
                end

                S_R: begin
                    if (m_arvalid & m_arready) m_arvalid <= 1'b0;

                    if (m_rvalid & m_rready) begin
                        rdata_latch   <= m_rdata;
                        m_rready      <= 1'b0;
                        d_bus_ready_r <= 1'b1;
                        // See S_W above: RRESP[1] flags a Load Access Fault.
                        d_bus_err_r   <= m_rresp[1];
                        state         <= S_DONE;
                    end
                end

                S_DONE: begin
                    // Exactly one cycle here.  d_bus_ready_r defaults back
                    // to 0 so the CPU sees a single-cycle completion pulse;
                    // returning to S_IDLE lets the next (post-advance)
                    // d_bus_en start a new transaction on the following
                    // cycle.
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    // Tier A #2 diagnostic: a write event with wstrb=0 is a no-op on the
    // AXI bus.  Under RV32I that can only happen via a reserved mem_op
    // encoding, which id.v never generates - catching it here surfaces
    // control-signal bugs during simulation without affecting synthesis.
    always @(posedge aclk) begin
        if (aresetn && m_wvalid && m_wready && (m_wstrb == 4'b0000)) begin
            $display("[axil_master_bridge] WARN: wstrb=0 write at addr=%h (op_latch=%b) @%0t",
                     m_awaddr, op_latch, $time);
        end
    end
`ifdef BRIDGE_TRACE
    always @(posedge aclk) begin
        if (aresetn) begin
            if (m_arvalid && m_arready)
                $display("[brm] t=%0t AR addr=%h", $time, m_araddr);
            if (m_rvalid && m_rready)
                $display("[brm] t=%0t R rdata=%h rresp=%b -> latch=%h ext=%h (op=%b boff=%b)",
                         $time, m_rdata, m_rresp, m_rdata, rdata_extracted, op_latch, addr_latch[1:0]);
            if (m_awvalid && m_awready)
                $display("[brm] t=%0t AW addr=%h", $time, m_awaddr);
            if (m_wvalid && m_wready)
                $display("[brm] t=%0t W  data=%h strb=%b", $time, m_wdata, m_wstrb);
            if (m_bvalid && m_bready)
                $display("[brm] t=%0t B  resp=%b", $time, m_bresp);
        end
    end
`endif
`endif

endmodule
