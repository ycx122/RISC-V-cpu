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

仓库里已经有测试顶层，并补充了两个仿真脚本：

- `sim/smoke.sh`：使用仓库内置 RISC-V 工具链和 `iverilog/vvp` 构建一个最小 `RV32IM` 程序，再加载到 `sim/tb/cpu_test.v` 做功能仿真
- `sim/smoke_mi.sh`：编译 `sim/tests/mi_smoke.S`（CSR 读写 + ecall/ebreak round-trip + `mepc`/`mcause` 断言 + 异步中断 round-trip），用同一 tb 校验 M-mode trap 路径。仓库不带 `rv32mi-p-*` 源码，这里用它代替。脚本自动给 tb 加 `+EINT_AT=3000000` 在 sync 子测试跑完后产生一次外部中断脉冲，handler 里校验 `mcause==0x80000007` 且 `mepc` 落在 int_loop 范围内，覆盖"mepc 指向下一条未提交指令"的语义。
- `sim/run_isa.sh`：把 `sw/tinyriscv/tests/isa/generated/` 下的 riscv-tests 镜像逐个喂给同一个 tb，跑完给出 PASS / FAIL / TIMEOUT / xfail / SKIP 汇总，供重构时做回归

当前仍然没有看到这些内容：

- `Makefile`
- ModelSim `do` 脚本
- 预置的官方测试程序集合
- 更通用的仿真文件清单说明

目前仓库额外提供了一层 `iverilog` 兼容模型，位于 `sim/models/xilinx_compat.v`，用于给下列 Vivado IP 提供轻量级仿真替身：

- `clk_wiz_0`
- `i_rom`
- `div_0`

如果你只是想先确认“工具链 + RTL + 仿真器”这条链路能跑起来，可以直接执行：

`bash sim/smoke.sh`

它会自动完成：

1. 编译一个最小 `RV32IM` 冒烟程序
2. 生成供 `i_rom` 加载的 Verilog hex 镜像
3. 用 `iverilog` 编译 `sim/tb/cpu_test.v` 和所需 RTL
4. 用 `vvp` 运行仿真并检查 `TEST_PASS`

如果你要手动跑其他程序镜像，通常需要完成：

1. 在仿真工具中建立工程
2. 把 `sim/tb/cpu_test.v` 设为顶层
3. 加入 `rtl` 下所需源文件，以及 `sim/models/xilinx_compat.v`
4. 准备程序镜像或使用下载路径写入 ROM

如果使用 `iverilog`/`vvp`，`i_rom` 支持通过运行参数 `+IROM=<hex文件路径>` 加载程序镜像。

### ISA 回归脚本

想跑完整的 rv32ui + rv32um 用例集：

```
bash sim/run_isa.sh                    # 全量
bash sim/run_isa.sh --only 'rv32um-*'  # 只跑 M 扩展
bash sim/run_isa.sh add sub mul        # 位置参数可作为附加过滤
```

脚本只编译一次 tb，然后依次以 `+IROM=<测试镜像>.verilog` 启动 `vvp`，按测试日志里的 `TEST_PASS` / `TEST_FAIL` 判定结果。每个用例的详细日志留在 `sim/output/isa/<名字>.log`。

脚本维护两个静态名单（见文件头部注释）：

- `SKIP_LIST`：依赖本实现未支持的扩展，会被直接标记 SKIP。当前为 `rv32ui-p-fence_i`。
- `EXPECTED_FAIL_LIST`：本实现目前跑不过、但属于已知架构缺口而非最近回归的用例；它们失败时记为 `xfail`，不会让整个脚本退出非零。现在是空列表——之前挂在这里的 `rv32ui-p-s{b,h}` 已经通过 `+DRAM` 预装通道在仿真里填进 `.data` 段初值后转绿（见下方「ISA 测试限制与架构边界」），`rv32ui-p-sw` 早在 PC 语义三处 off-by-4 修完之后就转绿了。

基线（把这个脚本跑绿应该看到的结果）：

- 46 个 PASS
- 0 个 xfail
- 1 个 SKIP（`rv32ui-p-fence_i`）
- 0 个新的 FAIL 或 TIMEOUT

以后做流水线/总线这类有回归风险的改动，请先在改动前后各跑一次 `sim/run_isa.sh`，对比两边输出。退出码非零或出现 `NEW failures` / `NEW timeouts` 就是回归。

### ISA 测试限制与架构边界

当前仓库可以用 `sw/tinyriscv/tests/isa` 里的旧版 ISA 用例做功能回归，但需要结合处理器本身的架构边界来解读结果：

