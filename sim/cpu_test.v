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

wire [7:0]uart_data=uu1.uart_ctr.uart_tx_data;

wire uart_lunch_en=uu1.uart_ctr.tx_en_delay;

always@(posedge clk)
begin
if(uart_lunch_en==1)
    $write("%c",uart_data);
end

always #10 clk=~clk;



initial 
begin
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


cpu_soc uu1 (.clk(clk),.rst_n(rst),.led(),.key(1),.uart_rxd(),.uart_txd(),.down_load_key(1), .e_inter(e_inter));


endmodule