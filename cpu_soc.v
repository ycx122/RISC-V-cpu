module cpu_soc (
  input clk,
  input rst,
  
  input [7:0]key,
  output reg [15:0]led,
  
  input 	uart_rxd,	//接收端口
  output 	uart_txd,	//发送端口
  input down_load_key

);


reg [31:0] led_r_data;
reg [31:0] key_r_data;

wire i_bus_en;
wire [31:0] i_data_in;
wire [31:0] pc_addr_out;
wire cpu_clk;
wire ram_clk;

wire [31:0] d_addr;
wire [31:0] d_data_out;
wire [31:0] ram_data_in;
wire d_en;
wire ram_we;
wire ram_re;
wire [2:0]mem_op_out;
wire [31:0]i_data_in_c;
wire d_bus_ready;
wire ram_ready;

wire [31:0] bus_data_in;

wire [31:0]reg_data   ;
wire rom_r_ready;
wire ram_en;
wire rom_en;
wire rst_n;

wire uart_en;
wire [7:0]uart_r_data_u;
wire [31:0] uart_r_data=(mem_op_out==0)?((uart_r_data_u[7]==1)?{{24{1'b1}},uart_r_data_u}:{{24{1'b0}},uart_r_data_u}):{{24{1'b0}},uart_r_data_u};
wire uart_ctr_tx;
wire uart_rom_tx;

wire uart_rxd_ctr;
wire uart_rxd_rom;

wire uart_ready;

wire [31:0] clnt_r_data;


assign uart_rxd_ctr=(down_load_key==1)?uart_rxd:1'b1;
assign uart_rxd_rom=(down_load_key==0)?uart_rxd:1'b1;

assign uart_txd=(down_load_key)?uart_ctr_tx:uart_rom_tx;

assign rst_n=rst;

assign i_data_in=i_data_in_c;

clk_wiz_0 clk_pll (   //pll
.clk_in1(clk) ,       //100MHZ
.clk_out1(cpu_clk) ,  //50MHZ
.clk_out2(ram_clk)    //100MHZ
);

assign d_bus_ready=(ram_ready & (!rom_en) & (!uart_en)) | rom_r_ready | uart_ready;
assign bus_data_in=ram_data_in | reg_data | led_r_data | key_r_data | uart_r_data | clnt_r_data;

cpu_jh a1 (
  .clk(cpu_clk) ,
  .cpu_rst(rst_n & down_load_key) ,
  .bus_data_in(bus_data_in) , 
  .d_bus_ready(d_bus_ready) , 
  .i_bus_ready(1'b1),
  .i_data_in(i_data_in) ,
  .pc_set_en(1'b0) , 
  
  .pc_set_data(),
  .e_inter() ,
  
  .data_addr_out(d_addr),
  .d_data_out(d_data_out)  ,
  .d_bus_en(d_en)  ,
  .i_bus_en(i_bus_en)  ,
  .pc_addr_out(pc_addr_out) ,
  
  .ram_we(ram_we), 
  .ram_re(ram_re),
  
  .mem_op_out(mem_op_out)
  );
  

  wire led_en;
  wire key_en;
  
  wire [15:0]rom_addr   ;
  wire rom_r_en   ;
  
  wire [7:0] rom_data;
  
  wire clnt_en;
  wire pic_en;
  
  addr2c a2 (
  .addr(d_addr),
  .d_en(d_en),
  .ram_en(ram_en) ,
  .led_en(led_en) ,
  .key_en(key_en),
  .rom_en(rom_en),
  .uart_en(uart_en),
  .clnt_en(clnt_en),
  .pic_en(pic_en)
  );
  
  rodata rodata(
    .clk(cpu_clk),                       
    .rst_n(rst_n),                     
    .rom_en(rom_en),   //come from addr2
    .mem_op(mem_op_out),               
    .re(ram_re),                        
    .rom_data(rom_data),             
    .addr(d_addr),         
                                
    .rom_addr   (rom_addr   ),             
    .rom_r_en   (rom_r_en   ),    //to rom     
    .reg_data   (reg_data   ),       
    .rom_r_ready(rom_r_ready)           

  );
  
  ram_c b1 (
  .clk(ram_clk) ,
  .i_en(i_bus_en),
  .d_en(ram_en),
  .d_addr((d_addr-32'h2000_0000)),
  .i_addr(pc_addr_out),
  .d_data_in(d_data_out),   //cpu_to_ram
  .mem_op(mem_op_out),
  .we(ram_we),
  .re(ram_re),
  .d_data_out(ram_data_in), //ram_to_cpu
  .i_data(i_data_in_c),
  .ram_ready(ram_ready),
  
  ///////////////////////////////////
  .cpu_clk(cpu_clk),
  .rom_addr(rom_addr),
  .rom_r_en(rom_r_en),
  .rom_data(rom_data),
  ///////////////////////////////////
  .rst_n(rst_n),
  .down_load_key(~down_load_key),
  .uart_rxd(uart_rxd_rom ),
  .uart_txd(uart_rom_tx)
  
  );

/////////////////////////////////////////////////////////////////////////////////led
  
  always@(posedge cpu_clk)
    if(led_en && ram_we)
        led=d_data_out;
  
  always@(*)
    if(led_en && ram_re)
        led_r_data={16'h00_00,led};
    else
        led_r_data=0;
        
////////////////////////////////////////////////////////////////////////////////key       
  always@(*)
    if(key_en && ram_re)
        key_r_data={24'h00_00,key};
    else
        key_r_data=0;    


////////////////////////////////////////////////////////////////////////////////    uart
cpu_uart uart_ctr(
    .clk(cpu_clk),
    .rst_n(rst),
    .rx(uart_rxd_ctr ),
    .uart_en(uart_en),
    .w_en(ram_we),
    .r_en(ram_re),
    .uart_w_data(d_data_out[7:0]),
    .uart_r_data_reg(uart_r_data_u),
    .tx(uart_ctr_tx),
    .uart_ready(uart_ready)
    );
    
    
   clnt clnt(
   .clk(cpu_clk),
   .rst_n(rst),
   .clnt_en(clnt_en),
   .re(ram_re),
   .we(ram_we),
   .clnt_addr(d_addr[2:0]),
   .din(d_data_out),
   .dout(clnt_r_data)
    );
//////////////////////////////////////////////////////////////////////////////////  pic    
/**    
hdmi_clour_bar hdmi_clour_bar(
  .clk50m(cpu_clk),
  .reset_n(rst),

  .hdmi1_clk_p(hdmi1_clk_p),
  .hdmi1_clk_n(hdmi1_clk_n),
  .hdmi1_dat_p(hdmi1_dat_p),
  .hdmi1_dat_n(hdmi1_dat_n),
  .hdmi1_oe(hdmi1_oe),
  
  .addr(d_addr),
  .w_en( pic_en && ram_we ),
  .din(d_data_out[2:0])

);

**/
    
    
endmodule

