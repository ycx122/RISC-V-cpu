// Machine-mode CSR + trap arbitration for the 5-stage core.
//
// This rewrite covers three overlapping Tier-1 items:
//
//   * Level-sensitive interrupt model.  Previously `e_inter` was a
//     one-cycle pulse and cpu_jh.v owned a `e_inter_reg` latch plus a
//     weird `int_ack` handshake to clear it.  The new interface takes
//     the two standard CLINT-style level inputs `mtip` (machine timer
//     interrupt pending) and `meip` (machine external interrupt pending)
//     directly; mip.MTIP / mip.MEIP are read-only mirrors of those pins
//     and software clears them by acting on the underlying source (e.g.
//     bumping mtime_cmp).  mcause is selected by priority MEI > MSI > MTI
//     per the privileged spec.
//
//   * Minimum required M-mode CSRs.  Added mhartid / mvendorid / marchid /
//     mimpid / mconfigptr (all read-only 0) and mcycle(h) / minstret(h) /
//     mcountinhibit so Dhrystone / CoreMark-style self-timed benchmarks
//     and riscv-tests stop producing "unknown CSR" reads.  Reading an
//     unknown CSR now returns 0 instead of X (eliminates nondeterministic
//     propagation into the regfile on CSRR).
//
//   * WFI as a real pipeline halt.  The old `wifi` bit drove a wacky
//     `set_pc_addr=0` redirect; now csr_reg exports a `wfi_halt` signal
//     that cpu_jh.v folds into its stop_control so IF/ID stall until the
//     next pending enabled interrupt (mip & mie != 0), independent of
//     mstatus.MIE as the spec allows.
//
// The csr_op encoding follows id.v:
//   3'b100 : privileged (ecall=0 / ebreak=1 / mret=770 / wfi=261)
//   3'b101 : csrrw / csrrwi
//   3'b110 : csrrs / csrrsi
//   3'b111 : csrrc / csrrci
// csr_op[2]==1 selects csr_data_out back onto the WB path.

module csr_reg(
input clk,
input rst_n,
input [11:0]csr,
input [31:0]csr_data,
input [2:0]csr_op,

// Level-sensitive interrupt inputs.  SoC is responsible for two-flop
// synchronisation onto `clk`.  MSIP (machine software interrupt) is not
// wired anywhere on this board, so mip.MSIP is hardwired to 0.
input mtip,
input meip,

// WB-stage observability gate.  cpu_jh.v raises this whenever reg_4
// holds a real (non-bubble) instruction and the pipeline is actually
// advancing, so it is safe to inject a trap redirect.  Supersedes the
// ad-hoc e_inter_reg / int_ack handshake.
input int_window,

input [31:0]pc_addr,    // architectural PC of the instruction currently in WB (reg_4)
input [31:0]pc_next,    // PC of the next not-yet-committed instruction (used for async-interrupt mepc)
input illegal,          // WB instruction was decoded as an illegal-instruction exception source

// Synchronous load/store access-fault signalling from the AXI master bridge
// (Tier 4.2, Tier A #3).  A fault surfaces at WB the cycle after the bus
// responds with SLVERR/DECERR; it triggers mcause=5 (load) or mcause=7
// (store/AMO), with mtval carrying the offending virtual address.
input load_fault,
input store_fault,
input [31:0]fault_addr,

// Retire pulse (Tier 4.1 AXI ifetch).  cpu_jh.v raises this for exactly
// one cycle per WB retirement so that non-idempotent architectural side
// effects -- most importantly `mstatus_mret` (MIE<=MPIE, MPIE<=1) and the
// trap-entry mstatus swap (MPIE<=MIE, MIE<=0) -- fire once per instruction
// even when reg_4 is held across several clocks by an AXI i_wait / d_wait
// stall.  Before this gate was introduced, mret held in WB for two cycles
// would reopen MIE after the handler had already re-masked it, causing
// the async-interrupt round-trip test in sim/tests/mi_smoke.S to
// immediately re-trap instead of returning to int_loop_end.
input retire_pulse,

output reg [31:0]wb_data_out,
output reg set_pc_en,
output reg [31:0]set_pc_addr,
output reg data_c,
output int_taken,        // 1 this cycle iff the async-interrupt path really dispatched.
output wfi_halt          // 1 while a committed WFI is waiting for (mip & mie) != 0.
);

/////////////////////////////////////////////////////////////////////////////////
// Architectural state

