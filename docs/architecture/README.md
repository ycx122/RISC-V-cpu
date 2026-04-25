# 内部架构文档

本文档从代码实现角度描述本仓库 SoC 的内部结构，覆盖 CPU 核、总线、存储、地址映射、外设及 FPGA 依赖，供阅读源码或做二次开发时参照。仿真流程和测试限制见 [../guides/simulation.md](../guides/simulation.md)。

## 顶层结构

SoC 顶层是 `rtl/soc/cpu_soc.v`，主要由以下几部分组成：

- `cpu_jh`：CPU 核（RV32IM，五级流水线）
- `axil_ifetch_bridge` + `icache`：取指侧 AXI4-Lite 主口桥 + **8 KB direct-mapped I-Cache**（512 line × 16 byte），支持 `-DICACHE_DISABLE`（直连 bridge）、`-DTCM_IFETCH`（i_rom port B 0 拍直连）三条路径
- `dcache` + `store_buffer`：数据侧 **8 KB direct-mapped write-back D-Cache**（512 line × 16 byte，仅 `0x2xxx_xxxx` 可缓存）+ **4-entry Store Buffer**（吸收 MMIO 写、承载 dirty line write-back），支持 `-DDCACHE_DISABLE` 旁路
- `axil_master_bridge`：把 CPU 遗留的 `d_bus_en / ram_we / ram_re / mem_op` 握手翻译成标准 **AXI4-Lite 主口**（AW/W/B/AR/R），同时承担读数据字节抽取 / 符号扩展与写数据的 WSTRB 字节通道生成；misalign 检测在此处 short-circuit 报 `d_bus_misalign=1`
- `axil_interconnect`：1 主→7 从的 AXI4-Lite 地址译码器（ROM / RAM / LED / KEY / CLINT / UART / PLIC），未映射区域合成 DECERR、ROM 写区域合成 SLVERR（详见 Tier A #1/#3）
- `axil_slave_wrapper`：通用 AXI4-Lite 从口 shim，把 AXI 握手转成 `{dev_en, dev_we, dev_re, dev_addr, dev_wdata, dev_wstrb, dev_rdata, dev_ready}` 的内部握手，各从设备无需了解 AXI
- `ram_c`：**256 KB** 数据 RAM 控制（4 byte-bank × 64 KiB，每 bank 由一个 WSTRB 位驱动）、指令 ROM 访问、UART 下载逻辑
- `rodata`：ROM 数据读控制（只返回 32 位对齐字，字节抽取 / 符号扩展由 master bridge 负责）
- `cpu_uart`：UART 控制器（含收发 FIFO）
- `clnt`：SiFive 风格 CLINT（`msip@0x0000 / mtimecmp@0x4000 / mtime@0xBFF8`）
- `plic`：8-source / 单 M-mode context 的 PLIC，外部中断与软件中断分别走 `meip` / `msip`

可以把系统的数据通路理解为：

```
CPU 数据侧 -> dcache + store_buffer -> axil_master_bridge -> axil_interconnect ->
              { axil_slave_wrapper × 7 } -> RAM / ROM / UART / LED / KEY / CLINT / PLIC
CPU 取指侧 -> axil_ifetch_bridge -> icache ----------------> i_rom (AXI4-Lite slave)
```

总线采用 **AXI4-Lite 标准**，因此 Xilinx MIG 的 AXI-Lite facade、`axi_uart16550`、`axi_qspi`、`axi_dma` 的 config 口等任何 AXI4-Lite IP 都可以直接挂上互连（只需要在 `axil_interconnect.v` 增加一条地址译码条目和一组从口 bundle）。

## CPU 核

CPU 主体位于 `rtl/core/cpu_jh.v`，整体是一个五级流水线实现。主要子模块：

- PC 与跳转控制（`pc.v` / `ju.v`）
- 指令译码 `id.v`
- ALU 运算
- 乘除法单元 `mul.v` / `mul_div`
- 访存阶段
- 写回阶段
- 停顿控制、流水线寄存器（`pipeline_regs.v`）和冲刷控制
- CSR 与异常/中断控制 `csr_reg.v`

指令集覆盖范围：

- `RV32I` 基本整数指令
- `M` 扩展乘除法指令
- `CSRRW` / `CSRRS` / `CSRRC`
- `ECALL` / `EBREAK` / `MRET`
- 机器态中断相关 CSR 读写
- `FENCE.I`（按"架构 NOP + 排干写回管线"实现，见 `id.v` MISC-MEM 分支）

已实现的 M 模式 CSR：`mstatus` / `misa` / `mie` / `mtvec` / `mscratch` / `mepc` / `mcause` / `mtval` / `mip`。

