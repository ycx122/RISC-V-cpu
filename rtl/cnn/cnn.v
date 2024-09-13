module cnn_16x16(
    input clk,
    input rst_n,
    ////////////////////////////////////////
    input a_vaild,
    output a_ready,
    
    input [31:0]in_a0 ,
    input [31:0]in_a1 ,    
    input [31:0]in_a2 ,
    input [31:0]in_a3 ,
    input [31:0]in_a4 ,
    input [31:0]in_a5 ,    
    input [31:0]in_a6 ,
    input [31:0]in_a7 ,
    input [31:0]in_a8 ,
    input [31:0]in_a9 ,    
    input [31:0]in_a10,
    input [31:0]in_a11,
    input [31:0]in_a12,
    input [31:0]in_a13,    
    input [31:0]in_a14,
    input [31:0]in_a15,
    ////////////////////////////////////////
    input b_vaild,
    output b_ready,
    
    input [31:0]in_b0 ,
    input [31:0]in_b1 ,    
    input [31:0]in_b2 ,
    input [31:0]in_b3 ,
    input [31:0]in_b4 ,
    input [31:0]in_b5 ,    
    input [31:0]in_b6 ,
    input [31:0]in_b7 ,
    input [31:0]in_b8 ,
    input [31:0]in_b9 ,    
    input [31:0]in_b10,
    input [31:0]in_b11,
    input [31:0]in_b12,
    input [31:0]in_b13,    
    input [31:0]in_b14,
    input [31:0]in_b15,
    ////////////////////////////////////////
    
    output [31:0]re,
    output re_vaild,
    input  re_ready
    );
    wire [31:0] mul_re0 ;
    wire [31:0] mul_re1 ;
    wire [31:0] mul_re2 ;
    wire [31:0] mul_re3 ;
    wire [31:0] mul_re4 ;
    wire [31:0] mul_re5 ;
    wire [31:0] mul_re6 ;
    wire [31:0] mul_re7 ;
    wire [31:0] mul_re8 ;
    wire [31:0] mul_re9 ;
    wire [31:0] mul_re10;
    wire [31:0] mul_re11;
    wire [31:0] mul_re12;
    wire [31:0] mul_re13;
    wire [31:0] mul_re14;
    wire [31:0] mul_re15;
    
    wire mul_vaild0 ;
    wire mul_vaild1 ;
    wire mul_vaild2 ;
    wire mul_vaild3 ;
    wire mul_vaild4 ;
    wire mul_vaild5 ;
    wire mul_vaild6 ;
    wire mul_vaild7 ;
    wire mul_vaild8 ;
    wire mul_vaild9 ;
    wire mul_vaild10;
    wire mul_vaild11;
    wire mul_vaild12;
    wire mul_vaild13;
    wire mul_vaild14;
    wire mul_vaild15;
   
    wire mul_ready0 ;
    wire mul_ready1 ;
    wire mul_ready2 ;
    wire mul_ready3 ;
    wire mul_ready4 ;
    wire mul_ready5 ;
    wire mul_ready6 ;
    wire mul_ready7 ;
    wire mul_ready8 ;
    wire mul_ready9 ;
    wire mul_ready10;
    wire mul_ready11;
    wire mul_ready12;
    wire mul_ready13;
    wire mul_ready14;
    wire mul_ready15;


    wire [31:0] add_re0 ;
    wire [31:0] add_re1 ;
    wire [31:0] add_re2 ;
    wire [31:0] add_re3 ;
    wire [31:0] add_re4 ;
    wire [31:0] add_re5 ;
    wire [31:0] add_re6 ;
    wire [31:0] add_re7 ;
    wire [31:0] add_re8 ;
    wire [31:0] add_re9 ;
    wire [31:0] add_re10;
    wire [31:0] add_re11;
    wire [31:0] add_re12;
    wire [31:0] add_re13;
    wire [31:0] add_re14;
    wire [31:0] add_re15;
    
    wire add_vaild0 ;
    wire add_vaild1 ;
    wire add_vaild2 ;
    wire add_vaild3 ;
    wire add_vaild4 ;
    wire add_vaild5 ;
    wire add_vaild6 ;
    wire add_vaild7 ;
    wire add_vaild8 ;
    wire add_vaild9 ;
    wire add_vaild10;
    wire add_vaild11;
    wire add_vaild12;
    wire add_vaild13;
    wire add_vaild14;
    wire add_vaild15;
   
    wire add_ready0 ;
    wire add_ready1 ;
    wire add_ready2 ;
    wire add_ready3 ;
    wire add_ready4 ;
    wire add_ready5 ;
    wire add_ready6 ;
    wire add_ready7 ;
    wire add_ready8 ;
    wire add_ready9 ;
    wire add_ready10;
    wire add_ready11;
    wire add_ready12;
    wire add_ready13;
    wire add_ready14;
    wire add_ready15;

    wire a_ready0 ;
    wire a_ready1 ;
    wire a_ready2 ;
    wire a_ready3 ;
    wire a_ready4 ;
    wire a_ready5 ;
    wire a_ready6 ;
    wire a_ready7 ;
    wire a_ready8 ;
    wire a_ready9 ;
    wire a_ready10;
    wire a_ready11;
    wire a_ready12;
    wire a_ready13;
    wire a_ready14;
    wire a_ready15;

    wire b_ready0 ;
    wire b_ready1 ;
    wire b_ready2 ;
    wire b_ready3 ;
    wire b_ready4 ;
    wire b_ready5 ;
    wire b_ready6 ;
    wire b_ready7 ;
    wire b_ready8 ;
    wire b_ready9 ;
    wire b_ready10;
    wire b_ready11;
    wire b_ready12;
    wire b_ready13;
    wire b_ready14;
    wire b_ready15;

