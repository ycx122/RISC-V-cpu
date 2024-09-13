module cpu_soc (
  input clk,
  input rst_n,
  
  input e_inter,
  
  input [7:0]key,
  output reg [15:0]led,
  
  input 	uart_rxd,	//接收端口
  output 	uart_txd,	//发送端口
  input down_load_key,   //0 is active
  
  output       tmds_clk_p ,    // TMDS 时钟通道
  output       tmds_clk_n ,
  output [2:0] tmds_data_p,   // TMDS 数据通道
  output [2:0] tmds_data_n

);
wire       tmds_clk_p   ;
wire       tmds_clk_n   ;
wire [2:0] tmds_data_p  ;
wire [2:0] tmds_data_n  ;
/////////////////////////////////
wire[31:0]d_addr       ;
wire[31:0]d_data_in    ;
wire[2:0] d_mem_op_in  ;
wire[31:0]d_data_out   ;
wire      d_bus_en     ;
wire      d_bus_ready  ;
wire      d_ram_we     ;
wire      d_ram_re     ;

wire [31:0]bus_addr     ;
wire [31:0]bus_data_in  ;
wire [2:0] bus_mem_op_in;
wire [31:0]bus_data_out ;
wire       bus_bus_en   ;
wire       bus_bus_ready;
wire        bus_ram_we  ;
wire        bus_ram_re  ;

///////////////////////////////////
reg [31:0] led_r_data;
reg [31:0] key_r_data;

wire i_bus_en;
wire [31:0] i_data_in;
wire [31:0] pc_addr_out;
wire cpu_clk;
wire ram_clk;

//wire [31:0] d_addr;
//wire [31:0] d_data_out;
wire [31:0] ram_data_in;
//wire d_en;

//wire [2:0]mem_op_out;
wire [31:0]i_data_in_c;
//wire d_bus_ready;
wire ram_ready;

//wire [31:0] bus_data_in;

wire [31:0]reg_data   ;
wire rom_r_ready;
wire ram_en;
wire rom_en;


wire uart_en;
wire [8:0]uart_r_data_u;
wire [31:0] uart_r_data={{23{1'b0}},uart_r_data_u};//(bus_mem_op_in==0)?((uart_r_data_u[7]==1)?{{24{1'b1}},uart_r_data_u}:{{24{1'b0}},uart_r_data_u}):{{24{1'b0}},uart_r_data_u};
wire uart_ctr_tx;
wire uart_rom_tx;

wire uart_rxd_ctr;
wire uart_rxd_rom;

wire uart_ready;

wire [31:0] clnt_r_data;
wire [31:0] cnn_r_data;

wire led_ready;
wire key_ready;
wire clnt_ready;
wire pic_ready;
wire cnn_ready;

wire pixel_clk   ;
wire pixel_clk_5x;
wire locked;
wire time_e_inter;

assign uart_rxd_ctr=(down_load_key==1)?uart_rxd:1'b1;
assign uart_rxd_rom=(down_load_key==0)?uart_rxd:1'b1;

assign uart_txd=(down_load_key)?uart_ctr_tx:uart_rom_tx;



assign i_data_in=i_data_in_c;

clk_wiz_0 clk_pll (   //pll
.clk_in1(clk) ,       //50MHZ
.clk_out1(cpu_clk) ,  //100MHZ
.clk_out2(ram_clk) ,
.clk_out3(pixel_clk),
.clk_out4(pixel_clk_5x),
.locked(locked)
);
//assign cpu_clk=clk;
//assign ram_clk=clk;


riscv_bus riscv_bus(
.clk        (cpu_clk),
.rst_n      (rst_n),
////////////////////////////////////// from cpu
.d_addr     (d_addr       ),
.d_data_in  (d_data_in    ),
.d_mem_op_in(d_mem_op_in  ),
.d_data_out (d_data_out   ),
.d_bus_en   (d_bus_en     ),
.d_bus_ready(d_bus_ready  ),
.d_ram_we   (d_ram_we     ),
.d_ram_re   (d_ram_re     ),
///////////////////////////////////// to ram/gpio/uart
.bus_addr     (bus_addr     ),
.bus_data_in  (bus_data_in  ),
.bus_mem_op_in(bus_mem_op_in),
.bus_data_out (bus_data_out ),
.bus_bus_en   (bus_bus_en   ), 
.bus_bus_ready(bus_bus_ready),
.bus_ram_we   ( bus_ram_we  ),
.bus_ram_re   ( bus_ram_re  )
);




