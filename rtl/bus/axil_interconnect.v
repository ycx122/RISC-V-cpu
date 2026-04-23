// -----------------------------------------------------------------------------
// axil_interconnect
//
// 1 master -> 7 slaves AXI4-Lite crossbar (really a combinational decoder,
// since we only have one CPU master and a single outstanding transaction at
// a time).  Address space is:
//
//   0x0000_0000 - 0x0FFF_FFFF : boot ROM (slave 0)
//   0x2000_0000 - 0x2FFF_FFFF : data RAM (slave 1)
//   0x4000_0000 - 0x40FF_FFFF : LED      (slave 2)
//   0x4100_0000 - 0x41FF_FFFF : KEY      (slave 3)
//   0x4200_0000 - 0x42FF_FFFF : CLINT    (slave 4)   - SiFive layout (see clnt.v)
//   0x4300_0000 - 0x43FF_FFFF : UART     (slave 5)
//   0x4400_0000 - 0x44FF_FFFF : PLIC     (slave 6)   - SiFive layout (see plic.v)
//
// Anything else falls through the decoder as "unmapped" - the crossbar then
// synthesises a DECERR response internally (Tier 4.2, Tier A #3) so
// stray MMIO pointers surface as a proper RISC-V load/store access fault
// (mcause=5/7) instead of silently hanging the pipeline.  Real AXI IP
// (e.g. Xilinx axi_interconnect) exposes the same behaviour.
//
// Tier A #1: any write that targets the ROM window (slave 0) is also
// routed through the synthetic error path, but with RESP=SLVERR instead
// of DECERR - the address *is* mapped, it just isn't writable.  The ROM
// slave's AW/W channels are never strobed; only reads reach it.  This
// surfaces accidental stores to ROM as a regular Store Access Fault so
// the BSP's trap handler sees an unambiguous mcause=7 + mtval.
//
// Handshake semantics for the error path mirror a real 1-cycle slave:
//   * AW/W accept on the cycle m_awvalid & m_wvalid are asserted
//     (m_{aw,w}ready are combinational 1 for wr_none | wr_ro).
//   * B response arrives one cycle later with m_bresp=DECERR (unmapped)
//     or SLVERR (ROM write).
//   * AR accepts on m_arvalid (m_arready combinational 1 for rd_none),
//     R response arrives one cycle later with m_rresp=DECERR and
//     m_rdata=0.
//
// Because the master bridge keeps one transaction in flight at a time and
// holds m_awaddr / m_araddr stable until the matching B / R handshake
// completes, the real-slave mux stays purely combinational; only the
// decerr-pending flags add state.
// -----------------------------------------------------------------------------
module axil_interconnect (
    input  wire        aclk,
    input  wire        aresetn,

    // --- master side -------------------------------------------------------
    input  wire [31:0] m_awaddr,
    input  wire [2:0]  m_awprot,
    input  wire        m_awvalid,
    output wire        m_awready,

    input  wire [31:0] m_wdata,
    input  wire [3:0]  m_wstrb,
    input  wire        m_wvalid,
    output wire        m_wready,

    output wire [1:0]  m_bresp,
    output wire        m_bvalid,
    input  wire        m_bready,

    input  wire [31:0] m_araddr,
    input  wire [2:0]  m_arprot,
    input  wire        m_arvalid,
    output wire        m_arready,

    output wire [31:0] m_rdata,
    output wire [1:0]  m_rresp,
    output wire        m_rvalid,
    input  wire        m_rready,

    // --- slave 0 : ROM -----------------------------------------------------
    output wire [31:0] rom_awaddr,
    output wire [2:0]  rom_awprot,
    output wire        rom_awvalid,
    input  wire        rom_awready,
    output wire [31:0] rom_wdata,
    output wire [3:0]  rom_wstrb,
    output wire        rom_wvalid,
    input  wire        rom_wready,
    input  wire [1:0]  rom_bresp,
    input  wire        rom_bvalid,
    output wire        rom_bready,
    output wire [31:0] rom_araddr,
    output wire [2:0]  rom_arprot,
    output wire        rom_arvalid,
    input  wire        rom_arready,
    input  wire [31:0] rom_rdata,
    input  wire [1:0]  rom_rresp,
    input  wire        rom_rvalid,
    output wire        rom_rready,

    // --- slave 1 : RAM -----------------------------------------------------
    output wire [31:0] ram_awaddr,
    output wire [2:0]  ram_awprot,
    output wire        ram_awvalid,
    input  wire        ram_awready,
    output wire [31:0] ram_wdata,
    output wire [3:0]  ram_wstrb,
    output wire        ram_wvalid,
    input  wire        ram_wready,
    input  wire [1:0]  ram_bresp,
    input  wire        ram_bvalid,
    output wire        ram_bready,
    output wire [31:0] ram_araddr,
    output wire [2:0]  ram_arprot,
    output wire        ram_arvalid,
    input  wire        ram_arready,
    input  wire [31:0] ram_rdata,
    input  wire [1:0]  ram_rresp,
    input  wire        ram_rvalid,
    output wire        ram_rready,

    // --- slave 2 : LED -----------------------------------------------------
    output wire [31:0] led_awaddr,
    output wire [2:0]  led_awprot,
    output wire        led_awvalid,
    input  wire        led_awready,
    output wire [31:0] led_wdata,
    output wire [3:0]  led_wstrb,
    output wire        led_wvalid,
    input  wire        led_wready,
    input  wire [1:0]  led_bresp,
    input  wire        led_bvalid,
    output wire        led_bready,
    output wire [31:0] led_araddr,
    output wire [2:0]  led_arprot,
    output wire        led_arvalid,
    input  wire        led_arready,
    input  wire [31:0] led_rdata,
    input  wire [1:0]  led_rresp,
    input  wire        led_rvalid,
    output wire        led_rready,

    // --- slave 3 : KEY -----------------------------------------------------
    output wire [31:0] key_awaddr,
    output wire [2:0]  key_awprot,
    output wire        key_awvalid,
    input  wire        key_awready,
    output wire [31:0] key_wdata,
    output wire [3:0]  key_wstrb,
    output wire        key_wvalid,
    input  wire        key_wready,
    input  wire [1:0]  key_bresp,
    input  wire        key_bvalid,
    output wire        key_bready,
    output wire [31:0] key_araddr,
    output wire [2:0]  key_arprot,
    output wire        key_arvalid,
    input  wire        key_arready,
    input  wire [31:0] key_rdata,
    input  wire [1:0]  key_rresp,
    input  wire        key_rvalid,
    output wire        key_rready,

    // --- slave 4 : CLINT ---------------------------------------------------
    output wire [31:0] clnt_awaddr,
    output wire [2:0]  clnt_awprot,
    output wire        clnt_awvalid,
    input  wire        clnt_awready,
    output wire [31:0] clnt_wdata,
    output wire [3:0]  clnt_wstrb,
    output wire        clnt_wvalid,
    input  wire        clnt_wready,
    input  wire [1:0]  clnt_bresp,
    input  wire        clnt_bvalid,
    output wire        clnt_bready,
    output wire [31:0] clnt_araddr,
    output wire [2:0]  clnt_arprot,
    output wire        clnt_arvalid,
    input  wire        clnt_arready,
    input  wire [31:0] clnt_rdata,
    input  wire [1:0]  clnt_rresp,
    input  wire        clnt_rvalid,
    output wire        clnt_rready,

    // --- slave 5 : UART ----------------------------------------------------
    output wire [31:0] uart_awaddr,
    output wire [2:0]  uart_awprot,
    output wire        uart_awvalid,
    input  wire        uart_awready,
    output wire [31:0] uart_wdata,
    output wire [3:0]  uart_wstrb,
    output wire        uart_wvalid,
    input  wire        uart_wready,
    input  wire [1:0]  uart_bresp,
    input  wire        uart_bvalid,
    output wire        uart_bready,
    output wire [31:0] uart_araddr,
    output wire [2:0]  uart_arprot,
    output wire        uart_arvalid,
    input  wire        uart_arready,
    input  wire [31:0] uart_rdata,
    input  wire [1:0]  uart_rresp,
    input  wire        uart_rvalid,
    output wire        uart_rready,

    // --- slave 6 : PLIC ----------------------------------------------------
    output wire [31:0] plic_awaddr,
    output wire [2:0]  plic_awprot,
    output wire        plic_awvalid,
    input  wire        plic_awready,
    output wire [31:0] plic_wdata,
    output wire [3:0]  plic_wstrb,
    output wire        plic_wvalid,
    input  wire        plic_wready,
    input  wire [1:0]  plic_bresp,
    input  wire        plic_bvalid,
    output wire        plic_bready,
    output wire [31:0] plic_araddr,
    output wire [2:0]  plic_arprot,
    output wire        plic_arvalid,
    input  wire        plic_arready,
    input  wire [31:0] plic_rdata,
    input  wire [1:0]  plic_rresp,
    input  wire        plic_rvalid,
    output wire        plic_rready
);

    localparam [1:0] RESP_SLVERR = 2'b10;
    localparam [1:0] RESP_DECERR = 2'b11;

    // -------------------------------------------------------------------------
    // Address decode (per-channel, purely combinational)
    // -------------------------------------------------------------------------
    function [6:0] decode;
        input [31:0] a;
        reg [6:0] d;
        begin
            d = 7'd0;
            if (a[31:28] == 4'h0)        d[0] = 1'b1;   // ROM
            else if (a[31:28] == 4'h2)   d[1] = 1'b1;   // RAM
            else if (a[31:24] == 8'h40)  d[2] = 1'b1;   // LED
            else if (a[31:24] == 8'h41)  d[3] = 1'b1;   // KEY
            else if (a[31:24] == 8'h42)  d[4] = 1'b1;   // CLINT
            else if (a[31:24] == 8'h43)  d[5] = 1'b1;   // UART
            else if (a[31:24] == 8'h44)  d[6] = 1'b1;   // PLIC
            decode = d;
        end
    endfunction

    wire [6:0] wr_sel_raw = decode(m_awaddr);
    wire [6:0] rd_sel     = decode(m_araddr);

    // Tier A #1: ROM (slave 0) is a read-only region.  Any write targeting
    // it is routed through the synthetic error path with BRESP=SLVERR so
    // software sees a Store Access Fault at WB instead of the previous
    // silent no-op.  (The ROM's AXI slave would otherwise accept the AW/W
    // and return OKAY, discarding the data - a typical bug in bring-up
    // code that previously produced no diagnostic at all.)  Real ROM reads
    // are still routed to the live slave.
    //
    // `wr_ro` is factored out both so the broadcast below can gate the
    // rom_awvalid / rom_wvalid lines off and so that the unmapped-path
    // state machine below can distinguish DECERR (truly unmapped) from
    // SLVERR (mapped-but-read-only) when it synthesises the B response.
    //
    // `wr_sel` is the write-path decode with the ROM slot forced low,
    // guaranteeing ROM writes never reach rom_{aw,w}valid.  Reads still
    // use the full `rd_sel` decode so ROM reads continue to hit the
    // live slave as before.
    wire       wr_ro   = wr_sel_raw[0];
    wire [6:0] wr_sel  = {wr_sel_raw[6:1], 1'b0};
    wire       wr_none = ~|wr_sel_raw;
    wire       rd_none = ~|rd_sel;

    // -------------------------------------------------------------------------
    // Synthetic error-slave state.  One cycle after an unmapped / read-only
    // AW/W (or an unmapped AR) handshake, we raise the matching B (or R)
    // valid with RESP=SLVERR (ROM write) or RESP=DECERR (truly unmapped) so
    // the master sees a proper response.  Held until the master accepts.
    //
    // `err_bresp_slv` captures the kind of write that triggered the
    // pending B: 1 = SLVERR (ROM write), 0 = DECERR (unmapped).  The two
    // fire modes are mutually exclusive on the same cycle.
    // -------------------------------------------------------------------------
    reg err_bvalid;
    reg err_bresp_slv;   // 1 = SLVERR, 0 = DECERR for the pending B response
    reg err_rvalid;

    wire wr_aw_fire_ro   = m_awvalid & m_wvalid & wr_ro;             // ROM write accepts AW+W same cycle
    wire wr_aw_fire_none = m_awvalid & m_wvalid & wr_none;           // unmapped write accepts AW+W same cycle
    wire err_aw_fire     = wr_aw_fire_ro | wr_aw_fire_none;
    wire err_ar_fire     = m_arvalid & rd_none;                      // unmapped read accepts AR

    always @(posedge aclk) begin
        if (!aresetn) begin
            err_bvalid    <= 1'b0;
            err_bresp_slv <= 1'b0;
            err_rvalid    <= 1'b0;
        end else begin
            if (err_bvalid & m_bready)
                err_bvalid <= 1'b0;
            else if (err_aw_fire & ~err_bvalid) begin
                err_bvalid    <= 1'b1;
                err_bresp_slv <= wr_aw_fire_ro;    // 1 = SLVERR (ROM), else DECERR
            end

            if (err_rvalid & m_rready)
                err_rvalid <= 1'b0;
            else if (err_ar_fire & ~err_rvalid)
                err_rvalid <= 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // Write address / data broadcast; valids are gated by the decode so only
    // the selected slave sees a request.
    // -------------------------------------------------------------------------
    assign rom_awaddr  = m_awaddr;  assign rom_awprot  = m_awprot;  assign rom_awvalid  = m_awvalid  & wr_sel[0];
    assign ram_awaddr  = m_awaddr;  assign ram_awprot  = m_awprot;  assign ram_awvalid  = m_awvalid  & wr_sel[1];
    assign led_awaddr  = m_awaddr;  assign led_awprot  = m_awprot;  assign led_awvalid  = m_awvalid  & wr_sel[2];
    assign key_awaddr  = m_awaddr;  assign key_awprot  = m_awprot;  assign key_awvalid  = m_awvalid  & wr_sel[3];
    assign clnt_awaddr = m_awaddr;  assign clnt_awprot = m_awprot;  assign clnt_awvalid = m_awvalid  & wr_sel[4];
    assign uart_awaddr = m_awaddr;  assign uart_awprot = m_awprot;  assign uart_awvalid = m_awvalid  & wr_sel[5];
    assign plic_awaddr = m_awaddr;  assign plic_awprot = m_awprot;  assign plic_awvalid = m_awvalid  & wr_sel[6];

    assign rom_wdata   = m_wdata;   assign rom_wstrb   = m_wstrb;   assign rom_wvalid   = m_wvalid   & wr_sel[0];
    assign ram_wdata   = m_wdata;   assign ram_wstrb   = m_wstrb;   assign ram_wvalid   = m_wvalid   & wr_sel[1];
    assign led_wdata   = m_wdata;   assign led_wstrb   = m_wstrb;   assign led_wvalid   = m_wvalid   & wr_sel[2];
    assign key_wdata   = m_wdata;   assign key_wstrb   = m_wstrb;   assign key_wvalid   = m_wvalid   & wr_sel[3];
    assign clnt_wdata  = m_wdata;   assign clnt_wstrb  = m_wstrb;   assign clnt_wvalid  = m_wvalid   & wr_sel[4];
    assign uart_wdata  = m_wdata;   assign uart_wstrb  = m_wstrb;   assign uart_wvalid  = m_wvalid   & wr_sel[5];
    assign plic_wdata  = m_wdata;   assign plic_wstrb  = m_wstrb;   assign plic_wvalid  = m_wvalid   & wr_sel[6];

    // Ready back to the master: unmapped / ROM-write addresses acknowledge
    // AW/W immediately (ungated by err_bvalid so the phases can begin; the
    // B phase below is what latches the SLVERR/DECERR pending flag and
    // stalls the master until B).
    wire wr_use_err = wr_none | wr_ro;

    assign m_awready = wr_use_err ? ~err_bvalid :
                       (wr_sel[1] & ram_awready) |
                       (wr_sel[2] & led_awready) |
                       (wr_sel[3] & key_awready) |
                       (wr_sel[4] & clnt_awready) |
                       (wr_sel[5] & uart_awready) |
                       (wr_sel[6] & plic_awready);

    assign m_wready  = wr_use_err ? ~err_bvalid :
                       (wr_sel[1] & ram_wready) |
                       (wr_sel[2] & led_wready) |
                       (wr_sel[3] & key_wready) |
                       (wr_sel[4] & clnt_wready) |
                       (wr_sel[5] & uart_wready) |
                       (wr_sel[6] & plic_wready);

    // -------------------------------------------------------------------------
    // B response: OR-mux across real slaves plus the synthetic DECERR source.
    // wr_none guarantees no real slave raises bvalid while err_bvalid is live,
    // so the two paths never collide on the same cycle.
    // -------------------------------------------------------------------------
    assign m_bvalid  = err_bvalid                     |
                       (wr_sel[1] & ram_bvalid)       |
                       (wr_sel[2] & led_bvalid)       |
                       (wr_sel[3] & key_bvalid)       |
                       (wr_sel[4] & clnt_bvalid)      |
                       (wr_sel[5] & uart_bvalid)      |
                       (wr_sel[6] & plic_bvalid);

    assign m_bresp   = err_bvalid                       ?
                         (err_bresp_slv ? RESP_SLVERR : RESP_DECERR) :
                       (({2{wr_sel[1]}} & ram_bresp)  |
                        ({2{wr_sel[2]}} & led_bresp)  |
                        ({2{wr_sel[3]}} & key_bresp)  |
                        ({2{wr_sel[4]}} & clnt_bresp) |
                        ({2{wr_sel[5]}} & uart_bresp) |
                        ({2{wr_sel[6]}} & plic_bresp));

    assign rom_bready  = m_bready & wr_sel[0];
    assign ram_bready  = m_bready & wr_sel[1];
    assign led_bready  = m_bready & wr_sel[2];
    assign key_bready  = m_bready & wr_sel[3];
    assign clnt_bready = m_bready & wr_sel[4];
    assign uart_bready = m_bready & wr_sel[5];
    assign plic_bready = m_bready & wr_sel[6];

    // -------------------------------------------------------------------------
    // Read address broadcast
    // -------------------------------------------------------------------------
    assign rom_araddr  = m_araddr;  assign rom_arprot  = m_arprot;  assign rom_arvalid  = m_arvalid  & rd_sel[0];
    assign ram_araddr  = m_araddr;  assign ram_arprot  = m_arprot;  assign ram_arvalid  = m_arvalid  & rd_sel[1];
    assign led_araddr  = m_araddr;  assign led_arprot  = m_arprot;  assign led_arvalid  = m_arvalid  & rd_sel[2];
    assign key_araddr  = m_araddr;  assign key_arprot  = m_arprot;  assign key_arvalid  = m_arvalid  & rd_sel[3];
    assign clnt_araddr = m_araddr;  assign clnt_arprot = m_arprot;  assign clnt_arvalid = m_arvalid  & rd_sel[4];
    assign uart_araddr = m_araddr;  assign uart_arprot = m_arprot;  assign uart_arvalid = m_arvalid  & rd_sel[5];
    assign plic_araddr = m_araddr;  assign plic_arprot = m_arprot;  assign plic_arvalid = m_arvalid  & rd_sel[6];

    assign m_arready = rd_none ? ~err_rvalid :
                       (rd_sel[0] & rom_arready) |
                       (rd_sel[1] & ram_arready) |
                       (rd_sel[2] & led_arready) |
                       (rd_sel[3] & key_arready) |
                       (rd_sel[4] & clnt_arready) |
                       (rd_sel[5] & uart_arready) |
                       (rd_sel[6] & plic_arready);

    assign m_rvalid  = err_rvalid                 |
                       (rd_sel[0] & rom_rvalid)   |
                       (rd_sel[1] & ram_rvalid)   |
                       (rd_sel[2] & led_rvalid)   |
                       (rd_sel[3] & key_rvalid)   |
                       (rd_sel[4] & clnt_rvalid)  |
                       (rd_sel[5] & uart_rvalid)  |
                       (rd_sel[6] & plic_rvalid);

    assign m_rdata   = err_rvalid ? 32'h0000_0000 :
                       (({32{rd_sel[0]}} & rom_rdata)  |
                        ({32{rd_sel[1]}} & ram_rdata)  |
                        ({32{rd_sel[2]}} & led_rdata)  |
                        ({32{rd_sel[3]}} & key_rdata)  |
                        ({32{rd_sel[4]}} & clnt_rdata) |
                        ({32{rd_sel[5]}} & uart_rdata) |
                        ({32{rd_sel[6]}} & plic_rdata));

    assign m_rresp   = err_rvalid ? RESP_DECERR :
                       (({2{rd_sel[0]}} & rom_rresp)  |
                        ({2{rd_sel[1]}} & ram_rresp)  |
                        ({2{rd_sel[2]}} & led_rresp)  |
                        ({2{rd_sel[3]}} & key_rresp)  |
                        ({2{rd_sel[4]}} & clnt_rresp) |
                        ({2{rd_sel[5]}} & uart_rresp) |
                        ({2{rd_sel[6]}} & plic_rresp));

    assign rom_rready  = m_rready & rd_sel[0];
    assign ram_rready  = m_rready & rd_sel[1];
    assign led_rready  = m_rready & rd_sel[2];
    assign key_rready  = m_rready & rd_sel[3];
    assign clnt_rready = m_rready & rd_sel[4];
    assign uart_rready = m_rready & rd_sel[5];
    assign plic_rready = m_rready & rd_sel[6];

endmodule
