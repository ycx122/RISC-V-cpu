`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// clnt - Core-Local INTerruptor, SiFive-compatible register layout.
//
// Tier 4 item 3 of PROCESSOR_IMPROVEMENT_PLAN.md: align CLINT register
// offsets with the de-facto standard used by SiFive / OpenSBI / Linux, so
// off-the-shelf firmware that parametrises the CLINT base address works
// unchanged against this SoC.
//
// Memory map (relative to the CLINT base address, hart 0 only; a future
// multi-hart rev fills in the 0x04 / 0x4008 / 0x4010 slots per extra hart):
//
//   0x0000   msip[0]     R/W 32-bit  bit 0 = MSIP for hart 0, rest WIRI
//   0x4000   mtimecmp_lo R/W 32-bit
//   0x4004   mtimecmp_hi R/W 32-bit
//   0xBFF8   mtime_lo    R/W 32-bit  (hart-shared, free-running counter)
//   0xBFFC   mtime_hi    R/W 32-bit
//
// Any other offset inside this slave's window decodes as read-0 / write-
// ignored.  The slave wrapper sitting in front of us has already turned
// AXI4-Lite into the simple `{en, we, re, wstrb, ...}` handshake below,
// so the wrapper guarantees single-transaction and byte-strobe semantics.
//
// Interrupt pins (level-sensitive, cpu_clk synchronous):
//   msip          = msip_reg[0]                            (to CSR mip.MSIP)
//   time_e_inter  = (mtime >= mtimecmp)                    (to CSR mip.MTIP)
//
// Historical note
//   The previous revision used a word-indexed four-register layout
//   (mtime_lo/hi at indexes 0/1, mtimecmp_lo/hi at indexes 2/3) plus a
//   bespoke `clnt_flag` enable at index 4.  `clnt_flag` was a vendor
//   extension not present in any real CLINT, so it is removed here:
//   the timer interrupt is now gated purely by mtimecmp vs mtime, as
//   software that follows the privileged spec expects.  To keep the
//   timer from firing immediately out of reset (mtime starts at 0),
//   mtimecmp is reset to 0xFFFF_FFFF_FFFF_FFFF (effectively "off").
// -----------------------------------------------------------------------------

module clnt(
    input            clk,
    input            rst_n,

    // Simple device-side handshake from axil_slave_wrapper.  The wrapper
    // presents aligned 32-bit transactions with byte-strobes; `addr` is
    // the full CPU-visible byte address within the slave window (at
    // least the low 16 bits are significant here).
    input            clnt_en,
    input            re,
    input            we,
    input  [15:0]    clnt_addr,
    input  [31:0]    din,
    input  [3:0]     wstrb,
    output reg [31:0] dout,
    output           clnt_ready,

    // Level-sensitive interrupt outputs to the CPU's CSR block.
    output           msip,
    output           time_e_inter
);

    // Free-running 64-bit machine timer (shared across all harts on a
    // real multi-hart CLINT).  Bumps every cpu_clk cycle unless software
    // is currently writing it.
    reg [63:0] mtime;

    // Per-hart 64-bit compare register.  Hart 0 only for now; the
    // 0x4008/0x400C pair would hold hart 1's.
    reg [63:0] mtimecmp;

    // Per-hart msip register.  SiFive exposes 32 bits but only bit 0 is
    // defined (IPI source); the remaining bits are WIRI, ignored on write
    // and read as 0 here.
    reg        msip_r;

    assign clnt_ready = clnt_en;
    assign msip        = msip_r;
    assign time_e_inter = (mtime >= mtimecmp);

    // Address decode.  SiFive aligns every register on a 4-byte boundary
    // and reserves the bits between blocks, so we decode on the full
    // low-16 address.  mstrb is an AXI4-Lite byte-strobe from the bridge.
    wire sel_msip     = (clnt_addr == 16'h0000);
    wire sel_mtcmp_lo = (clnt_addr == 16'h4000);
    wire sel_mtcmp_hi = (clnt_addr == 16'h4004);
    wire sel_mtime_lo = (clnt_addr == 16'hBFF8);
    wire sel_mtime_hi = (clnt_addr == 16'hBFFC);

    // Byte-wise write helper.  SiFive CLINT accepts 32-bit aligned
    // accesses; we honour wstrb on the off chance the CPU issues a sub-
    // word store, for symmetry with the rest of the memory map.
    function [31:0] apply_wstrb;
        input [31:0] cur;
        input [31:0] nd;
        input [3:0]  s;
        begin
            apply_wstrb = { s[3] ? nd[31:24] : cur[31:24],
                            s[2] ? nd[23:16] : cur[23:16],
                            s[1] ? nd[15:8]  : cur[15:8],
                            s[0] ? nd[7:0]   : cur[7:0] };
        end
    endfunction

    // ------------------------------------------------------------------
    // Read side
    // ------------------------------------------------------------------
    always @(*) begin
        if (clnt_en & re) begin
            case (1'b1)
                sel_msip:     dout = {31'b0, msip_r};
                sel_mtcmp_lo: dout = mtimecmp[31:0];
                sel_mtcmp_hi: dout = mtimecmp[63:32];
                sel_mtime_lo: dout = mtime[31:0];
                sel_mtime_hi: dout = mtime[63:32];
                default:      dout = 32'h0;
            endcase
        end else
            dout = 32'h0;
    end

    // ------------------------------------------------------------------
    // mtime (free-running)
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            mtime <= 64'h0;
        end else if (clnt_en & we & sel_mtime_lo) begin
            mtime <= { mtime[63:32], apply_wstrb(mtime[31:0], din, wstrb) };
        end else if (clnt_en & we & sel_mtime_hi) begin
            mtime <= { apply_wstrb(mtime[63:32], din, wstrb), mtime[31:0] };
        end else begin
            mtime <= mtime + 64'd1;
        end
    end

    // ------------------------------------------------------------------
    // mtimecmp (per-hart).  Reset value is all-ones so the timer stays
    // quiescent until software has deliberately programmed it; SiFive
    // CLINT resets the same way for the same reason.
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            mtimecmp <= {64{1'b1}};
        end else if (clnt_en & we & sel_mtcmp_lo) begin
            mtimecmp <= { mtimecmp[63:32],
                          apply_wstrb(mtimecmp[31:0], din, wstrb) };
        end else if (clnt_en & we & sel_mtcmp_hi) begin
            mtimecmp <= { apply_wstrb(mtimecmp[63:32], din, wstrb),
                          mtimecmp[31:0] };
        end
    end

    // ------------------------------------------------------------------
    // msip (software interrupt bit for hart 0).  Only bit 0 is meaningful.
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n)
            msip_r <= 1'b0;
        else if (clnt_en & we & sel_msip & wstrb[0])
            msip_r <= din[0];
    end

endmodule