assign a_ready=a_ready0 
|a_ready1 
|a_ready2 
|a_ready3 
|a_ready4 
|a_ready5 
|a_ready6 
|a_ready7 
|a_ready8 
|a_ready9 
|a_ready10
|a_ready11
|a_ready12
|a_ready13
|a_ready14
|a_ready15;


assign b_ready=b_ready0 
| b_ready1 
| b_ready2 
| b_ready3 
| b_ready4 
| b_ready5 
| b_ready6 
| b_ready7 
| b_ready8 
| b_ready9 
| b_ready10
| b_ready11
| b_ready12
| b_ready13
| b_ready14
| b_ready15 ;





floating_point_mul floating_point_mul0(
  .aclk                 (clk),
  .s_axis_a_tvalid      (a_vaild),
  .s_axis_a_tready      (a_ready0),
  .s_axis_a_tdata       (in_a0),
  
  .s_axis_b_tvalid      (b_vaild),
  .s_axis_b_tready      (b_ready0),
  .s_axis_b_tdata       (in_b0),
  
  .m_axis_result_tvalid (mul_vaild0),
  .m_axis_result_tready (mul_ready0),
  .m_axis_result_tdata  (mul_re0)
);

floating_point_mul floating_point_mul1(
  .aclk                 (clk),
  .s_axis_a_tvalid      (a_vaild),
  .s_axis_a_tready      (a_ready1),
  .s_axis_a_tdata       (in_a1),
  
  .s_axis_b_tvalid      (b_vaild),
  .s_axis_b_tready      (b_ready1),
  .s_axis_b_tdata       (in_b1),
  
  .m_axis_result_tvalid (mul_vaild1),
  .m_axis_result_tready (mul_ready1),
  .m_axis_result_tdata  (mul_re1)
);

floating_point_mul floating_point_mul2(
  .aclk                 (clk),
  .s_axis_a_tvalid      (a_vaild),
  .s_axis_a_tready      (a_ready2),
  .s_axis_a_tdata       (in_a2),
  
  .s_axis_b_tvalid      (b_vaild),
  .s_axis_b_tready      (b_ready2),
  .s_axis_b_tdata       (in_b2),
  
  .m_axis_result_tvalid (mul_vaild2),
  .m_axis_result_tready (mul_ready2),
  .m_axis_result_tdata  (mul_re2)
);