///////////////////////////////////////////////////////////////////////////////////////////////////////bus
assign bus_bus_ready=ram_ready | rom_r_ready | uart_ready | led_ready | key_ready | clnt_ready | cnn_ready|pic_ready;
assign bus_data_in=ram_data_in | reg_data | led_r_data | key_r_data | uart_r_data | clnt_r_data | cnn_r_data;
////////////////////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////
//reg e_inter=0;
//initial
//begin
//e_inter=0;
//# 2000
//e_inter=1;
//#40
//e_inter=0;
//end
////////////////////////////////////////////
reg e_inter_d1;
reg e_inter_d2;
always@(posedge cpu_clk) begin
    e_inter_d1<= (~e_inter)|time_e_inter;
    e_inter_d2<=e_inter_d1;
    end

//cpu_core
cpu_jh a1 (
  .clk(cpu_clk) ,
  .cpu_rst(rst_n & down_load_key) ,
  .bus_data_in(d_data_in) , 
  .d_bus_ready(d_bus_ready) , 
  .i_bus_ready(1'b1),
  .i_data_in(i_data_in) ,
  .pc_set_en(1'b0) , 
  
  .pc_set_data(0),
  .e_inter(e_inter_d1 & (~e_inter_d2)) ,
  
  .data_addr_out(d_addr),
  .d_data_out(d_data_out)  ,
  .d_bus_en(d_bus_en)  ,
  .i_bus_en(i_bus_en)  ,
  .pc_addr_out(pc_addr_out) ,
  
  .ram_we(d_ram_we), 
  .ram_re(d_ram_re),
  
  .mem_op_out(d_mem_op_in)
  );
  
  /////////////////////////////////////////////////////////////

  wire led_en;
  wire key_en;
  
  wire [15:0]rom_addr   ;
  wire rom_r_en   ;
  
  wire [7:0] rom_data;
  
  wire clnt_en;
  wire pic_en;
  
  wire cnn_en;
  
  //////////////////////////////////////////////////////////////
  
  addr2c a2 (                       //bus_ctr
  .addr(bus_addr),
  .d_en(bus_bus_en),
  .ram_en(ram_en) ,
  .led_en(led_en) ,
  .key_en(key_en),
  .rom_en(rom_en),
  .uart_en(uart_en),
  .clnt_en(clnt_en),
  .pic_en(pic_en),
  .cnn_en(cnn_en)
  );
  
  rodata rodata(                      //rom_ctr
    .clk(cpu_clk),                       
    .rst_n(rst_n),                     
    .rom_en(rom_en),   //come from addr2
    .mem_op(bus_mem_op_in),               
    .re(bus_ram_re),                        
    .rom_data(rom_data),             
    .addr(bus_addr),         
                                
    .rom_addr   (rom_addr   ),             
    .rom_r_en   (rom_r_en   ),    //to rom     
    .reg_data   (reg_data   ),       
    .rom_r_ready(rom_r_ready)           

  );
  
  ram_c b1 (                            //ram_ctr
  .clk(ram_clk) ,
  .i_en(i_bus_en),
  .d_en(ram_en),
  .d_addr((bus_addr-32'h2000_0000)),
  .i_addr(pc_addr_out),
  .d_data_in(bus_data_out),   //cpu_to_ram
  .mem_op(bus_mem_op_in),
  .we(bus_ram_we),
  .re(bus_ram_re),
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
    if(rst_n==0)
        led=0;
    else if(led_en && bus_ram_we)
        led=bus_data_out;
  
  always@(*)
    if(led_en && bus_ram_re)
        led_r_data={16'h00_00,led};
    else
        led_r_data=0;
        
 assign led_ready=led_en;
        
////////////////////////////////////////////////////////////////////////////////key       
  always@(*)
    if(key_en && bus_ram_re)
        key_r_data={24'h00_00,key};
    else
        key_r_data=0;    

assign key_ready=key_en;

////////////////////////////////////////////////////////////////////////////////    uart
cpu_uart uart_ctr(
    .clk(cpu_clk),
    .rst_n(rst_n),
    .rx(uart_rxd_ctr ),
    .uart_en(uart_en),
    .w_en(bus_ram_we),
    .r_en(bus_ram_re),
    .uart_w_data(bus_data_out[7:0]),
    .uart_r_data_reg(uart_r_data_u),
    .tx(uart_ctr_tx),
    .uart_ready(uart_ready),
    .addr(bus_addr-32'h4300_0000)
    );

///////////////////////////////////////////////////////////////////////////////// clnt    
    
   clnt clnt(
   .clk(cpu_clk),
   .rst_n(rst_n),
   .clnt_en(clnt_en),
   .re(bus_ram_re),
   .we(bus_ram_we),
   .clnt_addr(bus_addr[2:0]),
   .din(bus_data_out),
   .dout(clnt_r_data),
   .clnt_ready(clnt_ready),
   .time_e_inter(time_e_inter)
    );
    
//////////////////////////////////////////////////////////////////////////////////  cnn   
    
cnn_wrapper cnn1(
    .clk(cpu_clk),
    .rst_n(rst_n),
    // Bus signals
    .addr(bus_addr[8:2]),       // 5-bit address for accessing 32 registers plus control/status
    .data_in(bus_data_out),   // Data bus for writing into registers
    .data_out(cnn_r_data), // Data bus for reading from registers
    .wr_en(bus_ram_we&cnn_en),            // Write enable signal
    .rd_en(bus_ram_re&cnn_en),            // Read enable signal
    .ready(cnn_ready)
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

hdmi_colorbar_top hdmi(
    .pixel_clk   (pixel_clk),
    .pixel_clk_5x(pixel_clk_5x),
    .clk_locked(locked),
    
    .cpu_clk (cpu_clk),
    .addr    ((bus_addr-32'h50_00_00_00)>>2),
    .data_in (bus_data_out),
    .w_en    (pic_en && bus_ram_we),
    .ready   (pic_ready),
    
    
    .sys_rst_n(rst_n),
    
    .tmds_clk_p (tmds_clk_p ),    // TMDS 时钟通道
    .tmds_clk_n (tmds_clk_n ),
    .tmds_data_p(tmds_data_p),   // TMDS 数据通道
    .tmds_data_n(tmds_data_n)
);


endmodule

module riscv_bus(
input clk,
input rst_n,
////////////////////////////////////// from cpu

input [31:0]d_addr     ,
output reg [31:0]d_data_in  ,
input [2:0] d_mem_op_in,
input [31:0]d_data_out ,
input       d_bus_en   ,
output reg  d_bus_ready,
input       d_ram_we,
input       d_ram_re,
///////////////////////////////////// to ram/gpio/uart
output[31:0]bus_addr     ,
input [31:0]bus_data_in  ,
output[2:0] bus_mem_op_in,
output[31:0]bus_data_out ,
output      bus_bus_en   , 
input       bus_bus_ready,
output       bus_ram_we  ,
output       bus_ram_re
);
reg[31:0]addr     ;
reg[2:0] mem_op_in;
reg[31:0]data_out ;
reg      bus_en   ;
reg      ram_we   ;
reg      ram_re   ;


reg[31:0]data_in  ;

    
reg [1:0]state =0;
reg [1:0] n_state;


localparam IDLE =2'b00;
localparam WAIT_WBACK   =2'b01;
localparam TRANS   =2'b10;

//assign d_data_in=data_in;


assign bus_addr     =addr      ;
assign bus_mem_op_in=mem_op_in ;
assign bus_data_out =data_out  ;
assign bus_bus_en   =bus_en    ;
assign bus_ram_we   =ram_we    ;
assign bus_ram_re   =ram_re    ;


always@(posedge clk)
if(rst_n==0)
data_in=0;
else if(bus_bus_ready==1)
data_in=bus_data_in;

always@(posedge clk)
    if(rst_n==0)begin
        addr      <=0;
        mem_op_in <=0;
        data_out  <=0;
        bus_en    <=0;
        ram_we    <=0;
        ram_re    <=0;
        end
    else if(d_bus_en==1 & state==IDLE)
    begin
        addr      <=d_addr     ;
        mem_op_in <=d_mem_op_in;
        data_out  <=d_data_out ;
        bus_en    <=d_bus_en   ;
        ram_we    <=d_ram_we;
        ram_re    <=d_ram_re;
        end
    else if(bus_bus_ready==1 )begin
        addr      <=0;
        mem_op_in <=0;
        data_out  <=0;
        bus_en    <=0;
        ram_we    <=0;
        ram_re    <=0;
        end
    

    
    always@(*)
        case(state)
            IDLE:begin
                if(d_bus_en==1)
                    n_state=WAIT_WBACK;
                else
                    n_state=IDLE;
                end
            WAIT_WBACK:begin               
                if(bus_bus_ready==1)
                    n_state=TRANS;
                else
                    n_state=WAIT_WBACK;
                end
            TRANS:begin
                    n_state=IDLE;
                end
            default:n_state=IDLE;
            endcase

    always@(*)
    if(state==TRANS) begin
        d_bus_ready=1;
        d_data_in=data_in;
        end
    else begin
        d_data_in=0;
        d_bus_ready=0;
        end

    always@(posedge clk)
    if(rst_n==0)
        state=IDLE;
    else
        state=n_state;
      



endmodule

