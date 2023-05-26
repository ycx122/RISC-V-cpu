module otof(
    input clk,
    input [4:0] rs1,
    input [4:0] rs2,
    input [4:0] rd,
    input [4:0] rd_wb,
    input wb_en_2,
    input wb_en_5,
    input rst,
    
    input en,
    
    output reg local_stop
    );
    
    (* keep = "true" *)reg lunch_f0,lunch_f1,lunch_f2,lunch_f3;
    
    (* keep = "true" *)reg [4:0] wb_reg1,wb_reg2,wb_reg3,wb_reg0;
    
    (* keep = "true" *)reg eque_rs1;
    (* keep = "true" *)reg eque_rs2;
    
    always@(*)
        if( (rs1==wb_reg0 || rs1==wb_reg1 || rs1==wb_reg2  || rs1==wb_reg3) && rs1!=0  )
            eque_rs1=1;
        else 
            eque_rs1=0;
            
   always@(*)
        if( (rs2==wb_reg0 || rs2==wb_reg1 || rs2==wb_reg2  || rs2==wb_reg3) && rs2!=0  )
            eque_rs2=1;
        else 
            eque_rs2=0;
    always@(*)
        if(eque_rs2==1 || eque_rs1==1)
            local_stop=1;
        else
            local_stop=0;
    
    
//////////////////////////////////////////////////////////////////
    
    always@(posedge clk)
        if(rst==0)
            wb_reg0<=0;
        else if(rd_wb==wb_reg0 && wb_en_5==1  && rd_wb!=0)
            wb_reg0<=0;
        else if(wb_en_2==1 && lunch_f0==0 && rd!=0 && en==1)
            wb_reg0<=rd;
        
    always@(posedge clk)
        if(rst==0)
            wb_reg1<=0;
        else if(rd_wb==wb_reg1 && wb_en_5==1 && rd_wb!=0 && rd_wb!=wb_reg0)
            wb_reg1<=0;
        else if(wb_en_2==1 && lunch_f1==0 && lunch_f0==1 && rd!=0 && en==1)
            wb_reg1<=rd;    
            
    always@(posedge clk)
        if(rst==0)
            wb_reg2<=0;
        else if(rd_wb==wb_reg2 && wb_en_5==1 && rd_wb!=0 && rd_wb!=wb_reg0 && rd_wb!=wb_reg1)
            wb_reg2<=0;
        else if(wb_en_2==1 && lunch_f1==1 && lunch_f0==1 && lunch_f2==0 && rd!=0 && en==1)
            wb_reg2<=rd;
            
    always@(posedge clk)
        if(rst==0)
            wb_reg3<=0;
        else if(rd_wb==wb_reg3 && wb_en_5==1 && rd_wb!=0 && rd_wb!=wb_reg0 && rd_wb!=wb_reg1 && rd_wb!=wb_reg2)
            wb_reg3<=0;            
        else if(wb_en_2==1 && lunch_f1==1 && lunch_f0==1 && lunch_f2==1 && lunch_f3==0 && rd!=0 && en==1)
            wb_reg3<=rd;  
             
            
//////////////////////////////////////////////////////    
    always@(posedge clk)
        if(rst==0)
            lunch_f0<=0;
        else if(rd_wb==wb_reg0 && wb_en_5==1  && rd_wb!=0)
            lunch_f0<=0;
        else if(wb_en_2==1 && lunch_f0==0 && rd!=0 && en==1)
            lunch_f0<=1;
    
    always@(posedge clk)
        if(rst==0)
            lunch_f1<=0;
        else if(rd_wb==wb_reg1 && wb_en_5==1 && rd_wb!=0 && rd_wb!=wb_reg0)
            lunch_f1<=0;
        else if(wb_en_2==1 && lunch_f1==0 && lunch_f0==1 && rd!=0 && en==1)
            lunch_f1<=1;            
            
    always@(posedge clk)
        if(rst==0)
            lunch_f2<=0;
        else if(rd_wb==wb_reg2 && wb_en_5==1 && rd_wb!=0 && rd_wb!=wb_reg0 && rd_wb!=wb_reg1)
            lunch_f2<=0;
        else if(wb_en_2==1 && lunch_f1==1 && lunch_f0==1 && lunch_f2==0 && rd!=0 && en==1)
            lunch_f2<=1; 
            
    always@(posedge clk)
        if(rst==0)
            lunch_f3<=0;
        else if(rd_wb==wb_reg3 && wb_en_5==1 && rd_wb!=0 && rd_wb!=wb_reg0 && rd_wb!=wb_reg1 && rd_wb!=wb_reg2)
            lunch_f3<=0;
        else if(wb_en_2==1 && lunch_f1==1 && lunch_f0==1 && lunch_f2==1 && lunch_f3==0 && rd!=0 && en==1)
            lunch_f3<=1;             
    
    
    
    
endmodule