floating_point_mul floating_point_mul3(
  .aclk                 (clk),
  .s_axis_a_tvalid      (a_vaild),
  .s_axis_a_tready      (a_ready3),
  .s_axis_a_tdata       (in_a3),
  
  .s_axis_b_tvalid      (b_vaild),
  .s_axis_b_tready      (b_ready3),
  .s_axis_b_tdata       (in_b3),
  
  .m_axis_result_tvalid (mul_vaild3),
  .m_axis_result_tready (mul_ready3),
  .m_axis_result_tdata  (mul_re3)
);

///////////////////////////////////////////////////////////////////////////////////////

floating_point_mul floating_point_mul4(
  .aclk                 (clk),
  .s_axis_a_tvalid      (a_vaild),
  .s_axis_a_tready      (a_ready4),
  .s_axis_a_tdata       (in_a4),
  
  .s_axis_b_tvalid      (b_vaild),
  .s_axis_b_tready      (b_ready4),
  .s_axis_b_tdata       (in_b4),
  
  .m_axis_result_tvalid (mul_vaild4),
  .m_axis_result_tready (mul_ready4),
  .m_axis_result_tdata  (mul_re4)
);

floating_point_mul floating_point_mul5(
  .aclk                 (clk),
  .s_axis_a_tvalid      (a_vaild),
  .s_axis_a_tready      (a_ready5),
  .s_axis_a_tdata       (in_a5),
  
  .s_axis_b_tvalid      (b_vaild),
  .s_axis_b_tready      (b_ready5),
  .s_axis_b_tdata       (in_b5),
  
  .m_axis_result_tvalid (mul_vaild5),
  .m_axis_result_tready (mul_ready5),
  .m_axis_result_tdata  (mul_re5)
);

floating_point_mul floating_point_mul6(
  .aclk                 (clk),
  .s_axis_a_tvalid      (a_vaild),
  .s_axis_a_tready      (a_ready6),
  .s_axis_a_tdata       (in_a6),
  
  .s_axis_b_tvalid      (b_vaild),
  .s_axis_b_tready      (b_ready6),
  .s_axis_b_tdata       (in_b6),
  
  .m_axis_result_tvalid (mul_vaild6),
  .m_axis_result_tready (mul_ready6),
  .m_axis_result_tdata  (mul_re6)
);

floating_point_mul floating_point_mul7(
  .aclk                 (clk),
  .s_axis_a_tvalid      (a_vaild),
  .s_axis_a_tready      (a_ready7),
  .s_axis_a_tdata       (in_a7),
  
  .s_axis_b_tvalid      (b_vaild),
  .s_axis_b_tready      (b_ready7),
  .s_axis_b_tdata       (in_b7),
  
  .m_axis_result_tvalid (mul_vaild7),
  .m_axis_result_tready (mul_ready7),
  .m_axis_result_tdata  (mul_re7)
);

///////////////////////////////////////////////////////////////////////////////////////

floating_point_mul floating_point_mul8(
  .aclk                 (clk),
  .s_axis_a_tvalid      (a_vaild),
  .s_axis_a_tready      (a_ready8),
  .s_axis_a_tdata       (in_a8),
  
  .s_axis_b_tvalid      (b_vaild),
  .s_axis_b_tready      (b_ready8),
  .s_axis_b_tdata       (in_b8),
  
  .m_axis_result_tvalid (mul_vaild8),
  .m_axis_result_tready (mul_ready8),
  .m_axis_result_tdata  (mul_re8)
);

floating_point_mul floating_point_mul9(
  .aclk                 (clk),
  .s_axis_a_tvalid      (a_vaild),
  .s_axis_a_tready      (a_ready9),
  .s_axis_a_tdata       (in_a9),
  
  .s_axis_b_tvalid      (b_vaild),
  .s_axis_b_tready      (b_ready9),
  .s_axis_b_tdata       (in_b9),
  
  .m_axis_result_tvalid (mul_vaild9),
  .m_axis_result_tready (mul_ready9),
  .m_axis_result_tdata  (mul_re9)
);

