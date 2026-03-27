# 软件侧保留目录

`sw/tinyriscv` 现在只保留本处理器的软件相关内容，原上游工程中与当前仓库无关的 `rtl`、`sim`、`tb`、`fpga`、`pic`、`save`、`tinysim` 等目录已经移除。

当前目录结构如下：

- `tests/example`：C 语言示例程序与公共启动代码。
- `tests/isa`：旧版 RV32 ISA 指令测试。
- `tests/riscv-compliance`：新版 RISC-V compliance 测试。
- `tests/toolchain`：随仓库保留的 RISC-V GNU 工具链及相关脚本。

## 工具链

默认工具链路径为：

`tests/toolchain/riscv64-unknown-elf-gcc-8.3.0-2020.04.0-x86_64-linux-ubuntu14`

`tests/example/common.mk`、`tests/isa/Makefile`、`tests/riscv-compliance/Makefile` 都已经改为默认指向这里，并允许通过变量覆盖。

## 使用说明

- 构建示例程序：进入 `tests/example/<name>` 后执行 `make`。
- 构建旧版 ISA 测试：进入 `tests/isa` 后执行 `make`。
- 运行 compliance 构建：进入 `tests/riscv-compliance` 后执行 `make`。

这些目录下的 `.dump`、`.coe`、`.verilog`、`build_generated`、`generated` 等均视为生成物，不再保留在仓库里。
