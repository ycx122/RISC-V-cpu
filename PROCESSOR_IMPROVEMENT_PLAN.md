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

### 9. I-Cache / D-Cache ✅

- **状态**：I-Cache 在 Tier 4.2.6 完成；本节聚焦 **A1 D-Cache + A2 Store Buffer**（Tier A #1/#2）。
- **位置**：`rtl/bus/dcache.v`（新增）、`rtl/bus/store_buffer.v`（新增）、`rtl/soc/cpu_soc.v`（在 mem_ctrl 与 `axil_master_bridge` 之间插 D-Cache，新增 `-DDCACHE_DISABLE` 旁路）、`sim/filelist/rtl_soc.f` / `scripts/lint.sh`（rtl 列表同步）。
- **拓扑**：8 KB direct-mapped、16-byte line（4 word）、512 line；`tag=addr[31:13]`、`index=addr[12:4]`、`wsel=addr[3:2]`。Write-back、write-allocate；命中组合返回 `up_d_bus_ready` + 抽取后的字（与 I-Cache 命中等价的 0 拍消费）。
- **可缓存域**：仅 `0x2000_0000..0x2FFF_FFFF`（数据 RAM 窗口）；ROM (`0x0xxx_xxxx`) 与 MMIO (`0x4xxx_xxxx`) 走 bypass 路径。后续若把 ROM 也纳入可缓存域，需要在 dcache 里区分「dirty 不能 evict 到 ROM」的语义。
- **Store Buffer**：4-entry FIFO，每 entry `{addr, wdata, wstrb, op}`。两个用途：
  1. **MMIO 写吸收**：非可缓存 store 在 SB 有空位时同拍 retire（以前每次 MMIO 写要等 AW+W+B = 2 拍）；4 个回连续 UART poke 可以一次 1 拍 retire。
  2. **Write-back drain**：cache miss 撞到 dirty victim 时，dcache 把 4 个 dirty word push 进 SB 然后立刻发 line fill；4 个 evict word 在后台 drain 到 RAM，CPU 在 fill 完成后立刻拿到新数据。
- **Bridge 仲裁**：D-Cache 是 `axil_master_bridge` 上唯一的 client，内部把 `S_FILL`（4-beat line read）、`S_BYPASS`（CPU 单笔 NC 访问）和 SB drain 三者按 FSM 串行化。
- **Misalign / Access Fault**：mirror Tier A #2/#3 行为。dcache 在 IDLE 检测 misalign，直接组合给 CPU `up_d_bus_misalign=1`，绝不发 AXI；bridge 端的 fault 通过 `dn_d_bus_err` 在 S_BYPASS / S_FILL 透回 CPU；write-back drain 期间的 fault 是 imprecise（与商业 write-back cache 一致），实测 BSP 不踩，仅在故障注入测试中可见。
- **关键 bug 与修复（`sb_pop` 时序）**：初版 `sb_pop` 是 1 拍寄存器 NB，导致在 `dn_d_bus_ready=1` 当拍 SB 还显示 `head_valid=1`，下一拍 dcache 在 S_IDLE 又给 bridge 推了**同一条**已 pop 的 entry（"幻影 drain"）。下下拍 dcache 进入 S_BYPASS 准备发 ROM read，bridge 还在做幻影 write；幻影 write 完成时给的 `d_bus_ready=1` 被 S_BYPASS 误当成自己的 read ack，把 bridge 锁存的旧 rdata（上一次 ROM 读的 0x0a）回给 CPU——`xprintf` 死循环根因。修复：把 `sb_pop` 改成 `assign sb_pop = sb_drain_active & dn_d_bus_ready;` 组合输出，让 SB 的 `valid_mem[rd_ptr]=0 / occ--` 在 ack 当拍 NB 生效，下一拍 `head_valid=0`、不再发幻影 drain。
- **关键 bug 与修复（`sb_push` 时序，os_demo / freertos 10kHz）**：dcache 的 `sb_push` 是寄存器输出（决策 cycle N → push 到 SB 输入端 cycle N+1），而 `idle_nc_store_ok` / `S_WB_PUSH` 入口的 `S_IDLE` 分支只检查当前 cycle 的 `sb_full` / `sb_empty`，没考虑「上一拍已经决定、此刻还在 SB 输入端在途」的那次 push。最坏情形：连续 NC store 把 occ 抬到 3 时，dcache 看到 `~sb_full=1` 又决定 push，结果两条决策对应的 push 在 cycle K+1 / K+2 接连落进 SB——cycle K+2 那次撞到 `occ==4 && push==1`，store_buffer.v 报 `push into full SB`，丢的那条 store 又对应 trap 入口 context-save 的某个 SP-relative 字，后果就是 trap handler 看到一个被腰斩的栈帧、`mret` 跳飞，os_demo 在 `[task1] iter=2 tick=` 那行 UART 喷射途中 SB 溢出，FreeRTOS 10kHz 跑几个 tick 后栈被踩烂死循环。修复：`store_buffer.v` 暴露 `near_full = (occ + push - pop == DEPTH)` 与 `near_empty = (occ + push - pop == 0)`（都把当前周期已声明在 SB 输入端的 push/pop 一并算进去），dcache 把 `idle_nc_store_ok` 与「带 dirty victim 的 cacheable miss 进 `S_WB_PUSH`」/「NC load 进 `S_BYPASS`」三处门控统一换成 `~sb_near_full` 与 `sb_near_empty`，再没有「检查时不满，落地时已满」的 1 拍盲区。`sim/run_os_demo.sh`、`sim/run_freertos_demo.sh`（10 kHz tick）现在都干净通过。
- **`fence.i` 顺序**：靠 `cpu_jh.v` 的 `fence_stall` 排空数据侧（即排空 SB），与现有语义兼容；dcache 的 `flush` 端口暴露在外但 cpu_soc 接 1'b0（无效化整张 cache 是简单粗暴的语义，后续可挂到 `Zicbom`）。
- **回归**（三条 fetch 路径并跑）：
  - 默认（`I-Cache + D-Cache`）：`sim/run_isa.sh` 46/46 PASS（1 SKIP `fence_i`）、`sim/smoke.sh` PASS、`sim/run_dhrystone.sh` PASS（**TEST_PASS** 包括 `Str_1_Loc / Str_2_Loc` 完整字符串校验）；
  - `-DICACHE_DISABLE`：`sim/run_isa.sh` 46/46 PASS；
  - `-DTCM_IFETCH`：`sim/run_isa.sh` 46/46 PASS；
  - `-DDCACHE_DISABLE`：`sim/run_isa.sh` 46/46 PASS（旁路路径与 Tier 4.2 行为一致）。
- **资源估算（Artix-7 200T）**：tag SRAM 512 × 19 = 9.7 Kbit；data SRAM 512 × 128 bit = 64 Kbit（≈ 4 个 18-Kbit BRAM）；valid/dirty 1024 FF；FSM/比较 ~150 LUT。SB 4 × (32+32+4+3) = 284 bit ≈ 一个 distRAM；snoop 4 × 32-bit 比较器 + 字节合成 ~40 LUT。整体远小于 200T 余量。
- **后续可选**：
  - 扩 16 KB 或换 2-way set associative（命中率 + 抗 thrashing）；
  - dirty bit 改 per-word 而非 per-line（write-back 流量进一步减少）；
  - 把 ROM 域也加入 cacheable（需配套加「ROM 永远不 dirty」断言，避免错误 evict）；
  - 进一步实现 hit-under-miss（在 line fill 期间允许命中已经填好的字），需要让 hit 路径同时窥探 `fill_buf`，目前只做了 critical-word-first，对同 line 的后续字仍 stall 到 commit。

### 9.x · 总线组合握手 + I/D-Cache critical-word-first ✅

- **位置**：`rtl/bus/axil_master_bridge.v`（4 态 → 3 态 FSM，`m_arvalid / m_awvalid / m_wvalid / d_bus_ready / d_bus_err / d_bus_misalign / bus_data_in` 全部组合化）、`rtl/bus/dcache.v`（删除 `S_FILL_ACK`，`fill_cnt` 起始为 `miss_addr[3:2]`，用 `beats_rcv` 计数 + 显式 `fill_pending`）、`rtl/bus/icache.v`（CWF：`beats_rcv==0` 标定首拍 deliver，`fetch_target_match` 防 PC 重定向错配）。
- **动机**：Tier 4.2 末尾遗留的两条 follow-up：
  1. `axil_master_bridge` 原 `S_IDLE → S_R/S_W → S_DONE → S_IDLE` 4 态 FSM 让每一笔 load/store 都至少多 1 拍 latency（`S_DONE` parking 拍 + `S_IDLE → S_R/S_W` 注册 AR/AW）；
  2. I-Cache / D-Cache 都「填满整条 line 才 ack CPU」，关键字真正被消费的是第一拍 beat，剩下三拍其实可以后台填，CPU 没必要陪着等。