floating_point_mul floating_point_mul10(
  .aclk                 (clk),
  .s_axis_a_tvalid      (a_vaild),
  .s_axis_a_tready      (a_ready10),
  .s_axis_a_tdata       (in_a10),
  
  .s_axis_b_tvalid      (b_vaild),
  .s_axis_b_tready      (b_ready10),
  .s_axis_b_tdata       (in_b10),
  
  .m_axis_result_tvalid (mul_vaild10),
  .m_axis_result_tready (mul_ready10),
  .m_axis_result_tdata  (mul_re10)
);

floating_point_mul floating_point_mul11(
  .aclk                 (clk),
  .s_axis_a_tvalid      (a_vaild),
  .s_axis_a_tready      (a_ready11),
  .s_axis_a_tdata       (in_a11),
  
  .s_axis_b_tvalid      (b_vaild),
  .s_axis_b_tready      (b_ready11),
  .s_axis_b_tdata       (in_b11),
  
  .m_axis_result_tvalid (mul_vaild11),
  .m_axis_result_tready (mul_ready11),
  .m_axis_result_tdata  (mul_re11)
);

///////////////////////////////////////////////////////////////////////////////////////

floating_point_mul floating_point_mul12(
  .aclk                 (clk),
  .s_axis_a_tvalid      (a_vaild),
  .s_axis_a_tready      (a_ready12),
  .s_axis_a_tdata       (in_a12),
  
  .s_axis_b_tvalid      (b_vaild),
  .s_axis_b_tready      (b_ready12),
  .s_axis_b_tdata       (in_b12),
  
  .m_axis_result_tvalid (mul_vaild12),
  .m_axis_result_tready (mul_ready12),
  .m_axis_result_tdata  (mul_re12)
);

floating_point_mul floating_point_mul13(
  .aclk                 (clk),
  .s_axis_a_tvalid      (a_vaild),
  .s_axis_a_tready      (a_ready13),
  .s_axis_a_tdata       (in_a13),
  
  .s_axis_b_tvalid      (b_vaild),
  .s_axis_b_tready      (b_ready13),
  .s_axis_b_tdata       (in_b13),
  
  .m_axis_result_tvalid (mul_vaild13),
  .m_axis_result_tready (mul_ready13),
  .m_axis_result_tdata  (mul_re13)
);

floating_point_mul floating_point_mul14(
  .aclk                 (clk),
  .s_axis_a_tvalid      (a_vaild),
  .s_axis_a_tready      (a_ready14),
  .s_axis_a_tdata       (in_a14),
  
  .s_axis_b_tvalid      (b_vaild),
  .s_axis_b_tready      (b_ready14),
  .s_axis_b_tdata       (in_b14),
  
  .m_axis_result_tvalid (mul_vaild14),
  .m_axis_result_tready (mul_ready14),
  .m_axis_result_tdata  (mul_re14)
);

floating_point_mul floating_point_mul15(
  .aclk                 (clk),
  .s_axis_a_tvalid      (a_vaild),
  .s_axis_a_tready      (a_ready15),
  .s_axis_a_tdata       (in_a15),
  
  .s_axis_b_tvalid      (b_vaild),
  .s_axis_b_tready      (b_ready15),
  .s_axis_b_tdata       (in_b15),
  
  .m_axis_result_tvalid (mul_vaild15),
  .m_axis_result_tready (mul_ready15),
  .m_axis_result_tdata  (mul_re15)
);

///////////////////////////////////////////////////////////////////////////////////////

floating_point_add floating_point_add0(
  .aclk                 (clk),
  .s_axis_a_tvalid      (mul_vaild0),
  .s_axis_a_tready      (mul_ready0),
  .s_axis_a_tdata       (mul_re0),
  
  .s_axis_b_tvalid      (mul_vaild1),
  .s_axis_b_tready      (mul_ready1),
  .s_axis_b_tdata       (mul_re1),
  
  .m_axis_result_tvalid (add_vaild0),
  .m_axis_result_tready (add_ready0),
  .m_axis_result_tdata  (add_re0)
);

