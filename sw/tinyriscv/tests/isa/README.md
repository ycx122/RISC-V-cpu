RV32I instruction source code which copy from riscv(github).
I have modified it so can run on tinyriscv.
compile: type make under the cmd windows
recompile: type make after make clean under the cmd windows

Notes for this repository:
- These tests are used as functional regression tests for the current core, not as a complete compliance verdict by themselves.
- `fence_i` is not supported by this processor. The core does not implement the `Zifencei` extension, so the related test should be treated as not applicable.
- The current simulation flow can initialize `i_rom`, but does not yet provide a general RAM pre-initialization mechanism.
- Because of that limitation, some `load` tests may fail if they depend on specific data RAM contents prepared before execution. Such failures should be reviewed together with the memory initialization model before concluding that the load pipeline is incorrect.
