# 仿真与 ISA 回归指南

本文档描述本仓库的功能仿真入口、ISA 回归脚本以及已知的架构/测试限制。RTL 架构细节见 [../architecture/README.md](../architecture/README.md)。

## 仿真入口

仓库内提供的仿真顶层是 `sim/tb/cpu_test.v`。这个测试平台做了几件事：

- 例化顶层 `cpu_soc`
- 观察通用寄存器 `x1` 到 `x31`
- 把 UART 发出的字符直接打印到仿真控制台
- 等待 `x26 == 1` 作为测试结束标志
- 通过 `x27 == 1` 判断测试通过或失败

也就是说，当前测试平台沿用了常见 RISC-V 指令测试集的完成约定：

- `x26 = 1`：测试结束
- `x27 = 1`：测试通过
- `x27 != 1`：测试失败

## 冒烟仿真脚本

仓库提供了以下仿真脚本（基于内置 RISC-V 工具链与 `iverilog`/`vvp`）：

- `sim/smoke.sh`：构建一个最小 `RV32IM` 程序，加载到 `sim/tb/cpu_test.v` 做功能仿真
- `sim/smoke_mi.sh`：编译 `sim/tests/mi_smoke.S`（CSR 读写 + `ecall`/`ebreak` round-trip + `mepc`/`mcause` 断言 + 异步中断 round-trip），用同一 tb 校验 M-mode trap 路径。仓库不带 `rv32mi-p-*` 源码，这里用它代替。脚本自动给 tb 加 `+EINT_AT=3000000`，在 sync 子测试跑完后产生一次外部中断脉冲；handler 里校验 `mcause == 0x80000007` 且 `mepc` 落在 `int_loop` 范围内，覆盖 "mepc 指向下一条未提交指令" 的语义。
- `sim/run_isa.sh`：把 `sw/tinyriscv/tests/isa/generated/` 下的 riscv-tests 镜像逐个喂给同一个 tb，跑完给出 PASS / FAIL / TIMEOUT / xfail / SKIP 汇总，供重构时做回归。

如果你只是想先确认 "工具链 + RTL + 仿真器" 这条链路能跑起来，可以直接执行：

```
bash sim/smoke.sh
```

它会自动完成：

1. 编译一个最小 `RV32IM` 冒烟程序
2. 生成供 `i_rom` 加载的 Verilog hex 镜像
3. 用 `iverilog` 编译 `sim/tb/cpu_test.v` 和所需 RTL
4. 用 `vvp` 运行仿真并检查 `TEST_PASS`

如果使用 `iverilog`/`vvp`，`i_rom` 支持通过运行参数 `+IROM=<hex文件路径>` 加载程序镜像。

### 其他仿真器

如果要手动跑其他程序镜像（如在 ModelSim 或 Vivado 仿真器中），通常需要：

1. 在仿真工具中建立工程
2. 把 `sim/tb/cpu_test.v` 设为顶层
3. 加入 `rtl` 下所需源文件，以及 `sim/models/xilinx_compat.v`
4. 准备程序镜像或使用下载路径写入 ROM

`sim/models/xilinx_compat.v` 为下列 Vivado IP 提供轻量级仿真替身：`clk_wiz_0`、`i_rom`、`div_0`。

## ISA 回归脚本

想跑完整的 rv32ui + rv32um 用例集：

```
bash sim/run_isa.sh                    # 全量
bash sim/run_isa.sh --only 'rv32um-*'  # 只跑 M 扩展
bash sim/run_isa.sh add sub mul        # 位置参数可作为附加过滤
```

脚本只编译一次 tb，然后依次以 `+IROM=<测试镜像>.verilog` 启动 `vvp`，按测试日志里的 `TEST_PASS` / `TEST_FAIL` 判定结果。每个用例的详细日志保留在 `sim/output/isa/<名字>.log`。

脚本维护两个静态名单（见文件头部注释）：

- `SKIP_LIST`：依赖本实现未支持的扩展，会被直接标记 SKIP。当前为 `rv32ui-p-fence_i`。
- `EXPECTED_FAIL_LIST`：本实现目前跑不过、但属于已知架构缺口而非最近回归的用例；它们失败时记为 `xfail`，不会让整个脚本退出非零。现在是空列表。

**基线**（把这个脚本跑绿应该看到的结果）：

- 46 个 PASS
- 0 个 xfail
- 1 个 SKIP（`rv32ui-p-fence_i`）
- 0 个新的 FAIL 或 TIMEOUT

