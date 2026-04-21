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

// Probe the UART TX datapath so simulation can print characters directly.
wire [7:0]uart_data=uu1.uart_ctr.uart_tx_data;

wire uart_lunch_en=uu1.uart_ctr.tx_en_delay;

always@(posedge clk)
begin
if(uart_lunch_en==1)
    $write("%c",uart_data);
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
reg [7:0] dram_init_bytes [0:65535];
reg [1023:0] dram_init_file;
integer dram_i;
initial begin
    for (dram_i = 0; dram_i < 65536; dram_i = dram_i + 1)
        dram_init_bytes[dram_i] = 8'h00;
    if ($value$plusargs("DRAM=%s", dram_init_file)) begin
        $display("[sim] preloading dram from %0s", dram_init_file);
        $readmemh(dram_init_file, dram_init_bytes);
        for (dram_i = 0; dram_i < 16384; dram_i = dram_i + 1) begin
            uu1.b1.d_ram_1.u_ram._ram[dram_i] = dram_init_bytes[dram_i*4 + 0];
            uu1.b1.d_ram_2.u_ram._ram[dram_i] = dram_init_bytes[dram_i*4 + 1];
            uu1.b1.d_ram_3.u_ram._ram[dram_i] = dram_init_bytes[dram_i*4 + 2];
            uu1.b1.d_ram_4.u_ram._ram[dram_i] = dram_init_bytes[dram_i*4 + 3];
        end
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
        #100
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