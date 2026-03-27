# RISC-V CPU

一个基于 Verilog 编写的 `RV32IM` 五级流水线 RISC-V SoC 项目。仓库内容不只是一个 CPU 内核，还包含总线、存储器、UART 和定时中断，目标平台为 Xilinx FPGA。

当前仓库内只有这一份项目说明文档，因此本文档按代码实际结构重写，尽量回答这几个最核心的问题：

- 这个项目实现了什么
- 顶层模块和目录应该从哪里看起
- CPU 和外设如何连接
- 地址空间如何划分
- 现有仓库怎样做仿真、怎样理解上板流程

## 项目概览

项目核心是一个 `RV32IM` 五级流水线 CPU，SoC 顶层位于 `rtl/soc/cpu_soc.v`。从代码实现来看，系统具备以下能力：

- 五级流水线 CPU 核，核心文件为 `rtl/core/cpu_jh.v`
- 支持整数基础指令、乘除法扩展，以及一组机器态 CSR/异常相关指令
- 指令取指、数据访存、片上 RAM/ROM 与 MMIO 外设访问
- UART 串口通信
- `clnt` 定时器/中断相关寄存器
- UART 下载模式，用于向片上指令存储区写入程序

README 原文提到该项目经过仿真和上板验证；当前仓库保留了仿真入口 `sim/tb/cpu_test.v`，并通过 `sim/models/xilinx_compat.v` 提供 `iverilog` 兼容模型。

## 目录结构

项目主要目录如下：

| 路径 | 说明 |
| --- | --- |
| `rtl/core` | CPU 核心流水线与功能模块，如译码、ALU、寄存器堆、乘除法、CSR、PC 等 |
| `rtl/interconnect` | 地址译码与 CPU 访存总线握手控制 |
| `rtl/memory` | 数据 RAM、指令 ROM、只读数据与下载路径控制 |
| `rtl/peripherals` | UART、定时器等外设模块 |
| `rtl/common` | FIFO、RAM 等通用基础模块 |
| `rtl/soc` | SoC 顶层，负责连接 CPU、总线、存储器和外设 |
| `sim/tb` | 仿真测试顶层 |
| `sim/models` | Xilinx IP/原语的轻量仿真兼容模型 |

如果第一次阅读这个工程，建议按下面顺序看代码：

1. `rtl/soc/cpu_soc.v`
2. `rtl/core/cpu_jh.v`
3. `rtl/interconnect/addr2c.v`
4. `rtl/memory/ram_c.v`
5. `sim/tb/cpu_test.v`

## 顶层结构

SoC 顶层是 `cpu_soc`，主要由以下几部分组成：

- `cpu_jh`：CPU 核
- `riscv_bus`：CPU 数据访存到 SoC 外设之间的简单握手机制
- `addr2c`：地址译码，将访问分发到 RAM、ROM 和各类 MMIO 外设
- `ram_c`：数据 RAM 控制、指令 ROM 访问、UART 下载逻辑
- `rodata`：ROM 数据读控制
- `cpu_uart`：控制串口
- `clnt`：定时器/中断相关寄存器
从连接方式上看，可以把系统理解成：

`CPU -> 数据总线 -> 地址译码 -> RAM / ROM / UART / LED / KEY / CLNT`

同时，指令取值由 `cpu_jh` 通过 `ram_c` 访问指令存储体。

## CPU 实现说明

CPU 主体位于 `rtl/core/cpu_jh.v`，整体是一个五级流水线实现。代码中可以看到：

- PC 与跳转控制
- 指令译码 `id`
- ALU 运算
- 乘除法单元 `mul` / `mul_div`
- 访存阶段
- 写回阶段
- 停顿控制、流水线寄存器和冲刷控制
- CSR 与异常/中断控制 `csr_reg`

从 `rtl/core/id.v` 和 `rtl/core/csr_reg.v` 可见，该实现除 `RV32I` 基本整数指令外，还实现了：

- `M` 扩展中的乘除法相关指令
- `CSRRW` / `CSRRS` / `CSRRC`
- `ECALL`
- `EBREAK`
- `MRET`
- 机器态中断相关 CSR 读写

已在代码中出现的 CSR 包括：

- `mstatus`
- `misa`
- `mie`
- `mtvec`
- `mscratch`
- `mepc`
- `mcause`
- `mtval`
- `mip`