以后做流水线/总线这类有回归风险的改动，请先在改动前后各跑一次 `sim/run_isa.sh`，对比两边输出。退出码非零或出现 `NEW failures` / `NEW timeouts` 就是回归。

## ISA 测试限制与架构边界

当前仓库可以用 `sw/tinyriscv/tests/isa` 里的 ISA 用例做功能回归，但需要结合处理器本身的架构边界来解读结果。本节记录的问题都是踩过的坑，建议阅读一次避免重复调试。

### `fence.i` 与自修改指令存储

`fence.i` 现在已被 CPU 核识别（见 `rtl/core/id.v` 的 MISC-MEM 分支）并按"架构 NOP + 排干写回管线"实现：`cpu_jh.v` 里

```
fence_stall = id_is_fence_i & (reg_2_store | reg_3_store | (d_bus_en & ~d_bus_ready))
```

把 IF/ID/EX 挡住直到前序 store 全部离开流水线，再让 `fence.i` 前进到 WB。对顺序单发射、无 I-cache 的本实现已经足够。

但 `rv32ui-p-fence_i` 仍然被放入 `SKIP_LIST`：它的测试向量会往 `.text`（`0x00000000` 窗口）写指令再跳过去，这需要 SoC 的 ROM 控制器 (`rtl/memory/rodata.v`) 给 `i_rom` 端口 A 开 store 通路；当前实现是只读 ROM，属于 SoC / 存储子系统的改造范围，不是 CPU core 的事。只要该 SoC 仍然没有自修改指令存储，这条测试就继续 SKIP。

### M 模式 trap 路径

仓库未收录 `rv32mi-p-*` 源码，使用 `sim/tests/mi_smoke.S` 做替代。它覆盖 `csrrw/csrrs/csrrc` 的返回旧值和写回语义、`ecall`/`ebreak` 的 `mcause` 编码（11 / 3）、`mepc` 必须等于触发指令自身 PC，以及 `mret` 回到 `mepc` 下一条。

历史上 `csr_reg.v` 里写的是 `mepc <= pc_addr - 4`，那是为旧的 +4-off PC 语义而设；统一 PC 语义之后 `reg_4_pcaddr` 已经等于该指令的架构 PC，那个 `-4` 必须去掉，不然 handler 读 `mepc` 会落在前一条指令上（OS 常见的 `mepc += 4` 跳过 ecall 的写法就会死循环）。这条 bug 由 `sim/smoke_mi.sh` 守着。

### 异步中断的 `mepc` 语义

原来中断分支写的是 `mepc <= reg_4_pcaddr`，即 "正在 WB 的指令" 的 PC。这条指令其实已经提交过了，`mret` 再跳回去会重复执行一次（当它不是幂等的 ALU 指令时会产生可观察副作用）。

现在的做法是：`csr_reg.v` 多吃一个 `pc_next` 端口，`cpu_jh.v` 把 `reg_3_pcaddr`（MEM 级、仍未提交的那条）喂进去做 `mepc`。前面 branch/jal/jalr 已经在 ID 级把 `reg_3` 填成正确的 architectural next PC，所以这个值等价于 "WB 指令之后要执行的下一条"——包含 `PC+4` 和跳转目标两种情况。如果 trap 发生的那一拍 `reg_3` 刚好是 bubble（例如 branch 冲刷刚过一拍），`cpu_jh.v` 的 `int_take` 会等一拍到 `reg_3_pcaddr != 0` 再允许发 trap。

### `mstatus.MIE` reset 值

原来是 1，违反 RISC-V spec（spec 要求 reset 后 MIE=0）。旧值加上 tb 静态 `e_inter = 1` 会让 CPU 在软件还没写 `mtvec` 之前就立刻 trap 到 `mtvec = 0` 并在那里死循环，所以以前只能靠 "静态 e_inter + 永不开 MIE" 掩盖它。现在 `csr_reg.v` 的 `initial` 与同步 reset 都把 MIE 初始化为 0。

### 中断 pending 锁存的反馈环

`cpu_jh.v` 里有一个 `e_inter_reg` 保存 "有未处理的中断请求"，需要在 trap 真正发生时清 0。旧逻辑用 "进入采样窗口"（`pc_en & reg_4_pcaddr != 0`）当清除条件，结果 MIE=0 时照样清，每拍清一次再置一次，等软件开 MIE 时永远抓不到它。

修复方法是 `csr_reg.v` 新导出一根 `int_taken = e_inter & MIE & MIE7` 的组合信号回传给 `cpu_jh.v`，`e_inter_reg` 只有在 `int_take & int_ack` 都为 1 的那一拍才清零。