- **处理（`axil_master_bridge`）**：
  - **FSM 塌成 3 态**：`S_IDLE → S_R / S_W`，response 通道（`B / R`）回来那拍组合输出 `d_bus_ready / d_bus_err / d_bus_misalign / bus_data_in`，bridge 与 CPU 在同一时钟沿上做下一拍的状态推进。S_DONE parking 拍删掉是安全的——旧版 S_DONE 的存在是为了避免「CPU 还没消费 ack 就被同拍重发同一笔事务」，组合 ack 把 ack 和 reg_3 advance 合并到同一沿后这条隐患天然消失（reg_3 在 ack 那拍就已经 advance，下一拍 `d_bus_en` 反映的是新指令）。
  - **AR / AW / W / wstrb / wdata 全部组合**：`m_arvalid = idle_r_issue`、`m_awvalid = m_wvalid = idle_w_issue`，`m_araddr / m_awaddr` 直接来自 `d_addr` 的高 30 位拼对齐位；`m_wstrb / m_wdata` 由 `mem_op + d_addr[1:0] + d_data_out` 组合算。`addr_latch / op_latch` 仍按 AR/AW fire 那拍寄存，留给 R 通道字节抽取做 base，避免把 `d_addr → m_araddr → interconnect → m_rdata → bus_data_in` 全部串成一条组合长链。
  - **未对齐 short-circuit 也组合**：`idle_misalign`（CPU 发 misaligned load/store）那拍直接拉 `d_bus_ready=1, d_bus_misalign=1`，state 留在 S_IDLE 不变，AXI 总线上不发任何事务；与 Tier A #2 的语义一致，但少一个 parking 拍。
- **处理（D-Cache CWF）**：
  - **FSM 删 `S_FILL_ACK`**：进入 `S_FILL` 时 `fill_cnt <= miss_addr[3:2]`（关键字偏移），`beats_rcv` 计数到 3 时直接转回 S_IDLE 并 commit 新 line。首拍 CWF 用 **`beats_rcv==0 & dn_d_bus_ready`** 限定 `up_d_bus_ready` 只 pulse 一次（无需额外 `fill_first_done` 寄存器）。
  - **CWF deliver 路径**：第一拍 beat 到达时（`fill_first_beat = fill_pending & dn_d_bus_ready & (beats_rcv==0)`）组合驱动 `up_d_bus_ready=1` 并 `up_bus_data_in = extract_load(dn_bus_data_in, ...)`——直接用 AXI R 通道送上来的字而不是 fill_buf 里寄存版本，省一拍。
  - **背景填 + 显式 fill_pending**：`assign fill_pending = (state==S_FILL)`；第一拍 beat ack 之后 CPU 会推进 reg_3 并可能立刻发出新的 load/store；此时 D-Cache 状态仍是 `S_FILL`，所有 `idle_*` 通道（hit / NC store / misalign）都被 `state == S_IDLE` 锁住，新请求会自然 stall，等当前 line commit 后 (state→S_IDLE) 再服务。Hit-under-miss / 同 line 不同字 deliver 留作 follow-up。
- **处理（I-Cache CWF）**：
  - 同样把 `fill_cnt <= up_wsel` 作为起始 beat 偏移，用 `beats_rcv` 计数到 3 表示整行收齐；首拍用 **`fill_critical_beat = (state==S_FILL) & dn_ready & (beats_rcv==0)`**。
  - `fill_deliver = fill_critical_beat & fetch_target_match`：`fetch_target_match` 即 `up_idx/up_tag/up_wsel` 与 miss 时锁存的 `fill_*` 一致，防 stale-fill（trap / pending redirect 改了 PC 时不能把旧 line 的字塞给新 PC）。
  - 第一拍 beat 之后 CPU 的 reg_1 已经拿到关键字、`pc_addr` 一拍内可能 advance；icache 继续在背景接收剩下三拍并最终在 `beats_rcv==3` 那拍 commit `tag_mem / valid / data_mem`。背景填期间任何 lookup 都因 `state != S_IDLE` 而 miss → stall（hit-under-miss 同样列为 follow-up）。
- **回归**：
  - `sim/run_isa.sh` 46/46 PASS（1 SKIP `fence_i`），同步在 `-DTCM_IFETCH` / `-DICACHE_DISABLE` / `-DDCACHE_DISABLE` / `-DICACHE_DISABLE -DDCACHE_DISABLE` 四个编译开关下都 46/46；
  - `sim/smoke.sh`、`sim/bus_bench.sh`、`sim/bpu_bench.sh` 全绿；`sim/smoke_mi.sh` 与基线状态等价（基线已知 Test 10 imprecise SB 路径未消费 DECERR，是 Tier 9 D-Cache 文档中已记录的 known limitation，本次改动不引入新失败）；
  - `sim/run_dhrystone.sh` 端到端：mcycle `2534 → 2381`、cycles/Dhrystone `506 → 476`、IPC `0.574 → 0.611`、DMIPS/MHz `1.124 → 1.195`（**+6.3%**）；
  - `sim/bus_bench.sh` ROM `.rodata` lw（NC bypass 路径）`9.00 → 7.00 cyc/iter`（**−22.2%**），RAM 命中路径不变（cache hit 主导，组合 bridge 只在 miss / NC / writeback 路径出现）。
- **时序注意点**：组合化后新增了三条值得在 P&R 上盯一下的路径：
  1. `d_addr → m_araddr / m_awaddr → interconnect → s_*ready` —— 主桥到从桥决策的 AR/AW 路径变长；
  2. `m_rvalid → bridge.d_bus_ready → dcache → cpu.hazard_ctrl.d_wait` —— bypass / fill-first-beat 那拍的 ack 反馈链路；
  3. `m_rdata → bridge.bus_data_in → dcache → mem_ctrl.j2_p_out → reg_4_in` —— 关键字数据通路。
  Artix-7 100T / 200T 当前频率档位下 iverilog/Verilator 仿真均无问题；如果未来在更高 fmax 上踩到 setup violation，可以**只**把 `m_arvalid / m_awvalid / m_wvalid` 退化回 1 拍寄存（保留 `S_DONE` 删除带来的 1 拍收益），这是 PROCESSOR_IMPROVEMENT_PLAN 之前明确给出的 fmax 退路。
- **后续可选**：
  - I-Cache / D-Cache 加 hit-under-miss：在 fill_buf 上挂一个 partial-line snoop，让对同一 line 已落地字的 hit 不再 stall 到 line commit；
  - 把 D-Cache 的 NC store 也用组合 bridge 直接 ack（目前仍走 SB，多一拍 SB push），能再压一拍 MMIO 写延迟；
  - 把 4-beat 单笔 AR 升级为 AXI4 burst（INCR len=4），上游接 MIG 时一次 burst 就能把整条 line 拉回。

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

### 1. 总线升级到 AXI4-Lite ✅

- **位置**：`rtl/bus/axil_master_bridge.v`（新增）、`rtl/bus/axil_slave_wrapper.v`（新增）、`rtl/bus/axil_interconnect.v`（新增）、`rtl/soc/cpu_soc.v`（重写）、`rtl/memory/ram_c.v`（重写数据侧）、`rtl/memory/rodata.v`（简化）。
- **处理**：
  - **CPU 侧零侵入**：`cpu_jh.v` 的 `{d_bus_en, ram_we, ram_re, d_addr, d_data_out, mem_op, d_bus_ready, bus_data_in}` 端口完全保留。新增 `axil_master_bridge` 专门把这个遗留握手翻译成标准 AXI4-Lite 主口（AW / W / B / AR / R），FSM 四态 `S_IDLE → S_W|S_R → S_DONE → S_IDLE`，其中 `S_DONE` 复刻旧 `riscv_bus` 的 `TRANS` 1 拍隔离状态，防止流水线推进前被同拍重发事务。
  - **字节通道统一由 master bridge 处理**：写侧生成 AXI `WSTRB`（`SB/SH/SW` + `d_addr[1:0]` → 4-bit strobe）并把数据打到正确字节通道；读侧永远发起对齐 32-bit 读，然后根据 `op_latch + addr_latch[1:0]` 抽取字节 / 半字并做符号 / 零扩展。所有从设备都只需面对「32b 字 + WSTRB」这一种 AXI4-Lite 原生接口，和 Xilinx MIG、`axi_uart16550`、`axi_qspi`、`axi_dma` 的 slave 口形状一致。
  - **六从地址译码**：新增 `axil_interconnect`（1 主 → 6 从），内部纯组合译码 + OR-mux 响应路径，按 `[31:28]` / `[31:24]` 截断地址到 `ROM / RAM / LED / KEY / CLINT / UART` 六个 bundle。退休旧 `rtl/interconnect/addr2c.v`（整个目录移除）。
  - **通用从口 shim**：`axil_slave_wrapper` 把 AXI4-Lite 从口化成 `{dev_en, dev_we, dev_re, dev_addr, dev_wdata, dev_wstrb, dev_rdata, dev_ready}` 的简化握手，FSM `S_IDLE → S_WRITE|S_READ → S_BRESP|-`。读通道优先级高于写通道，单事务 in-flight，避免乱序回调。
  - **`ram_c.v` 改造**：删除原本基于 `mem_op` 的跨 bank 字节旋转（`lb/lh/lw/sb/sh/sw` 的软补偿逻辑），改为 4 字节 bank 各自由一个 `WSTRB[i]` 驱动写使能，读通道并回 32b 字；i_rom（指令取指）与 UART 下载路径不动。这一改版暴露给 AXI-Lite 的形状就是「32b RAM + wstrb」，可以直接被 Xilinx AXI BRAM Controller / MIG 的 AXI-Lite facade 替换。
  - **`rodata.v` 精简**：原来的 7 态 FSM 自带一个 `mem_op` 驱动的符号扩展 / 字节抽取分支（耦合了 CPU 私有概念），现在只按状态顺序组装对齐 32b 字，抽取与扩展交给 master bridge 统一做。FSM 的字节顺序（4 拍 stream + 2 拍 i_rom 输出寄存器延迟）完全保留，因此上板 Vivado BRAM 读时序不变。
  - **LED / KEY 转标准从口**：不再由 SoC 顶层内嵌的 `if-else` 驱动。LED 经 `axil_slave_wrapper` 接到一个尊重 `WSTRB[1:0]` 的 16-bit 输出寄存器；KEY 经同一 shim 接回只读 8-bit 输入。
  - **地址映射未改**：软件层面的 memory map（ROM `0x0000_0000` / RAM `0x2000_0000` / LED `0x4000_0000` / KEY `0x4100_0000` / CLINT `0x4200_0000` / UART `0x4300_0000`）与 interrupt 语义完全保持，所以 `sim/run_isa.sh`（46/46 PASS + 1 SKIP `fence_i`）和 `sim/smoke_mi.sh`（全绿，含新改写后的数据通路）无回归。
