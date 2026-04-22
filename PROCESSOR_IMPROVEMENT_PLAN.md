# RISC-V 处理器改进计划

本文档基于对核心 RTL（`rtl/core/cpu_jh.v`、`id.v`、`csr_reg.v`、`mul_div.v`、`ram_c.v`）、SoC 与 README 中「已知架构缺口」的梳理，按**投入产出比**排序，作为后续迭代的路线图。

**当前基线**：`RV32IM` + M-mode trap；`sim/run_isa.sh` 约 46 PASS / 1 SKIP（`fence_i` 与 ROM 自修改相关）/ 0 xfail。

---

## Tier 1 — 低成本、高价值的规范与正确性补齐（建议先做）

> **状态：全部完成**（`sim/run_isa.sh` 46/46 绿，`sim/smoke_mi.sh` 全部 PASS 含新增 Test 7/8）。

### 1. 去掉 load 的人为多周期延迟 ✅

- **位置**：`rtl/memory/ram_c.v` 中 `delay` 模块与 `ram_ready` 组合逻辑。
- **问题**：BRAM 已能在 `cpu_clk` 上 1 拍读出，但 `delay` FSM 将读完成拖到额外周期，每条 load 空转。
- **处理**：删除 `delay` FSM，`ram_ready = (re | we) & d_en` 直接组合返回，与 `dram` 原语的组合读一致。load-heavy 工作负载受益明显。

### 2. IllegalInstruction 异常 ✅

- **位置**：`rtl/core/id.v`、`rtl/core/cpu_jh.v`、`rtl/core/csr_reg.v`。
- **处理**：
  - `id.v` 新加 `illegal` 输出：未知 RV32I opcode（`default` 分支）、非 RV32I 宽度且非零编码均置位，并把控制信号强制为安全 NOP（不写回、不访存、不跳转）。
  - `illegal` 贯穿 `reg_2/reg_3/reg_4` 传到 WB。
  - `csr_reg.v` 在 WB 看到 `illegal & pc_addr != 0 & !int_taken` 时抬 `trap_take_illegal`：`mcause=2`、`mtval=0`、`mepc=pc_addr`、`mstatus_trap_entry` 更新栈。
  - 新增 smoke Test 7 覆盖。

### 3. 规范化 `mstatus` / MPIE 栈 ✅

- **位置**：`rtl/core/csr_reg.v`。
- **处理**：`mstatus_trap_entry` / `mstatus_mret` 两个 function 做字段化更新（只动 MIE / MPIE / MPP，其余 WARL 位保留），reset 值改为 spec 合规的 `0x0000_1800`（MPP=M, MPIE=0, MIE=0）。所有 trap 入口（async / illegal / ecall / ebreak）和 mret 复用同一套 helper。

### 4. 补齐只读与性能类 CSR ✅

- **位置**：`rtl/core/csr_reg.v`。
- **处理**：
  - 只读机器识别 CSR：`mvendorid` / `marchid` / `mimpid` / `mhartid` / `mconfigptr` 读回 0，写忽略。
  - `mcycle(h)` / `minstret(h)` 64-bit 计数器，`mcountinhibit` 的 CY / IR 位控制暂停，软件可通过 CSRRW 写入补偿。
  - `mcycle` / `minstret` 同时镜像到 `cycle` / `instret` 的 `0xC00` / `0xC80` / `0xC02` / `0xC82` 只读窗口。
  - `misa` 扩展为 `RV32IM` 正确编码。
  - 未知 CSR 读返回 0（旧版是 `x`，会随机污染 regfile）。

### 5. 定时器与外部中断规范化 ✅

