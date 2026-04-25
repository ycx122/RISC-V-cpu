`timescale 1ns/1ps    
module cpu_test();



reg clk,rst,e_inter;
    wire[31:0] x1 = uu1.a1.b2.regs[1];
    wire[31:0] x2 = uu1.a1.b2.regs[2];
    wire[31:0] x3 = uu1.a1.b2.regs[3];
    wire[31:0] x4 = uu1.a1.b2.regs[4];
    wire[31:0] x5 = uu1.a1.b2.regs[5];
    wire[31:0] x6 = uu1.a1.b2.regs[6];
    wire[31:0] x7 = uu1.a1.b2.regs[7];
    wire[31:0] x8 = uu1.a1.b2.regs[8];
    wire[31:0] x9 = uu1.a1.b2.regs[9];
    wire[31:0] x10 = uu1.a1.b2.regs[10];
    wire[31:0] x11 = uu1.a1.b2.regs[11];
    wire[31:0] x12 = uu1.a1.b2.regs[12];
    wire[31:0] x13 = uu1.a1.b2.regs[13];
    wire[31:0] x14 = uu1.a1.b2.regs[14];
    wire[31:0] x15 = uu1.a1.b2.regs[15];
    wire[31:0] x16 = uu1.a1.b2.regs[16];
    wire[31:0] x17 = uu1.a1.b2.regs[17];
    wire[31:0] x18 = uu1.a1.b2.regs[18];
    wire[31:0] x19 = uu1.a1.b2.regs[19];   
    wire[31:0] x20 = uu1.a1.b2.regs[20];
    wire[31:0] x21 = uu1.a1.b2.regs[21];
    wire[31:0] x22 = uu1.a1.b2.regs[22];
    wire[31:0] x23 = uu1.a1.b2.regs[23];
    wire[31:0] x24 = uu1.a1.b2.regs[24];
    wire[31:0] x25 = uu1.a1.b2.regs[25];
    wire[31:0] x26 = uu1.a1.b2.regs[26];
    wire[31:0] x27 = uu1.a1.b2.regs[27];
    wire[31:0] x28 = uu1.a1.b2.regs[28];
    wire[31:0] x29 = uu1.a1.b2.regs[29];   
    wire[31:0] x30 = uu1.a1.b2.regs[30];
    wire[31:0] x31 = uu1.a1.b2.regs[31];
reg [31:0]r;

// Simulation-side UART console:
//
// Print the byte when the SoC accepts a write to the UART MMIO window,
// rather than when the serial shifter later drains it.
//
// Why this level instead of probing `uart_tx` directly?
//   1. `cpu_uart` can accept writes much faster than the 115200-baud TX
//      engine drains them, so long software strings can overflow the TX
//      FIFO in simulation if we try to mirror the real serial path.
//   2. For software bring-up, what we actually want is "what byte did the
//      program ask the UART to send?"  The accepted MMIO write is exactly
//      that event.
//   3. This keeps the console fast: we are not forced to wait ~4340 clk
//      per character just to see printf output in `vvp`.
wire [7:0] uart_tx_byte  = uu1.uart_dev_wdata[7:0];
wire       uart_tx_fire  = uu1.uart_dev_en & uu1.uart_dev_we & uu1.uart_dev_ready;

always@(posedge clk)
begin
if(uart_tx_fire == 1'b1)
    $write("%c", uart_tx_byte);
end

// UART-driven exit protocol, intended for programs that never set
// x26/x27 (RTOS, CoreMark, Dhrystone, long-running self-checking demos).
//
//   +UART_PASS_PATTERN=<s>   : when the UART stream contains <s>,
//                              finish the sim with TEST_PASS banner
//   +UART_FAIL_PATTERN=<s>   : same but with TEST_FAIL banner
//
// The pattern is a bare ASCII string -- no shell escaping required.
// `\n` in software-side `printf` arrives as byte 0x0a, so a pattern like
// `OS_DEMO_PASS` matches regardless of line ending.  Matching is naive
// (linear scan with a sliding index), which is plenty for the short
// unique markers these test programs actually use.
//
// Pattern storage is fixed at 64 chars.  Longer patterns are silently
// truncated.  This also limits pass/fail keywords to printable ASCII --
// NUL (0x00) is the end-of-string sentinel.
localparam integer UART_PATTERN_MAX = 64;
reg [UART_PATTERN_MAX*8-1:0] pass_pattern_raw;
reg [UART_PATTERN_MAX*8-1:0] fail_pattern_raw;
reg [7:0] pass_pattern [0:UART_PATTERN_MAX-1];
reg [7:0] fail_pattern [0:UART_PATTERN_MAX-1];
integer pass_pattern_len;
integer fail_pattern_len;
integer pass_match_idx;
integer fail_match_idx;
reg pass_pattern_enabled;
reg fail_pattern_enabled;
integer pp_i;

initial begin
    pass_pattern_enabled = 1'b0;
    fail_pattern_enabled = 1'b0;
    pass_pattern_len     = 0;
    fail_pattern_len     = 0;
    pass_match_idx       = 0;
    fail_match_idx       = 0;
    for (pp_i = 0; pp_i < UART_PATTERN_MAX; pp_i = pp_i + 1) begin
        pass_pattern[pp_i] = 8'h00;
        fail_pattern[pp_i] = 8'h00;
    end

    if ($value$plusargs("UART_PASS_PATTERN=%s", pass_pattern_raw)) begin
        // $value$plusargs packs the string right-justified: the last
        // character of the user input ends up in bits [7:0], so walk the
        // reg from the LSB upward to recover the original left-to-right
        // byte order.  The loop runs until it finds the leading NUL
        // padding, which gives us the pattern length in the process.
        pass_pattern_len = 0;
        for (pp_i = 0; pp_i < UART_PATTERN_MAX; pp_i = pp_i + 1) begin
            if (pass_pattern_raw[pp_i*8 +: 8] != 8'h00)
                pass_pattern_len = pp_i + 1;
        end
        for (pp_i = 0; pp_i < pass_pattern_len; pp_i = pp_i + 1)
            pass_pattern[pp_i] =
                pass_pattern_raw[(pass_pattern_len-1-pp_i)*8 +: 8];
        pass_pattern_enabled = (pass_pattern_len > 0);
        if (pass_pattern_enabled)
            $display("[sim] UART_PASS_PATTERN armed (%0d bytes)", pass_pattern_len);
    end

    if ($value$plusargs("UART_FAIL_PATTERN=%s", fail_pattern_raw)) begin
        fail_pattern_len = 0;
        for (pp_i = 0; pp_i < UART_PATTERN_MAX; pp_i = pp_i + 1) begin
            if (fail_pattern_raw[pp_i*8 +: 8] != 8'h00)
                fail_pattern_len = pp_i + 1;
        end
        for (pp_i = 0; pp_i < fail_pattern_len; pp_i = pp_i + 1)
            fail_pattern[pp_i] =
                fail_pattern_raw[(fail_pattern_len-1-pp_i)*8 +: 8];
        fail_pattern_enabled = (fail_pattern_len > 0);
        if (fail_pattern_enabled)
            $display("[sim] UART_FAIL_PATTERN armed (%0d bytes)", fail_pattern_len);
    end
end

// Naive streaming match: advance the match index on a character hit,
// drop back to 0 (or 1 if the mismatching byte itself matches the first
// pattern byte) on a miss.  Good enough for short, unique banners.
task automatic report_pass_banner;
    begin
        $display("~~~~~~~~~~~~~~~~~~~ TEST_PASS ~~~~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~ #####     ##     ####    #### ~~~~~~~~~");
        $display("~~~~~~~~~ #    #   #  #   #       #     ~~~~~~~~~");
        $display("~~~~~~~~~ #    #  #    #   ####    #### ~~~~~~~~~");
        $display("~~~~~~~~~ #####   ######       #       #~~~~~~~~~");
        $display("~~~~~~~~~ #       #    #  #    #  #    #~~~~~~~~~");
        $display("~~~~~~~~~ #       #    #   ####    #### ~~~~~~~~~");
        $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
    end
endtask

task automatic report_fail_banner;
    input [255:0] reason;
    begin
        $display("~~~~~~~~~~~~~~~~~~~ TEST_FAIL ~~~~~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        $display("~~~~~~~~~~######    ##       #    #     ~~~~~~~~~~");
        $display("~~~~~~~~~~#        #  #      #    #     ~~~~~~~~~~");
        $display("~~~~~~~~~~#####   #    #     #    #     ~~~~~~~~~~");
        $display("~~~~~~~~~~#       ######     #    #     ~~~~~~~~~~");
        $display("~~~~~~~~~~#       #    #     #    #     ~~~~~~~~~~");
        $display("~~~~~~~~~~#       #    #     #    ######~~~~~~~~~~");
        $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        $display("reason = %0s", reason);
    end
endtask

always @(posedge clk) begin
    if (uart_tx_fire) begin
        if (pass_pattern_enabled) begin
            if (uart_tx_byte == pass_pattern[pass_match_idx])
                pass_match_idx = pass_match_idx + 1;
            else if (uart_tx_byte == pass_pattern[0])
                pass_match_idx = 1;
            else
                pass_match_idx = 0;

            if (pass_match_idx >= pass_pattern_len) begin
                $display("\n[sim] UART_PASS_PATTERN matched @%0t", $time);
                report_pass_banner;
                $finish;
            end
        end

        if (fail_pattern_enabled) begin
            if (uart_tx_byte == fail_pattern[fail_match_idx])
                fail_match_idx = fail_match_idx + 1;
            else if (uart_tx_byte == fail_pattern[0])
                fail_match_idx = 1;
            else
                fail_match_idx = 0;

            if (fail_match_idx >= fail_pattern_len) begin
                $display("\n[sim] UART_FAIL_PATTERN matched @%0t", $time);
                report_fail_banner("UART_FAIL_PATTERN");
                $finish;
            end
        end
    end
end

// Hard cycle cap for programs that may never trip the x26/x27 or UART
// pattern exits (e.g. a hang we explicitly want to surface as a FAIL
// rather than have the outer shell `timeout` kill vvp from the side).
//
//   +MAX_CYCLES=N
//
// N is counted in CPU clock edges (the same clock the testbench drives
// at `always #10 clk = ~clk`, so 1 cycle = 20 ns).  Reaching the cap
// dumps state and finishes with a TEST_FAIL banner so regressions still
// come back with a clean non-zero exit code instead of a truncated log.
integer max_cycles;
integer cycle_cnt;
reg     max_cycles_enabled;

