#include "../include/500a.h"

extern void fill_array(float* src, float* dest, int len);
float* cnn_ptr;

void wait_cnn_result(){
	
	while(*(cnn_ptr+34) ==0){    //is re valid
		
	}
	
}

float get_cnn_result(){
	
	return (*(cnn_ptr+33)) ;
	
}

void cnn_a_fill(float *a){
	
	
	fill_array(a, cnn_ptr, 16);
	
	
}

void cnn_b_fill(float *b){
	
	fill_array(b, cnn_ptr+16, 16);
	
}

void cnn_start(){
	
		*(cnn_ptr+32)=1;  //start computer
	
}

float InvSqrt(float x)
{
    float xhalf = 0.5f*x;
    int i = *(int*)&x; // get bits for floating VALUE 
    i = 0x5f375a86- (i>>1); // gives initial guess y0
    x = *(float*)&i; // convert bits BACK to float
    x = x*(1.5f-xhalf*x*x); // Newton step, repeating increases accuracy
    x = x*(1.5f-xhalf*x*x); // Newton step, repeating increases accuracy
    x = x*(1.5f-xhalf*x*x); // Newton step, repeating increases accuracy

    return 1/x;
}

//////////////////////////////////////////////////////////////////////////////////
float BN1_bias[8] = {-0.27537104,0.030754639,-0.011053412,0.085985944,0.22936966,0.026348703,0.16049820,0.42847496};
float BN1_weight[8] = {0.62367034,0.84134376,1.0878372,0.79262042,0.50660938,0.94630951,0.78199196,0.43972337};
float BN1_mean[8] = {0.097767130,0.080128297,-0.16926473,0.14075334,0.16014580,-0.042374808,0.25471988,0.027786441};
float BN1_var[8] = {0.35349211,0.18690374,1.0513554,0.31012776,0.64914739,0.19614591,1.1050427,1.2181598};

float BN2_bias[8] = {-0.26388049,-0.043216743,0.31687236,0.21173026,0.27213928,0.23971127,0.37337458,0.34654677};
float BN2_weight[8] = {1.0404744,1.0530006,1.2847824,1.3477633,1.0504165,1.0308563,1.2794256,1.2796582};
float BN2_mean[8] = {-0.032174170,-0.11227562,-0.21804683,-0.14492525,0.19528864,-0.096821241,0.24040088,0.32524592};
float BN2_var[8] = {0.050037812,0.27428067,0.027961724,0.43082830,0.090213597,0.079475857,0.62828022,0.036136918};

float fc_bias[2] = {-0.20975235,-0.21913882};
float fc_weight[2][8] = {{0.29891759,0.041057885,-0.28072003,0.65356690,-0.35423139,0.37486383,0.59477103,-0.011380713},
                                        {-0.11617786,-0.34778461,0.45367137,-0.49875751,0.18035783,-0.18061233,-0.46998841,0.36476001}};

float conv1[4][4][8]={1};
float conv2[4][4][8]={1};
float conv3[4][4][8]={1};
float XTest[93][65]={1};

  float x0[97][69] = {0};
  float x1[47][33][8] = {0};
  float x2[47][33][8] = {0};
  float xp1[51][37][8] = {0};
  float x3[24][17][8] = {0};
  float x4[24][17][8] = {0};
  float xp2[28][21][8] = {0};
  float x[13][9][8] = {0};

  float xm[8] = {-1024};
//  float xf[2] = {0};
  float kernel[4][4],a[4][4];
  float xf_sum = 0;
  float xf0 = -0.20975235;
  float xf1 = -0.21913882;
  int y = 0;