- **位置**：`rtl/peripherals/timer/clnt.v`、`rtl/soc/cpu_soc.v`、`rtl/core/cpu_jh.v`、`rtl/core/csr_reg.v`。
- **处理**：
  - `clnt.v` 的 `time_e_inter` 由单拍脉冲改为电平：`(clnt_flag != 0) & (mtime >= mtime_cmp)`。软件通过 bump `mtime_cmp` 清除 MTIP。
  - `cpu_soc.v` 对 `e_inter`（低有效）做两拍同步后取反为电平型 `meip`，和 `time_e_inter` 一起喂给 `cpu_jh`。
  - `cpu_jh.v` 删除 `e_inter_reg` / `int_ack` / 脉冲上升沿检测等 hack，换成简单的 `int_window = pc_en & (reg_4_pcaddr!=0) & (reg_3_pcaddr!=0)` 观测窗口。
  - `csr_reg.v` 里 `mip.MTIP` / `mip.MEIP` 变成只读、硬连接到外部电平；CSRRW 仅修改软件位。中断优先级按 spec 选 cause：MEI (0x8000_000B) > MSI (0x8000_0003) > MTI (0x8000_0007)。
  - smoke Test 6 对应更新为期望 `mcause == 0x8000_000B`；tb `+EINT_AT` 改为持续置位（level-sensitive 语义）。

### 6. `WFI` 真实现 ✅

- **位置**：`rtl/core/csr_reg.v`、`rtl/core/cpu_jh.v`。
- **处理**：
  - 删除非标准 `wifi` 寄存器与 `set_pc_addr=0` 的伪重定向。
  - `csr_reg.v` 新增 `wfi_active` 状态：WFI retire 时置位并锁存 `wfi_resume_pc = pc_next`；`(mip & mie) != 0` 时清零。
  - 新输出 `wfi_halt`，在 `cpu_jh.v` 经 `stop_control` 的 `local_stop` 冻结 `pc/reg_1/reg_2`（允许 `reg_3/reg_4` 继续排空）。
  - 若 WFI halt 期间到来 enabled 中断且 `mstatus.MIE=1`，以 `wfi_resume_pc` 作 mepc 入 trap；若 `mstatus.MIE=0`，WFI 直接 wake 继续执行下一条（符合 spec 3.3.3）。
  - 新增 smoke Test 8 覆盖 MIE=0 下 WFI 的 wake-without-trap 行为。

---

## Tier 2 — 性能与结构（处理器「像现代核」）

### 7. 可综合的迭代除法器 ✅

- **位置**：`rtl/core/div_gen.v`（新增）、`rtl/core/mul_div.v`、`sim/models/xilinx_compat.v`。
- **处理**：
  - 新增 `div_gen`：32-bit 无符号 restoring **radix-4** 迭代除法器，**每拍出 2 bit 商**，18 拍完成（1 拍 latch + 16 拍迭代 + 1 拍 done pulse）。组合步骤在 `(D, 2D, 3D)` 三个 34-bit 并行减法器 + 优先级 mux 上做选择；`3D = 2D + D` 在 S_IDLE latch operands 时一次性预算进 `div3_r`，不把乘法放到迭代关键路径。纯 Verilog 可综合，仿真与上板行为一致；依赖 `op1`/`op2` 先取正再进来，符号重构仍在 `mul_div.v` 顶层 mux 处理。
  - 重写 `mul_div.v`：删掉旧的 AXI-Stream 风格 `div_state_machine` 握手以及对 Xilinx `div_0` IP 的依赖，改用 level-based `start` / 单拍 `ready` 直连 `div_gen`；保留所有 div-by-zero / MIN_INT÷-1 overflow 语义。
  - 退役 `sim/models/xilinx_compat.v` 里的 `div_0` 仿真桩；`sim/run_isa.sh` / `sim/smoke.sh` / `sim/smoke_mi.sh` 的 RTL 列表加入 `rtl/core/div_gen.v`。
  - 除零仍天然得到 `quot=0xFFFF_FFFF, rem=dividend`：divisor=0 时所有倍数都是 0，每拍 `ge3=1` 强制 `q_next=2'b11`，16 拍后 `quot` 填满全 1，`rem_r` 逐步把 dividend 重新移进来。
  - 回归：`sim/run_isa.sh` 依然 46/46 PASS（1 SKIP，`fence_i`），其中 `rv32um-p-{div,divu,rem,remu,mul,mulh,mulhsu,mulhu}` 全部通过新除法器；`sim/smoke_mi.sh` 全绿。
  - 相对上一代 radix-2（33 拍）延迟缩短约 **45%**。