## 时钟与运行模式

`cpu_soc` 中实例化了时钟 IP `clk_wiz_0`。注释显示：

- 输入时钟：`50 MHz`
- 输出 `cpu_clk`：`100 MHz`
- 同时生成 CPU 与 RAM 相关时钟

原 README 中提到 Artix-7 最高可支持 `125 MHz`，但仓库代码中默认连线以 `clk_wiz_0` 的实际配置为准。

系统还存在一个很重要的模式选择信号：

- `down_load_key = 1`：正常运行模式，CPU 释放复位并开始执行
- `down_load_key = 0`：下载模式，CPU 保持复位，串口切换到程序下载路径

也就是说，这个设计支持通过 UART 向指令存储区域写入程序，再切回正常运行模式启动 CPU。

## 存储与启动机制

`ram_c.v` 同时承担了几项工作：

- 数据 RAM 的读写控制
- 指令侧 ROM 的访问
- UART 下载写 ROM 的逻辑

从代码看，系统区分了两类存储访问：

- 指令取值：CPU 按 `pc_addr_out` 读指令存储体
- 数据访问：通过总线读写 RAM 或 MMIO

此外，`ram_c` 内部还带有一条 UART 下载通路：

- 当下载模式使能时，UART 接收到的字节会顺序写入 ROM 端口
- 当收到首字节时，还会通过 `uart_txd` 回传固定字节作为握手反馈

这说明该项目的程序装载方式并不是完全依赖外部预初始化文件，也支持串口在线下载到指令存储器。

## 地址映射

地址译码逻辑位于 `rtl/interconnect/addr2c.v`。按照代码中的范围，SoC 地址空间如下：

| 地址范围 | 目标模块 | 说明 |
| --- | --- | --- |
| `0x0000_0000` - `0x0FFF_FFFF` | ROM | 只读区，含程序/常量访问路径 |
| `0x2000_0000` - `0x2FFF_FFFF` | RAM | 数据 RAM |
| `0x4000_0000` - `0x40FF_FFFF` | LED | LED 映射寄存器 |
| `0x4100_0000` - `0x41FF_FFFF` | KEY | 按键输入寄存器 |
| `0x4200_0000` - `0x42FF_FFFF` | CLNT | 定时器/中断相关寄存器 |
| `0x4300_0000` - `0x43FF_FFFF` | UART | 串口控制/数据接口 |
### LED

LED 由 `cpu_soc.v` 内部寄存器直接维护：

- 写访问时更新 `led`
- 读访问时返回 `{16'h0, led}`

### KEY

按键输入读出值为：

- `{24'h0, key}`

### CLNT

`rtl/peripherals/timer/clnt.v` 提供了一个类似简化版 `mtime`/`mtimecmp` 的接口，包含：

- `mtime[31:0]`
- `mtime[63:32]`
- `mtime_cmp[31:0]`
- `mtime_cmp[63:32]`
- `clnt_flag`

当 `mtime == mtime_cmp` 时，若 `clnt_flag` 有效，则触发 `time_e_inter`，最终送入 CPU 的中断输入路径。

### UART

UART 控制器位于 `rtl/peripherals/uart/cpu_uart.v`，内部带收发 FIFO。其功能特点包括：

- 接收数据进入 FIFO，CPU 通过读操作取走
- 发送数据通过写 FIFO 排队发送
- 访问基地址在 `0x4300_0000`
- 在 SoC 顶层存在两路 UART 选择：
  - 控制 UART
  - 下载 ROM 用 UART

由 `down_load_key` 选择当前串口通路。

## 仿真

仓库内提供的仿真入口是 `sim/tb/cpu_test.v`。

这个测试平台做了几件事：

- 例化顶层 `cpu_soc`
- 观察通用寄存器 `x1` 到 `x31`
- 把 UART 发出的字符直接打印到仿真控制台
- 等待 `x26 == 1` 作为测试结束标志
- 通过 `x27 == 1` 判断测试通过或失败

也就是说，当前测试平台沿用了常见 RISC-V 指令测试集的完成约定：

- `x26 = 1`：测试结束
- `x27 = 1`：测试通过
- `x27 != 1`：测试失败

### 当前仓库中的仿真现状

仓库里已经有测试顶层，但没有看到这些内容：