- **8/16/32 bit 访问**：继续支持。字节 / 半字在 master bridge 端以 `WSTRB` 写入、以单个 32-bit AXI 读 + 字节抽取 + 符号/零扩展读出；与 AXI4-Lite 标准和 RISC-V `lb/lh/lw/lbu/lhu/sb/sh/sw` 均一致。
- **未对齐访问**：沿用旧核的"bridge 内硬补丁"策略——master bridge 发出的 AR/AW 永远对齐（强制 `awaddr[1:0]=00`），然后在字节抽取级用 `addr_latch[1:0]` 修正；不抛 `LoadAddressMisaligned` / `StoreAddressMisaligned`。这与仓库 README 已登记的架构缺口一致，`rv32mi-p-ma_*` 本来就不跑。
- **回归**：`sim/run_isa.sh` 46/46 PASS（1 SKIP `fence_i`），`sim/smoke_mi.sh` 全绿；`sim/run_isa.sh` / `sim/smoke_mi.sh` / `sim/smoke.sh` / `sim/bpu_bench.sh` / `scripts/lint.sh` 的 RTL 列表全部同步加入新 `rtl/bus/*.v` 并删掉 `addr2c.v`。

### 2. AXI4-Lite 总线快速路径 + ROM 宽读口 ✅ · DECERR / Access Fault ✅ · Tier A #1/#2/#3 ✅

- **位置**：`rtl/bus/axil_slave_wrapper.v`（重写为组合握手）、`rtl/memory/rodata.v`（7 态 → 3 态 FSM）、`rtl/memory/ram_c.v`（`i_rom` port A 实例化改 32-bit + byte-strobe）、`rtl/soc/cpu_soc.v`（`rom_addr_word/rom_data_word` 线宽同步）、`sim/models/xilinx_compat.v`（`i_rom` port A 32-bit 读 + 4-bit byte-write 使能仿真桩）、`sim/tests/bus_bench.S`（新增）、`sim/bus_bench.sh`（新增）。
- **动机**：Tier 4.1 完成后用微基准量化，单次 RAM load 要 4 拍 bus 延迟（master_bridge `S_IDLE→S_R→S_DONE` 2 拍 + slave_wrapper `IDLE→READ→R-pulse` 2 拍），`.rodata` 读更是要 ~11 拍（i_rom port A 8-bit → 7 态字节 walker）。两项都是 standard AXI4-Lite 在"小从机"上常见的 handshake 冗余。
- **处理**：
  - **`axil_slave_wrapper` 改组合握手**：`s_arready / s_awready / s_wready` 直接 `assign = (state==IDLE)`（写通道额外要求 AW+W 同拍到），`s_rvalid / s_bvalid` 组合为 `(state==READ|WRITE) & dev_ready`。FSM 从 4 态（IDLE / WRITE / BRESP / READ）塌成 3 态（IDLE / READ / WRITE），省掉 BRESP 的寄存回读 + 旧版 READ 里把 `s_rvalid` 寄存一拍的 2 个 overhead cycle。前提是主桥必须在发起 AR / AW+W 的同时就把 `m_rready / m_bready` 拉高（本仓 `axil_master_bridge` 正是这么做的），在代码注释里把这条 contract 写死。
  - **`i_rom` port A 升为 32-bit**：按 Xilinx BRAM 标准「32-bit 读 + 4-bit byte-write enable」配置；地址从 `[15:0]` 字节转为 `[13:0]` 字；`dina` 宽 32 bit，`wea` 宽 4 bit。UART 下载依旧是字节流，实现上把每字节复制到四条 lane（`{4{uart_rx_data}}`）再用 `wea = 1'b1 << byte_addr[1:0]` 选中目标 lane，行为与原 8-bit 版本一一对应。
  - **`rodata.v` 简化为 3 态**：`IDLE → WAIT1 → WAIT2`，在 WAIT2 直接组合输出 `rom_r_ready=1` 且 `reg_data = rom_data`（主桥同拍捕获到 `rdata_latch`）；WAIT2 黏住直到 `rom_en` 落下以容忍主侧 rready 暂时未至。三态对应 i_rom port A 的 2-stage 输出寄存器 + 1 拍 handshake，ROM 8-bit byte walker 自然消失。
- **仿真桩**：`sim/models/xilinx_compat.v` 里 `i_rom` 重写成 32-bit 读 + 4-bit byte-write，输出寄存器仍然 2 级以保持与板上 Vivado BRAM 行为一致。上板时需要在 Vivado BRAM Generator 里把 port A 选成「Byte Write Enable = 8」+ 32-bit 接口；老的 8-bit port A 配置不再兼容（注释里有提示）。
- **实测性能**（`sim/bus_bench.sh`，每 kernel 5000 次迭代，单迭代 3 条指令 `lw/sw + addi + bne`）：

  | Kernel             | Tier 4.1 cyc/iter | Tier 4.2 cyc/iter | 改进 |
  |--------------------|------------------:|------------------:|-----:|
  | RAM `lw`           | 7.00              | 6.00              | **−14.3%** |
  | RAM `sw`           | 7.00              | 6.00              | **−14.3%** |
  | ROM `.rodata` `lw` | **13.00**         | **8.00**          | **−38.5%** |
  | 总运行（三 kernel 合计） | 135 014           | 100 020           | **−25.9%** |

  折算到总线延迟本身：RAM load-to-use 从 4 拍压到 3 拍（slave_wrapper 省 1 拍），`.rodata` load-to-use 从 ~11 拍压到 5 拍（rodata FSM 从 7 拍 → 3 拍 + wrapper 少 1 拍）。