- **后续可选**：再堆 radix-8 或 SRT-4（有 redundant/负商位）、dividend LZC 跳步 early-termination；FPGA 上如能容忍 2–3 拍组合减法器可继续压延迟。

### 8. 分支预测 ✅

- **位置**：`rtl/core/branch_pred.v`（新增）、`rtl/core/pc.v`、`rtl/core/cpu_jh.v`。
- **处理**：
  - 新增 `branch_pred`：**32 条目直接映射 BTB + 32 条目 2-bit BHT + 4 深度 RAS**，按 `pc[6:2]` 索引。BTB 条目格式 `{valid, tag, target, type}` 其中 `type ∈ {cond, jal, jalr, ret}`；JAL/JALR 在 BTB 命中即预测 taken，条件分支靠 BHT（2-bit 饱和计数器，复位态 `weakly NT`）决定；`ret`（JALR 返回）的目标优先走 RAS。所有 lookup 组合完成（无读延迟），训练来自 ID 级的真实解析结果。
  - `pc.v` 新增两条 sequential 路径：IF 级 `bp_pred_taken → bp_pred_target` 做推测重定向；ID 级 `id_mispred_en` 做 mispredict 纠偏（优先级：trap > id_mispred > bp_pred > pc+4）。
  - `cpu_jh.v` 扩展 `reg_1` 携带 `pred_taken / pred_target` 元数据，在 ID 对比架构正确下一 PC 与预测的下一 PC，不匹配时产生 1 拍的 `id_mispred_en` 并走原 `data_f_control` flush reg_1 的路径——mispredict 惩罚保持与改造前一致的 1 拍。
  - RAS push/pop 按 RISC-V spec 2.5 提示推断：`JAL/JALR with rd∈{x1,x5}` → call push，`JALR with rs1∈{x1,x5}` 且 `rd∉{x1,x5}` → ret pop；swap/coroutine 简化为 push-only。
  - BTB 别名自纠：非分支指令退休时若 `pred_taken=1`（说明 BTB 被别的 PC 污染），同拍清 `btb_valid` 条目，避免持续误预测。
  - 训练与 mispredict 均用 `pc_en & pcaddr!=0 & ~csr_data_c` 门控：load-use / CSR-use 停顿、trap 提交、bubble 都不会污染表。
  - 新增编译开关 `-DBPU_DISABLE`：强制 `bp_taken=0` 以复现无 BP 基线，方便 A/B 回归。
  - 新增 `sim/bpu_bench.sh`（可选 `--compare`）+ `sim/tests/bpu_bench.S` 量化收益。
- **面积估算**：BTB 32 × ~60 bit ≈ 1.9 Kb、BHT 32 × 2 bit = 64 bit、RAS 4 × 32 bit + 2 bit ≈ 130 bit，合计 ~2.1 Kb（约 260 FF），相对现有核可忽略。
- **实测性能**（`sim/bpu_bench.sh --compare`，iverilog 仿真，`rv32im`）：
  | Kernel | 无 BP | 启用 BP | 加速 |
  |--------|------:|--------:|-----:|
  | 10k `addi+bne` 紧密循环 | 29 999 | 20 002 | **33.3%** |
  | 5k `jal+ret` 函数调用流 | 34 999 | 25 003 | **28.6%** |
  | 10k 前向永不 taken 分支 | 39 999 | 30 002 | **25.0%** |
  | 总运行 | 105 017 | 75 027 | **28.6%** |
- **回归**：`sim/run_isa.sh` 46/46 PASS（1 SKIP `fence_i`），`sim/smoke.sh` / `sim/smoke_mi.sh` 全绿；`-DBPU_DISABLE` 编译路径也通过 `run_isa.sh` 回归。
- **后续可选**：扩大 BTB（64–128 条目），BHT 换 gshare/tournament，RAS 加预测级 push/pop 与 checkpoint 回滚。

