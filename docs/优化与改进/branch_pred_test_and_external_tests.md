# `branch_pred_test.s` 测试链路与外部测试集接入记录

本文回答两个问题：

1. `./obj_dir/VTop --perfc test_programs/branch_pred_test.s` 这种测试方式如何实现。
2. 是否可以引入常用外部测试集（GitHub 可下载）来测试本项目，以及当前接入情况。

---

## 1. `branch_pred_test.s` 这种测试方式是怎么实现的

### 1.1 命令行到参数

`--perfc` 在仿真入口 `ParseArgs()` 中被解析为 `args.logPerformance = 1`：

- `sim/Top_tb.cpp:488-513`

程序路径 `test_programs/branch_pred_test.s` 会被识别为汇编源文件（`.s/.S`）。

### 1.2 `.s` 文件如何被执行

当输入是 `.s` 时，`Initialize()` 会先做两步：

1. 调 `riscv32-unknown-elf-as` 把 `.s` 汇编成 `temp.o`
2. 调 `riscv32-unknown-elf-ld` 与 `test_programs/entry.o` 链接成 `a.out`

然后把 `args.progFile` 改为 `a.out`，后续按 ELF 流程加载：

- `sim/Top_tb.cpp:549-561`
- ELF 段加载逻辑：`sim/Top_tb.cpp:563-641`

### 1.3 `--perfc` 什么时候打印

运行循环中按 `minstret` 周期触发统计打印：

- 间隔：`8 * 1024 * 1024` 指令
- 条件：`wrap->csr->minstret >= nextMinstretPerf && args.logPerformance`
- 调用：`LogPerf(core)`

代码：

- `sim/Top_tb.cpp:767-811`

仿真退出后还会无条件再打印一次 `LogPerf(core)`，并打印 `main_time / 2`：

- `sim/Top_tb.cpp:820-827`

### 1.4 `branch_pred_test.s` 本身在测什么

`test_programs/branch_pred_test.s` 逻辑很小：循环 1000 次，包含两种分支模式：

- `beqz a1, .skip`：由计数器奇偶决定，近似 50/50 跳转
- `bnez a0, .loop`：循环回跳，绝大多数迭代为 taken，最后一次 not-taken

文件：

- `test_programs/branch_pred_test.s`

因此它可以快速观察：

- 分支预测命中/失配（`branch mispredicts`）
- 各类 flush cause 分布（`ORD/BTK/BNT/RET/IBR/MEM`）
- 前后端 stall 对比（`frontend/backend/store/load/ROB stalled`）

---

## 2. 外部常用测试集接入

本次已在顶层 `Makefile` 增加外部测试相关目标：

- `external-tests-fetch`：拉取 `riscv-tests`
- `external-tests-build`：初始化子模块并构建 `riscv-tests` 的 `isa`（`XLEN=32`）
- `external-tests-run`：运行完整 ISA 回归（通过 `scripts/test_suite.py`）
- `external-tests-smoke`：运行小规模 smoke 子集（`rv32ui,rv32um,rv32uc`）
- `external-arch-tests-fetch`：拉取 `riscv-arch-test`（源码接入）

实现位置：

- `Makefile`

### 2.1 回归脚本增强

`scripts/test_suite.py` 已重构为参数化工具，支持：

- ELF 自动发现（检测 ELF 魔数，不再依赖 `grep -IL`）
- 按类别过滤（`--categories`）
- 限制每类样本数量（`--max-tests-per-category`）
- 失败自动 debug 重跑（`-x 0`，可 `--no-debug-on-fail` 关闭）

实现位置：

- `scripts/test_suite.py`

---

## 3. 本次实际执行记录（2026-03-08）

### 3.1 已成功

1. 拉取 `riscv-tests` 成功
   - 目录：`external-tests/riscv-tests`
2. 拉取 `riscv-arch-test` 成功
   - 目录：`external-tests/riscv-arch-test`

### 3.2 当前阻塞

`riscv-tests` 构建阶段失败，错误为：

```text
.../riscv-tests/isa/Makefile:58: *** couldn't find gcc.  Stop.
```

本机缺少交叉编译器（已实测）：

```text
riscv32-unknown-elf-gcc not found
riscv64-unknown-elf-gcc not found
```

因此当前 `external-tests-smoke` 会提示未发现 ELF（尚未完成 `riscv-tests` 编译产物生成）。

---

## 4. 使用方式（具备交叉工具链后）

```bash
# 1) 拉取外部测试
make external-tests-fetch
make external-arch-tests-fetch

# 2) 构建 riscv-tests (rv32)
make external-tests-build

# 3) 运行 smoke 或全量
make external-tests-smoke
make external-tests-run
```

如果你安装了工具链，建议先确认：

```bash
which riscv32-unknown-elf-gcc
```

---

## 5. 结论

1. `./obj_dir/VTop --perfc test_programs/branch_pred_test.s` 已有完整实现链路：`参数解析 -> .s 汇编/链接 -> ELF 加载 -> 仿真 -> perfc 统计输出`。
2. 外部常用测试集可以接入，且本次已完成仓库级接入与脚本化入口。
3. 当前环境的唯一主要阻塞是缺少 RISC-V 交叉 GCC，补齐后即可直接跑 `riscv-tests` 回归。
