# RISC-V CPU

一个基于 Verilog 编写的 **RV32IM 五级流水线** RISC-V SoC 项目。仓库内容不只是一个 CPU 内核，还包含 AXI4-Lite 总线、存储器、UART 和定时中断等外设，目标平台为 Xilinx FPGA。

## 特性概览

- 五级流水线 CPU 核（`rtl/core/cpu_jh.v`），支持 `RV32IM` + M 模式 CSR / 异常 / 中断 / `FENCE.I`
- AXI4-Lite 总线互连（1 主 → 6 从），可直接挂任何 AXI4-Lite IP
- 片上 ROM / RAM、UART（含 FIFO）、定时器 `CLNT`、LED / KEY 映射寄存器
- 支持 **UART 在线下载** 程序到指令存储器
- 提供 `iverilog` 兼容模型（`sim/models/xilinx_compat.v`），可在无 Vivado 环境下做功能仿真
- 配套 ISA 回归脚本（rv32ui + rv32um 共 46 个 PASS）

## 性能指标

当前 CPU 在 `sim/run_dhrystone.sh` 下的 Dhrystone 2.1 跑分如下（`-O2 -march=rv32im -mabi=ilp32`，仿真版强制 `Number_Of_Runs = 5`）：

| 指标 | 数值 |
| --- | --- |
| 总 `mcycle` | 2534 |
| 总 `minstret` | 1455 |
| **Cycles / Dhrystone** | **506** |
| Instret / Dhrystone | 291 |
| **IPC** | **0.574** |
| **DMIPS/MHz** | **1.124** |

测量方式：`sw/tinyriscv/tests/example/dhyrstone/dhry_stubs.c` 的 `csr_cycle()` / `csr_instret()` 直接通过 `csrr` 读取架构 CSR `mcycle` / `mcycleh` 与 `minstret` / `minstreth`（用读 hi → 读 lo → 再读 hi 的标准防撕裂序列），与 SoC 上 CLINT `mtime` 的 MMIO 时基解耦。复现：

```bash
bash sim/run_dhrystone.sh
# 关键输出：
#   (*) Cycles per Dhrystone:  506
#   (*) IPC (minstret/mcycle): 0.574
#         1000000/(User_Cycle/Number_Of_Runs)/1757 = 1.124 DMIPS/MHz
```

`Cycles / Dhrystone` 与频率解耦，是后续流水线 / Cache 优化的主指标；`DMIPS/MHz ≈ 1.12` 大致处于「单发射 5 级顺序核」的常见区间（参考 SiFive E31 ≈ 1.61）。仿真版只跑 5 轮，`csrr` 自身的取样开销会带来 ~1–2 % 的轻微偏差，需要更精确数据时可以临时把 `dhry_1.c` 里的 `Number_Of_Runs` 调到 50–100 再跑。

## 目录结构

| 路径 | 说明 |
| --- | --- |
| `rtl/core` | CPU 核心流水线与功能模块（译码、ALU、寄存器堆、乘除法、CSR、PC 等）|
| `rtl/bus` | AXI4-Lite master bridge、互连、slave wrapper |
| `rtl/memory` | 数据 RAM、指令 ROM、只读数据与下载路径控制 |
| `rtl/peripherals` | UART、定时器等外设模块 |
| `rtl/common` | FIFO、RAM 等通用基础模块 |
| `rtl/soc` | SoC 顶层，连接 CPU、总线、存储器与外设 |
| `sim/tb` | 仿真测试顶层 |
| `sim/models` | Xilinx IP / 原语的轻量仿真兼容模型 |
| `sim` 下 `*.sh` | smoke / ISA / bench 等仿真脚本 |
| `sw/tinyriscv` | 上游 `tinyriscv` 软件与测试（`Apache License 2.0`）|
| `docs/` | 架构与使用文档 |

第一次阅读代码建议的顺序：

1. `rtl/soc/cpu_soc.v`
2. `rtl/core/cpu_jh.v`
3. `rtl/bus/axil_master_bridge.v` / `rtl/bus/axil_interconnect.v`
4. `rtl/memory/ram_c.v`
5. `sim/tb/cpu_test.v`

## 快速开始

前置：仓库附带的 RISC-V 工具链与 `iverilog` / `vvp`。

`sw/FreeRTOS-Kernel` 以 git submodule 形式纳入，克隆时需要带上 `--recursive`，否则 FreeRTOS 相关目标无法构建：

```bash
git clone --recursive https://github.com/ycx122/RISC-V-cpu.git
# 如果已经 clone 过但漏了 submodule：
git submodule update --init --recursive
```

最小冒烟仿真（确认工具链 + RTL + 仿真器链路正常）：

```bash
bash sim/smoke.sh
```

M 模式 trap 路径冒烟（CSR / `ecall` / `ebreak` / 异步中断）：

```bash
bash sim/smoke_mi.sh
```

跑完整 ISA 回归（rv32ui + rv32um）：

```bash
bash sim/run_isa.sh                    # 全量
bash sim/run_isa.sh --only 'rv32um-*'  # 只跑 M 扩展
```

详细的仿真流程、`+IROM` / `+DRAM` / `+EINT_AT` 等运行参数，以及已知的架构边界与测试限制，参见 [docs/guides/simulation.md](docs/guides/simulation.md)。

## 文档导航

- [内部架构文档](docs/architecture/README.md) — SoC 顶层、CPU 流水线、存储器、地址映射、FPGA 依赖
- [仿真与 ISA 回归指南](docs/guides/simulation.md) — 仿真入口、回归脚本、已知限制与架构边界
- [PROCESSOR_IMPROVEMENT_PLAN.md](PROCESSOR_IMPROVEMENT_PLAN.md) — 处理器迭代计划与进度

## 工具链参考

如果只是想快速把一段汇编转为机器码，可以参考在线工具：

- [RISC-V 在线汇编工具](http://tice.sea.eseo.fr/riscv/)

完整软件构建建议使用标准 RISC-V GNU Toolchain，结合自己的链接脚本、镜像生成流程和 ROM 初始化方式。

## 当前仓库已知空缺

虽然仓库已经能跑功能仿真与 ISA 回归，但仍缺少：

- 完整 Vivado 工程文件与板级约束（`.xdc`）
- 目标开发板型号与外设引脚说明
- UART 下载协议细节
- ROM / RAM 初始化文件生成流程

因此，现阶段更适合把本仓库理解为 "RTL 源码仓库"，而不是 "开箱即用工程仓库"。

## 第三方代码与致谢

本仓库包含并使用了来自 `tinyriscv` 的部分代码、目录结构和测试内容，当前主要保留在 `sw/tinyriscv/` 目录下，并在此基础上结合本仓库的处理器实现做了裁剪、整理和适配。

`sw/tinyriscv/` 目录中的上游内容继续按 `Apache License 2.0` 分发，对应许可证文件保留在 `sw/tinyriscv/LICENSE`。除另有说明的第三方内容外，本仓库其余内容的许可证见根目录 `LICENSE`。

同时感谢 `tinyriscv` 相关博客内容对本项目的启发，尤其是在学习 RISC-V 软件构建与编译方案过程中提供了很大帮助。
