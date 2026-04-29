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
// FSM (PROCESSOR_IMPROVEMENT_PLAN Tier 4.2 follow-up: combinational
// handshake)
// ------------------------------------------------------------------
// Earlier this file used a 4-state FSM `S_IDLE -> S_R/S_W -> S_DONE
// -> S_IDLE`, which cost 4 cycles per CPU memory transaction (1 cycle
// to register AR/AW, 1 cycle for the AR/AW handshake, 1 cycle for
// R/B, 1 cycle for the parking S_DONE pulse).  Profiling on the data
// side and on D-Cache line fills showed those cycles dominated the
// achievable IPC, so the FSM was collapsed to 3 states with the
// ready-side outputs driven combinationally:
//
//   S_IDLE:  m_arvalid / m_awvalid / m_wvalid track `d_bus_en`
//            combinationally so the AR / AW+W handshake can complete
//            in the very same cycle the CPU asserts d_bus_en.  A
//            naturally-misaligned request short-circuits without
//            issuing an AXI transaction; ack pulses combinationally.
//
//   S_R:     waiting for the slave to return R.  m_rready is held
//            high; the cycle R fires we drive d_bus_ready (and
//            d_bus_err) combinationally back to the CPU and the CPU
//            advances reg_3 on the same edge that returns the bridge
//            to S_IDLE.  No "S_DONE parking cycle" is needed because
//            the CPU has already consumed the ack by the time the
//            next cycle starts.
//
//   S_W:     mirror of S_R for AW + W transactions.  m_bready is
//            held high; B fires combinationally onto d_bus_ready.
//
// `addr_latch` / `op_latch` are still registered at AR/AW fire time
// so byte / half-word extraction on R has the right offset even if
// the slave takes more than one cycle to come back.  This is the
// "fmax fallback" the plan explicitly called out: the only new
// combinational paths are `d_addr -> m_araddr / m_awaddr / wdata /
// wstrb` and `m_rdata -> bus_data_in`; addr_latch keeps the byte-
// extract mux out of the AR address path on the slave side.
//
// Protocol assumptions
// --------------------
// * The CPU only issues one outstanding transaction at a time, and keeps
//   {d_addr, d_data_out, mem_op, ram_we, ram_re} stable from the cycle
//   `d_bus_en=1` is first seen until `d_bus_ready=1`.  This matches the
//   current `mem_ctrl.v` drive pattern.
// * `ram_we` and `ram_re` are mutually exclusive and at most one of them
//   is asserted together with `d_bus_en`.
// * Slave-side AW/W contract: AW and W are accepted together (`s_awready
//   & s_wready` both go high in the same cycle).  This holds for every
//   slave on this SoC -- the local `axil_slave_wrapper.v` only raises
//   either ready when both AW and W valid are present, and the
//   interconnect's synthetic SLVERR / DECERR error path acks them
//   atomically as well.  If a future external slave needs AW/W to fire
//   independently, this FSM will need an explicit aw_done / w_done
//   tracker; flagged in `state_next` below.
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
    output wire        m_awvalid,
    input  wire        m_awready,
    output wire [31:0] m_awaddr,
    output wire [2:0]  m_awprot,

    output wire        m_wvalid,
    input  wire        m_wready,
    output wire [31:0] m_wdata,
    output wire [3:0]  m_wstrb,

    input  wire        m_bvalid,
    output wire        m_bready,
    input  wire [1:0]  m_bresp,

    output wire        m_arvalid,
    input  wire        m_arready,
    output wire [31:0] m_araddr,
    output wire [2:0]  m_arprot,

    input  wire        m_rvalid,
    output wire        m_rready,
    input  wire [31:0] m_rdata,
    input  wire [1:0]  m_rresp
);

    // AXI protection signals are fixed: unprivileged / secure / data.
    assign m_awprot = 3'b000;
    assign m_arprot = 3'b000;

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    localparam [1:0] S_IDLE = 2'd0;
    localparam [1:0] S_W    = 2'd1;  // write: AW + W issued, waiting for B
    localparam [1:0] S_R    = 2'd2;  // read : AR issued, waiting for R

    reg [1:0] state;

    // Latched copy of the CPU request kept around for the byte-lane
    // extract mux on the R side.  Captured at the cycle the AR / AW+W
    // handshake fires (state advancing to S_R / S_W), which is also the
    // cycle the AXI bus officially "owns" the transaction; the CPU may
    // hold d_addr stable until d_bus_ready, but using the latch here
    // keeps the rdata-extract combinational path off d_addr -> m_araddr
    // -> interconnect entirely.
    reg [31:0] addr_latch;
    reg [2:0]  op_latch;

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
    // Write-side data / strobe shaping (combinational from the live d_addr /
    // d_data_out / mem_op).
    // -------------------------------------------------------------------------
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
                // Aligned SH: byte_off is 00 or 10.  byte_off=01/11 trips
                // the misaligned-trap path above and never makes it to AXI,
                // so we don't need to fabricate sane wstrb for those.
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
    // Combinational issue conditions (drive the AXI valid signals directly
    // from S_IDLE, no register stage in between).
    // -------------------------------------------------------------------------
    wire idle_misalign = (state == S_IDLE) & d_bus_en & (ram_we | ram_re) & req_misaligned;
    wire idle_w_issue  = (state == S_IDLE) & d_bus_en & ram_we & ~req_misaligned;
    wire idle_r_issue  = (state == S_IDLE) & d_bus_en & ram_re & ~req_misaligned;

    assign m_arvalid = idle_r_issue;
    assign m_araddr  = {d_addr[31:2], 2'b00};

    assign m_awvalid = idle_w_issue;
    assign m_awaddr  = {d_addr[31:2], 2'b00};
    assign m_wvalid  = idle_w_issue;
    assign m_wdata   = wdata_shift;
    assign m_wstrb   = wstrb_shift;

    // We hold m_rready / m_bready only while waiting for the
    // corresponding response, but every slave on this SoC asserts the
    // response combinationally from the cycle it transitions to its
    // post-AR / post-AW+W state, so the response always lands AT the
    // earliest in the cycle right after the address phase fires - by
    // which point we are already in S_R / S_W with the ready high.
    // axil_slave_wrapper.v's header documents the matching contract.
    assign m_rready = (state == S_R);
    assign m_bready = (state == S_W);

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
            2'b00: rb_sel = m_rdata[7:0];
            2'b01: rb_sel = m_rdata[15:8];
            2'b10: rb_sel = m_rdata[23:16];
            2'b11: rb_sel = m_rdata[31:24];
        endcase

        case (byte_off_latched[1])
            1'b0: rh_sel = m_rdata[15:0];
            1'b1: rh_sel = m_rdata[31:16];
        endcase

        case (op_latch)
            3'b000:  rdata_extracted = {{24{rb_sel[7]}},  rb_sel};   // LB
            3'b001:  rdata_extracted = {{16{rh_sel[15]}}, rh_sel};   // LH
            3'b010:  rdata_extracted = m_rdata;                      // LW
            3'b100:  rdata_extracted = {24'd0, rb_sel};              // LBU
            3'b101:  rdata_extracted = {16'd0, rh_sel};              // LHU
            default: rdata_extracted = m_rdata;
        endcase
    end

    // -------------------------------------------------------------------------
    // Completion pulses (combinational).
    //
    // The CPU pipeline (hazard_ctrl / mem_ctrl) treats `d_bus_ready` as a
    // 1-cycle pulse synchronous to `aclk`.  Driving it combinationally
    // from `m_rvalid / m_bvalid` means CPU's reg_3 advances on the same
    // edge the bridge state register transitions back to S_IDLE, so the
    // very next cycle the CPU presents its post-advance d_bus_en for a
    // fresh transaction (no extra parking cycle).  See the FSM block
    // comment up top for the rationale on why this is safe vs. the old
    // S_DONE design.
    // -------------------------------------------------------------------------
    wire write_done = (state == S_W) & m_bvalid & m_bready;
    wire read_done  = (state == S_R) & m_rvalid & m_rready;

    assign bus_data_in    = rdata_extracted;
    assign d_bus_ready    = idle_misalign | write_done | read_done;
    assign d_bus_err      = (write_done & m_bresp[1]) | (read_done & m_rresp[1]);
    assign d_bus_misalign = idle_misalign;

    // -------------------------------------------------------------------------
    // FSM next-state.  Address and op are latched into addr_latch / op_latch
    // when the AR / AW+W handshake fires, regardless of how many cycles the
    // R / B response actually takes.
    // -------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            state      <= S_IDLE;
            addr_latch <= 32'd0;
            op_latch   <= 3'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    // misalign keeps state at S_IDLE: the comb ack+misalign
                    // is enough, no AXI transaction is launched, and the CPU
                    // has advanced by the next clock edge so we never see
                    // the same misaligned d_bus_en twice.
                    if (idle_w_issue & m_awready & m_wready) begin
                        addr_latch <= d_addr;
                        op_latch   <= mem_op;
                        state      <= S_W;
                    end else if (idle_r_issue & m_arready) begin
                        addr_latch <= d_addr;
                        op_latch   <= mem_op;
                        state      <= S_R;
                    end
                end

                S_W: begin
                    if (m_bvalid & m_bready) state <= S_IDLE;
                end

                S_R: begin
                    if (m_rvalid & m_rready) state <= S_IDLE;
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
            $display("[axil_master_bridge] WARN: wstrb=0 write at addr=%h (mem_op=%b) @%0t",
                     m_awaddr, mem_op, $time);
        end
    end
`ifdef BRIDGE_TRACE
    always @(posedge aclk) begin
        if (aresetn) begin
            if (m_arvalid && m_arready)
                $display("[brm] t=%0t AR addr=%h", $time, m_araddr);
            if (m_rvalid && m_rready)
                $display("[brm] t=%0t R rdata=%h rresp=%b -> ext=%h (op=%b boff=%b)",
                         $time, m_rdata, m_rresp, rdata_extracted, op_latch, addr_latch[1:0]);
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