## 时钟与运行模式

`cpu_soc` 实例化了时钟 IP `clk_wiz_0`。默认配置：

- 输入时钟：50 MHz
- 输出 `cpu_clk`：100 MHz
- 同时生成 CPU 与 RAM 相关时钟

`down_load_key` 用于模式选择：

- `down_load_key = 1`：正常运行模式，CPU 释放复位并开始执行
- `down_load_key = 0`：下载模式，CPU 保持复位，串口切换到程序下载路径

## 存储与启动机制

`ram_c.v` 同时承担：

- 数据 RAM 的读写控制
- 指令侧 ROM 的访问
- UART 下载写 ROM 的逻辑

系统区分两类存储访问：

- 指令取值：CPU 按 `pc_addr_out` 读指令存储体
- 数据访问：通过 AXI4-Lite 总线读写 RAM 或 MMIO

`ram_c` 内部带有一条 UART 下载通路：下载模式使能时，UART 接收到的字节会顺序写入 ROM 端口，收到首字节时还会通过 `uart_txd` 回传固定字节作为握手反馈。也就是说，装载方式并不完全依赖外部预初始化文件，也支持串口在线下载到指令存储器。

## 地址映射

地址译码逻辑位于 `rtl/bus/axil_interconnect.v`（每个从口都挂在 1 主→6 从的 AXI4-Lite 互连上）。SoC 地址空间：

| 地址范围 | 目标模块 | 说明 |
| --- | --- | --- |
| `0x0000_0000` – `0x0FFF_FFFF` | ROM | 只读区，含程序/常量访问路径 |
| `0x2000_0000` – `0x2FFF_FFFF` | RAM | 数据 RAM |
| `0x4000_0000` – `0x40FF_FFFF` | LED | LED 映射寄存器 |
| `0x4100_0000` – `0x41FF_FFFF` | KEY | 按键输入寄存器 |
| `0x4200_0000` – `0x42FF_FFFF` | CLNT | 定时器 / 中断相关寄存器 |
| `0x4300_0000` – `0x43FF_FFFF` | UART | 串口控制 / 数据接口 |
| `0x4400_0000` – `0x44FF_FFFF` | PLIC | SiFive 风格 PLIC（priority/pending/enable/threshold/claim） |

未映射地址在 `axil_interconnect` 内合成 DECERR；ROM 区段（`0x0xxx_xxxx`）的写事务被合成为 SLVERR。两者都会在 CPU 端抬起 `d_bus_err`，最终触发 `mcause=5/7` 的 Load/Store Access Fault。

### LED

LED 由 `cpu_soc.v` 内部寄存器直接维护：

- 写访问时更新 `led`
- 读访问时返回 `{16'h0, led}`

### KEY

按键输入读出值为 `{24'h0, key}`。

### CLNT

`rtl/peripherals/timer/clnt.v` 已对齐 SiFive CLINT 偏移：

| 偏移 | 名称 | 说明 |
| --- | --- | --- |
| `0x0000` | `msip[0]` | 软件中断（仅 bit0 有效），驱动 `mip.MSIP` |
| `0x4000` / `0x4004` | `mtimecmp[31:0]` / `[63:32]` | 64 bit 比较器，reset 为全 1（默认不触发） |
| `0xBFF8` / `0xBFFC` | `mtime[31:0]` / `[63:32]` | 64 bit 计数器（直接用 `cpu_clk`） |

`time_e_inter = (mtime >= mtimecmp)` 电平输出，软件通过 bump `mtimecmp` 清 MTIP。

### PLIC

`rtl/peripherals/plic/plic.v` 是 SiFive 风格的极简 PLIC：8 source、3-bit priority、单 M-mode context。寄存器：source priority `0x04..0x1C`、pending `0x1000`、context-0 enable `0x2000`、threshold `0x20_0000`、claim/complete `0x20_0004`。仲裁结果走 `meip` 电平输出；source 0 reserved，source 1 = 外部 `e_inter`（两拍同步 + 取反后 latch）。

### Cache 与 Store Buffer

