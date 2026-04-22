// -----------------------------------------------------------------------------
// axil_slave_wrapper -- AXI4-Lite slave shim onto a simple dev-side bus.
//
//   s_awaddr / s_awvalid / s_awready   \
//   s_wdata  / s_wstrb   / s_wvalid     \  AXI4-Lite
//   s_wready / s_bresp   / s_bvalid      \  slave port
//   s_bready / s_araddr  / s_arprot       > (driven by axil_interconnect)
//   s_arvalid/ s_arready / s_rdata       /
//   s_rresp  / s_rvalid  / s_rready     /
//                                      /
//   ↓ reshape                         /
//
//   dev_en / dev_we / dev_re / dev_addr / dev_wdata / dev_wstrb
//   dev_rdata / dev_ready
//
// Fast-path design (2026-04 rewrite, Tier 4.2 of the improvement plan):
// ---------------------------------------------------------------------
// The first version of this wrapper registered every AXI output, so each
// transaction burned ~3 handshake cycles on top of the device's own
// latency.  That made even a 1-cycle BRAM read cost 5 CPU cycles of
// load-to-use.
//
// This rewrite keeps the handshake outputs combinational wherever that
// is still AXI-legal, so a device whose `dev_ready` is combinational
// (e.g. the 4-bank BRAM, or the LED/KEY registers) completes the AXI
// handshake in the SAME cycle `dev_ready` first goes high.  The only
// state this wrapper still needs is whether it is currently servicing a
// read or a write -- that is enforced through a tiny 3-state FSM
// (IDLE / READ / WRITE) so back-to-back transactions are serialised.
//
// Timing invariants the wrapper relies on (all held by the master
// bridge in rtl/bus/axil_master_bridge.v):
//
//   * The master asserts `m_rready` (=> `s_rready`) as soon as it has
//     issued `m_arvalid`, and keeps it high until the R handshake
//     completes.  `m_bready` is treated the same way for writes.
//     Consequence: whenever `s_rvalid` goes combinationally high, the
//     corresponding `s_rready` is already 1, so the handshake always
//     completes in the cycle `dev_ready` first rises.
//
//   * Only one transaction is in flight at a time.
//
//   * Write address and write data arrive together (AW+W in the same
//     cycle).  The wrapper asserts `s_awready` and `s_wready` only when
//     both are valid, so a master that interleaves AW/W separately will
//     still block safely (just won't hit the fast path).
//
// AR has priority over AW+W inside IDLE so a stream of writes cannot
// starve reads.  With a single CPU master this is academic, but it
// keeps the wrapper correct if we ever plug in a DMA master.
// -----------------------------------------------------------------------------
module axil_slave_wrapper (
    input  wire        aclk,
    input  wire        aresetn,

    // AXI4-Lite slave port
    input  wire [31:0] s_awaddr,
    input  wire [2:0]  s_awprot,
    input  wire        s_awvalid,
    output wire        s_awready,

    input  wire [31:0] s_wdata,
    input  wire [3:0]  s_wstrb,
    input  wire        s_wvalid,
    output wire        s_wready,

    output wire [1:0]  s_bresp,
    output wire        s_bvalid,
    input  wire        s_bready,

    input  wire [31:0] s_araddr,
    input  wire [2:0]  s_arprot,
    input  wire        s_arvalid,
    output wire        s_arready,

    output wire [31:0] s_rdata,
    output wire [1:0]  s_rresp,
    output wire        s_rvalid,
    input  wire        s_rready,

    // Device-side (simple handshake)
    output reg         dev_en,
    output reg         dev_we,
    output reg         dev_re,
    output reg  [31:0] dev_addr,
    output reg  [31:0] dev_wdata,
    output reg  [3:0]  dev_wstrb,
    input  wire [31:0] dev_rdata,
    input  wire        dev_ready
);

    // prot wires are unused; keep lint quiet.
    wire _unused_prot = s_awprot[0] ^ s_arprot[0] ^ s_bready ^ s_rready;

    localparam [1:0] S_IDLE  = 2'd0;
    localparam [1:0] S_READ  = 2'd1;
    localparam [1:0] S_WRITE = 2'd2;

    reg [1:0] state;

    // -------------------------------------------------------------------------
    // Combinational AXI outputs.
    //
    // s_arready is high whenever we are idle; AR is accepted immediately.
    // s_awready / s_wready are high when idle AND both AW and W are
    //                valid this cycle (so we enter S_WRITE atomically).
    // s_rvalid   is combinational from dev_ready while in S_READ,
    //                so a combinational-ready device completes the R
    //                handshake in the same cycle.  Relies on s_rready
    //                already being 1 (see master bridge contract).
    // s_bvalid   mirrors s_rvalid for writes.
    //
    // AR takes priority over AW+W so a busy-write stream cannot starve
    // the read channel; wvalid/awvalid are gated on the absence of AR
    // in the same cycle.
    // -------------------------------------------------------------------------
    assign s_arready = (state == S_IDLE);
    assign s_awready = (state == S_IDLE) & s_awvalid & s_wvalid & ~s_arvalid;
    assign s_wready  = (state == S_IDLE) & s_awvalid & s_wvalid & ~s_arvalid;

    assign s_rvalid  = (state == S_READ)  & dev_ready;
    assign s_rdata   = dev_rdata;
    assign s_rresp   = 2'b00;

    assign s_bvalid  = (state == S_WRITE) & dev_ready;
    assign s_bresp   = 2'b00;

    // -------------------------------------------------------------------------
    // Tiny FSM.  dev_en / dev_we / dev_re / dev_addr / dev_wdata /
    // dev_wstrb are registered so slaves see clean, stable inputs.
    // -------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            state     <= S_IDLE;
            dev_en    <= 1'b0;
            dev_we    <= 1'b0;
            dev_re    <= 1'b0;
            dev_addr  <= 32'd0;
            dev_wdata <= 32'd0;
            dev_wstrb <= 4'd0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (s_arvalid) begin
                        state     <= S_READ;
                        dev_en    <= 1'b1;
                        dev_re    <= 1'b1;
                        dev_we    <= 1'b0;
                        dev_addr  <= s_araddr;
                        dev_wdata <= 32'd0;
                        dev_wstrb <= 4'd0;
                    end else if (s_awvalid & s_wvalid) begin
                        state     <= S_WRITE;
                        dev_en    <= 1'b1;
                        dev_we    <= 1'b1;
                        dev_re    <= 1'b0;
                        dev_addr  <= s_awaddr;
                        dev_wdata <= s_wdata;
                        dev_wstrb <= s_wstrb;
                    end
                end

                S_READ: begin
                    // Drop dev_en/dev_re and return to IDLE the cycle
                    // dev_ready first rises.  Per the contract above,
                    // s_rready is already 1, so the master captures
                    // rdata the very same cycle.
                    if (dev_ready) begin
                        state  <= S_IDLE;
                        dev_en <= 1'b0;
                        dev_re <= 1'b0;
                    end
                end

                S_WRITE: begin
                    if (dev_ready) begin
                        state  <= S_IDLE;
                        dev_en <= 1'b0;
                        dev_we <= 1'b0;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
