# RISC-V-cpu
一个使用 risc-v 指令集的cpu

所有指令都经过modelsim行为级仿真测试，没有遇到问题

# 提供一个有趣的汇编编译为机器码的工具
网站 http://tice.sea.eseo.fr/riscv/
具体的gcc工具可以在risc—v官网进行查找（官方提供的GitHub库）

# 框架
RISC CPU常规的五级流水线。跳转指令不预测，直接冲刷流水线。

# 后续开发

目前cpu处于初级阶段，使用较高层次的行为级描述建模，还可以进一步细化进行相应的开发。