- `fence.i` 现在已被 CPU 核识别（见 `rtl/core/id.v` 的 MISC-MEM 分支）并按"架构 NOP + 排干写回管线"实现：`cpu_jh.v` 里 `fence_stall = id_is_fence_i & (reg_2_store | reg_3_store | (d_bus_en & ~d_bus_ready))`，把 IF/ID/EX 挡住直到前序 store 全部离开流水线，再让 `fence.i` 前进到 WB。这对顺序单发射、无 I-cache 的本实现已经足够。
- 但 `rv32ui-p-fence_i` 仍然进 `SKIP_LIST`：它的测试向量会往 `.text`（`0x00000000` 窗口）写指令再跳过去，这需要 SoC 的 ROM 控制器 (`rtl/memory/rodata.v`) 给 `i_rom` 端口 A 开 store 通路；当前实现是只读 ROM，属于 SoC/存储子系统的改造范围，不是 CPU core 的事。只要该 SoC 仍然没有自修改指令存储，这条测试就继续 SKIP。
- M 模式 trap 路径：仓库未收录 `rv32mi-p-*` 源码，我们用 `sim/tests/mi_smoke.S` 做替代。它覆盖 `csrrw/csrrs/csrrc` 的返回旧值和写回语义、`ecall`/`ebreak` 的 `mcause` 编码（11/3）、`mepc` 必须等于触发指令自身 PC，以及 `mret` 回到 `mepc` 下一条。历史上 `csr_reg.v` 里写的是 `mepc<=pc_addr-4`，那是为旧的 +4-off PC 语义而设；统一 PC 语义之后 `reg_4_pcaddr` 已经等于该指令的架构 PC，那个 `-4` 必须去掉，不然 handler 读 `mepc` 会落在前一条指令上（OS 常见的 `mepc+=4` 跳过 ecall 的写法就会死循环）。这条 bug 由 `sim/smoke_mi.sh` 守着。
- 异步中断的 `mepc` 语义：原来中断分支写的是 `mepc<=reg_4_pcaddr`，即"正在 WB 的指令"的 PC。这条指令其实已经提交过了，`mret` 再跳回去会重复执行一次（当它不是幂等的 ALU 指令时会产生可观察副作用）。现在的做法是：`csr_reg.v` 多吃一个 `pc_next` 端口，`cpu_jh.v` 把 `reg_3_pcaddr`（MEM 级、仍未提交的那条）喂进去做 `mepc`。前面 branch/jal/jalr 已经在 ID 级把 `reg_3` 填成正确的 architectural next PC，所以这个值等价于 "WB 指令之后要执行的下一条"——包含 `PC+4` 和跳转目标两种情况。如果 trap 发生的那一拍 `reg_3` 刚好是 bubble（例如 branch 冲刷刚过一拍），`cpu_jh.v` 的 `int_take` 会等一拍到 `reg_3_pcaddr != 0` 再允许发 trap。
- `mstatus.MIE` reset 值：原来是 1，违反 RISC-V spec（spec 要求 reset 后 MIE=0）。旧值加上 tb 静态 `e_inter=1` 会让 CPU 在软件还没写 `mtvec` 之前就立刻 trap 到 `mtvec=0` 并在那里死循环，所以以前只能靠"静态 e_inter + 永不开 MIE"掩盖它。现在 `csr_reg.v` 的 `initial` 与同步 reset 都把 MIE 初始化为 0。
- 中断 pending 锁存的反馈环：`cpu_jh.v` 里有一个 `e_inter_reg` 保存 "有未处理的中断请求"，需要在 trap 真正发生时清 0。旧逻辑用"进入采样窗口"（`pc_en & reg_4_pcaddr!=0`）当清除条件，结果 MIE=0 时照样清，每拍清一次再置一次，等软件开 MIE 时永远抓不到它。修掉的方法是 `csr_reg.v` 新导出一根 `int_taken = e_inter & MIE & MIE7` 的组合信号回传给 `cpu_jh.v`，`e_inter_reg` 只有在 `int_take & int_ack` 都为 1 的那一拍才清零。
- 中断触发模型：`cpu_soc.v` 里的 `e_inter` 输入是**下降沿脉冲**（内部做了 `~e_inter` 再边沿检测），不是高电平。tb `sim/tb/cpu_test.v` 一直把 `e_inter` 拉 1，这就是"从不产生中断"。需要跑异步中断路径的测试时，用 `+EINT_AT=<ns>` 让 tb 在指定仿真时间产生一次负脉冲；`sim/smoke_mi.sh` 里 `mi_smoke` 的 Test 6 就走这条路径。
- 对齐访问：`rtl/memory/ram_c.v` 的地址选择逻辑实际上用跨 bank 拼接 **硬件 fix-up** 了 misaligned LH/LW/SH/SW；不会抛 `LoadAddressMisaligned` / `StoreAddressMisaligned` 异常。这是本实现相对 spec 的一个显式选择：对简单 M-mode-only 的核子来说这是允许的，但意味着 `rv32mi-p-ma_addr` / `rv32mi-p-ma_fetch` 一类要求抛异常的测试我们本来就跑不过。Misaligned JALR 目标同样不会触发 `InstructionAddressMisaligned`，`pc.v` 会直接把该地址写进 `pc_addr`，fetch 到的指令取决于 ROM 行为。两条路径都在这里登记为"已知架构缺口"，改它需要同时动 `ram_c.v` / `pc.v` 和 `csr_reg.v` 的 trap 分发，本轮不在范围内。
- `rv32ui-p-l{b,bu,h,hu,w}` 实际上是访问 `.rodata`（落在 ROM 窗口），不需要 RAM 初始化通路。仿真里之前这五个 load 测试一直 FAIL 的真实原因是 `sim/models/xilinx_compat.v` 的 `i_rom` 端口 A 是 0-cycle 组合读，而 `rtl/memory/rodata.v` 的 7-state FSM 是按 Vivado BRAM "Read-First with Output Register" 模式（2-cycle 读延迟）写的：采样字节整齐落后了 2 拍，结果是 `reg_data = {mem[0], mem[0], mem[addr+3], mem[addr+2]}`。现在 `i_rom` 端口 A 已经加了两级输出寄存器与板上行为对齐，这五个 load 测试直接转绿，无需改 `rodata.v`（改 `rodata.v` 反而会在板上炸）。
- PC 语义三处 off-by-4：旧版 `rtl/core/id.v` 的 auipc（`(addr-4)+imm`）、`rtl/core/ju.v` 的 jal/jalr link（`pc_addr` 而非 `pc_addr+4`）、以及 `rtl/core/pc.v` 的 JALR 目标（直接用 `rs1+imm` 而不扣 1 周期取指 bubble）互相抵消，使得 `la` 算出的绝对地址恰好是 spec_target−4。对纯跳转型 test 能通过（因为取指 bubble 会自动吞掉首条指令）；但 `sw`/`sh`/`sb` 等把这个地址当数据地址用时就会落到 `0x1FFFFFFC` 这个未被 `addr2c.v` 映射的位置，总线永远不 ready。三处已同步修复（auipc=`addr+imm`、link=`pc_addr+4`、pc.v JALR=`rs1+imm-4` 补 bubble），`rv32ui-p-sw` 因此转绿。
- `.data` 仿真预装通道：`rv32ui-p-s{b,h}` 的 `TEST_ST_OP` 用例要求 RAM 在 reset 后保留 `.data` 段初值（`0xef` / `0xbeef`）——真板上这是 crt0 从 ROM 拷到 RAM 的结果，但本 SoC 没有 boot loader。`sim/run_isa.sh` 现在会为每个用例跑一次 `riscv64-unknown-elf-objcopy -O binary -j .data <elf>` 抽出 `.data` 字节流，转 byte-per-line hex 后通过 `+DRAM=<file>` 传进 `sim/tb/cpu_test.v`；测试台在 reset 释放前用 `$readmemh` 读进 64 KB 临时数组，再按 byte 索引分发到 `ram_c.v` 的四个 `dram` bank（`uu1.b1.d_ram_{1..4}.u_ram._ram`）。纯仿真路径，不改板上 RTL，两个 store 测试因此直接转绿，列表基线从 `44 PASS / 2 xfail` 升到 `46 PASS / 0 xfail`。

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

## 第三方代码与致谢

本仓库包含并使用了来自 `tinyriscv` 的部分代码、目录结构和测试内容，当前主要保留在 `sw/tinyriscv` 目录下，并在此基础上结合本仓库的处理器实现做了裁剪、整理和适配。

`sw/tinyriscv` 目录中的上游内容继续按 `Apache License 2.0` 分发，对应许可证文件保留在 `sw/tinyriscv/LICENSE`。除另有说明的第三方内容外，本仓库其余内容的许可证见根目录 `LICENSE`。

同时感谢 `tinyriscv` 相关博客内容对本项目的启发，尤其是在我学习 RISC-V 软件构建与编译方案的过程中提供了很大帮助。

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