floating_point_add floating_point_add1(
  .aclk                 (clk),
  .s_axis_a_tvalid      (mul_vaild2),
  .s_axis_a_tready      (mul_ready2),
  .s_axis_a_tdata       (mul_re2),
  
  .s_axis_b_tvalid      (mul_vaild3),
  .s_axis_b_tready      (mul_ready3),
  .s_axis_b_tdata       (mul_re3),
  
  .m_axis_result_tvalid (add_vaild1),
  .m_axis_result_tready (add_ready1),
  .m_axis_result_tdata  (add_re1)
);

floating_point_add floating_point_add2(
  .aclk                 (clk),
  .s_axis_a_tvalid      (mul_vaild4),
  .s_axis_a_tready      (mul_ready4),
  .s_axis_a_tdata       (mul_re4),
  
  .s_axis_b_tvalid      (mul_vaild5),
  .s_axis_b_tready      (mul_ready5),
  .s_axis_b_tdata       (mul_re5),
  
  .m_axis_result_tvalid (add_vaild2),
  .m_axis_result_tready (add_ready2),
  .m_axis_result_tdata  (add_re2)
);

floating_point_add floating_point_add3(
  .aclk                 (clk),
  .s_axis_a_tvalid      (mul_vaild6),
  .s_axis_a_tready      (mul_ready6),
  .s_axis_a_tdata       (mul_re6),
  
  .s_axis_b_tvalid      (mul_vaild7),
  .s_axis_b_tready      (mul_ready7),
  .s_axis_b_tdata       (mul_re7),
  
  .m_axis_result_tvalid (add_vaild3),
  .m_axis_result_tready (add_ready3),
  .m_axis_result_tdata  (add_re3)
);

floating_point_add floating_point_add4(
  .aclk                 (clk),
  .s_axis_a_tvalid      (mul_vaild8),
  .s_axis_a_tready      (mul_ready8),
  .s_axis_a_tdata       (mul_re8),
  
  .s_axis_b_tvalid      (mul_vaild9),
  .s_axis_b_tready      (mul_ready9),
  .s_axis_b_tdata       (mul_re9),
  
  .m_axis_result_tvalid (add_vaild4),
  .m_axis_result_tready (add_ready4),
  .m_axis_result_tdata  (add_re4)
);

floating_point_add floating_point_add5(
  .aclk                 (clk),
  .s_axis_a_tvalid      (mul_vaild10),
  .s_axis_a_tready      (mul_ready10),
  .s_axis_a_tdata       (mul_re10),
  
  .s_axis_b_tvalid      (mul_vaild11),
  .s_axis_b_tready      (mul_ready11),
  .s_axis_b_tdata       (mul_re11),
  
  .m_axis_result_tvalid (add_vaild5),
  .m_axis_result_tready (add_ready5),
  .m_axis_result_tdata  (add_re5)
);

floating_point_add floating_point_add6(
  .aclk                 (clk),
  .s_axis_a_tvalid      (mul_vaild12),
  .s_axis_a_tready      (mul_ready12),
  .s_axis_a_tdata       (mul_re12),
  
  .s_axis_b_tvalid      (mul_vaild13),
  .s_axis_b_tready      (mul_ready13),
  .s_axis_b_tdata       (mul_re13),
  
  .m_axis_result_tvalid (add_vaild6),
  .m_axis_result_tready (add_ready6),
  .m_axis_result_tdata  (add_re6)
);

floating_point_add floating_point_add7(
  .aclk                 (clk),
  .s_axis_a_tvalid      (mul_vaild14),
  .s_axis_a_tready      (mul_ready14),
  .s_axis_a_tdata       (mul_re14),
  
  .s_axis_b_tvalid      (mul_vaild15),
  .s_axis_b_tready      (mul_ready15),
  .s_axis_b_tdata       (mul_re15),
  
  .m_axis_result_tvalid (add_vaild7),
  .m_axis_result_tready (add_ready7),
  .m_axis_result_tdata  (add_re7)
);