initial begin
    max_cycles_enabled = 1'b0;
    cycle_cnt          = 0;
    if ($value$plusargs("MAX_CYCLES=%d", max_cycles)) begin
        if (max_cycles > 0) begin
            max_cycles_enabled = 1'b1;
            $display("[sim] MAX_CYCLES=%0d armed", max_cycles);
        end
    end
end

always @(posedge clk) begin
    if (max_cycles_enabled) begin
        cycle_cnt = cycle_cnt + 1;
        if (cycle_cnt >= max_cycles) begin
            $display("\n[sim] MAX_CYCLES=%0d reached @%0t (pc=%h x26=%0d x27=%0d)",
                     max_cycles, $time,
                     uu1.a1.pc_addr_out,
                     uu1.a1.b2.regs[26],
                     uu1.a1.b2.regs[27]);
            report_fail_banner("MAX_CYCLES reached");
            for (r = 1; r < 32; r = r + 1)
                $display("x%2d = 0x%x", r, uu1.a1.b2.regs[r]);
            $finish;
        end
    end
end

always #10 clk=~clk;

// Optional simulation-only RAM preload channel.
//
// Real hardware ships an ELF image where `.data` lives in the RAM window at
// 0x20000000 (VMA) but is physically stored in ROM at a high LMA; a tiny
// boot copy loop (crt0) moves it into RAM before main() runs.  This SoC
// does not have such a loader, so RAM comes up all zeros in simulation.
//
// riscv-tests expect the `.data` section's initializer pattern to already
// be in memory (e.g. rv32ui-p-sb / rv32ui-p-sh read back partially
// overwritten `0xef` / `0xbeef` words).  When sim/run_isa.sh is invoked
// with `+DRAM=<file>.data.hex`, this block pre-populates all four byte
// banks of `ram_c` so those tests pass without needing an on-chip
// bootloader.  The hex file is a flat byte-per-line dump of the `.data`
// segment starting at the VMA base (`_ram[0]` across the four banks
// corresponds to byte address 0x20000000).
// dram_init_bytes is sized to the largest RAM we currently target (256 KB
// total, 64 KiB/bank).  We always zero-initialise every bank cell so any
// stack/.bss access into RAM lands in a defined value rather than an 'X'
// (which would propagate through compares and stall the test forever).
// The +DRAM preload then overwrites the .data prefix.
reg [7:0] dram_init_bytes [0:262143];   // 256 KiB
reg [1023:0] dram_init_file;
integer dram_i;
initial begin
    for (dram_i = 0; dram_i < 262144; dram_i = dram_i + 1)
        dram_init_bytes[dram_i] = 8'h00;
    // Always pre-zero every bank (65536 bytes per bank) so the entire
    // 256 KB window starts well-defined.  The test image, when present,
    // is only a few hundred bytes, but the stack lives at the top of
    // RAM and would otherwise read from uninitialised cells.
    for (dram_i = 0; dram_i < 65536; dram_i = dram_i + 1) begin
        uu1.b1.d_ram_1.u_ram._ram[dram_i] = 8'h00;
        uu1.b1.d_ram_2.u_ram._ram[dram_i] = 8'h00;
        uu1.b1.d_ram_3.u_ram._ram[dram_i] = 8'h00;
        uu1.b1.d_ram_4.u_ram._ram[dram_i] = 8'h00;
    end
    if ($value$plusargs("DRAM=%s", dram_init_file)) begin
        $display("[sim] preloading dram from %0s", dram_init_file);
        $readmemh(dram_init_file, dram_init_bytes);
        for (dram_i = 0; dram_i < 65536; dram_i = dram_i + 1) begin
            uu1.b1.d_ram_1.u_ram._ram[dram_i] = dram_init_bytes[dram_i*4 + 0];
            uu1.b1.d_ram_2.u_ram._ram[dram_i] = dram_init_bytes[dram_i*4 + 1];
            uu1.b1.d_ram_3.u_ram._ram[dram_i] = dram_init_bytes[dram_i*4 + 2];
            uu1.b1.d_ram_4.u_ram._ram[dram_i] = dram_init_bytes[dram_i*4 + 3];
        end
    end