### 中断触发模型

`cpu_soc.v` 里的 `e_inter` 输入是**下降沿脉冲**（内部做了 `~e_inter` 再边沿检测），不是高电平。tb `sim/tb/cpu_test.v` 一直把 `e_inter` 拉 1，这就是 "从不产生中断"。需要跑异步中断路径的测试时，用 `+EINT_AT=<ns>` 让 tb 在指定仿真时间产生一次负脉冲；`sim/smoke_mi.sh` 里 `mi_smoke` 的 Test 6 就走这条路径。

### 对齐访问

`rtl/memory/ram_c.v` 的地址选择逻辑实际上用跨 bank 拼接 **硬件 fix-up** 了 misaligned LH/LW/SH/SW，不会抛 `LoadAddressMisaligned` / `StoreAddressMisaligned` 异常。这是本实现相对 spec 的一个显式选择：对简单 M-mode-only 的核子来说允许，但意味着 `rv32mi-p-ma_addr` / `rv32mi-p-ma_fetch` 一类要求抛异常的测试本来就跑不过。

Misaligned JALR 目标同样不会触发 `InstructionAddressMisaligned`，`pc.v` 会直接把该地址写进 `pc_addr`，fetch 到的指令取决于 ROM 行为。两条路径都登记为 "已知架构缺口"，改它需要同时动 `ram_c.v` / `pc.v` 和 `csr_reg.v` 的 trap 分发。

### ROM 读延迟

`rv32ui-p-l{b,bu,h,hu,w}` 实际上是访问 `.rodata`（落在 ROM 窗口），不需要 RAM 初始化通路。仿真里这五个 load 测试之前一直 FAIL 的真实原因是 `sim/models/xilinx_compat.v` 的 `i_rom` 端口 A 是 0-cycle 组合读，而 `rtl/memory/rodata.v` 的 7-state FSM 是按 Vivado BRAM "Read-First with Output Register" 模式（2-cycle 读延迟）写的：采样字节整齐落后了 2 拍，结果是 `reg_data = {mem[0], mem[0], mem[addr+3], mem[addr+2]}`。

现在 `i_rom` 端口 A 已经加了两级输出寄存器与板上行为对齐，这五个 load 测试直接转绿，无需改 `rodata.v`（改 `rodata.v` 反而会在板上炸）。

### PC 语义三处 off-by-4

旧版代码中有三处相互抵消的 off-by-4：

- `rtl/core/id.v` 的 `auipc`：`(addr - 4) + imm`
- `rtl/core/ju.v` 的 `jal` / `jalr` link：`pc_addr` 而非 `pc_addr + 4`
- `rtl/core/pc.v` 的 JALR 目标：直接用 `rs1 + imm` 而不扣 1 周期取指 bubble

它们互相抵消后，`la` 算出的绝对地址恰好是 spec_target − 4。对纯跳转型 test 能通过（因为取指 bubble 会自动吞掉首条指令）；但 `sw` / `sh` / `sb` 等把这个地址当数据地址用时就会落到 `0x1FFFFFFC` 这个未被 `addr2c.v` 映射的位置，总线永远不 ready。

三处已同步修复（`auipc = addr + imm`、link = `pc_addr + 4`、`pc.v` JALR = `rs1 + imm - 4` 补 bubble），`rv32ui-p-sw` 因此转绿。

### `.data` 仿真预装通道

`rv32ui-p-s{b,h}` 的 `TEST_ST_OP` 用例要求 RAM 在 reset 后保留 `.data` 段初值（`0xef` / `0xbeef`）——真板上这是 crt0 从 ROM 拷到 RAM 的结果，但本 SoC 没有 boot loader。

`sim/run_isa.sh` 现在会为每个用例跑一次 `riscv64-unknown-elf-objcopy -O binary -j .data <elf>` 抽出 `.data` 字节流，转 byte-per-line hex 后通过 `+DRAM=<file>` 传进 `sim/tb/cpu_test.v`；测试台在 reset 释放前用 `$readmemh` 读进 64 KB 临时数组，再按 byte 索引分发到 `ram_c.v` 的四个 `dram` bank（`uu1.b1.d_ram_{1..4}.u_ram._ram`）。

这是纯仿真路径，不改板上 RTL，两个 store 测试因此直接转绿，列表基线从 `44 PASS / 2 xfail` 升到 `46 PASS / 0 xfail`。