void loop() {


  xprintf("start get");
  //第一层卷积
  for(int i=0;i<93;i++)
  {
    for(int j=0;j<65;j++)
      x0[i+2][j+2] = XTest[i][j];
  }
  for(int k=0;k<8;k++)
  {
    for(int i=0;i<4;i++)
    {
      for(int j=0;j<4;j++)
        kernel[i][j] = conv1[i][j][k];
    }
    for(int i=0;i<47;i++)
    {
      for(int j=0;j<33;j++)
      {
        for(int m=0;m<4;m++)//矩阵乘法
        {
          for(int n=0;n<4;n++)
          {
            a[m][n] = x0[2*i+m][2*j+n]*kernel[m][n];
            x1[i][j][k] += a[m][n];
          }
        }
      }
    }
  }
  
  for(int k=0;k<8;k++)
  {
    for(int i=0;i<47;i++)
    {
      for(int j=0;j<33;j++)
        x2[i][j][k] = BN1_weight[k]*(x1[i][j][k]-BN1_mean[k])/InvSqrt(BN1_var[k])+BN1_bias[k];
    }
  }

  for(int k=0;k<8;k++)
  {
    for(int i=0;i<47;i++)
    {
      for(int j=0;j<33;j++)
      {
        if(x2[i][j][k]<0)
          x2[i][j][k] = 0;
      }
    }
  }

  //第二层卷积
  for(int k=0;k<8;k++)
  {
    for(int i=0;i<47;i++)
    {
      for(int j=0;j<33;j++)
        xp1[i+2][j+2][k] = x2[i][j][k];
    } 
  }
  for(int k=0;k<8;k++)
  {
    for(int i=0;i<4;i++)
    {
      for(int j=0;j<4;j++)
        kernel[i][j] = conv2[i][j][k];
    }
    for(int i=0;i<24;i++)
    {
      for(int j=0;j<17;j++)
      {
        for(int m=0;m<4;m++)
        {
          for(int n=0;n<4;n++)
          {
            a[m][n] = xp1[2*i+m][2*j+n][k]*kernel[m][n];
            x3[i][j][k] += a[m][n];
          }
        }
      }
    }
  }
  
  for(int k=0;k<8;k++)
  {
    for(int i=0;i<24;i++)
    {
      for(int j=0;j<17;j++)
        x4[i][j][k] = BN2_weight[k]*(x3[i][j][k]-BN2_mean[k])/InvSqrt(BN2_var[k])+BN2_bias[k];
    }
  }

  for(int k=0;k<8;k++)
  {
    for(int i=0;i<24;i++)
    {
      for(int j=0;j<17;j++)
      {
        if(x4[i][j][k]<0)
          x4[i][j][k] = 0;
      }
    }
  }

  //第三层卷积
  for(int k=0;k<8;k++)
  {
    for(int i=0;i<24;i++)
    {
      for(int j=0;j<17;j++)
        xp2[i+2][j+2][k] = x4[i][j][k];
    } 
  }
  for(int k=0;k<8;k++)
  {
    for(int i=0;i<4;i++)
    {
      for(int j=0;j<4;j++)
        kernel[i][j] = conv3[i][j][k];
    }
    for(int i=0;i<13;i++)
    {
      for(int j=0;j<9;j++)
      {
        for(int m=0;m<4;m++)
        {
          for(int n=0;n<4;n++)
          {
            a[m][n] = xp2[2*i+m][2*j+n][k]*kernel[m][n];
            x[i][j][k] += a[m][n];
          }
        }
      }
    }
  }

  //最大池化
  for(int k=0;k<8;k++)
  {
    for(int i=0;i<13;i++)
    {
      for(int j=0;j<9;j++)
      {
        if(x[i][j][k]>xm[k])
          xm[k] = x[i][j][k];
      }
    }
  }

  for(int k=0;k<8;k++)
  {
    xf0 += fc_weight[0][k]*xm[k];
    xf1 += fc_weight[1][k]*xm[k];
  }
  if(xf1>0.45)
    y = 1;
  else 
    y = 0;
  xprintf("result= %f",y);
}


void main ()
{
    cpu_init();
    GPIO_FLAG=0;    
    GPIO_LED=0;
	
	cnn_ptr=(float *)0x60000000;
	

	xprintf("go to while");
    while (1){
		
	//cnn_b_fill(a);
	//cnn_a_fill(a);
	
	//cnn_start();
	
	//wait_cnn_result();
	
	//float re=get_cnn_result();
	loop();
	

	
    }
    
    
    
}