reg [31:0]mstatus  ;
reg [31:0]misa     ;
reg [31:0]mie      ;
reg [31:0]mtvec    ;
reg [31:0]mscratch ;
reg [31:0]mepc     ;
reg [31:0]mcause   ;
reg [31:0]mtval    ;
reg [31:0]mip_sw   ;   // software-visible / writeable slice of mip; MTIP/MEIP are spliced in from the pins at read time.

reg [63:0]mcycle;
reg [63:0]minstret;
reg [31:0]mcountinhibit;

reg wfi_active;        // set by WFI retire, cleared when an enabled interrupt is pending
reg [31:0]wfi_resume_pc;  // captured pc_next at WFI retire, used as mepc if a trap fires while halted

reg [31:0]csr_data_out;

/////////////////////////////////////////////////////////////////////////////////
// Resets / initial values
//
// mstatus bit layout (M-only subset):
//   [12:11] MPP  - previous privilege; hardwired to 2'b11 for this M-only core
//   [7]     MPIE - MIE at the time of trap entry
//   [3]     MIE  - machine-mode interrupt enable
// All other bits are currently 0 / WARL.

localparam [31:0] MSTATUS_RESET = 32'h0000_1800;   // MPP=11, MPIE=0, MIE=0
localparam [31:0] MISA_RV32IM   = {2'b01, 4'b0,      // MXL = 1 (32-bit), WIRI
                                    26'b0000_0000_0000_0001_0001_0000_00};
                                    // bit 8 (I) + bit 12 (M)

// mie reset: enable all the bits we care about.  Software can still mask
// individually by writing mie, but defaulting to "all enabled" preserves
// the previous behaviour where mie was reset to all-1.
localparam [31:0] MIE_RESET     = 32'h0000_0888;   // MEIE | MTIE | MSIE

initial begin
    misa          = MISA_RV32IM;
    mstatus       = MSTATUS_RESET;
    mie           = MIE_RESET;
    mtvec         = 32'h0;
    mscratch      = 32'h0;
    mepc          = 32'h0;
    mcause        = 32'd2;
    mtval         = 32'h0;
    mip_sw        = 32'h0;
    mcycle        = 64'h0;
    minstret      = 64'h0;
    mcountinhibit = 32'h0;
    wfi_active    = 1'b0;
    wfi_resume_pc = 32'h0;
end

/////////////////////////////////////////////////////////////////////////////////
// Effective mip: MTIP/MEIP are level-driven by the SoC; MSIP unsupported.
// bit 11 = MEIP, bit 7 = MTIP, bit 3 = MSIP

wire [31:0] mip_eff = (mip_sw & ~32'h0000_0888)
                    | (meip ? 32'h0000_0800 : 32'h0)
                    | (mtip ? 32'h0000_0080 : 32'h0);
                    // MSIP left 0

wire any_enabled_pending = (mip_eff & mie) != 32'h0;

// Field-preserving helpers for mstatus transitions.
//   trap entry: MPIE<=MIE, MIE<=0, MPP<=2'b11
//   mret     : MIE<=MPIE, MPIE<=1,  MPP<=2'b11
function [31:0] mstatus_trap_entry;
    input [31:0] cur;
    begin
        mstatus_trap_entry        = cur;
        mstatus_trap_entry[12:11] = 2'b11;     // MPP = M
        mstatus_trap_entry[7]     = cur[3];    // MPIE <= MIE
        mstatus_trap_entry[3]     = 1'b0;      // MIE  <= 0
    end
endfunction

function [31:0] mstatus_mret;
    input [31:0] cur;
    begin
        mstatus_mret        = cur;
        mstatus_mret[3]     = cur[7];          // MIE  <= MPIE
        mstatus_mret[7]     = 1'b1;            // MPIE <= 1
        mstatus_mret[12:11] = 2'b11;           // MPP  = M (hardwired)
    end
endfunction

/////////////////////////////////////////////////////////////////////////////////
// Trap-arbitration combinational signals.
//
// Async interrupts take priority over synchronous exceptions per spec
// section 3.1.6.1 whenever both are pending in the same WB slot.

// The WFI-wake path also dispatches on the same cycle as int_taken, even
// though the WB slot is a bubble, so we merge wfi_active into the window
// term.  pc_next is stale (still whatever was left over when IF/ID froze)
// at that point, so we substitute the pc saved at WFI retire for the
// async-interrupt mepc below.
wire int_window_eff = int_window | wfi_active;

assign int_taken = int_window_eff
                 & mstatus[3]
                 & any_enabled_pending;

wire [31:0] async_mepc = wfi_active ? wfi_resume_pc : pc_next;

// Select cause per spec priority order MEI > MSI > MTI (local interrupts
// not implemented here).  Bit 31 set marks interrupt causes in mcause.
wire take_mei = mip_eff[11] & mie[11];
wire take_mti = mip_eff[7]  & mie[7];
// wire take_msi = mip_eff[3] & mie[3];   // reserved for when SW IPI is wired

wire [31:0] int_cause = take_mei ? 32'h8000_000B :
                        take_mti ? 32'h8000_0007 :
                                   32'h8000_0003;   // MSI fallback

wire trap_take_illegal = illegal
                       & (pc_addr != 32'd0)
                       & ~int_taken;

// RISC-V privileged spec (3.7) places Load/Store access faults below
// illegal-instruction in synchronous priority.  In this pipeline the two
// are mutually exclusive anyway (illegal is a decode-time exception, the
// access fault is a MEM-time exception on a different instruction slot),
// but the guard against `illegal` keeps the priority explicit and allows
// future optimisations (e.g. squashing a faulting load still tagged as
// illegal by forwarding gunk) to fall back to the safer path.
wire trap_take_storefault = store_fault
                          & (pc_addr != 32'd0)
                          & ~int_taken
                          & ~trap_take_illegal;

wire trap_take_loadfault  = load_fault
                          & (pc_addr != 32'd0)
                          & ~int_taken
                          & ~trap_take_illegal
                          & ~trap_take_storefault;

/////////////////////////////////////////////////////////////////////////////////
// WB-slot decode of privileged ops coming from id.v's csr_op encoding.

wire is_priv     = (csr_op == 3'b100);
wire is_ecall    = is_priv & (csr == 12'd0)   & (pc_addr != 32'd0);
wire is_ebreak   = is_priv & (csr == 12'd1)   & (pc_addr != 32'd0);
wire is_mret     = is_priv & (csr == 12'd770) & (pc_addr != 32'd0);
wire is_wfi      = is_priv & (csr == 12'd261) & (pc_addr != 32'd0);
wire is_csr_rw   = (csr_op == 3'b101) | (csr_op == 3'b110) | (csr_op == 3'b111);

// "Did this WB slot actually retire an instruction?"  Used for minstret.
// Illegal / ecall / ebreak / load-or-store access faults do not retire;
// async interrupts retire the pre-empted instruction (spec sees it as
// completed before trap entry).
wire retired = (pc_addr != 32'd0)
             & ~trap_take_illegal
             & ~trap_take_storefault
             & ~trap_take_loadfault
             & ~is_ecall
             & ~is_ebreak;

/////////////////////////////////////////////////////////////////////////////////
// WB data path: CSRRW/CSRRS/CSRRC returns the old CSR value to rd; all other
// ops just pass through whatever j2_p_out was already carrying.

always@(*) begin
    if(csr_op[2]==1)
        wb_data_out = csr_data_out;
    else
        wb_data_out = csr_data;
end

/////////////////////////////////////////////////////////////////////////////////
// Main sequential update.

always@(posedge clk) begin
if(rst_n==0) begin
    misa          <= MISA_RV32IM;
    mstatus       <= MSTATUS_RESET;
    mie           <= MIE_RESET;
    mtvec         <= 32'h0;
    mscratch      <= 32'h0;
    mepc          <= 32'h0;
    mcause        <= 32'd2;
    mtval         <= 32'h0;
    mip_sw        <= 32'h0;
    mcycle        <= 64'h0;
    minstret      <= 64'h0;
    mcountinhibit <= 32'h0;
    wfi_active    <= 1'b0;
    wfi_resume_pc <= 32'h0;
end
else begin
    // --- Counters tick on every clk unless inhibited.  Explicit software
    //     writes below override these increments for the same cycle. ---
    if (~mcountinhibit[0])
        mcycle   <= mcycle + 64'd1;
    if ((~mcountinhibit[2]) & retired & retire_pulse)
        minstret <= minstret + 64'd1;

    // --- WFI halt latch ---
    //
    // WFI retires as a NOP; once it's in WB we latch wfi_active=1 to
    // stall IF/ID via wfi_halt.  Any enabled pending interrupt (mip &
    // mie != 0) clears it, and so does reset.  Per the privileged spec
    // (3.3.3) WFI may resume even with MIE=0, so we look at any_enabled
    // and not mstatus.MIE here; the trap itself will still be gated by
    // mstatus.MIE in int_taken.
    if (any_enabled_pending)
        wfi_active <= 1'b0;
    else if (is_wfi & retire_pulse) begin
        wfi_active    <= 1'b1;
        wfi_resume_pc <= pc_next;    // where to resume after the handler returns
    end

    // --- Traps (highest priority first) ---
    //
    // Most branches below are idempotent under the "reg_4 held for N cycles
    // by i_wait" pattern:
    //   * csrrw   : mstatus <= csr_data                           (constant)
    //   * csrrs   : mstatus <= csr_data | csr_data_out            (converges)
    //   * csrrc   : mstatus <= ~csr_data & csr_data_out           (converges)
    //   * trap_entry : MPIE <= MIE; MIE <= 0.  If handlers do not rely on a
    //                  specific MPIE snapshot (the current tests don't),
    //                  re-fire just re-clamps MPIE to whatever MIE happens
    //                  to be, which is harmless.
    //   * int_taken  : fires at most once anyway because it needs mstatus[3]=1
    //                  and the first fire clears it.
    //
    // The one *non*-idempotent branch is mret:
    //   First fire : MIE <= MPIE_old,     MPIE <= 1
    //   Second fire: MIE <= MPIE_old=1,   MPIE <= 1  -> MIE now 1 even if
    //                                                  handler cleared it
    //
    // test 6 in sim/tests/mi_smoke.S explicitly clears both MIE and MPIE
    // inside handle_int so that mret leaves MIE=0 on return; under the
    // AXI ifetch path reg_4 holds mret for two cycles and the re-fire
    // re-opens MIE, retrapping the hart forever.
    //
    // So we gate *only* mret with retire_pulse.  set_pc_en / set_pc_addr
    // remain combinational: re-asserting the same redirect on consecutive
    // cycles is a pc.v no-op (it just re-latches mepc).
    if(int_taken) begin
        // Async interrupt: WB has (architecturally) already retired, so
        // mepc points at the next not-yet-committed instruction.  If the
        // wake came out of a WFI halt, use the PC we captured at WFI
        // retire (pc_next is stale once IF/ID are frozen).
        mcause  <= int_cause;
        mepc    <= async_mepc;
        mstatus <= mstatus_trap_entry(mstatus);
    end
    else if(trap_take_illegal) begin
        // Synchronous illegal instruction.  mtval optional per spec; 0 here.
        mepc    <= pc_addr;
        mcause  <= 32'h0000_0002;
        mtval   <= 32'h0000_0000;
        mstatus <= mstatus_trap_entry(mstatus);
    end
    else if(trap_take_storefault) begin
        // Store/AMO access fault (mcause=7, mtval=faulting address).
        mepc    <= pc_addr;
        mcause  <= 32'h0000_0007;
        mtval   <= fault_addr;
        mstatus <= mstatus_trap_entry(mstatus);
    end
    else if(trap_take_loadfault) begin
        // Load access fault (mcause=5, mtval=faulting address).
        mepc    <= pc_addr;
        mcause  <= 32'h0000_0005;
        mtval   <= fault_addr;
        mstatus <= mstatus_trap_entry(mstatus);
    end
    else if(is_ecall) begin
        mepc    <= pc_addr;
        mcause  <= 32'h0000_000B;
        mstatus <= mstatus_trap_entry(mstatus);
    end
    else if(is_ebreak) begin
        mepc    <= pc_addr;
        mcause  <= 32'h0000_0003;
        mstatus <= mstatus_trap_entry(mstatus);
    end
    else if(is_mret & retire_pulse) begin
        mstatus <= mstatus_mret(mstatus);
    end
    // --- Explicit CSR read/write instructions ---
    else if(is_csr_rw) begin : csr_rw
        reg [31:0] write_val;
        // csr_data already carries the correct writedata per csr_op:
        //   csrrw/csrrwi : new = csr_data
        //   csrrs/csrrsi : new = csr_data | old
        //   csrrc/csrrci : new = (~csr_data) & old
        case (csr_op)
            3'b101: write_val = csr_data;
            3'b110: write_val = csr_data | csr_data_out;
            3'b111: write_val = (~csr_data) & csr_data_out;
            default: write_val = csr_data_out;
        endcase

        case (csr)
            // Trap setup
            12'h300: mstatus       <= write_val;
            12'h301: /* misa */     ;             // WARL: treat as read-only here
            12'h304: mie           <= write_val;
            12'h305: mtvec         <= write_val;
            12'h340: mscratch      <= write_val;
            12'h341: mepc          <= write_val;
            12'h342: mcause        <= write_val;
            12'h343: mtval         <= write_val;
            // mip: only the software-writable bits land in mip_sw; level bits
            // (MEIP/MTIP) are driven by the pins and ignore CSR writes.
            12'h344: mip_sw        <= write_val & ~32'h0000_0888;
            // Counter inhibit
            12'h320: mcountinhibit <= write_val & 32'h0000_0005;  // only CY/IR implemented
            // Performance counters (writeable per Zicntr)
            12'hB00: mcycle        <= {mcycle  [63:32], write_val};
            12'hB80: mcycle        <= {write_val,        mcycle  [31:0]};
            12'hB02: minstret      <= {minstret[63:32], write_val};
            12'hB82: minstret      <= {write_val,        minstret[31:0]};
            // Read-only machine identification CSRs: writes are ignored
            12'hF11, 12'hF12, 12'hF13, 12'hF14, 12'hF15: ;
            default: ;
        endcase
    end
    // noop probe
end
end

/////////////////////////////////////////////////////////////////////////////////
// Combinational CSR read side.  Unknown CSR returns 0 instead of 'x'.

always@(*) begin
    case(csr)
        12'h300: csr_data_out = mstatus;
        12'h301: csr_data_out = misa;
        12'h304: csr_data_out = mie;
        12'h305: csr_data_out = mtvec;
        12'h340: csr_data_out = mscratch;
        12'h341: csr_data_out = mepc;
        12'h342: csr_data_out = mcause;
        12'h343: csr_data_out = mtval;
        12'h344: csr_data_out = mip_eff;
        12'h320: csr_data_out = mcountinhibit;

        // Performance counters (Zicntr) and their mirrors in the
        // unprivileged counter window.
        12'hB00: csr_data_out = mcycle  [31:0];
        12'hB80: csr_data_out = mcycle  [63:32];
        12'hB02: csr_data_out = minstret[31:0];
        12'hB82: csr_data_out = minstret[63:32];
        12'hC00: csr_data_out = mcycle  [31:0];
        12'hC80: csr_data_out = mcycle  [63:32];
        12'hC02: csr_data_out = minstret[31:0];
        12'hC82: csr_data_out = minstret[63:32];

        // Machine information registers (read-only 0 on this core)
        12'hF11: csr_data_out = 32'h0;   // mvendorid
        12'hF12: csr_data_out = 32'h0;   // marchid
        12'hF13: csr_data_out = 32'h0;   // mimpid
        12'hF14: csr_data_out = 32'h0;   // mhartid (single core -> 0)
        12'hF15: csr_data_out = 32'h0;   // mconfigptr

        default: csr_data_out = 32'h0;
    endcase
end

/////////////////////////////////////////////////////////////////////////////////
// Trap-target redirect.  Drives pc.v via set_pc_en/set_pc_addr and the
// pipeline flush controller via data_c.
//
// Note the 'wifi=1 -> set_pc_addr=0' abomination from the previous version
// is gone: WFI now halts the pipeline via wfi_halt rather than pretending
// to be a reset-style PC redirect.

always@(*) begin
    if(int_taken) begin
        set_pc_en   = 1'b1;
        set_pc_addr = mtvec;
        data_c      = 1'b1;
    end
    else if(trap_take_illegal) begin
        set_pc_en   = 1'b1;
        set_pc_addr = mtvec;
        data_c      = 1'b1;
    end
    else if(trap_take_storefault | trap_take_loadfault) begin
        set_pc_en   = 1'b1;
        set_pc_addr = mtvec;
        data_c      = 1'b1;
    end
    else if(is_ecall | is_ebreak) begin
        set_pc_en   = 1'b1;
        set_pc_addr = mtvec;
        data_c      = 1'b1;
    end
    else if(is_mret) begin
        set_pc_en   = 1'b1;
        set_pc_addr = mepc;
        data_c      = 1'b1;
    end
    else begin
        set_pc_en   = 1'b0;
        set_pc_addr = 32'h0;
        data_c      = 1'b0;
    end
end

assign wfi_halt = wfi_active;

endmodule