### 9. I-Cache / D-Cache

- **现状**：`ram_c` 直连 BRAM，无 cache 抽象。
- **方向**：小规模 direct-mapped I$/D$（如 2–4 KB、16B line）；若外接 DDR，cache + 标准总线几乎必做。

### 10. 流水线模块化 ✅

- **位置**：`rtl/core/cpu_jh.v`、`rtl/core/pipeline_regs.v`（新增）、`rtl/core/hazard_ctrl.v`（新增）、`rtl/core/flush_ctrl.v`（新增）、`rtl/core/stop_cache.v`（新增）、`rtl/core/branch_unit.v`（新增）、`rtl/core/forward_mux.v`（新增）、`rtl/core/mem_ctrl.v`（新增）。
- **处理**：
  - 将 `cpu_jh.v` 末尾内联的 `reg_1 / reg_2 / reg_3 / reg_4` 四段流水寄存器模块搬到 `pipeline_regs.v`；`stop_cache` 搬到同名文件；`stop_control` 重命名为 `hazard_ctrl.v`；`data_f_control` 重命名为 `flush_ctrl.v`。
  - 抽出 `branch_unit.v`：把 ID 级分支 / JAL / JALR 解析、实际下一 PC、mispredict 比对、BPU 训练提示（call / ret / valid）、以及给 `flush_ctrl` 的 `c_pc` 全部收口到一个模块，`cpu_jh.v` 只负责把它与 `branch_pred` 连起来。
  - 抽出 `forward_mux.v`：封装 rs1 / rs2 两路 4 选 1 旁路（00 regfile / 01 EX / 10 MEM / 11 WB），选子由 `otof1.v` 出；编码说明集中在 mux 里。
  - 抽出 `mem_ctrl.v`：EX/MEM 段的组合逻辑（`d_bus_en / data_addr_out / d_data_out / ram_we / ram_re / mem_op_out`、`j_p_out → j2_p_out` 选择器、以及 `reg_3_wq` 早写回对 reg_4 `rd / wb_en` 的屏蔽），从 4 个 `always @(*)` 块合并成一个模块。
  - `cpu_jh.v` 现在只剩顶层端口声明 + 子模块例化 + 少量跨级胶水（`fence_stall`、`local_stop_d1`、`div_wait_d1`、`reg_3_wq = reg_3_wq_out & ~csr_pc_en`、`int_window`、`pc_set_en_pc/pc_set_data_pc` 复用优先级、BPU_DISABLE 编译开关）。按阶段 IF → ID → EX → MEM → WB 顺序排列，注释指向对应子模块。
  - **实例名保持不变**（`a1 / b2 / a5 / a1_2 / a2_3 / a3_4 / a4_5 / bp_u / ca1 / b1 / b5` 等），`sim/tb/cpu_test.v` 里直接点进 `uu1.a1.b2.regs[r]` / `uu1.a1.a5.mstatus` 的硬编码层级依然可用，不需要改 tb。
- **时序语义**：纯结构重构，**没有修改任何时序行为**——`local_stop` 门控、`reg_2` 的 `_r` 影子寄存器 bubble 注入、`reg_3` 的 `div_wait_d1` 清零、`reg_4` 的 `reg4_en` 优先于 `rst` 的旧语义、`flush_ctrl` 的 `rst[0..3]` 编码、BPU 预测 / mispredict 1 拍惩罚全部按位保留。`sim/run_isa.sh` 46/46 PASS（1 SKIP），`sim/smoke.sh` / `sim/smoke_mi.sh` 全绿，`-DBPU_DISABLE` 编译路径亦回归通过。
- **暂未做流水线握手（ready / valid）**：控制信号存在较多跨级复用（例如 `pc_en` 同时门控 PC、reg 使能、branch_unit 的 mispredict 有效位；`reg_3_wq` 同时用作 regfile 早写回 w_en_2 与 reg_4 的 rd 屏蔽；`reg_2_load / reg_2_csr[2]` 同时驱动 otof1 的 hazard 检测与旁路选通），全部改为标准握手需要同步改所有模块的阻塞/注泡语义，风险较高。已保留现有 enable + bubble-inject + flush 的语义作为后续握手化的起点。
- **后续可选**：
  - 进一步把 IF / ID / EX / MEM / WB 各 stage 再包成 `stage_*.v`（目前按"功能模块"拆，不是严格按阶段），需要把跨级转发端口显式化；
  - 把 `otof1` 与 `forward_mux` 合并成 `hazard_fwd.v`；
  - 正式做 ready / valid 握手，配合 `pc_en` / `reg_X_en` / `local_stop` 的统一重构。

