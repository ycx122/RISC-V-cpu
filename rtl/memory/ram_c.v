`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// ram_c  --  AXI4-Lite-friendly 4-bank byte-addressable data RAM
//            + dual-port boot-ROM + UART download glue.
//
// History
//   2022-01-21  initial version: 4 byte-banks, mem_op-aware byte lane
//               rotation, bespoke bus handshake via d_en/we/re/ram_ready.
//   2026-04-22  AXI4-Lite refactor (Tier 4.1 of PROCESSOR_IMPROVEMENT_PLAN):
//               * Removed internal mem_op-dependent byte lane rotation
//                 and sign-extension.  Byte-lane steering for stores and
//                 the load-side byte / half-word extraction now live in
//                 rtl/bus/axil_master_bridge.v, which is exactly the
//                 shape that standard AXI4-Lite expects of a "32b RAM
//                 with wstrb" slave.
//               * New dev-side port takes a 4-bit WSTRB directly; each
//                 wstrb bit drives exactly one of the four byte banks.
//                 That is already the natural AXI4-Lite mapping, and
//                 lets Xilinx MIG's AXI-Lite facade / OpenXilinx
//                 AXI BRAM Controller drop in as a replacement.
//               * Misaligned accesses are no longer rotated across
//                 banks.  Callers (or the bridge) are responsible for
//                 presenting aligned word addresses.  The CPU never
//                 generates a misaligned base access (compiler emits
//                 byte/half-word ops for those cases), so this is a
//                 non-regression in practice and matches how real AXI4
//                 slaves behave.
//
//   2026-04 later (Tier 4.2 / .rodata fast path):
//               * i_rom port A was widened to 32-bit read + 4-bit
//                 byte-strobe write.  rodata.v now asks for a full
//                 aligned word in one shot (3-cycle FSM instead of
//                 the old 7-state byte-walker) so ROM load-to-use
//                 drops from ~12 cycles to ~5.
//               * UART download still writes one received byte at a
//                 time, but encodes "write byte N" as a 32-bit data
//                 replica driven onto all four lanes with wea[]
//                 selecting exactly the target byte lane.
//               * rom_addr is now a 14-bit *word* address (was 16-bit
//                 byte).  Callers (rodata, UART download counter)
//                 were updated to match.
// -----------------------------------------------------------------------------
module ram_c(
    input              clk,
    input              i_en,

    // --- simple device-side bus (driven by axil_slave_wrapper in cpu_soc) ---
    input              d_en,       // transaction active
    input              we,         // write cycle
    input              re,         // read  cycle
    input      [31:0]  d_addr,     // 32b byte address; [1:0] ignored (aligned)
    input      [31:0]  d_wdata,    // write data, byte-lane positioned
    input      [3:0]   d_wstrb,    // per-byte write enables (AXI WSTRB)
    output     [31:0]  d_rdata,    // 32b word read data
    output             d_ready,    // combinational "done"

    // --- instruction fetch port (direct, no bus) ----------------------------
    input      [31:0]  i_addr,
    output     [31:0]  i_data,

    // --- dual-port ROM port-A sharing (for rodata + UART download) ----------
    // rom_addr is a 14-bit *word* address (32-bit port-A), driven by rodata.
    input              cpu_clk,
    input      [13:0]  rom_addr,
    input              rom_r_en,
    output     [31:0]  rom_data,

    // --- UART download path (unchanged) -------------------------------------
    input              down_load_key,
    input              uart_rxd,
    output             uart_txd,

    input              rst_n
);

    // -------------------------------------------------------------------------
    // 4 byte-wide BRAM banks.  Each bank has an independent write enable
    // so AXI WSTRB maps 1:1 onto per-bank writes (no rotation needed).
    //
    // 2026-04 scale-up: bank_addr is now 16-bit (was 15-bit) to address
    // 64 KiB per bank (256 KB RAM total).  The cpu_soc.v wrapper drops
    // the leading 0x2000_0000 base before forwarding `d_addr`, so bits
    // [17:2] cover the full 256 KB window without spilling into the
    // address tag.
    // -------------------------------------------------------------------------
    wire [15:0] bank_addr = d_addr[17:2];

    wire [3:0] bank_we = d_wstrb & {4{d_en & we}};
    wire       bank_re = d_en & re;

    wire [7:0] d_out_ram1, d_out_ram2, d_out_ram3, d_out_ram4;

    // Bank 0 = byte lane 0 (address +0) = d_wdata[7:0]
    // Bank 1 = byte lane 1 (address +1) = d_wdata[15:8]
    // Bank 2 = byte lane 2 (address +2) = d_wdata[23:16]
    // Bank 3 = byte lane 3 (address +3) = d_wdata[31:24]
    dram d_ram_1(.clka(cpu_clk), .clkb(cpu_clk), .ena(bank_we[0]), .enb(bank_re),
                 .dina(d_wdata[7:0]),   .doutb(d_out_ram1),
                 .addra(bank_addr),     .addrb(bank_addr),
                 .wea(bank_we[0]));
    dram d_ram_2(.clka(cpu_clk), .clkb(cpu_clk), .ena(bank_we[1]), .enb(bank_re),
                 .dina(d_wdata[15:8]),  .doutb(d_out_ram2),
                 .addra(bank_addr),     .addrb(bank_addr),
                 .wea(bank_we[1]));
    dram d_ram_3(.clka(cpu_clk), .clkb(cpu_clk), .ena(bank_we[2]), .enb(bank_re),
                 .dina(d_wdata[23:16]), .doutb(d_out_ram3),
                 .addra(bank_addr),     .addrb(bank_addr),
                 .wea(bank_we[2]));
    dram d_ram_4(.clka(cpu_clk), .clkb(cpu_clk), .ena(bank_we[3]), .enb(bank_re),
                 .dina(d_wdata[31:24]), .doutb(d_out_ram4),
                 .addra(bank_addr),     .addrb(bank_addr),
                 .wea(bank_we[3]));

    // The `dram` primitive's output is combinational (see rtl/common/
    // primitives/ram.v), so reads complete in the same cycle the request
    // is presented and writes take effect at the next posedge.  d_ready
    // therefore follows d_en * (we | re) combinationally, matching the
    // pre-refactor ram_ready semantics.
    assign d_rdata = {d_out_ram4, d_out_ram3, d_out_ram2, d_out_ram1};
    assign d_ready = d_en & (we | re);

    // -------------------------------------------------------------------------
    // UART download counter (byte counter driven into i_rom port A).
    //
    // Port A is now 32-bit wide with 4 byte-strobes, but UART streams
    // bytes in one at a time.  Every received byte is placed on all
    // four WDATA lanes (dina = {4{rx_byte}}) and the per-byte wea[]
    // enables exactly the lane corresponding to rom_w_byte_addr[1:0].
    // The port-A address drops the low 2 bits to get the word address.
    // -------------------------------------------------------------------------
    wire        rx_done_pos;
    wire        rx_done;
    wire [7:0]  uart_rx_data;
    reg  [15:0] rom_w_byte_addr = 16'd0;

    wire        rom_w_en      = rx_done_pos & down_load_key;
    wire [13:0] rom_w_word    = rom_w_byte_addr[15:2];
    wire [1:0]  rom_w_lane    = rom_w_byte_addr[1:0];
    wire [3:0]  rom_w_wea     = rom_w_en ? ({3'b000, 1'b1} << rom_w_lane) : 4'b0000;
    wire [31:0] rom_w_dina    = {4{uart_rx_data}};

    edge_detect2 edge_detect2_inst (
        .clk    (cpu_clk),
        .signal (rx_done),
        .pe     (rx_done_pos),
        .ne     (),
        .de     ()
    );

    // -------------------------------------------------------------------------
    // Dual-port boot ROM:
    //   port B : 32-bit instruction fetch
    //   port A : shared between ROM data reads (rodata) and UART download
    //
    // Read (rodata) and write (UART download) paths are mutually exclusive
    // at the system level -- download_key gates whether the CPU runs at all
    // -- so a simple OR of the addresses is fine.  wea[] is driven purely
    // by the UART write path; rodata drives reads with wea==0.
    // -------------------------------------------------------------------------
    i_rom i_rom(
        .clkb  (clk),
        .addrb (i_addr[15:2]),
        .enb   (i_en),
        .doutb (i_data),
        .dinb  (32'b0),
        .web   (1'b0),

        .clka  (cpu_clk),
        .addra ((rom_addr   & {14{rom_r_en}}) |
                (rom_w_word & {14{rom_w_en}})),
        .ena   (rom_r_en | rom_w_en),
        .douta (rom_data),
        .dina  (rom_w_dina),
        .wea   (rom_w_wea)
    );

    // UART RX: captures each byte streamed in while in download mode.
    // Each received byte becomes the next byte of i_rom.
    uart_rx uart_rx(
        .sys_clk      (cpu_clk),
        .sys_rst_n    (rst_n),
        .uart_rxd     (uart_rxd),
        .uart_rx_done (rx_done),
        .uart_rx_data (uart_rx_data)
    );

    // UART TX: echo an 'S' (0x53) back on the very first byte received in
    // download mode, as a minimal "download started" indicator.
    uart_tx uart_tx(
        .sys_clk   (cpu_clk),
        .sys_rst_n (rst_n),
        .uart_data (8'd83),
        .uart_tx_en(rx_done_pos == 1'b1 && rom_w_byte_addr == 16'd0),
        .uart_txd  (uart_txd)
    );

    always @(posedge cpu_clk) begin
        if (rst_n == 1'b0)
            rom_w_byte_addr <= 16'd0;
        else if (rx_done_pos && down_load_key)
            rom_w_byte_addr <= rom_w_byte_addr + 16'd1;
    end

endmodule

// -----------------------------------------------------------------------------
// One-cycle edge detector on `signal`:
//   pe = rising edge, ne = falling edge, de = either edge.
// -----------------------------------------------------------------------------
module edge_detect2(
    input      clk,
    input      signal,
    output reg pe,
    output reg ne,
    output reg de
);
    reg reg1;
    always @(posedge clk) begin
        reg1 <= signal;
        pe   <= (~reg1) & signal;
        ne   <= reg1 & (~signal);
        de   <= reg1 ^ signal;
    end
endmodule