/////////////////////////////////////////////////////////////////////////////////////////////
floating_point_add floating_point_add1_0(
  .aclk                 (clk),
  .s_axis_a_tvalid      (add_vaild7),
  .s_axis_a_tready      (add_ready7),
  .s_axis_a_tdata       (add_re7   ),
  
  .s_axis_b_tvalid      (add_vaild6),
  .s_axis_b_tready      (add_ready6),
  .s_axis_b_tdata       (add_re6   ),
  
  .m_axis_result_tvalid (add_vaild8),
  .m_axis_result_tready (add_ready8),
  .m_axis_result_tdata  (add_re8)
);

floating_point_add floating_point_add1_1(
  .aclk                 (clk),
  .s_axis_a_tvalid      (add_vaild5),
  .s_axis_a_tready      (add_ready5),
  .s_axis_a_tdata       (add_re5   ),
  
  .s_axis_b_tvalid      (add_vaild4),
  .s_axis_b_tready      (add_ready4),
  .s_axis_b_tdata       (add_re4   ),
  
  .m_axis_result_tvalid (add_vaild9),
  .m_axis_result_tready (add_ready9),
  .m_axis_result_tdata  (add_re9)
);

floating_point_add floating_point_add1_2(
  .aclk                 (clk),
  .s_axis_a_tvalid      (add_vaild3),
  .s_axis_a_tready      (add_ready3),
  .s_axis_a_tdata       (add_re3   ),
  
  .s_axis_b_tvalid      (add_vaild2),
  .s_axis_b_tready      (add_ready2),
  .s_axis_b_tdata       (add_re2   ),
  
  .m_axis_result_tvalid (add_vaild10),
  .m_axis_result_tready (add_ready10),
  .m_axis_result_tdata  (add_re10)
);

floating_point_add floating_point_add1_3(
  .aclk                 (clk),
  .s_axis_a_tvalid      (add_vaild1),
  .s_axis_a_tready      (add_ready1),
  .s_axis_a_tdata       (add_re1   ),
  
  .s_axis_b_tvalid      (add_vaild0),
  .s_axis_b_tready      (add_ready0),
  .s_axis_b_tdata       (add_re0   ),
  
  .m_axis_result_tvalid (add_vaild11),
  .m_axis_result_tready (add_ready11),
  .m_axis_result_tdata  (add_re11)
);

floating_point_add floating_point_add2_0(
  .aclk                 (clk),
  .s_axis_a_tvalid      (add_vaild8),
  .s_axis_a_tready      (add_ready8),
  .s_axis_a_tdata       (add_re8   ),
  
  .s_axis_b_tvalid      (add_vaild9),
  .s_axis_b_tready      (add_ready9),
  .s_axis_b_tdata       (add_re9   ),
  
  .m_axis_result_tvalid (add_vaild12),
  .m_axis_result_tready (add_ready12),
  .m_axis_result_tdata  (add_re12)
);

floating_point_add floating_point_add2_1(
  .aclk                 (clk),
  .s_axis_a_tvalid      (add_vaild10),
  .s_axis_a_tready      (add_ready10),
  .s_axis_a_tdata       (add_re10   ),
  
  .s_axis_b_tvalid      (add_vaild11),
  .s_axis_b_tready      (add_ready11),
  .s_axis_b_tdata       (add_re11   ),
  
  .m_axis_result_tvalid (add_vaild13),
  .m_axis_result_tready (add_ready13),
  .m_axis_result_tdata  (add_re13)
);

floating_point_add floating_point_add3_0(
  .aclk                 (clk),
  .s_axis_a_tvalid      (add_vaild12),
  .s_axis_a_tready      (add_ready12),
  .s_axis_a_tdata       (add_re12   ),
  
  .s_axis_b_tvalid      (add_vaild13),
  .s_axis_b_tready      (add_ready13),
  .s_axis_b_tdata       (add_re13   ),
  
  .m_axis_result_tvalid (add_vaild14),
  .m_axis_result_tready (add_ready14),
  .m_axis_result_tdata  (add_re14)
);
  assign re=add_re14;
  assign re_vaild=add_vaild14;
  assign add_ready14=re_ready;



endmodule
