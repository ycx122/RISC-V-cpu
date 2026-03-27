OUTPUT_ARCH( "riscv" )
ENTRY(_start)


MEMORY
{
  rom (rxai!w) :   ORIGIN = 0x00000000, LENGTH = 64K
  ram (wa!rix) :   ORIGIN = 0x20000000, LENGTH = 64K
}

SECTIONS
{
    . = 0x00000000;
    
    .text.init : { 
    *(.text.init) 
    }>rom AT>rom
    
    .text : 
    {
      *(.text) 
    }>rom AT>rom
    
    .rodata :
    {
        *(.rodata) 
    }>rom AT>rom
    
    . = ALIGN(4);
	
    .data : 
    { 
        *(.data)
    }>ram AT>rom
    
    .bss : 
    { 
        *(.bss) 
    }>ram AT>ram
    
    _end = .;
}

