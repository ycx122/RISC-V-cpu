`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// cpu_soc - top-level SoC integration.
//
// 2026-04 refactor (Tier 4.1 of PROCESSOR_IMPROVEMENT_PLAN):
//
//   The previous generation used a custom `riscv_bus` two-phase
//   handshake + a one-hot `addr2c` address decoder.  Both have been
//   retired; the SoC now uses a standard AXI4-Lite interconnect:
//
//     cpu_jh  ->  axil_master_bridge  ->  axil_interconnect  ->  { 6 slaves }
//
//   * axil_master_bridge converts the CPU's legacy
//     `{d_bus_en / ram_we / ram_re / mem_op}` shape into aligned
//     AXI4-Lite AW/W/B/AR/R transactions and handles byte-lane
//     steering + sign-extension for loads.
//   * axil_slave_wrapper is a reusable shim: AXI4-Lite slave port
//     -> simple `{dev_en / dev_we / dev_re / dev_addr / dev_wdata /
//     dev_wstrb / dev_rdata / dev_ready}` handshake that the
//     existing slave modules consume.  No slave module has to know
//     anything about AXI itself.
//
//   The crossbar decodes on the full address and routes to the six
//   slaves fixed below.  Software memory map is unchanged:
//
//     0x0000_0000 - 0x0FFF_FFFF : boot ROM  (rodata + i_rom)
//     0x2000_0000 - 0x2FFF_FFFF : data RAM  (ram_c)
//     0x4000_0000 - 0x40FF_FFFF : LED
//     0x4100_0000 - 0x41FF_FFFF : KEY
//     0x4200_0000 - 0x42FF_FFFF : CLINT  (SiFive layout: msip@+0x0000,
//                                         mtimecmp@+0x4000, mtime@+0xBFF8)
//     0x4300_0000 - 0x43FF_FFFF : UART16550-ish
//     0x4400_0000 - 0x44FF_FFFF : PLIC   (SiFive layout: prio@+0x0000,
//                                         pending@+0x1000, enable@+0x2000,
//                                         threshold@+0x200000,
//                                         claim/complete@+0x200004)
//
//   Any Xilinx AXI4-Lite peripheral (MIG's AXI-Lite facade, axi_uart16550,
//   axi_qspi, axi_dma's config port, ...) can now be bolted onto the
//   crossbar by adding a decode entry and a slave port.
//
// 2026-04 follow-up (Tier 4 / item 4 step A of PROCESSOR_IMPROVEMENT_PLAN):
//
//   Instruction fetch now also goes through AXI4-Lite by default.  The
//   CPU's existing fetch handshake {i_bus_en, pc_addr_out, i_data_in,
//   i_bus_ready} is bridged to a dedicated, read-only AXI4-Lite master
//   which talks to a private slave wrapper in front of ram_c's i_rom
//   port B:
//
//     cpu_jh.pc_addr_out  ->  axil_ifetch_bridge  (AR/R only)
//        ^                               |
//        |                               v
//        +--  i_data_in <--  axil_slave_wrapper  ->  ram_c (i_rom port B)
//
//   The fetch path is on its own link (not routed through the data-side
//   1->6 interconnect) so the data-side timing is unchanged bit-for-bit.
//   A later step will merge the two masters through a 2->N crossbar so
//   the CPU can also fetch from DDR / RAM / any AXI-Lite memory.
//
//   Compile-time fallback: passing `-DTCM_IFETCH` (iverilog/verilator
//   +define+TCM_IFETCH) restores the legacy direct-connect path where
//   pc_addr_out drives ram_c.i_addr combinationally and i_bus_ready is
//   hard-tied high (1-cycle BRAM port-B read).  The build flag exists
//   as an FPGA resource-squeeze escape hatch and as an A/B regression
//   switch while the AXI fetch path matures.
// -----------------------------------------------------------------------------
module cpu_soc (
    input              clk,
    input              rst_n,

    input              e_inter,

    input      [7:0]   key,
    output reg [15:0]  led,

    input              uart_rxd,       // UART RX
    output             uart_txd,       // UART TX
    input              down_load_key   // 0 = download mode, 1 = execute mode
);

    // -------------------------------------------------------------------------
    // Clocking.  clk_wiz_0 is a Vivado PLL on hardware; in simulation the
    // compat stub passes the 50 MHz clk through unchanged (see
    // sim/models/xilinx_compat.v).  Treat `cpu_clk` as the single AXI-Lite
    // domain throughout the SoC; `ram_clk` was only ever a duplicate and is
    // tied to the same source.
    // -------------------------------------------------------------------------
    wire cpu_clk;
    wire ram_clk;

    clk_wiz_0 clk_pll (
        .clk_in1 (clk),
        .clk_out1(cpu_clk),
        .clk_out2(ram_clk),
        .clk_out3(),
        .clk_out4(),
        .locked  ()
    );

    // -------------------------------------------------------------------------
    // CPU legacy bus + bridge.
    // -------------------------------------------------------------------------
    wire [31:0] d_addr;
    wire [31:0] d_data_in;     // load data into CPU (post-extraction)
    wire [31:0] d_data_out;    // store data from CPU (pre-lane shift)
    wire [2:0]  d_mem_op_in;
    wire        d_bus_en;
    wire        d_bus_ready;
    wire        d_bus_err;       // 1-cycle pulse w/ d_bus_ready: AXI SLVERR/DECERR
    wire        d_bus_misalign;  // 1-cycle pulse w/ d_bus_ready: misaligned load/store (Tier A #2)
    wire        d_ram_we;
    wire        d_ram_re;

    wire        i_bus_en;
    wire [31:0] pc_addr_out;

    // Instruction fetch feeds into cpu_jh.{i_data_in, i_bus_ready}; the
    // sources differ between TCM_IFETCH (hardwired to ram_c's combinational
    // i_data + ready=1) and the AXI4-Lite fetch bridge (both come from
    // u_axil_ifetch).  See the `ifdef TCM_IFETCH block further down.
    wire [31:0] ifetch_i_data;
    wire        ifetch_i_ready;

    // Muxed instruction-side port onto ram_c (i_rom port B).  In TCM mode
    // these are driven directly by the CPU; in AXI mode they are driven by
    // the ifetch slave wrapper so the BRAM read is transacted over AXI4-Lite.
    wire        ram_i_en;
    wire [31:0] ram_i_addr;
    wire [31:0] ram_i_data;

    // Interrupt synchroniser.  `e_inter` is the active-low external
    // interrupt pin (board button / external source pulls it low).  Invert
    // and double-flop onto cpu_clk to get a clean level-sensitive request
    // line that is then fed to the PLIC as source #1; the PLIC performs
    // enable/priority/threshold arbitration and drives meip into the core.
    reg eirq_sync0, eirq_sync1;
    always @(posedge cpu_clk) begin
        if (rst_n == 1'b0) begin
            eirq_sync0 <= 1'b0;
            eirq_sync1 <= 1'b0;
        end else begin
            eirq_sync0 <= ~e_inter;
            eirq_sync1 <=  eirq_sync0;
        end
    end
    wire ext_irq_level = eirq_sync1;     // PLIC source 1

    // Driven by the CLINT and PLIC instances below.
    wire time_e_inter;
    wire msip_level;
    wire meip_level;          // from PLIC (any enabled source > threshold)
    wire mtip_level = time_e_inter;

    // fence.i invalidate pulse from the pipeline.  Connected to the
    // I-Cache's `flush` input when the default (cached) instruction path
    // is compiled in; harmlessly absorbed in the TCM_IFETCH / ICACHE_DISABLE
    // branches below.
    wire flush_icache;

    cpu_jh a1 (
        .clk        (cpu_clk),
        .cpu_rst    (rst_n & down_load_key),
        .bus_data_in(d_data_in),
        .d_bus_ready   (d_bus_ready),
        .d_bus_err     (d_bus_err),
        .d_bus_misalign(d_bus_misalign),
        .i_bus_ready   (ifetch_i_ready),
        .i_data_in  (ifetch_i_data),
        .pc_set_en  (1'b0),
        .pc_set_data(32'd0),
        .mtip       (mtip_level),
        .meip       (meip_level),
        .msip       (msip_level),

        .data_addr_out(d_addr),
        .d_data_out   (d_data_out),
        .d_bus_en     (d_bus_en),
        .i_bus_en     (i_bus_en),
        .pc_addr_out  (pc_addr_out),
        .ram_we       (d_ram_we),
        .ram_re       (d_ram_re),
        .mem_op_out   (d_mem_op_in),
        .flush_icache (flush_icache)
    );

    // -------------------------------------------------------------------------
    // AXI4-Lite master from the CPU
    // -------------------------------------------------------------------------
    wire [31:0] m_awaddr;
    wire [2:0]  m_awprot;
    wire        m_awvalid, m_awready;
    wire [31:0] m_wdata;
    wire [3:0]  m_wstrb;
    wire        m_wvalid, m_wready;
    wire [1:0]  m_bresp;
    wire        m_bvalid, m_bready;
    wire [31:0] m_araddr;
    wire [2:0]  m_arprot;
    wire        m_arvalid, m_arready;
    wire [31:0] m_rdata;
    wire [1:0]  m_rresp;
    wire        m_rvalid, m_rready;

    axil_master_bridge u_axil_master (
        .aclk       (cpu_clk),
        .aresetn    (rst_n),

        .d_bus_en   (d_bus_en),
        .ram_we     (d_ram_we),
        .ram_re     (d_ram_re),
        .d_addr     (d_addr),
        .d_data_out (d_data_out),
        .mem_op     (d_mem_op_in),
        .bus_data_in   (d_data_in),
        .d_bus_ready   (d_bus_ready),
        .d_bus_err     (d_bus_err),
        .d_bus_misalign(d_bus_misalign),

        .m_awvalid  (m_awvalid),
        .m_awready  (m_awready),
        .m_awaddr   (m_awaddr),
        .m_awprot   (m_awprot),

        .m_wvalid   (m_wvalid),
        .m_wready   (m_wready),
        .m_wdata    (m_wdata),
        .m_wstrb    (m_wstrb),

        .m_bvalid   (m_bvalid),
        .m_bready   (m_bready),
        .m_bresp    (m_bresp),

        .m_arvalid  (m_arvalid),
        .m_arready  (m_arready),
        .m_araddr   (m_araddr),
        .m_arprot   (m_arprot),

        .m_rvalid   (m_rvalid),
        .m_rready   (m_rready),
        .m_rdata    (m_rdata),
        .m_rresp    (m_rresp)
    );

    // -------------------------------------------------------------------------
    // Per-slave AXI4-Lite ports (to/from the crossbar)
    // -------------------------------------------------------------------------
    `define AXIL_SLAVE_SIG(name) \
        wire [31:0] name``_awaddr; wire [2:0] name``_awprot; wire name``_awvalid; wire name``_awready; \
        wire [31:0] name``_wdata;  wire [3:0] name``_wstrb;  wire name``_wvalid;  wire name``_wready;  \
        wire [1:0]  name``_bresp;  wire name``_bvalid;  wire name``_bready;                            \
        wire [31:0] name``_araddr; wire [2:0] name``_arprot; wire name``_arvalid; wire name``_arready; \
        wire [31:0] name``_rdata;  wire [1:0] name``_rresp;  wire name``_rvalid;  wire name``_rready

    `AXIL_SLAVE_SIG(rom_s);
    `AXIL_SLAVE_SIG(ram_s);
    `AXIL_SLAVE_SIG(led_s);
    `AXIL_SLAVE_SIG(key_s);
    `AXIL_SLAVE_SIG(clnt_s);
    `AXIL_SLAVE_SIG(uart_s);
    `AXIL_SLAVE_SIG(plic_s);

    `undef AXIL_SLAVE_SIG

    axil_interconnect u_axil_xbar (
        .aclk     (cpu_clk),  .aresetn  (rst_n),

        .m_awaddr (m_awaddr), .m_awprot (m_awprot), .m_awvalid (m_awvalid), .m_awready (m_awready),
        .m_wdata  (m_wdata),  .m_wstrb  (m_wstrb),  .m_wvalid  (m_wvalid),  .m_wready  (m_wready),
        .m_bresp  (m_bresp),  .m_bvalid (m_bvalid), .m_bready  (m_bready),
        .m_araddr (m_araddr), .m_arprot (m_arprot), .m_arvalid (m_arvalid), .m_arready (m_arready),
        .m_rdata  (m_rdata),  .m_rresp  (m_rresp),  .m_rvalid  (m_rvalid),  .m_rready  (m_rready),

        .rom_awaddr(rom_s_awaddr), .rom_awprot(rom_s_awprot), .rom_awvalid(rom_s_awvalid), .rom_awready(rom_s_awready),
        .rom_wdata (rom_s_wdata),  .rom_wstrb (rom_s_wstrb),  .rom_wvalid (rom_s_wvalid),  .rom_wready (rom_s_wready),
        .rom_bresp (rom_s_bresp),  .rom_bvalid(rom_s_bvalid), .rom_bready (rom_s_bready),
        .rom_araddr(rom_s_araddr), .rom_arprot(rom_s_arprot), .rom_arvalid(rom_s_arvalid), .rom_arready(rom_s_arready),
        .rom_rdata (rom_s_rdata),  .rom_rresp (rom_s_rresp),  .rom_rvalid (rom_s_rvalid),  .rom_rready (rom_s_rready),

        .ram_awaddr(ram_s_awaddr), .ram_awprot(ram_s_awprot), .ram_awvalid(ram_s_awvalid), .ram_awready(ram_s_awready),
        .ram_wdata (ram_s_wdata),  .ram_wstrb (ram_s_wstrb),  .ram_wvalid (ram_s_wvalid),  .ram_wready (ram_s_wready),
        .ram_bresp (ram_s_bresp),  .ram_bvalid(ram_s_bvalid), .ram_bready (ram_s_bready),
        .ram_araddr(ram_s_araddr), .ram_arprot(ram_s_arprot), .ram_arvalid(ram_s_arvalid), .ram_arready(ram_s_arready),
        .ram_rdata (ram_s_rdata),  .ram_rresp (ram_s_rresp),  .ram_rvalid (ram_s_rvalid),  .ram_rready (ram_s_rready),

        .led_awaddr(led_s_awaddr), .led_awprot(led_s_awprot), .led_awvalid(led_s_awvalid), .led_awready(led_s_awready),
        .led_wdata (led_s_wdata),  .led_wstrb (led_s_wstrb),  .led_wvalid (led_s_wvalid),  .led_wready (led_s_wready),
        .led_bresp (led_s_bresp),  .led_bvalid(led_s_bvalid), .led_bready (led_s_bready),
        .led_araddr(led_s_araddr), .led_arprot(led_s_arprot), .led_arvalid(led_s_arvalid), .led_arready(led_s_arready),
        .led_rdata (led_s_rdata),  .led_rresp (led_s_rresp),  .led_rvalid (led_s_rvalid),  .led_rready (led_s_rready),

        .key_awaddr(key_s_awaddr), .key_awprot(key_s_awprot), .key_awvalid(key_s_awvalid), .key_awready(key_s_awready),
        .key_wdata (key_s_wdata),  .key_wstrb (key_s_wstrb),  .key_wvalid (key_s_wvalid),  .key_wready (key_s_wready),
        .key_bresp (key_s_bresp),  .key_bvalid(key_s_bvalid), .key_bready (key_s_bready),
        .key_araddr(key_s_araddr), .key_arprot(key_s_arprot), .key_arvalid(key_s_arvalid), .key_arready(key_s_arready),
        .key_rdata (key_s_rdata),  .key_rresp (key_s_rresp),  .key_rvalid (key_s_rvalid),  .key_rready (key_s_rready),

        .clnt_awaddr(clnt_s_awaddr), .clnt_awprot(clnt_s_awprot), .clnt_awvalid(clnt_s_awvalid), .clnt_awready(clnt_s_awready),
        .clnt_wdata (clnt_s_wdata),  .clnt_wstrb (clnt_s_wstrb),  .clnt_wvalid (clnt_s_wvalid),  .clnt_wready (clnt_s_wready),
        .clnt_bresp (clnt_s_bresp),  .clnt_bvalid(clnt_s_bvalid), .clnt_bready (clnt_s_bready),
        .clnt_araddr(clnt_s_araddr), .clnt_arprot(clnt_s_arprot), .clnt_arvalid(clnt_s_arvalid), .clnt_arready(clnt_s_arready),
        .clnt_rdata (clnt_s_rdata),  .clnt_rresp (clnt_s_rresp),  .clnt_rvalid (clnt_s_rvalid),  .clnt_rready (clnt_s_rready),

        .uart_awaddr(uart_s_awaddr), .uart_awprot(uart_s_awprot), .uart_awvalid(uart_s_awvalid), .uart_awready(uart_s_awready),
        .uart_wdata (uart_s_wdata),  .uart_wstrb (uart_s_wstrb),  .uart_wvalid (uart_s_wvalid),  .uart_wready (uart_s_wready),
        .uart_bresp (uart_s_bresp),  .uart_bvalid(uart_s_bvalid), .uart_bready (uart_s_bready),
        .uart_araddr(uart_s_araddr), .uart_arprot(uart_s_arprot), .uart_arvalid(uart_s_arvalid), .uart_arready(uart_s_arready),
        .uart_rdata (uart_s_rdata),  .uart_rresp (uart_s_rresp),  .uart_rvalid (uart_s_rvalid),  .uart_rready (uart_s_rready),

        .plic_awaddr(plic_s_awaddr), .plic_awprot(plic_s_awprot), .plic_awvalid(plic_s_awvalid), .plic_awready(plic_s_awready),
        .plic_wdata (plic_s_wdata),  .plic_wstrb (plic_s_wstrb),  .plic_wvalid (plic_s_wvalid),  .plic_wready (plic_s_wready),
        .plic_bresp (plic_s_bresp),  .plic_bvalid(plic_s_bvalid), .plic_bready (plic_s_bready),
        .plic_araddr(plic_s_araddr), .plic_arprot(plic_s_arprot), .plic_arvalid(plic_s_arvalid), .plic_arready(plic_s_arready),
        .plic_rdata (plic_s_rdata),  .plic_rresp (plic_s_rresp),  .plic_rvalid (plic_s_rvalid),  .plic_rready (plic_s_rready)
    );

    // -------------------------------------------------------------------------
    // Slave 0 : boot ROM (rodata sequencer behind i_rom port A)
    // -------------------------------------------------------------------------
    wire        rom_dev_en;
    wire        rom_dev_we;
    wire        rom_dev_re;
    wire [31:0] rom_dev_addr;
    wire [31:0] rom_dev_wdata;
    wire [3:0]  rom_dev_wstrb;
    wire [31:0] rom_dev_rdata;
    wire        rom_dev_ready;

    axil_slave_wrapper u_rom_wrap (
        .aclk    (cpu_clk),   .aresetn(rst_n),
        .s_awaddr(rom_s_awaddr), .s_awprot(rom_s_awprot), .s_awvalid(rom_s_awvalid), .s_awready(rom_s_awready),
        .s_wdata (rom_s_wdata),  .s_wstrb (rom_s_wstrb),  .s_wvalid (rom_s_wvalid),  .s_wready (rom_s_wready),
        .s_bresp (rom_s_bresp),  .s_bvalid(rom_s_bvalid), .s_bready (rom_s_bready),
        .s_araddr(rom_s_araddr), .s_arprot(rom_s_arprot), .s_arvalid(rom_s_arvalid), .s_arready(rom_s_arready),
        .s_rdata (rom_s_rdata),  .s_rresp (rom_s_rresp),  .s_rvalid (rom_s_rvalid),  .s_rready (rom_s_rready),

        .dev_en   (rom_dev_en),
        .dev_we   (rom_dev_we),
        .dev_re   (rom_dev_re),
        .dev_addr (rom_dev_addr),
        .dev_wdata(rom_dev_wdata),
        .dev_wstrb(rom_dev_wstrb),
        .dev_rdata(rom_dev_rdata),
        .dev_ready(rom_dev_ready)
    );

    // ROM is read-only; writes silently complete in 0 cycles (slave wrapper
    // raises BRESP=OKAY for us).  Feed rodata's read handshake.
    //
    // Since Tier 4.2 rodata uses i_rom port A as a 32-bit read port
    // (14-bit word address + 32-bit data), with the byte-strobe write
    // side owned exclusively by the UART download path inside ram_c.
    wire [13:0] rom_addr_word;
    wire        rom_r_en;
    wire [31:0] rom_data_word;
    wire [31:0] rom_dev_word;
    wire        rom_dev_word_ready;

    rodata u_rodata (
        .clk        (cpu_clk),
        .rst_n      (rst_n),
        .rom_en     (rom_dev_en),
        .re         (rom_dev_re),
        .addr       (rom_dev_addr),
        .reg_data   (rom_dev_word),
        .rom_r_ready(rom_dev_word_ready),
        .rom_addr   (rom_addr_word),
        .rom_r_en   (rom_r_en),
        .rom_data   (rom_data_word)
    );

    // For ROM writes from software (e.g. self-modifying code): not supported
    // by this physical ROM; we pretend the write completed so the CPU makes
    // forward progress rather than hanging.  Fence_i / self-modifying-code
    // tests still skip (matches PROCESSOR_IMPROVEMENT_PLAN.md).
    assign rom_dev_rdata = rom_dev_word;
    assign rom_dev_ready = rom_dev_we ? 1'b1 : rom_dev_word_ready;

    // -------------------------------------------------------------------------
    // Slave 1 : data RAM (ram_c)
    // -------------------------------------------------------------------------
    wire        ram_dev_en;
    wire        ram_dev_we;
    wire        ram_dev_re;
    wire [31:0] ram_dev_addr;
    wire [31:0] ram_dev_wdata;
    wire [3:0]  ram_dev_wstrb;
    wire [31:0] ram_dev_rdata;
    wire        ram_dev_ready;

    axil_slave_wrapper u_ram_wrap (
        .aclk    (cpu_clk),   .aresetn(rst_n),
        .s_awaddr(ram_s_awaddr), .s_awprot(ram_s_awprot), .s_awvalid(ram_s_awvalid), .s_awready(ram_s_awready),
        .s_wdata (ram_s_wdata),  .s_wstrb (ram_s_wstrb),  .s_wvalid (ram_s_wvalid),  .s_wready (ram_s_wready),
        .s_bresp (ram_s_bresp),  .s_bvalid(ram_s_bvalid), .s_bready (ram_s_bready),
        .s_araddr(ram_s_araddr), .s_arprot(ram_s_arprot), .s_arvalid(ram_s_arvalid), .s_arready(ram_s_arready),
        .s_rdata (ram_s_rdata),  .s_rresp (ram_s_rresp),  .s_rvalid (ram_s_rvalid),  .s_rready (ram_s_rready),

        .dev_en   (ram_dev_en),
        .dev_we   (ram_dev_we),
        .dev_re   (ram_dev_re),
        .dev_addr (ram_dev_addr),
        .dev_wdata(ram_dev_wdata),
        .dev_wstrb(ram_dev_wstrb),
        .dev_rdata(ram_dev_rdata),
        .dev_ready(ram_dev_ready)
    );

    // Multiplex UART RX/TX between boot download mode and the normal MMIO
    // UART.  Only one of the two consumes the physical UART at a time.
    wire uart_ctr_tx;
    wire uart_rom_tx;
    wire uart_rxd_ctr = (down_load_key == 1'b1) ? uart_rxd : 1'b1;
    wire uart_rxd_rom = (down_load_key == 1'b0) ? uart_rxd : 1'b1;
    assign uart_txd = down_load_key ? uart_ctr_tx : uart_rom_tx;

    // NOTE: the b1 instance name is load-bearing (cpu_test.v reaches through
    // `uu1.b1.d_ram_1.u_ram._ram[...]` to preload the RAM via +DRAM).
    ram_c b1 (
        .clk          (ram_clk),
        .i_en         (ram_i_en),
        .d_en         (ram_dev_en),
        .we           (ram_dev_we),
        .re           (ram_dev_re),
        // ram_c is rebased to start at address 0 inside the 0x2000_0000 window.
        .d_addr       (ram_dev_addr - 32'h2000_0000),
        .d_wdata      (ram_dev_wdata),
        .d_wstrb      (ram_dev_wstrb),
        .d_rdata      (ram_dev_rdata),
        .d_ready      (ram_dev_ready),

        .i_addr       (ram_i_addr),
        .i_data       (ram_i_data),

        .cpu_clk      (cpu_clk),
        .rom_addr     (rom_addr_word),
        .rom_r_en     (rom_r_en),
        .rom_data     (rom_data_word),

        .rst_n        (rst_n),
        .down_load_key(~down_load_key),
        .uart_rxd     (uart_rxd_rom),
        .uart_txd     (uart_rom_tx)
    );

    // -------------------------------------------------------------------------
    // Slave 2 : LED (write-only 16-bit output register at offset 0)
    // -------------------------------------------------------------------------
    wire        led_dev_en;
    wire        led_dev_we;
    wire        led_dev_re;
    wire [31:0] led_dev_addr;
    wire [31:0] led_dev_wdata;
    wire [3:0]  led_dev_wstrb;
    wire [31:0] led_dev_rdata;
    wire        led_dev_ready;

    axil_slave_wrapper u_led_wrap (
        .aclk    (cpu_clk),   .aresetn(rst_n),
        .s_awaddr(led_s_awaddr), .s_awprot(led_s_awprot), .s_awvalid(led_s_awvalid), .s_awready(led_s_awready),
        .s_wdata (led_s_wdata),  .s_wstrb (led_s_wstrb),  .s_wvalid (led_s_wvalid),  .s_wready (led_s_wready),
        .s_bresp (led_s_bresp),  .s_bvalid(led_s_bvalid), .s_bready (led_s_bready),
        .s_araddr(led_s_araddr), .s_arprot(led_s_arprot), .s_arvalid(led_s_arvalid), .s_arready(led_s_arready),
        .s_rdata (led_s_rdata),  .s_rresp (led_s_rresp),  .s_rvalid (led_s_rvalid),  .s_rready (led_s_rready),

        .dev_en   (led_dev_en),
        .dev_we   (led_dev_we),
        .dev_re   (led_dev_re),
        .dev_addr (led_dev_addr),
        .dev_wdata(led_dev_wdata),
        .dev_wstrb(led_dev_wstrb),
        .dev_rdata(led_dev_rdata),
        .dev_ready(led_dev_ready)
    );

    always @(posedge cpu_clk) begin
        if (rst_n == 1'b0)
            led <= 16'd0;
        else if (led_dev_en & led_dev_we) begin
            // Honour WSTRB so byte-wise accesses work too.
            if (led_dev_wstrb[0]) led[7:0]  <= led_dev_wdata[7:0];
            if (led_dev_wstrb[1]) led[15:8] <= led_dev_wdata[15:8];
        end
    end

    assign led_dev_rdata = {16'd0, led};
    assign led_dev_ready = led_dev_en & (led_dev_we | led_dev_re);

    // -------------------------------------------------------------------------
    // Slave 3 : KEY (read-only 8-bit input register at offset 0)
    // -------------------------------------------------------------------------
    wire        key_dev_en;
    wire        key_dev_we;
    wire        key_dev_re;
    wire [31:0] key_dev_addr;
    wire [31:0] key_dev_wdata;
    wire [3:0]  key_dev_wstrb;
    wire [31:0] key_dev_rdata;
    wire        key_dev_ready;

    axil_slave_wrapper u_key_wrap (
        .aclk    (cpu_clk),   .aresetn(rst_n),
        .s_awaddr(key_s_awaddr), .s_awprot(key_s_awprot), .s_awvalid(key_s_awvalid), .s_awready(key_s_awready),
        .s_wdata (key_s_wdata),  .s_wstrb (key_s_wstrb),  .s_wvalid (key_s_wvalid),  .s_wready (key_s_wready),
        .s_bresp (key_s_bresp),  .s_bvalid(key_s_bvalid), .s_bready (key_s_bready),
        .s_araddr(key_s_araddr), .s_arprot(key_s_arprot), .s_arvalid(key_s_arvalid), .s_arready(key_s_arready),
        .s_rdata (key_s_rdata),  .s_rresp (key_s_rresp),  .s_rvalid (key_s_rvalid),  .s_rready (key_s_rready),

        .dev_en   (key_dev_en),
        .dev_we   (key_dev_we),
        .dev_re   (key_dev_re),
        .dev_addr (key_dev_addr),
        .dev_wdata(key_dev_wdata),
        .dev_wstrb(key_dev_wstrb),
        .dev_rdata(key_dev_rdata),
        .dev_ready(key_dev_ready)
    );

    assign key_dev_rdata = {24'd0, key};
    assign key_dev_ready = key_dev_en;

    // -------------------------------------------------------------------------
    // Slave 4 : CLINT (timer)
    // -------------------------------------------------------------------------
    wire        clnt_dev_en;
    wire        clnt_dev_we;
    wire        clnt_dev_re;
    wire [31:0] clnt_dev_addr;
    wire [31:0] clnt_dev_wdata;
    wire [3:0]  clnt_dev_wstrb;
    wire [31:0] clnt_dev_rdata;
    wire        clnt_dev_ready;

    axil_slave_wrapper u_clnt_wrap (
        .aclk    (cpu_clk),   .aresetn(rst_n),
        .s_awaddr(clnt_s_awaddr), .s_awprot(clnt_s_awprot), .s_awvalid(clnt_s_awvalid), .s_awready(clnt_s_awready),
        .s_wdata (clnt_s_wdata),  .s_wstrb (clnt_s_wstrb),  .s_wvalid (clnt_s_wvalid),  .s_wready (clnt_s_wready),
        .s_bresp (clnt_s_bresp),  .s_bvalid(clnt_s_bvalid), .s_bready (clnt_s_bready),
        .s_araddr(clnt_s_araddr), .s_arprot(clnt_s_arprot), .s_arvalid(clnt_s_arvalid), .s_arready(clnt_s_arready),
        .s_rdata (clnt_s_rdata),  .s_rresp (clnt_s_rresp),  .s_rvalid (clnt_s_rvalid),  .s_rready (clnt_s_rready),

        .dev_en   (clnt_dev_en),
        .dev_we   (clnt_dev_we),
        .dev_re   (clnt_dev_re),
        .dev_addr (clnt_dev_addr),
        .dev_wdata(clnt_dev_wdata),
        .dev_wstrb(clnt_dev_wstrb),
        .dev_rdata(clnt_dev_rdata),
        .dev_ready(clnt_dev_ready)
    );

    // SiFive-style CLINT: msip at +0x0000, mtimecmp at +0x4000, mtime at
    // +0xBFF8.  The slave wrapper already aligned `clnt_dev_addr` on
    // byte boundaries, so we just pass the low 16 bits through.
    clnt u_clnt (
        .clk         (cpu_clk),
        .rst_n       (rst_n),
        .clnt_en     (clnt_dev_en),
        .re          (clnt_dev_re),
        .we          (clnt_dev_we),
        .clnt_addr   (clnt_dev_addr[15:0]),
        .din         (clnt_dev_wdata),
        .wstrb       (clnt_dev_wstrb),
        .dout        (clnt_dev_rdata),
        .clnt_ready  (clnt_dev_ready),
        .msip        (msip_level),
        .time_e_inter(time_e_inter)
    );

    // -------------------------------------------------------------------------
    // Slave 5 : UART
    // -------------------------------------------------------------------------
    wire        uart_dev_en;
    wire        uart_dev_we;
    wire        uart_dev_re;
    wire [31:0] uart_dev_addr;
    wire [31:0] uart_dev_wdata;
    wire [3:0]  uart_dev_wstrb;
    wire [31:0] uart_dev_rdata;
    wire        uart_dev_ready;

    axil_slave_wrapper u_uart_wrap (
        .aclk    (cpu_clk),   .aresetn(rst_n),
        .s_awaddr(uart_s_awaddr), .s_awprot(uart_s_awprot), .s_awvalid(uart_s_awvalid), .s_awready(uart_s_awready),
        .s_wdata (uart_s_wdata),  .s_wstrb (uart_s_wstrb),  .s_wvalid (uart_s_wvalid),  .s_wready (uart_s_wready),
        .s_bresp (uart_s_bresp),  .s_bvalid(uart_s_bvalid), .s_bready (uart_s_bready),
        .s_araddr(uart_s_araddr), .s_arprot(uart_s_arprot), .s_arvalid(uart_s_arvalid), .s_arready(uart_s_arready),
        .s_rdata (uart_s_rdata),  .s_rresp (uart_s_rresp),  .s_rvalid (uart_s_rvalid),  .s_rready (uart_s_rready),

        .dev_en   (uart_dev_en),
        .dev_we   (uart_dev_we),
        .dev_re   (uart_dev_re),
        .dev_addr (uart_dev_addr),
        .dev_wdata(uart_dev_wdata),
        .dev_wstrb(uart_dev_wstrb),
        .dev_rdata(uart_dev_rdata),
        .dev_ready(uart_dev_ready)
    );

    wire [8:0] uart_r_data_u;
    // The uart_ctr instance name is load-bearing: cpu_test.v probes
    // `uu1.uart_ctr.uart_tx_data` / `uu1.uart_ctr.tx_en_delay` directly.
    cpu_uart uart_ctr (
        .clk            (cpu_clk),
        .rst_n          (rst_n),
        .rx             (uart_rxd_ctr),
        .uart_en        (uart_dev_en),
        .w_en           (uart_dev_we),
        .r_en           (uart_dev_re),
        .uart_w_data    (uart_dev_wdata[7:0]),
        .uart_r_data_reg(uart_r_data_u),
        .tx             (uart_ctr_tx),
        .uart_ready     (uart_dev_ready),
        .addr           (uart_dev_addr - 32'h4300_0000)
    );

    assign uart_dev_rdata = {23'd0, uart_r_data_u};

    // -------------------------------------------------------------------------
    // Slave 6 : PLIC (SiFive-style platform-level interrupt controller)
    //
    //   Sources wired for this SoC:
    //     id 0 : reserved (spec-mandated, tied off)
    //     id 1 : external interrupt pad (e_inter), already synchronised
    //            onto cpu_clk above
    //     id 2..7 : unused, tied to 0 (ready for future UART-RX / timer /
    //               DMA / etc. aggregation without changing the address
    //               map).
    //   Output: meip_level -> cpu_jh.meip.
    // -------------------------------------------------------------------------
    wire        plic_dev_en;
    wire        plic_dev_we;
    wire        plic_dev_re;
    wire [31:0] plic_dev_addr;
    wire [31:0] plic_dev_wdata;
    wire [3:0]  plic_dev_wstrb;
    wire [31:0] plic_dev_rdata;
    wire        plic_dev_ready;

    axil_slave_wrapper u_plic_wrap (
        .aclk    (cpu_clk),   .aresetn(rst_n),
        .s_awaddr(plic_s_awaddr), .s_awprot(plic_s_awprot), .s_awvalid(plic_s_awvalid), .s_awready(plic_s_awready),
        .s_wdata (plic_s_wdata),  .s_wstrb (plic_s_wstrb),  .s_wvalid (plic_s_wvalid),  .s_wready (plic_s_wready),
        .s_bresp (plic_s_bresp),  .s_bvalid(plic_s_bvalid), .s_bready (plic_s_bready),
        .s_araddr(plic_s_araddr), .s_arprot(plic_s_arprot), .s_arvalid(plic_s_arvalid), .s_arready(plic_s_arready),
        .s_rdata (plic_s_rdata),  .s_rresp (plic_s_rresp),  .s_rvalid (plic_s_rvalid),  .s_rready (plic_s_rready),

        .dev_en   (plic_dev_en),
        .dev_we   (plic_dev_we),
        .dev_re   (plic_dev_re),
        .dev_addr (plic_dev_addr),
        .dev_wdata(plic_dev_wdata),
        .dev_wstrb(plic_dev_wstrb),
        .dev_rdata(plic_dev_rdata),
        .dev_ready(plic_dev_ready)
    );

    wire [7:0] plic_src_vec = { 6'b0, ext_irq_level, 1'b0 };

    plic #(
        .N_SRC         (8),
        .PRIORITY_WIDTH(3)
    ) u_plic (
        .clk        (cpu_clk),
        .rst_n      (rst_n),
        .plic_en    (plic_dev_en),
        .re         (plic_dev_re),
        .we         (plic_dev_we),
        .plic_addr  (plic_dev_addr[23:0]),
        .din        (plic_dev_wdata),
        .wstrb      (plic_dev_wstrb),
        .dout       (plic_dev_rdata),
        .plic_ready (plic_dev_ready),
        .irq_sources(plic_src_vec),
        .meip       (meip_level)
    );

    // -------------------------------------------------------------------------
    // Instruction-fetch path (TCM direct-connect vs AXI4-Lite master
    // [+ optional I-Cache]).
    //
    // Three compile configurations, selected by `define`s passed to the
    // simulator / synthesizer:
    //
    //   default (no define)        CPU -> icache -> axil_ifetch_bridge
    //                              -> axil_slave_wrapper -> i_rom port B.
    //                              2 KB / 16 B line / direct-mapped cache
    //                              absorbs AXI hand-shake latency on hits.
    //
    //   `-DICACHE_DISABLE`         CPU -> axil_ifetch_bridge directly.
    //                              Matches the Tier 4.2.1 (step A) path and
    //                              is kept around as an A/B reference.
    //
    //   `-DTCM_IFETCH`             CPU -> ram_c.i_rom port B directly
    //                              (combinational 1-cycle BRAM read), no
    //                              AXI in front of ifetch.  FPGA
    //                              resource-squeeze escape hatch.
    //
    // All three branches terminate at {ifetch_i_data, ifetch_i_ready} (feeding
    // cpu_jh.i_data_in / i_bus_ready) and drive {ram_i_en, ram_i_addr}
    // into ram_c's i_rom port B; ram_c.i_data (ram_i_data) flows back
    // either straight to the CPU (TCM), through the ifetch slave wrapper
    // (ICACHE_DISABLE), or through (cache miss -> slave wrapper) on a
    // cache miss in the default build.
    //
    // See PROCESSOR_IMPROVEMENT_PLAN.md Tier 4 item 4 for the rationale
    // behind keeping the AXI fetch path on its own private link for now
    // (not routed through the 1->6 data-side interconnect).
    // -------------------------------------------------------------------------
`ifdef TCM_IFETCH
    // --- Legacy direct-connect fetch (FPGA resource-squeeze fallback) -------
    //   pc_addr_out  -> i_rom port B addr (combinational 1-cycle BRAM read)
    //   i_rom.doutb  -> cpu_jh.i_data_in
    //   i_bus_ready  = 1  (BRAM port B is always ready)
    assign ram_i_en       = i_bus_en;
    assign ram_i_addr     = pc_addr_out;
    assign ifetch_i_data  = ram_i_data;
    assign ifetch_i_ready = 1'b1;

    // flush_icache is meaningless when there is no cache between the CPU
    // and the BRAM; drain it into a harmless wire so the lint tools do
    // not complain about an unused driver.
    wire _unused_tcm_flush = flush_icache;
`else
    // --- AXI4-Lite instruction fetch --------------------------------------
    //
    // Both the cached and uncached configurations use the same AXI4-Lite
    // master bridge (axil_ifetch_bridge).  In the cached build the I-Cache
    // sits between the CPU and the bridge; in ICACHE_DISABLE the CPU drives
    // the bridge directly.  All downstream AXI / BRAM plumbing is shared
    // and lives in the single block below.
    wire        if_m_arvalid;
    wire        if_m_arready;
    wire [31:0] if_m_araddr;
    wire [2:0]  if_m_arprot;
    wire        if_m_rvalid;
    wire        if_m_rready;
    wire [31:0] if_m_rdata;
    wire [1:0]  if_m_rresp;

    // i_bus_err is surfaced by the bridge.  In the default (cached) build it
    // is consumed by the I-Cache; in ICACHE_DISABLE it is merely observed
    // and not yet wired into an Instruction Access Fault path.
    wire        if_bus_err;

    // Bridge CPU-side port -- driven either by the cache (default) or by
    // cpu_jh directly (ICACHE_DISABLE).
    wire        br_up_en;
    wire [31:0] br_up_addr;
    wire [31:0] br_up_data;
    wire        br_up_ready;

`ifdef ICACHE_DISABLE
    // --- AXI ifetch without cache (Tier 4.2.1 step A behaviour) ------------
    assign br_up_en       = i_bus_en;
    assign br_up_addr     = pc_addr_out;
    assign ifetch_i_data  = br_up_data;
    assign ifetch_i_ready = br_up_ready;

    // No cache to flush.
    wire _unused_nocache_flush = flush_icache;
`else
    // --- AXI ifetch with 2 KB direct-mapped I-Cache (default) -------------
    //
    //   cpu_jh  <->  icache  <->  axil_ifetch_bridge  <->  i_rom port B
    //
    // The cache sees the CPU's legacy {i_bus_en / pc_addr / i_data /
    // i_bus_ready} handshake on one side and the bridge's CPU-side port
    // shape (same signals, plus an optional i_bus_err) on the other.  A
    // 1-cycle flush pulse from cpu_jh.flush_icache synchronously clears
    // every valid bit so a following fetch re-reads memory (fence.i).
    icache u_icache (
        .aclk   (cpu_clk),
        .aresetn(rst_n),
        .flush  (flush_icache),

        .up_en   (i_bus_en),
        .up_addr (pc_addr_out),
        .up_data (ifetch_i_data),
        .up_ready(ifetch_i_ready),
        .up_err  (/* unused; merged into bridge's err path */),

        .dn_en   (br_up_en),
        .dn_addr (br_up_addr),
        .dn_data (br_up_data),
        .dn_ready(br_up_ready),
        .dn_err  (if_bus_err)
    );
`endif

    axil_ifetch_bridge u_axil_ifetch (
        .aclk       (cpu_clk),
        .aresetn    (rst_n),

        .i_bus_en   (br_up_en),
        .pc_addr    (br_up_addr),
        .i_data     (br_up_data),
        .i_bus_ready(br_up_ready),
        .i_bus_err  (if_bus_err),

        .m_arvalid  (if_m_arvalid),
        .m_arready  (if_m_arready),
        .m_araddr   (if_m_araddr),
        .m_arprot   (if_m_arprot),

        .m_rvalid   (if_m_rvalid),
        .m_rready   (if_m_rready),
        .m_rdata    (if_m_rdata),
        .m_rresp    (if_m_rresp)
    );

    // Dedicated slave wrapper in front of i_rom port B.  Write channels
    // are tied off because the fetch bridge is read-only; the wrapper's
    // WRITE FSM path is therefore never entered.  dev_ready tracks dev_en
    // combinationally because i_rom port B is a 1-cycle combinational read
    // (see sim/models/xilinx_compat.v and the real Vivado BRAM config).
    wire        if_dev_en;
    wire        if_dev_we;
    wire        if_dev_re;
    wire [31:0] if_dev_addr;
    wire [31:0] if_dev_wdata;
    wire [3:0]  if_dev_wstrb;

    axil_slave_wrapper u_ifetch_rom_wrap (
        .aclk    (cpu_clk),     .aresetn(rst_n),

        // write channels tied off
        .s_awaddr (32'd0), .s_awprot (3'd0), .s_awvalid(1'b0), .s_awready(),
        .s_wdata  (32'd0), .s_wstrb  (4'd0), .s_wvalid (1'b0), .s_wready (),
        .s_bresp  (),      .s_bvalid (),    .s_bready (1'b1),

        // read channel pair with the bridge
        .s_araddr (if_m_araddr), .s_arprot (if_m_arprot),
        .s_arvalid(if_m_arvalid),.s_arready(if_m_arready),
        .s_rdata  (if_m_rdata),  .s_rresp  (if_m_rresp),
        .s_rvalid (if_m_rvalid), .s_rready (if_m_rready),

        // device-side (drives ram_c.i_addr / ram_c.i_en)
        .dev_en   (if_dev_en),
        .dev_we   (if_dev_we),
        .dev_re   (if_dev_re),
        .dev_addr (if_dev_addr),
        .dev_wdata(if_dev_wdata),
        .dev_wstrb(if_dev_wstrb),
        .dev_rdata(ram_i_data),          // combinational from i_rom port B
        .dev_ready(if_dev_en)            // port B is 0-cycle ready
    );

    assign ram_i_en   = if_dev_en & if_dev_re;
    assign ram_i_addr = if_dev_addr;

    // Lint quietening: dev_we / dev_wdata / dev_wstrb are driven by the
    // wrapper even though the write FSM can never enter here (s_awvalid /
    // s_wvalid are tied to 0).  Include if_bus_err in the ICACHE_DISABLE
    // configuration where nothing else consumes it (the cache takes the
    // err signal otherwise).
`ifdef ICACHE_DISABLE
    wire _unused_ifetch = if_dev_we ^ (|if_dev_wdata) ^ (|if_dev_wstrb) ^
                          if_bus_err;
`else
    wire _unused_ifetch = if_dev_we ^ (|if_dev_wdata) ^ (|if_dev_wstrb);
`endif
`endif

endmodule