- **I-Cache**（`rtl/bus/icache.v`）：8 KB direct-mapped、16 B line（4 word）、512 line。命中 0 拍组合返回；miss 时 4 次 AR 串行 line fill；`fence.i` 整张 invalidate（`flush_icache` pulse）；`-DICACHE_DISABLE` 旁路、`-DTCM_IFETCH` 直接走 i_rom port B。
- **D-Cache**（`rtl/bus/dcache.v`）：8 KB direct-mapped、16 B line、write-back、write-allocate。仅 `0x2xxx_xxxx`（数据 RAM 窗口）可缓存；ROM / MMIO bypass。命中组合返回 `up_d_bus_ready` + 抽取后的字。dirty line 在 miss 时把 4 个 word 推进 store buffer 做后台 drain，新 line fill 同时启动。`-DDCACHE_DISABLE` 旁路退化到 Tier 4.2 行为。
- **Store Buffer**（`rtl/bus/store_buffer.v`）：4-entry FIFO，承载非可缓存 store（MMIO 写 1 拍 retire）与 cache write-back drain（4 dirty word 后台流向 RAM）。`sb_pop` 是组合输出（与 `dn_d_bus_ready` 同拍生效），避免 ack 延迟一拍导致的 "幻影 drain"。snoop 走每 entry 字地址比较 + 字节合成，目前仅做 informational 检查；非可缓存 load 通过等 SB 排空保证程序序，可缓存 load 因为命中走 cache 数据自然反映前序 store。

### UART

UART 控制器位于 `rtl/peripherals/uart/cpu_uart.v`，内部带收发 FIFO：

- 接收数据进入 FIFO，CPU 通过读操作取走
- 发送数据通过写 FIFO 排队发送
- 访问基地址 `0x4300_0000`
- SoC 顶层存在两路 UART 选择（控制 UART 与下载 ROM 用 UART），由 `down_load_key` 切换

## FPGA 与上板依赖

从 RTL 结构看，该项目面向 Xilinx FPGA，这意味着：

- 时钟、RAM、FIFO、部分算术单元依赖厂商 IP
- 上板前需要准备对应开发板约束和 Vivado 工程环境

同时为了便于 `iverilog` 做功能仿真，仓库在 `sim/models/xilinx_compat.v` 中补了兼容模型。**需要注意**：

- `sim/models` 下的兼容模块主要服务于行为级仿真
- 它们并不等同于原 Vivado IP 的时序、性能和实现质量
- 能跑通 `iverilog` 不代表已经恢复到适合直接上板的实现状态

当前仓库中暂未包含：

- 完整 Vivado 工程文件
- 板级约束文件（`.xdc`）
- 指定开发板型号说明
- 上板接线说明
- 串口波特率和下载协议说明

因此，现阶段更适合把本仓库理解为 "RTL 源码仓库"，而不是 "开箱即用工程仓库"。

### 除法器说明

当前 `iverilog` 兼容层中的 `div_0` 使用 Verilog 直接 `/` 和 `%` 运算来给出商和余数，适合功能仿真，但这不应直接视为最终上板实现。

直接写除法在综合后通常不利于时序收敛。后续如果继续面向 FPGA 优化，建议把除法路径改成更明确的多周期实现、流水化实现，或者重新接回专门的除法 IP。

## 关键文件索引

| 文件 | 作用 |
| --- | --- |
| `rtl/soc/cpu_soc.v` | SoC 顶层，连接 CPU、总线、存储器与外设 |
| `rtl/core/cpu_jh.v` | CPU 主体，五级流水线控制中心 |
| `rtl/core/id.v` | 指令译码 |
| `rtl/core/csr_reg.v` | CSR、异常和中断控制 |
| `rtl/core/pipeline_regs.v` | 流水线寄存器与停顿/冲刷控制 |
| `rtl/bus/axil_master_bridge.v` | 数据侧 CPU 遗留握手 → AXI4-Lite 主口桥 + misalign short-circuit |
| `rtl/bus/axil_ifetch_bridge.v` | 取指侧只读 AXI4-Lite 主口桥 |
| `rtl/bus/icache.v` | 8 KB direct-mapped 取指 cache |
| `rtl/bus/dcache.v` | 8 KB direct-mapped write-back 数据 cache（含 store-buffer 集成） |
| `rtl/bus/store_buffer.v` | 4-entry FIFO，承载 MMIO 写吸收与 cache write-back drain |
| `rtl/bus/axil_interconnect.v` | 1 主→7 从 AXI4-Lite 地址译码 + DECERR/SLVERR 合成 |
| `rtl/bus/axil_slave_wrapper.v` | 通用 AXI4-Lite 从口 shim |
| `rtl/memory/ram_c.v` | 256 KB RAM、ROM、下载路径 |
| `rtl/memory/rodata.v` | ROM 读控制 |
| `rtl/peripherals/uart/cpu_uart.v` | UART 控制器 |
| `rtl/peripherals/timer/clnt.v` | SiFive 风格 CLINT |
| `rtl/peripherals/plic/plic.v` | 8-source SiFive 风格 PLIC |
| `sim/tb/cpu_test.v` | 仿真入口 |