- 一键运行脚本
- `Makefile`
- ModelSim `do` 脚本
- 预置的官方测试程序集合
- 仿真文件清单说明

目前仓库额外提供了一层 `iverilog` 兼容模型，位于 `sim/models/xilinx_compat.v`，用于给下列 Vivado IP 提供轻量级仿真替身：

- `clk_wiz_0`
- `i_rom`
- `div_0`

因此，如果你要自己跑仿真，通常需要手动完成：

1. 在仿真工具中建立工程
2. 把 `sim/tb/cpu_test.v` 设为顶层
3. 加入 `rtl` 下所需源文件，以及 `sim/models/xilinx_compat.v`
4. 准备程序镜像或使用下载路径写入 ROM

如果使用 `iverilog`/`vvp`，`i_rom` 支持通过运行参数 `+IROM=<hex文件路径>` 加载程序镜像。

### 除法器说明

当前 `iverilog` 兼容层中的 `div_0` 使用 Verilog 直接 `/` 和 `%` 运算来给出商和余数，适合功能仿真，但这不应直接视为最终上板实现。

原因是直接写除法在综合后通常不利于时序收敛，后续如果继续面向 FPGA 优化，建议把除法路径改成更明确的多周期实现、流水化实现，或者重新接回专门的除法 IP。

如果后续补齐脚本，建议把仿真流程单独拆成 `docs/simulation.md` 或在本 README 中新增命令示例。

## 上板与 FPGA 依赖

从 RTL 结构看，该项目最初面向 Xilinx FPGA，这意味着：

- 工程面向 Xilinx FPGA
- 时钟、RAM、FIFO、部分算术单元可能依赖厂商 IP
- 上板前需要准备对应开发板约束和 Vivado 工程环境

与此同时，当前仓库为了便于 `iverilog` 做功能仿真，已经在 `sim/models/xilinx_compat.v` 中补了兼容模型。需要区分：

- `sim/models` 下的兼容模块主要服务于行为级仿真
- 它们并不等同于原 Vivado IP 的时序、性能和实现质量
- 能跑通 `iverilog` 不代表已经恢复到适合直接上板的实现状态

当前仓库中暂未看到以下关键文件：

- 完整 Vivado 工程文件
- 板级约束文件 `xdc`
- 指定开发板型号说明
- 上板接线说明
- 串口波特率和下载协议说明

因此，现阶段更适合把本仓库理解为“RTL 源码仓库”，而不是“开箱即用工程仓库”。

## 关键文件索引

如果你要定位不同功能，下面这些文件最值得优先查看：

| 文件 | 作用 |
| --- | --- |
| `rtl/soc/cpu_soc.v` | SoC 顶层，连接 CPU、总线、存储器与外设 |
| `rtl/core/cpu_jh.v` | CPU 主体，五级流水线控制中心 |
| `rtl/core/id.v` | 指令译码 |
| `rtl/core/csr_reg.v` | CSR、异常和中断控制 |
| `rtl/interconnect/addr2c.v` | 地址译码与 MMIO 片选 |
| `rtl/memory/ram_c.v` | RAM、ROM、下载路径 |
| `rtl/memory/rodata.v` | ROM 读控制 |
| `rtl/peripherals/uart/cpu_uart.v` | UART 控制器 |
| `rtl/peripherals/timer/clnt.v` | 定时器/中断相关逻辑 |
| `sim/tb/cpu_test.v` | 仿真入口 |

## 工具链参考

如果你只是想快速把一段汇编转为机器码，可以参考 README 原先提供的在线工具：

- [RISC-V 在线汇编工具](http://tice.sea.eseo.fr/riscv/)

如果你要进行更完整的软件构建，建议使用标准 RISC-V GNU Toolchain，并结合你自己的链接脚本、镜像生成流程和 ROM 初始化方式。

## 当前文档已知空缺

虽然本文档已经按源码补全了主结构，但仓库中仍有一些信息没有被源码完全说明：

- 官方测试集具体来源和导入方式
- UART 下载协议细节
- ROM/RAM 初始化文件生成流程
- 目标 FPGA 开发板型号与外设引脚
- Vivado 工程版本与创建步骤

如果后续继续完善仓库，建议优先补充：

1. 一份可直接运行的仿真脚本
2. 一份板级约束文件
3. 一份串口下载与程序构建说明
4. 一份更清晰的外设寄存器文档

