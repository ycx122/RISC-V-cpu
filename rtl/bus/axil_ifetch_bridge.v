`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// axil_ifetch_bridge
//
// Tier 4 / PROCESSOR_IMPROVEMENT_PLAN item 4 (step A): bridge the CPU's
// legacy instruction-fetch port {i_bus_en, pc_addr, i_data, i_bus_ready}
// onto a read-only AXI4-Lite master (AR/R only).  This is the first step
// towards putting instruction fetch behind a cache and ultimately behind
// DDR: once the CPU drives a standard AXI master it no longer cares what
// physical memory lives behind it.
//
// Design notes
// ------------
// * Read-only master.  AW / W / B are not present on this bridge at all
//   (the module has no write-side ports).  An instruction fetch that goes
//   out of the mapped instruction memory range is surfaced by the slave
//   returning SLVERR/DECERR; we propagate that through `i_bus_err` for a
//   future `mcause=1 (Instruction Access Fault)` hookup.  At this step
//   the CPU core just ignores `i_bus_err`, so the signal is wired-but-
//   unused at the top level.
//
// * Single outstanding transaction.  The CPU's IF path is naturally
//   single-issue: it emits one PC per cycle, and when it stalls on a
//   fetch it holds PC stable (see hazard_ctrl.v: `i_wait = i_bus_en &
//   ~i_bus_ready` freezes the whole pipeline).  A single in-flight AR
//   is therefore sufficient, and trivially correct to reason about.
//
// * Fast handshake back to the CPU.  `i_bus_ready` is a combinational
//   pulse from `m_rvalid` (gated by state==S_R), and `i_data` is wired
//   straight from `m_rdata`.  This keeps the bridge's contribution to
//   fetch latency to zero cycles on top of the slave's own R latency,
//   so a 1-cycle slave (like the combinational i_rom port B read) ends
//   up at exactly 2 cycles per instruction in steady state:
//
//     N+0: bridge IDLE, m_arvalid=1 with pc_addr=PC_A -> AR fires
//     N+1: bridge S_R,  slave presents data -> R fires; i_bus_ready=1
//          pulses combinationally, CPU samples i_data at this edge
//     N+2: bridge IDLE, PC has advanced to PC_B -> next AR fires
//
//   Compared to TCM (direct BRAM port B) this is a 2x IPC loss.  The
//   point of step A is to prove the AXI path, not to match TCM on
//   performance; an I-cache added in step B brings hit latency back
//   down to 1 cycle.
//
// * Aligned AR.  The low two bits of `m_araddr` are forced to 00; the
//   CPU never issues a misaligned fetch (it would trap at ID otherwise)
//   but this keeps the contract clean for the slave.
//
// * Protocol assumptions
//   - `i_bus_en` is always 1 while the CPU wants to run (see cpu_jh.v
//     where it is initialised to 1 and never cleared).  The bridge
//     still AND-gates AR issue on it so reset behaves nicely.
//   - `pc_addr` is stable while a transaction is in flight (enforced
//     by hazard_ctrl freezing PC during `i_wait`).
//   - The downstream slave holds AR / R handshakes per AXI4-Lite:
//     arready combinational in IDLE is fine; rvalid once asserted
//     stays high until rready accepts.  This matches both
//     axil_slave_wrapper.v and the DECERR behaviour of
//     axil_interconnect.v.
//   - aresetn is active-low.
// -----------------------------------------------------------------------------
module axil_ifetch_bridge (
    input  wire        aclk,
    input  wire        aresetn,

    // ---- CPU-side instruction fetch handshake ------------------------------
    input  wire        i_bus_en,
    input  wire [31:0] pc_addr,
    output wire [31:0] i_data,
    output wire        i_bus_ready,
    // 1-cycle pulse aligned with `i_bus_ready`: set when the AXI RRESP for
    // the completing fetch was SLVERR (2'b10) or DECERR (2'b11).  Hooked up
    // at the top level to a future Instruction Access Fault path; left as
    // a bus-only signal during step A.
    output wire        i_bus_err,

    // ---- AXI4-Lite master (read-only) --------------------------------------
    output wire        m_arvalid,
    input  wire        m_arready,
    output wire [31:0] m_araddr,
    output wire [2:0]  m_arprot,

    input  wire        m_rvalid,
    output wire        m_rready,
    input  wire [31:0] m_rdata,
    input  wire [1:0]  m_rresp
);

    // -------------------------------------------------------------------------
    // Tiny two-state FSM:
    //   S_IDLE : no transaction in flight; issue AR as soon as i_bus_en.
    //   S_R    : AR accepted, waiting for R handshake.
    // -------------------------------------------------------------------------
    localparam S_IDLE = 1'b0;
    localparam S_R    = 1'b1;

    reg        state;
    // Address captured at AR accept.  Used to qualify the R-side response:
    // if the CPU redirects pc mid-fetch (trap entry, pending-redirect
    // replay, etc.) the AR already sitting in the downstream slave will
    // still return data for the ORIGINAL request, which the CPU must NOT
    // latch into reg_1 (it would be a well-formed word from the wrong PC
    // and cpu_jh can't tell it apart from the right word).  We drop
    // i_bus_ready on mismatch so the CPU keeps i_wait high, and re-issue
    // the AR for the new pc the cycle we return to S_IDLE.
    reg [29:0] inflight_word;

    always @(posedge aclk) begin
        if (!aresetn) begin
            state         <= S_IDLE;
            inflight_word <= 30'd0;
        end else begin
            case (state)
                S_IDLE: if (m_arvalid & m_arready) begin
                    state         <= S_R;
                    inflight_word <= pc_addr[31:2];
                end
                S_R   : if (m_rvalid  & m_rready)  state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end

    // AR issue: combinational in S_IDLE while the CPU wants a fetch.
    // Address is aligned to a word boundary.  ARPROT[2]=1 marks this as an
    // instruction access, which future downstream IP (e.g. a PMP / bus
    // monitor) can use to enforce "no data access into .text".
    assign m_arvalid = (state == S_IDLE) & i_bus_en;
    assign m_araddr  = {pc_addr[31:2], 2'b00};
    assign m_arprot  = 3'b100;

    // R accept: assert rready throughout S_R so a 1-cycle slave can close
    // the handshake in the same cycle rvalid goes high.  We accept the R
    // beat regardless of whether the CPU is still interested (so the
    // slave's channel drains and a fresh AR can be issued next cycle) but
    // only forward i_bus_ready upstream when the captured inflight word
    // still matches pc_addr.
    assign m_rready = (state == S_R);

    // CPU-side outputs are pure combinational from the AXI R channel.
    //  * i_bus_ready pulses for exactly one cycle (the cycle R handshake
    //    fires) iff the inflight address still matches pc_addr.
    //  * i_data is m_rdata during that same cycle.  Outside of the pulse
    //    it is don't-care; nothing downstream samples it when
    //    i_bus_ready=0 (stop_cache only latches on stall transitions and
    //    reg_1 is gated by reg1_en which in turn depends on i_wait, i.e.
    //    on i_bus_ready).
    //  * i_bus_err mirrors RRESP[1] on the same pulse (1 => SLVERR/DECERR).
    wire fetch_done  = (state == S_R) & m_rvalid & m_rready;
    wire fetch_match = (inflight_word == pc_addr[31:2]);

    assign i_data      = m_rdata;
    assign i_bus_ready = fetch_done & fetch_match;
    assign i_bus_err   = fetch_done & fetch_match & m_rresp[1];

endmodule