---

## Tier 3 — ISA / 特权模式扩展

| 扩展 / 能力 | 工作量（相对） | 软件侧收益 |
|-------------|----------------|------------|
| Zicsr / Zifencei 归档 | 低 | 与 spec 表述一致 |
| Zba / Zbb / Zbs | 低（多数为 ALU） | GCC `-march=rv32im_zba_zbb` 等 |
| Zicond | 低 | 条件移动类优化 |
| C（压缩） | 中 | 代码体积、通用工具链默认常开 |
| A（原子） | 中 | 多核/锁、C11 atomic |
| PMP | 中 | RTOS MPU 隔离 |
| S-mode + Sv32 | 高 | **Linux 等完整 OS** |
| F/D 浮点 | 很高 | 科学计算、完整 libc |

- **RTOS 向**：C + PMP 往往足够。
- **Linux 向**：S-mode + Sv32 + A + C 等为硬门槛。

---

## Tier 4 — SoC 基础设施

1. **总线**：将定制握手升级为 **AXI4-Lite** 或 **AHB-Lite**，便于接 MIG、16550、QSPI、DMA 等。
2. **CLINT + PLIC**：采用常见 memory map（如 SiFive 风格），提升与 OpenSBI / Linux 的兼容性。
3. **RISC-V Debug Module（JTAG）**：对接 openocd/gdb。
4. **启动链**：BootROM + 可选从 Flash/SD 装载；UART 下载路径可逐步外置化。
5. **外设规范化**：UART 兼容 16550；GPIO 从 `cpu_soc.v` 内嵌 reg 中独立。
6. **容量**：当前数据 RAM 约 128 KB 级；接 DDR 后地址空间与控制器需一并规划。

---

## Tier 5 — 验证与工程化

1. **Verilator `--lint-only`**：尽早暴露组合块中 `<=`、位宽、未初始化等问题。
2. **构建系统**：根目录 `Makefile` 或 CMake：`test` / `lint` / `fpga` 等统一入口。
3. **`rv32mi-p` 完整集**：在 `mi_smoke` 之外引入上游 riscv-tests 的 mi 系列。
4. **形式化**：如 riscv-formal / SymbiYosys 对单发射核性价比高。
5. **随机测试**：RISCV-DV + Spike lock-step。
6. **性能基线**：Dhrystone / CoreMark 纳入 `sw/` 与 smoke，每次改动对比 DMIPS/MHz。
7. **CI**：如 GitHub Actions 跑 `sim/run_isa.sh`，防止回归。

---

## 建议落地顺序

1. **第一轮**：Tier 1 的 1、2、3、4、6；回归 `sim/run_isa.sh` 与 `sim/smoke_mi.sh`。
2. **第二轮**：Tier 1 第 5 项 + CLINT/PLIC 端口与 MMIO 对齐；退役 tb 侧 `e_inter` hack。
3. **第三轮**：Tier 2 第 7 项 + Tier 5 的 lint、Makefile、性能基线。
4. **之后按目标分叉**：
   - 教学/优雅核：Tier 2 的 BPU、Cache、模块拆分；
   - RTOS：Tier 3 的 Zba/Zbb、C、PMP；
   - Linux：Tier 3 的 S-mode + Sv32 + A + C，并配 Tier 4 的 AXI、DDR、CLINT/PLIC、Debug。

---

*文档生成自对仓库当前实现的审查；具体数字（如 IPC 提升比例）随程序与配置变化，实施时以实测为准。*
