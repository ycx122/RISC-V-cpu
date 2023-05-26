# RISC-V-cpu
一个使用 risc-v 指令集的cpu，RV32I

所有指令都经过modelsim行为级仿真和上板仿真，确认无误。可以使用c语言编译形成的代码。

# 提供一个有趣的汇编编译为机器码的工具
网站 http://tice.sea.eseo.fr/riscv/
具体的gcc工具可以在risc—v官网进行查找（官方提供的GitHub库）

# 框架
RISC CPU常规的五级流水线。跳转指令不预测，直接冲刷流水线。

# 后续开发
暂无