- **回归**：`sim/run_isa.sh` 46/46 PASS（1 SKIP `fence_i`），`sim/smoke_mi.sh` / `sim/smoke.sh` / `scripts/lint.sh` 全绿；无新 xfail。新加回归工具 `sim/bus_bench.sh` + `sim/tests/bus_bench.S` 以便后续做总线层面的 A/B。
- **后续可选（Tier 4 第 3–6 项的后续踏板）**：
  - ~~把 `axil_master_bridge` 的 `S_IDLE → S_R/S_W` 转换也组合化（m_arvalid 在 IDLE 直接跟随 `d_bus_en`）~~ → 已在 [Tier 9.x 总线组合握手 + I/D-Cache critical-word-first](#9x--总线组合握手--idcache-critical-word-first-) 完成，把 4 态 FSM 塌成 3 态 + 删 `S_DONE`，配合 D-Cache CWF 让 Dhrystone IPC 0.574 → 0.611、ROM `.rodata` 9 → 7 cyc/iter；
  - 引入 1 拍 Store Buffer（CPU 写完立刻 retire，写后 load 靠 bypass），可把 sw 的 6 拍/iter 降到接近 3 拍/iter（已在 Tier 9 D-Cache + SB 中完成）；
  - 挂 Xilinx `axi_uart16550` / `axi_qspi` / `axi_dma` 做真实 AXI 负载；
  - 接 MIG 的 AXI4-Lite facade 以替换当前内建 BRAM 的 RAM 窗口；
  - 补一个 AXI4-Lite ↔ APB 桥，方便挂低速 APB IP。

#### Tier A #3 · DECERR / Load & Store Access Fault

- **位置**：`rtl/bus/axil_interconnect.v`（新增 `aclk/aresetn` 端口 + DECERR 响应合成器）、`rtl/bus/axil_master_bridge.v`（新增 `d_bus_err` 输出，锁存 `m_{b,r}resp[1]`）、`rtl/core/pipeline_regs.v`（`reg_4` 新增 `load_fault/store_fault/fault_addr` 字段）、`rtl/core/cpu_jh.v`（顶层 `d_bus_err` 入口 + fault 传递与 `rd/wb_en` 屏蔽）、`rtl/core/csr_reg.v`（`trap_take_{load,store}fault` 分支，`mcause=5/7`、`mtval=fault_addr`）、`rtl/soc/cpu_soc.v`（桥与 CPU、互连的新端口走线）、`sim/tests/mi_smoke.S`（新增 Test 9/10）。
- **问题**：Tier 4.1/4.2 之前对未映射的 MMIO 访问要么原地 hang（互连发不出 `bvalid/rvalid`），要么变成 silent no-op，软件没有任何可观测信号，调试极痛。
- **处理**：
  - **互连内生成合成 DECERR 从口**：`axil_interconnect.v` 加一个小的 2 bit 状态（`err_bvalid/err_rvalid`）。当 AW+W 同拍命中 `wr_none` 时，下一拍把 `m_bvalid/m_bresp=2'b11` 推给主桥；AR 命中 `rd_none` 同理下一拍给出 `m_rvalid/m_rresp=DECERR, m_rdata=0`。`m_{aw,w,ar}ready` 在 unmapped 路径下由 `~err_{b,r}valid` 门控，保证响应挂起期间不会再次接收新的 AW/W/AR；handshake 时序和真实 1-cycle AXI 从机一致，Master bridge 看到的 AW/W→B 或 AR→R 延迟不超过 1 拍。
  - **Master bridge 透出 `d_bus_err`**：`axil_master_bridge.v` 在 `S_W/S_R` 把 `m_bresp[1]`（区分 SLVERR=10 / DECERR=11 与 OKAY=00 / EXOKAY=01）或 `m_rresp[1]` 锁进 `d_bus_err_r`，与 `d_bus_ready_r` 同步 1 拍 pulse 送给 CPU。非 reset 路径默认每拍清零，保证不会跨事务残留。
  - **CPU 把 fault 带到 WB**：`cpu_jh.v` 在 MEM 级组合出 `r3_load_fault = d_bus_ready & d_bus_err & reg_3_load` / `r3_store_fault` / `r3_fault_addr = reg_3_p_out`，并把 `reg_3_rd/wb_en` 在 load fault 时强制清零（garbage rdata 不允许污染 rd；store 无 rd，自然不动）。三者与原有 `illegal` 一道经 `reg_4` 传到 `csr_reg`，**没有改动 `mem_ctrl.v`**——所有门控都收口在 `cpu_jh.v` 顶层，避免 `mem_ctrl` 继续耦合 fault 路径。
  - **`csr_reg.v` 的 trap 优先级**：按 RISC-V 特权规约 3.7，Load/Store access fault 的同步优先级低于 illegal instruction、高于 ecall / ebreak。具体实现是 `trap_take_storefault = store_fault & ~int_taken & ~trap_take_illegal`、`trap_take_loadfault = load_fault & ~int_taken & ~trap_take_illegal & ~trap_take_storefault`；两者都会写 `mepc=pc_addr, mtval=fault_addr`，`mcause=7`（store）或 `mcause=5`（load），并走和其他同步异常完全相同的 `mstatus_trap_entry` + `mtvec` 重定向路径。`retired` 统计里也会把 fault 的 WB slot 从 minstret 中排除。
- **测试**：`sim/tests/mi_smoke.S` 扩了两条：
  - **Test 9 · Load access fault**：`lw a3, 0(0x5000_0000)` 预埋 `a3=0xbad00` 作 sentinel；handler 验 `mcause=5 / mepc=&load_fault_site / mtval=0x5000_0000 / a3 仍为 0xbad00`（即 rd 没被 DECERR 的 garbage 覆盖）。
  - **Test 10 · Store access fault**：`sw t2, 0(0x5000_0004)` 验 `mcause=7 / mepc=&store_fault_site / mtval=0x5000_0004`（mtval 跟踪真实故障地址，不是老数据）。
- **回归**：`sim/smoke_mi.sh` 全绿（含 Test 9 / Test 10）、`sim/run_isa.sh` 46/46 PASS（1 SKIP `fence_i`，与基线一致）、`sim/smoke.sh` 全绿、`sim/bus_bench.sh` `RAM 6.00 / ROM 8.00 cyc/iter`（Tier 4.2 性能基线未退）、`scripts/lint.sh` 全绿；无新 xfail。
- **向外露出的行为契约**：
  - 任何 `[0x4400_0000, 0x1FFF_FFFF] ∪ [0x3000_0000, 0x3FFF_FFFF] ∪ [0x4400_0000, 0xFFFF_FFFF]` 范围（即六条从口窗口以外的所有地址）都会被合成为 DECERR；写不再 silent、读不再挂死；
  - 软件在 `mtvec` 处可以靠 `mcause ∈ {5, 7}` 区分 load/store access fault、靠 `mtval` 得到具体 bad pointer；
  - ROM 写（0x0000_0000 段的写事务）目前仍是 silent OK（`axil_slave_wrapper` 直接返回 OKAY），后续若要把 ROM 写也报 SLVERR，只需在 ROM 从口前后加一层过滤器重写 `bresp`，与本机制天然兼容。
- **后续可选（Tier A #1 / #2 / 诊断告警均已完成 ✅，见下方两个子节；剩余可选项）**：
  - 把 `axil_interconnect.v` 的 `wr_ro` 机制一般化成「按 slot 配置 `ROM=RO / RW`」，将来若 CLINT 某些字段、PLIC threshold 等变只读，直接在表里打标；
  - 把 `d_bus_misalign` 与 `d_bus_err` 合并为 2-bit 故障码（`00=OK / 01=misalign / 10=access / 11=reserved`），可以少走一根独立线；
  - 接上 `Zicsr` 下发的 `mtval` 宽度扩展（在 Sv32 / 64 位地址空间中该字段不止 32 bit）。

#### Tier A #1 · ROM 写 SLVERR + Tier A #2 · Misaligned Load/Store Trap (mcause=4/6)

- **位置**：`rtl/bus/axil_master_bridge.v`（新增 `d_bus_misalign` 输出 + S_IDLE 未对齐检测 short-circuit + `WSTRB=0` 仿真诊断）、`rtl/bus/axil_interconnect.v`（`wr_ro` + `err_bresp_slv` 合成 SLVERR）、`rtl/core/cpu_jh.v`（新增 `d_bus_misalign` 端口、`r3_load_misalign` / `r3_store_misalign` 组合信号、load rd/wb_en 屏蔽扩展到 misalign 路径）、`rtl/core/pipeline_regs.v`（`reg_4` 增加 `load_misalign` / `store_misalign` 字段）、`rtl/core/csr_reg.v`（新增 `trap_take_load/storemisalign`，在 illegal 之下 / access fault 之上排优先级，mcause=4/6 + mtval=fault_addr）、`rtl/soc/cpu_soc.v`（走线）、`sim/tests/mi_smoke.S`（新增 Test 14/15/16 + 三个对应 handler）。

- **动机**：Tier 4.1/4.2/Tier A #3 落定后，剩下两类软件可观察的"静默吃掉"行为：
  - ROM 写：`axil_slave_wrapper` + `rodata.v` 组合会接受 AW/W、回 OKAY，然后丢弃数据。对 BSP 来说，「写了然后读不回来」是极难调试的 heisenbug。
  - Misaligned load/store：master bridge 此前把 AR/AW 的低 2 bit 直接与 0 `concat`，slave 看到的是对齐事务；软件层面观察到的是「错地址访问 + 成功读到隔壁数据」，比 silent 更糟。

- **处理（Tier A #1 · ROM SLVERR）**：
  - `axil_interconnect.v` 写通道把 ROM slot（`wr_sel_raw[0]`）从 `wr_sel` 里强行 mask 掉（`wr_sel = {wr_sel_raw[6:1], 1'b0}`），ROM 的 `awvalid / wvalid / bready` 因此永远为 0，真实 ROM slave 看不见写事务；
  - 合成错误 slave 的状态寄存器由 `err_bvalid` 扩成 `{err_bvalid, err_bresp_slv}`：`wr_ro` 触发时锁 `err_bresp_slv=1`，下一拍 `m_bresp=SLVERR`（2'b10）；`wr_none` 触发时锁 0，保持 DECERR（2'b11）。`m_awready / m_wready` 的 combinational 1 条件从 `wr_none` 推广成 `wr_none | wr_ro`；
  - CPU 侧零修改：master bridge 既有的 `d_bus_err = m_bresp[1]` 对 SLVERR / DECERR 同样命中，Tier A #3 的 `load_fault / store_fault` 路径直接继承。写 ROM 在 CPU 眼里就变成一次 mcause=7（Store Access Fault），mtval 是被写的 ROM 偏移。
  - ROM 读不受影响：`rd_sel` 不做 mask，ROM `arvalid` 继续正常发起。

- **处理（Tier A #2 · Misalign Trap）**：
  - `axil_master_bridge.v` 在 S_IDLE 组合算 `misaligned_req(op, d_addr[1:0])`：byte 永远对齐；half-word 要求 `addr[0]=0`；word 要求 `addr[1:0]=0`。检测到未对齐时直接 `state <= S_DONE`，不置 `m_awvalid / m_arvalid`，只把 `addr_latch <= d_addr`（保留原始未对齐地址供 mtval 使用）并在同一拍脉冲 `d_bus_ready_r=1, d_bus_misalign_r=1, d_bus_err_r=0`；AXI 总线上永远看不到未对齐事务，所以不会污染 slave；
  - `cpu_jh.v` 用与 Tier A #3 完全对称的语义把 misalign 传到 WB：`r3_load_misalign = d_bus_ready & d_bus_misalign & reg_3_load`，`r3_store_misalign` 同理；load rd/wb_en 屏蔽合并为 `r3_any_load_squash = r3_load_fault | r3_load_misalign`，确保 Test 15 里 `a3` 的 sentinel 不会被 stale `rdata_latch` 覆盖；
  - `csr_reg.v` 在 `trap_take_illegal` 与 `trap_take_storefault / trap_take_loadfault` 之间插入 `trap_take_storemisalign / trap_take_loadmisalign`，严格按 RISC-V Priv 3.7 的同步异常优先级（illegal > misalign > access-fault > ecall）。trap entry 分支写 `mcause=6 / 4 + mtval=fault_addr + mepc=pc_addr`，`set_pc_en` / `data_c` 与其他同步异常共用同一组合路径；`retired`（minstret 门控）也把 misalign 排除。
  - **行为契约**（给软件）：
    - `LH / LHU / SH` 在 `addr[0]=1` → mcause=4/6, mtval=原地址；
    - `LW / SW` 在 `addr[1:0]≠0` → mcause=4/6；
    - `LB / LBU / SB` 永远对齐，无论地址如何。

- **处理（`WSTRB=0` 诊断告警）**：`axil_master_bridge.v` 加 `ifndef SYNTHESIS` 包裹的 `always @(posedge aclk)`，在 W 握手成功且 `wstrb==0` 时 `$display` 一条 WARN。iverilog / Verilator 都会输出；综合被 `SYNTHESIS` 屏蔽，Vivado 不受影响。当前 `mem_ctrl.v` 不会生成 `wstrb=0` 的写，这是纯防御性断言，用于未来若引入 `sc.w` / AMO 或直接 AXI master 时定位控制信号 bug。

- **Smoke 测试**（`sim/tests/mi_smoke.S`）：
  - **Test 14 · Store misalign**：`sh t2, 0(0x2000_0001)` → 期望 `mcause=6 / mepc=&store_misalign_site / mtval=0x2000_0001`；handler 写 `x28=0x6006`。RAM 该地址永远不应被污染（没有 AXI 事务发出）。
  - **Test 15 · Load misalign**：`lw a3, 0(0x2000_0001)` 预埋 `a3=0xbad15` sentinel → 期望 `mcause=4 / mepc=&load_misalign_site / mtval=0x2000_0001 / a3 仍为 0xbad15`（说明 rd 写回被正确屏蔽）；handler 写 `x28=0x4004`。
  - **Test 16 · ROM write SLVERR**：`sw t2, 0(0x0000_0010)` → 期望 `mcause=7 / mepc=&rom_write_site / mtval=0x0000_0010`（handler 复用 `handle_store_fault` 并按 mepc 分支到 `handle_store_fault_rom`，写 `x28=0xc0de`）。
  - `handle_store_fault` 重构：`store_fault_site`（Test 10，mtval=0x5000_0004，DECERR）与 `rom_write_site`（Test 16，mtval=0x0000_0010，SLVERR）按 mepc 分派到 `handle_store_fault_unmapped` / `handle_store_fault_rom`，CSR 层面区分不了 SLVERR / DECERR，故只能靠 mepc。

- **回归**（三条 fetch 路径并跑 + 全脚本）：
  - 默认 I-Cache：`sim/run_isa.sh` 46/46 PASS（1 SKIP `fence_i`）、`sim/smoke_mi.sh` 全绿（Test 1–16 含新加 14/15/16）、`sim/smoke.sh` PASS、`sim/bpu_bench.sh` 20010 / 25019 / 30010 cyc PASS、`sim/bus_bench.sh` RAM 6.00 / ROM 8.00 cyc/iter PASS、`sim/run_os_demo.sh` PASS、`scripts/lint.sh` 全绿；
  - `-DTCM_IFETCH` 路径：`run_isa.sh` 46/46 PASS、`smoke_mi.sh` 全绿；
  - `-DICACHE_DISABLE` 路径：`run_isa.sh` 46/46 PASS、`smoke_mi.sh` 全绿。

- **面积 / 时序**：`axil_master_bridge.v` 新增一个 `req_misaligned` 3→1 组合分支 + `d_bus_misalign_r` 单 FF；`axil_interconnect.v` 新增 `err_bresp_slv` 单 FF + 1 bit `wr_ro`；CPU 侧 `reg_4` 新增 2 bit FF。整体 <10 个 FF + 一打 LUT，对 Artix-7 100T 可忽略。关键路径未改变——misalign 检测与 `wstrb_shift` 组合同级，不延长 AW/W 到 slave 的路径。

- **后续可选**：
  - 让 PMP / `mtvec` 打印 / backtrace 工具链消费 mcause=4/6/7 的 mtval，形成完整的「坏指针定位」闭环；
  - 将来若要「写到 CLINT reserved offset」「写到 PLIC pending」也报 SLVERR，只需在对应从口前加类似 `wr_ro` 过滤器；
  - 与 Tier 3 的 A（原子）扩展联动：`LR/SC` 对 misaligned 要求额外的「Atomic access misaligned（mcause=6 或自定义）」，到时在 master bridge 的 misalign 检测里增加 op=atomic 分支即可。

### 2.5 取指走 AXI4-Lite（无 I-Cache 版）✅

- **位置**：`rtl/bus/axil_ifetch_bridge.v`（新增）、`rtl/soc/cpu_soc.v`（新增 ifetch 主口 + `axil_slave_wrapper` 包 i_rom port B，加 `-DTCM_IFETCH` 回退）、`rtl/core/cpu_jh.v`（替换 `stop_cache` 的同拍语义 + 新增 `wb_fresh / mem_fresh` retire-pulse）、`rtl/core/csr_reg.v`（新增 `retire_pulse` 端口，仅门控 `mstatus_mret` 非幂等分支；`minstret` / `wfi_active` 同步收口一拍）、`sim/run_isa.sh`（新增 `ISA_IVERILOG_DEFS`）、6 份脚本 `rtl_files` 同步。
- **动机**：Tier 4 第 3–6 项（DDR、MIG、AXI 外设）都要求 ifetch 走标准 AXI。先把取指从「BRAM 同拍直连」改成「只读 AXI4-Lite master」，既验证整条 AXI ifetch 路径，又为下一步把 I-Cache 挂到同一 master 口留好接入点。目标 FPGA 为 Artix-7 100T（xc7a100t），AXI 频率与现有数据侧一致。
- **处理**：
  - **`axil_ifetch_bridge.v`**：只读 2 态 FSM（`S_IDLE → S_R`），`m_arvalid` 在 `IDLE` 由 `i_bus_en` 拉起、`m_araddr={pc_addr[31:2],2'b00}` 强制对齐、`m_rready=(state==S_R)`；`i_bus_ready = fetch_done = (state==S_R) & m_rvalid & m_rready`；`i_bus_err = fetch_done & m_rresp[1]`（DECERR / SLVERR，后续挂 Access Fault 再消费）。与 `axil_master_bridge` 分开例化，避免取指 / 数据共用 outstanding slot。
  - **`cpu_soc.v` 接线**：新增第 7 条从口 bundle `ROM_IFETCH`（复用 i_rom port B 的 14-bit 字地址 + 2-cycle `rvalid`），经 `axil_slave_wrapper` 翻成 AXI4-Lite 从口；取指 master 直接点对点连到这个从口（不进 `axil_interconnect`，省一层 mux 组合路径）。`TCM_IFETCH` 编译开关打开时 `i_bus_ready=1'b1`、`i_data=i_rom_dout_b`，走与 Tier 4.1 之前完全相同的直连 BRAM 路径，用于 FPGA 资源紧张 / 快速调试回退。
  - **同拍语义保持**：原 `stop_cache.v` 设计前提是「每拍都能拿到新指令」，直接放在 AXI ifetch 之后会把 `i_wait` 期间 master bridge 驱动的 R-channel 残留数据当成 NOP 塞进 reg_1，导致 PC=0 附近爆 illegal。`cpu_jh.v` 用一个 valid-gated 锁存器 `last_inst_r`（仅 `i_bus_ready` 为 1 时捕获 `i_data_in`）替换 `stop_cache` 的原始输出，`stop_cache_reg1 = i_bus_ready ? i_data_in : last_inst_r`；在 TCM 路径下 `i_bus_ready≡1`，退化成纯组合直通，与老行为按位一致。
  - **Retire-pulse 修 `mret` 非幂等**：AXI 取指每条指令在 WB 多停留 ≥1 拍（`i_wait` 握住 `reg_4`），暴露出 `mstatus_mret`（`MIE<=MPIE, MPIE<=1`）在第二次触发时会把已清掉的 MIE 重新打开，导致 `sim/tests/mi_smoke.S` Test 6（异步中断 round-trip）在 mret 后立刻 re-trap 成死循环。`cpu_jh.v` 用 `reg4_en_d1 / reg3_en_d1` 产生 `wb_fresh / mem_fresh`，只在「reg_4 刚换新指令」的那一拍拉高；`regfile` 的 WB / MEM 两个写端口都门控在 fresh 脉冲上，`otof1` 的 WB forwarding 使能也一并门控，避免被握住的 `reg_4` 反复 retire。`csr_reg.v` 加 `retire_pulse` 输入，**只**把 `is_mret` 的 `mstatus` 更新门控起来（以及 `minstret` / WFI 锁存的一次性脉冲化）；其他分支（`is_csr_rw`、trap 入口、同步异常）在 hold 模式下是幂等的（`csrrs/csrrc` 在第二次会收敛到同一值，`mstatus_trap_entry` 会把 `MPIE<=MIE` 再写一次等），因此不需要多余的 gate。`set_pc_en / set_pc_addr` 依旧组合输出，保证 trap 重定向在当拍生效，而不会因为 `retire_pulse` 延迟到下一拍出现「PC 已跳，`mstatus` 未改，下一拍立即 re-trap」的陷阱。
  - **`regfile` 写侧一次性化**：WB 的 `write_ce` = `reg_4_wb_en & wb_fresh`，EX 快写端 `w_en_2` = `reg_3_wq & reg_3_wb_en_in & mem_fresh`。这样 load-use / i_wait 等把 reg_3 / reg_4 握住的场景下，同一条指令不会被多次写入 regfile；结合 `otof1.wb_en_wb = reg_4_wb_en & wb_fresh`，WB forwarding 的消费者在 stale WB slot 时会回落到 regfile，避免把 `csr_data_out` 已经换值的 CSR 结果当成旧值转发。
  - **`stop_cache.v` 暂时保留**：目前还在 `sim/run_isa.sh` / `sim/smoke*.sh` / `scripts/lint.sh` 的 rtl_files 里编译，但 `cpu_jh.v` 不再例化它；下一轮接 I-Cache 时再决定是彻底删掉还是改造成 line-fill buffer。
- **AXI 延迟构成**：每条指令取指 = AR (1 拍) + R (1 拍) = **2 拍 throughput**（对比 TCM 1 拍）。在不加 I-Cache 的前提下 ISA 回归 wall-time 从 ~50s 上升到 ~50s（`rv32ui-p-sw` 一条单测从 1s → 9s 最显著，符合 2x 理论值）。`sim/bus_bench.sh` 的 RAM / ROM 数字不变，因为 bus_bench 本身跑在数据侧。
- **回归**（两路径并跑）：
  - AXI 路径：`sim/run_isa.sh` 46/46 PASS（1 SKIP `fence_i`），`sim/smoke.sh` / `sim/smoke_mi.sh`（含 Test 6 异步中断 + Test 9/10 access fault）全绿，`sim/bpu_bench.sh` / `sim/bus_bench.sh` 全绿。
  - TCM 路径（`MI_IVERILOG_DEFS=-DTCM_IFETCH` / `SMOKE_IVERILOG_DEFS=-DTCM_IFETCH` / `ISA_IVERILOG_DEFS=-DTCM_IFETCH`）：同 4 条回归 + lint 全绿，确保回退路径可用。
- **Artix-7 100T 资源余量**：`axil_ifetch_bridge` 仅 1 个 FSM 位 + 几个 mux，`axil_slave_wrapper` 复用既有 shim，无新 BRAM。I-Cache（下一步 2–4 KB、16/32B line）在 100T 上是宽裕的。
- **下一步（Tier 4.2.1 I-Cache）**：在 `axil_ifetch_bridge` 与 CPU 之间插一个 direct-mapped / 2-way set-associative I-Cache；line fill 用 AXI4-Lite burst 长度不够的话，先做逐字 AR；配合 `fence.i` 无效化整张 cache（简单粗暴，后续再做 per-line 的 CBO.INVAL）。I-Cache 命中后 `i_bus_ready` 可组合回到同拍，`stop_cache.v` 真正可以退休。

### 2.6 取指 I-Cache + 流水线 drain + pending-redirect ✅

- **位置**：`rtl/bus/icache.v`（新增）、`rtl/bus/axil_ifetch_bridge.v`（新增 `inflight_word` 门控）、`rtl/soc/cpu_soc.v`（在 `axil_ifetch_bridge` 与 i_rom AXI 从口之间插 I-Cache；新增 `-DICACHE_DISABLE` 让 CPU 直接打到 bridge）、`rtl/core/cpu_jh.v`（`flush_icache` pulse 驱动、stop_cache 输入换成 valid-gated IFETCH_BUBBLE_NOP 注入、新增 `pending_redirect_r` 单 slot 捕获器）、`rtl/core/hazard_ctrl.v`（drain policy：`i_wait` 只冻结 `pc_en` / `reg1_en`，`reg_2..reg_4` 保持推进）、`rtl/core/flush_ctrl.v`（`pending_redirect_apply` 新 squash 源，只 flush `reg_1`）、`sim/tb/cpu_test.v`（`x26==1` 后 drain 窗口 `#100 → #500`）、`sim/smoke_mi.sh`（默认 timeout `10s → 30s`）、6 份脚本 + lint 的 `rtl_files` 加 `icache.v`。

- **设计**：
  - **I-Cache 拓扑**：2 KB direct-mapped、16-byte line（4 × 32 bit word），128 line、`index=addr[10:4]`、`tag=addr[31:11]`、`word_off=addr[3:2]`。Line 数据 SRAM (`lines[index][word_off]`) 与 tag/valid SRAM 分两路，lookup 完全组合回 `i_bus_ready`（命中下 CPU 侧 0 拍等待，复刻 TCM 行为）。
  - **Miss FSM**：2 状态 `S_IDLE → S_FILL`。进 `S_FILL` 时锁 `fill_addr_r={miss_tag, miss_index, 4'b0000}`，按 `word_off=0..3` 串行发 4 次对齐 AR；每收到一个 R beat 就把数据写进 `lines[fill_index][beat_cnt]`；beat_cnt=3 收到后同拍拉 `valid_r[fill_index]=1` 并给 CPU `i_bus_ready=1`。**升级为 critical-word-first（Tier 9.x）**：`fill_cnt` 起始改成 `up_wsel`，第一拍 beat 即组合返回 `i_bus_ready=1` + 关键字数据，剩下 3 拍后台 wrap 填线，命中拍延迟从「填完 4 拍才 ack」缩到「关键字拍即 ack」。
  - **Stale-fill 防护**：CPU 在 miss fill 过程中如果因为 trap / pending redirect / mispredict 改了 `up_addr`，填完的数据与当前 `up_addr` 不一定匹配。`icache.v` 加 `fill_addr_match = ({up_addr[31:4]} == fill_addr_r[31:4])` 门控 `i_bus_ready` 与数据 mux；不匹配时 CPU 视为继续 miss，等待下一次 lookup（此时下一次可能 hit，因为 valid_r 已经写入了对应 line）。
  - **`fence.i`**：`id.v` 已有 `is_fence_i` 解码；`cpu_jh.v` 在 fence.i 即将进入 `reg_1` 的同拍（`reg1_en & incoming_is_fence_i`）一次性脉冲 `flush_icache`，`icache.v` 把 `valid_r` 整张清零。选择同拍而非下一拍，是因为下一拍 lookup 的组合路径已经在采 valid 位——晚一拍会漏掉「fence.i 的后继 PC 命中旧 line」的窗口。
- **处理**：
  - **`axil_ifetch_bridge.v` 加 `inflight_word`**：bridge 发 AR 后 PC 可能会在 trap / pending redirect 下被改写，R beat 回来时对应的是旧 PC。改成 `S_IDLE` 锁 `inflight_word = pc_addr`，`i_bus_ready = fetch_done & (pc_addr == inflight_word)`；不匹配时直接在 master 端吞掉这笔 R 事务，避免把 stale 指令推给 CPU / I-Cache。`-DICACHE_DISABLE` 路径下也走这条防护（Tier 2.5 里遗留的 bug）。
  - **Drain policy（`hazard_ctrl.v`）**：原语义下 `i_wait` 冻结全流水，cache miss 期间 `reg_2..reg_4` 无法 retire；改成 `i_wait` 只冻结 `pc_en / reg1_en`，`reg2_en..reg4_en` 保持高位。`cpu_jh.v` 把 `stop_cache_reg1 = i_bus_ready ? i_data_in : IFETCH_BUBBLE_NOP`，miss 期间给 `reg_1` 注 `addi x0,x0,0`（寄存器无副作用的 bubble），`reg_2..reg_4` 持续排空在途事务。`d_wait / local_stop / div_wait` 仍然冻结全流水（操作数可能来自被停住的下游）。
  - **Pending redirect**：Drain 打开后新问题是——miss 窗口里一条分支走到 ID 解析出 `id_mispred_en_raw=1` 时，`pc_en=0` 导致 `pc.v` 接不到这次 redirect，miss 解除后 PC 顺序推进到错路径。`cpu_jh.v` 新加单 slot `pending_redirect_r`，`pending_trigger = id_mispred_en_raw & reg_1_is_ctrl & i_wait & ~d_wait & ~local_stop & ~div_wait & ~pending_redirect_r` 在 miss 窗口里捕获 misprediction target；`pc_en` 第一次拉高的那拍，`pending_redirect_apply = pending_redirect_r & pc_en` 送进 `pc.v` 实现 redirect。同拍 `flush_ctrl` 的 `rst[0]` 把 `reg_1` 也 squash（此时 `reg_1` 刚采到 miss 最后一 beat 的 fall-through PC 指令，属于 wrong path）；`reg_2..reg_4` 不动（它们是 drain 中排空的合法在途事务）。Trap `pc_set_en_pc` 永远优先于 pending redirect（MEPC/MCAUSE 以 CSR 实际跳转的指令为准）。
  - **Retire-pulse 与 drain 的交互**：Tier 2.5 引入的 `wb_fresh / mem_fresh`（`reg*_en` 的上升沿）在 drain 下天然对——`reg_3 / reg_4` 持续被 enable，每拍都是 fresh，所以 `mstatus_mret / minstret / csrrs` 等非幂等侧效继续受 retire-pulse 门控一次性起效，与 Tier 2.5 行为一致；NOP bubble（`wb_en=0`）本身不会污染 regfile，也不会写 CSR。
  - **Testbench drain 窗口 `#100 → #500`**：riscv-tests 以 `li s10,1; li s11,1; loop` 结尾。Testbench `wait(x26==1)` 即 `li s10,1` retire 后等 `#N` 再采 `x27`。TCM 路径下 `s10 / s11` 连发两拍，`#100`（5 周期）足够；I-Cache 路径下如果 `s10`（PC=0x29c）与 `s11`（PC=0x2a0）跨 cache line，`li s11,1` 要等一次 4-beat line fill 才能 retire，`#100` 来不及。把等待放到 `#500`（25 周期）是保守的最大 miss penalty + 流水线深度，仍远小于真正 hang 情况下的 per-test timeout，不会掩盖失败。
  - **`smoke_mi.sh` timeout `10s → 30s`**：I-Cache 版 `sim/tests/mi_smoke.S` 单跑 wall-time 涨到 ~12s（iverilog 解释执行 + AXI 事务增多 + drain 窗口扩大），默认 10s 会超时误报失败。放到 30s，真正 hang（如未来加的 PLIC / Debug 把 interrupt 卡死）仍能观察到。
- **路径构成（三条 fetch 路径都保留，编译开关选择）**：
  - 默认：CPU → `axil_ifetch_bridge` → `icache.v` → i_rom AXI slave；命中 0 拍、miss 一次 4-beat line fill（~8 拍），命中率高时 wall-time 接近 TCM；
  - `-DICACHE_DISABLE`：CPU → `axil_ifetch_bridge` → i_rom AXI slave；每拍一条 AXI 读，2 拍 throughput 上限，fetch 永远不 cache，作为 A/B 基线；
  - `-DTCM_IFETCH`：CPU → i_rom port B 直连，0 拍 throughput（Tier 2.5 之前的旧行为），用于 FPGA 资源紧张或快速调试。
- **回归**（三条 fetch 路径均走一遍）：
  - 默认 I-Cache：`sim/run_isa.sh` 46/46 PASS（1 SKIP `fence_i`）、`sim/smoke_mi.sh` 全绿（含 Test 6/7/8/9/10）、`sim/smoke.sh` PASS、`sim/bpu_bench.sh` 20010 / 25019 / 30010 cyc PASS、`sim/bus_bench.sh` RAM 6.00 / ROM 8.00 cyc/iter PASS、`scripts/lint.sh` 全绿；
  - `-DICACHE_DISABLE`：`ISA_IVERILOG_DEFS=-DICACHE_DISABLE bash sim/run_isa.sh` 46/46 PASS、`MI_IVERILOG_DEFS=-DICACHE_DISABLE bash sim/smoke_mi.sh` 全绿；
  - `-DTCM_IFETCH`：`ISA_IVERILOG_DEFS=-DTCM_IFETCH bash sim/run_isa.sh` 46/46 PASS、`MI_IVERILOG_DEFS=-DTCM_IFETCH bash sim/smoke_mi.sh` 全绿。
- **资源估算（Artix-7 100T）**：数据 SRAM 128 × 128 bit = 16 Kbit = 2 个 18-Kbit BRAM；tag/valid SRAM 128 × (21+1) = ~2.7 Kbit（分布式 RAM 或 1 个 BRAM）；FSM + compare 约 80 FF + 100 LUT。整体资源占用可以忽略；line fill AR/R 复用既有 ifetch AXI master，不增加总线仲裁复杂度。
- **已知限制与后续**：
  - 4-beat line fill 串行发 AR（未用 AXI4 burst），纯 Lite 实现；如果后续上 AXI4 full 或 axi_bram 的 burst 端口，line fill 可缩到 1 个 AR + 4 拍 R，再省 3 拍 miss penalty；
  - Critical-word-first 目前退化成「填 word 0..3、最后一 beat 给 ready」，一个简单优化是在命中拍返回请求字、再后台填完剩下三字，能把 miss-to-use 再减 2–3 拍；
  - `fence.i` 粒度是「整张 invalidate」，后续 `Zicbom` / `Zicbop` 可以补 per-line `CBO.INVAL`；
  - D-Cache 还没做：后续 Tier 4.2.7 的方向是把数据侧也走 cache，那时候 retire-pulse + drain 的语义已经在 I-Cache 上验证过，可以复用。

### 3. CLINT + PLIC ✅

- **位置**：`rtl/peripherals/timer/clnt.v`（按 SiFive 偏移重写）、`rtl/peripherals/plic/plic.v`（新增）、`rtl/bus/axil_interconnect.v`（新增第 7 条 PLIC 从口窗口）、`rtl/soc/cpu_soc.v`（接线、e_inter→PLIC source 1、`meip`/`mtip`/`msip` 同步）、`rtl/core/csr_reg.v`（接入 `msip`、`mip.MSIP` 变成硬线、优先级排序同步）、`rtl/core/cpu_jh.v`（顶层端口透传 `msip`）、`sim/tests/mi_smoke.S`（`Test 11 = mtime sanity`、`Test 12 = MSIP round-trip`、`Test 13 = MTI round-trip`、`Test 6` 重写为 PLIC 编程后触发 MEIP）、6 份脚本 `rtl_files` 同步 `plic.v`。
- **动机**：Tier 4.1 把 CLINT 挂上 AXI4-Lite 时沿用了私有 word-index layout（`mtime/mtimecmp` 在 word index 0/2/1/3，还有非标 `clnt_flag`）。OpenSBI / Linux device tree 默认按 SiFive CLINT 偏移 (`msip@0x0000 / mtimecmp@0x4000 / mtime@0xBFF8`) 计算，需要一次 map 对齐；外部中断目前是把 `e_inter` 直接当 `mip.MEIP`，也缺一个标准 PLIC 做优先级 / claim / complete 仲裁，跑一条中断软件就拆一次 glue。这里把两者一次做完。
- **处理**：
  - **CLINT SiFive 对齐**：`clnt.v` 重写地址译码，`msip@0x0000`（只有 bit0 有效，其余 WIRI）、`mtimecmp@0x4000/0x4004`、`mtime@0xBFF8/0xBFFC`，`mtimecmp` reset 为 `64'hFFFF_FFFF_FFFF_FFFF`（SiFive 同款「默认不触发」），`time_e_inter = (mtime >= mtimecmp)` 电平式输出；`clnt_flag` 非标字段彻底移除（取消「软件没设置 enable 位就不触发」这种私有语义，改回 spec）。byte-strobe 走统一 `apply_wstrb`，未使用的偏移读 0 / 写忽略。软件层 `mtime_cmp` 写入等效 AXI4-Lite 32-bit aligned store，与 OpenSBI `sbi_timer_event_start` 发出的访问形状一致。
  - **PLIC SiFive 风格**：`rtl/peripherals/plic/plic.v` 新增 8 源 / 3-bit priority / 单 M-mode context 的极简 PLIC：
    - `0x0000_0004..0x0000_001C`：source 1..7 priority（source 0 reserved=0）。
    - `0x0000_1000`：pending bits[31:0]（只读镜像 `pending_r`，写忽略）。
    - `0x0000_2000`：context 0 enable bits[31:0]。
    - `0x0020_0000`：context 0 threshold。
    - `0x0020_0004`：context 0 claim/complete：读 = 当前仲裁赢家 id（清该源 pending）、写 = EOI（只要 id 在 1..7 就放行 gateway）。
    - 仲裁：`best_prio / best_id = max{prio[i] | pending_r[i] & enable_r[i]}`，同 prio 下低 id 优先；`meip = (best_prio > threshold)`，电平输出，和 SiFive 一致。
    - gateway：源到 `pending_r` 的写入是 edge-gated 的 `gateway_r[i]`；claim 时清 `gateway_r[i]`、complete 时释放 `gateway_r[i]`——即使源端电平仍 asserted，也必须先 complete 下一次才会重新 latch，避免 storm。linter 为了避让 iverilog 里「function 输出切片」的 syntax error，按 source 单独 `for` 展开 `wstrb` 合成。
  - **Interconnect 新从口**：`axil_interconnect.v` 加一条窗口 `0x4400_0000..0x44FF_FFFF` 指向 PLIC，其它 5 条窗口 (`ROM / RAM / LED / KEY / CLINT / UART`) 原样保留；未映射地址依旧走 DECERR 合成器（Tier A #3 的行为）。
  - **SoC 接线**：`cpu_soc.v` 把顶层 `e_inter`（低有效）两拍同步 + 取反后作为 PLIC source 1，不再直连 CSR；PLIC 输出 `meip`、CLINT 输出 `mtip` / `msip` 三根 interrupt pin 都经 2-FF sync 后喂给 `cpu_jh`；`TCM_IFETCH` / `ICACHE_DISABLE` / 默认 I-Cache 三条编译路径保持一致。
  - **CSR 改造**：`csr_reg.v` 新增 `msip_i` 输入（原来 `mip.MSIP` 是软件写的软位，现在改成硬线 + 电平）；`mip_eff = {meip_i, /*unused*/, mtip_i, /*unused*/, msip_i, ...} | mip_soft`；`int_cause` 的优先级继续按 spec 是 `MEI (0x8000_000B) > MSI (0x8000_0003) > MTI (0x8000_0007)`。mret / trap entry 走已有的 `mstatus_trap_entry / mstatus_mret` helper，没有新加 CSR 行为。
  - **Smoke 测试更新**：`sim/tests/mi_smoke.S`:
    - **Test 11**：两次 `lw` 读 `mtime_lo` 验证自增，做 SiFive 地址存在性的最低 sanity。
    - **Test 12**：写 `CLINT.msip[0]=1`、先 mask `mie.MEIE`（避开 e_inter 仍 asserted 的 MEIP 抢占）、再开 `mstatus.MIE`；期望 `mcause=0x8000_0003`（MSI）；handler 清 `msip`、永久 mask `mstatus.MIE+MPIE`、写 `x28=0xb00b`。
    - **Test 13**：mask `mie.MSIE`、写 `mtimecmp = mtime_lo + 1`（`mtime` 在 RMW 过程中已自增，retire 完 `sw` 时 MTIP 立刻拉起）、开 `mstatus.MIE`；期望 `mcause=0x8000_0007`（MTI）；handler 先写 `mtimecmp_hi=-1` 再写 `mtimecmp_lo=-1`（原子上抬 comparator 到「永不触发」）、永久 mask MIE+MPIE、写 `x28=0xd07`。
    - **Test 6**（重写）：先按 spec 编程 PLIC —— `priority[1]=1`、`enable[1]=1`、`threshold=0`，再恢复 `mie.MEIE+MSIE`、开 `mstatus.MIE`。`int_loop` 里自旋等中断；期望 `mcause=0x8000_000B` 且 `mepc ∈ [int_loop, int_loop_end)`；handler 做 PLIC claim（校验返回 id=1）、write-back complete、永久 mask MIE+MPIE、把 `mepc` 改写到 `int_loop_end`、写 `x28=0xabcd`、mret。
  - **脚本同步**：`sim/run_isa.sh` / `sim/smoke.sh` / `sim/smoke_mi.sh` / `sim/bpu_bench.sh` / `sim/bus_bench.sh` / `scripts/lint.sh` 的 `rtl_files` 全部加入 `rtl/peripherals/plic/plic.v`，否则 PLIC 在除 smoke_mi 之外的任何入口都会 elaborate 失败。
- **回归**（三条 fetch 路径并跑 + 全套脚本）：
  - 默认 I-Cache：`sim/run_isa.sh` 46/46 PASS（1 SKIP `fence_i`），`sim/smoke_mi.sh` 全绿（Test 1–13 含新加的 11/12/13），`sim/smoke.sh` PASS，`scripts/lint.sh` 全绿；
  - `-DICACHE_DISABLE`：`MI_IVERILOG_DEFS=-DICACHE_DISABLE bash sim/smoke_mi.sh` 全绿；
  - `-DTCM_IFETCH`：`MI_IVERILOG_DEFS=-DTCM_IFETCH bash sim/smoke_mi.sh` 全绿（Test 13 最后用「mtimecmp = mtime+1」+ handler 原子 `-1 → hi/lo` 的写法才能稳定触发，偏移 32 下 TCM 0 拍取指路径会在 nop 窗口内 bne 过早 fail）。
- **行为契约**（给软件 / DT binding）：
  - `reg CLINT_base = 0x4200_0000; size = 0x0001_0000`；`timebase-frequency` 与 cpu_clk 相等；软件通过「先 `mtimecmp_hi=0xFFFF_FFFF`、再写 `mtimecmp_lo=new_lo`、再写 `mtimecmp_hi=new_hi`」的 SiFive 建议序列即可避免在 64-bit 跨字写时产生虚假的 MTIP 毛刺。
  - `reg PLIC_base = 0x4400_0000; size = 0x0100_0000`；`#interrupt-cells = 1`；source 0 reserved；source 1 = 外部 `e_inter`；context 0 = hart 0 M-mode；priority 域宽 3 bit (`0..7`)；threshold/claim/complete 按 SiFive layout。OpenSBI `platform_interrupt_init` 的默认值（priority=1 / threshold=0 / enable 某源）开箱即工作。
  - `mip.MSIP` 现在只读（硬线到 CLINT），CSR 写忽略。写软中断要走 MMIO `CLINT.msip[0]`。`mip.MEIP` 由 PLIC 电平输出决定；`mip.MTIP` 由 CLINT `(mtime >= mtimecmp)` 决定；三者都是 level-sensitive，软件可以随时 `csrr mip` 读当前瞬时状态。
- **Artix-7 100T 资源估算**：PLIC 总共 8 源 × 3 bit priority + 8 bit enable + 8 bit pending + 8 bit gateway + 3 bit threshold + 3 bit best_prio + 4 bit best_id ≈ 70 FF + 一个 8-wide max-priority 组合比较器（7 个 3-bit compare + 2 级优先 mux），几十个 LUT。CLINT 改动只是把寄存器偏移换位，资源不变（64 bit mtime + 64 bit mtimecmp + 1 bit msip + 译码组合）。增量可以忽略。
- **后续可选**：
  - 扩展到 31 源（SiFive 默认 31 源单 word）或 1023 源（完整 PLIC 多 word pending/enable）；
  - 多 hart：按 SiFive 把 `msip[1..N]` 放在 `0x0004 * hart_id`、每 hart 一个 CLINT context；PLIC 增加 context 1..N（S-mode、hart N 的 M/S）；
  - `mtime` / `mtimecmp` 外挂到独立 timer clock（当前直接用 cpu_clk，OK 但限制了低功耗 gating）；
  - 补一个「sstc」或 S-mode 版 CLINT/PLIC 以配合 Tier 3 的 S-mode + Sv32。

### 4. RISC-V Debug Module（JTAG）

- 对接 openocd/gdb。

### 5. 启动链

- BootROM + 可选从 Flash/SD 装载；UART 下载路径可逐步外置化。

### 6. 外设规范化

- UART 兼容 16550（可直接换 Xilinx `axi_uart16550`）；GPIO 进一步独立到专用 AXI-Lite IP。

### 7. 容量

- 当前数据 RAM 约 128 KB 级；接 DDR 后地址空间与控制器需一并规划。Tier 4.1 已把 CPU 侧对 AXI4-Lite 的依赖固化，因此换成 MIG 的 AXI4-Lite facade 时只需在 `axil_interconnect.v` 添加一条从口 bundle 即可。

### 8. Artix-7 200T 资源放大配置 ✅

- **位置**：`rtl/common/primitives/ram.v`（每 byte-bank 32 KiB → 64 KiB，共 256 KB RAM）、`rtl/memory/ram_c.v`（bank 地址扩位）、`rtl/bus/icache.v`（128 line → 512 line，2 KB → **8 KB** I-Cache，`IDX_W` 改成由 `NUM_LINES` 计算）、`rtl/core/branch_pred.v`（BTB 32 → **128**、RAS 4 → **16**）、`sw/bsp/ld/default.lds`（RAM 区改 256 KB、栈尺寸放大）、`sim/tb/cpu_test.v`（`+DRAM` 预加载先把 4 个 64 KiB bank 全部清零再覆盖 `.data` 镜像，否则 X 会扩散到 `sb / sh / sw` ISA 测试）。
- **动机**：Tier A 引入 D-Cache 后，整体核已逼近"较大规模 MCU"形态，Artix-7 200T 留出的 BRAM/DSP/LUT 余量足以再拉一档容量与性能。先把 RAM 与 BPU/I-Cache 一起放大，给后续 MIG / DDR / 复杂 BSP 留一致 footprint。ROM 暂未扩，主要是 i_rom 仿真桩与 Vivado BRAM Generator 配置耦合，避免一次改动跨 RTL/仿真/上板三处。
- **处理要点**：
  - **RAM 64 KiB / bank**：`MemNum=65536`、`MemAddrBus=16`；为 iverilog 解释执行做一次小优化，把 `always @(*)` 改成 `always @(addr_o or re_i or rst)` 显式列出敏感量，否则 64 KiB 数组 + 通配敏感会让仿真 startup 阶段非常慢。
  - **I-Cache 8 KB / 512 line**：`NUM_LINES` 参数化；`IDX_W` 由 `NUM_LINES` 计算（5..11 bit），后续可以一改参数把容量挤到 16 KB。
  - **BPU 放大**：BTB 128 entry（按 `pc[8:2]` 索引）+ RAS 16 entry，配合 dhrystone 这种深递归调用栈，retire-pulse 与 misprediction 路径不变。
  - **链接脚本**：RAM region 改成 `0x2000_0000..0x2003_FFFF`（256 KB），栈底自动随 region 顶部上移；ROM region 0x0xxx 不动。Dhrystone 与 `run_os_demo` 都依赖更大的栈，原 8 KB 栈在 `Dhrystone_Number_Of_Runs >= 5` 时已经会撞到 `.bss`。
- **回归**（三条 fetch 路径 × DCACHE 开关 × benchmark）：
  - 默认 I-Cache + D-Cache：`sim/run_isa.sh` 46/46 PASS（1 SKIP）、`sim/smoke.sh` PASS、`sim/run_dhrystone.sh` PASS；
  - `-DTCM_IFETCH`：`sim/run_isa.sh` 46/46 PASS；
  - `-DICACHE_DISABLE`：`sim/run_isa.sh` 46/46 PASS；
  - `-DDCACHE_DISABLE`：`sim/run_isa.sh` 46/46 PASS；
  - `scripts/lint.sh` 全绿。
- **后续可选**：
  - ROM 同步扩到 ≥128 KB（需要 i_rom 仿真桩与 Vivado BRAM Generator port A 字宽 / 地址位一起改）；
  - 把 BHT 也从 32 entry 扩到 128 entry / gshare；
  - 把 RAM 换成 MIG 的 AXI4-Lite facade（保留当前 256 KB BRAM 作 TCM，DDR 走另一条 cacheable 区段）。

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