end

// Optional external-interrupt assertion.  cpu_soc's `e_inter` pin is the
// active-low external interrupt source: the SoC inverts and synchronises
// it onto cpu_clk to produce a level-sensitive MEIP into the CSR file.
// With `e_inter` permanently high the core never sees an async interrupt,
// which is fine for ordinary ISA regression but hides the interrupt-mepc
// path entirely.  When run with `+EINT_AT=<ns>` we assert the source at
// that simulation time and leave it asserted: because the interrupt is
// level-sensitive, the handler is expected to either clear the source
// (not modelled on this board) or permanently mask MIE.
integer eint_when;
initial begin
    if ($value$plusargs("EINT_AT=%d", eint_when)) begin
        #(eint_when);
        e_inter = 0;   // assert MEIP and leave it asserted
    end
end

// Optional simulation watchdog for debugging hangs: enable with +WATCHDOG.
// Dumps CPU state (PC, key CSRs, GPRs) and finishes the sim when it fires,
// so a hung vvp does not need to be killed with `timeout`.
initial begin : sim_watchdog
    if ($test$plusargs("WATCHDOG")) begin
        #5_000_000;
        $display("[sim] WATCHDOG fired @%0t: x26=%0d x27=%0d x3=%0d pc=%h mstatus=%h mcause=%h mepc=%h mtvec=%h",
            $time,
            uu1.a1.b2.regs[26], uu1.a1.b2.regs[27], uu1.a1.b2.regs[3],
            uu1.a1.pc_addr_out,
            uu1.a1.a5.mstatus, uu1.a1.a5.mcause, uu1.a1.a5.mepc, uu1.a1.a5.mtvec);
        for (r = 1; r < 32; r = r + 1)
            $display("x%2d = 0x%x", r, uu1.a1.b2.regs[r]);
        $finish;
    end
end

initial 
begin
// Keep interrupts inactive, pulse reset, then wait for the test protocol
// used by many RISC-V ISA tests:
// x26 == 1 means finished, x27 == 1 means pass.
e_inter=1;
clk=0;
rst=1;
#100
rst=0;
#1000
rst=1;

        wait(x26 == 32'b1)   // wait sim end, when x26 == 1
        // Drain window for the AXI + I-Cache ifetch path.  riscv-tests end
        // with two back-to-back writes (s10=1 then s11=1) followed by an
        // infinite loop.  On TCM (zero-latency fetch) the two retire one
        // cycle apart, so #100 (5 cycles) was enough to observe x27.  With
        // the cached AXI frontend, a cache miss that straddles the
        // s10/s11 boundary delays the s11 retire by up to one line-fill
        // (~10 cycles).  #500 is conservative: it still lets a genuinely
        // failing test (s11=0) fall through to the reporting branch
        // without inflating overall regression runtime.
        #500
        if (x27 == 32'b1) begin
            $display("~~~~~~~~~~~~~~~~~~~ TEST_PASS ~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~ #####     ##     ####    #### ~~~~~~~~~");
            $display("~~~~~~~~~ #    #   #  #   #       #     ~~~~~~~~~");
            $display("~~~~~~~~~ #    #  #    #   ####    #### ~~~~~~~~~");
            $display("~~~~~~~~~ #####   ######       #       #~~~~~~~~~");
            $display("~~~~~~~~~ #       #    #  #    #  #    #~~~~~~~~~");
            $display("~~~~~~~~~ #       #    #   ####    #### ~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
        end else begin
            $display("~~~~~~~~~~~~~~~~~~~ TEST_FAIL ~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("~~~~~~~~~~######    ##       #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#        #  #      #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#####   #    #     #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#       ######     #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#       #    #     #    #     ~~~~~~~~~~");
            $display("~~~~~~~~~~#       #    #     #    ######~~~~~~~~~~");
            $display("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
            $display("fail testnum = %2d", x3);
            for (r = 1; r < 32; r = r + 1)
                $display("x%2d = 0x%x", r, uu1.a1.b2.regs[r]);
        end

    $stop;

end


// Run in normal execute mode (`down_load_key = 1`) during simulation.
cpu_soc uu1 (.clk(clk),.rst_n(rst),.led(),.key(8'd1),.uart_rxd(),.uart_txd(),.down_load_key(1'b1), .e_inter(e_inter));


endmodule