# PageWalker 请求仲裁改进说明

## 1. 背景与需求

在 SoomRV 现有实现中，`PageWalker` 的请求选择位于 `src/PageWalker.sv`。原逻辑在 `IDLE` 状态下遍历 `IN_rqs`，若同拍多路 `valid`，后出现的请求会覆盖前面请求，等效为“最后 valid 胜出”。

这一行为本身并不违反功能正确性，但存在两个工程问题：

1. 仲裁语义隐式绑定在循环顺序上，不便于验证与排障。
2. 长期运行时容易形成端口偏置，请求公平性不可观测。

因此，P0-2 的目标不是重写页表遍历主流程，而是把“请求选择策略”从隐式覆盖改为显式仲裁，并且保持原实现可随时回切。

---

## 2. 总体设计

### 2.1 代码组织策略

沿用 `TLB_IMPL` 与 `BRANCH_PRED_IMPL` 的工程化模式：

1. 保留原实现：`src/PageWalker.sv`
2. 新增改进实现：`src/PageWalker_pw_arb.sv`
3. 新增仲裁子模块：`src/PageWalkReqArbiter.sv`
4. 在 `Makefile` 新增开关 `PAGEWALKER_IMPL=orig/pw_arb`

这样做的收益是：验证可对照、问题可回滚、结论可复现。

### 2.2 仲裁策略取舍

对比过两种方案：

1. 固定优先级（组合最短，但长期可能偏置固定端口）
2. 轮转起点扫描（复杂度略高，但公平性更好）

最终采用“轮转起点扫描”：

1. 每拍从 `rrStart` 开始扫描第一个 `valid` 请求。
2. 一旦选择成功，下一拍 `rrStart` 前移到 `sel+1`。

该策略在不引入队列结构的前提下，解决了“隐式覆盖 + 固定偏置”问题，且对原状态机侵入较小。

---

## 3. 详细实现

### 3.1 `PageWalkReqArbiter`

`src/PageWalkReqArbiter.sv` 将请求选择独立成可复用模块，输入为：

1. `IN_valid[NUM_RQS-1:0]`
2. `IN_start`

输出为：

1. `OUT_idx`
2. `OUT_valid`

模块行为是“从 `IN_start` 起按环形顺序扫描，命中第一个 `valid` 即返回”。

### 3.2 `PageWalker_pw_arb` 主流程改动

`src/PageWalker_pw_arb.sv` 在原 `PageWalker` 基础上增加：

1. 轮转指针寄存器 `rrStart`
2. 请求有效位展开 `rqValid`
3. `PageWalkReqArbiter` 实例

在 `IDLE` 分支中由 `selRqValid/selRqIdx` 直接驱动发起请求，替代原先“for 循环覆盖式选择”。页表遍历（两级访问、fault 检查、回填结果）主路径保持不变。

### 3.3 构建系统与测试入口

`Makefile` 新增：

1. `PAGEWALKER_IMPL ?= pw_arb`
2. `PAGEWALKER_IMPL=orig -> src/PageWalker.sv`
3. `PAGEWALKER_IMPL=pw_arb -> src/PageWalker_pw_arb.sv`

并将 `src/PageWalkReqArbiter.sv` 纳入 `SRC_FILES`。

`test_programs/dev` 新增微测试：

1. `pagewalk_req_arb_tb.sv`
2. `run-pw-arb` 目标

---

## 4. 测试与验证

本节验证时间为 **2026-03-08**。

### 4.1 修复构建验证流程

前一轮失败根因不是 RTL 功能错误，而是把两条顶层构建命令并行执行，竞争同一个 `obj_dir`，导致 Verilator 产物互相覆盖（出现 PCH 缺失与异常 C++ 编译错误）。

本轮采用串行流程修复：

1. `make clean`
2. `make soomrv PAGEWALKER_IMPL=orig BRANCH_PRED_IMPL=bt_arb`
3. `make clean`
4. `make soomrv PAGEWALKER_IMPL=pw_arb BRANCH_PRED_IMPL=bt_arb`

结果：两种实现均完成全量构建。

### 4.2 微测试（仲裁行为）

执行：

```bash
make -C test_programs/dev run-pw-arb
```

结果：

1. 输出 `RESULT_PAGEWALK_REQ_ARB=PASS`
2. 场景 `all/sparse/single/none/explicit_priority` 全部通过

结论：显式仲裁策略行为符合预期。

### 4.3 页表相关回归（端到端）

原计划程序为 `test_programs/virtual_mem.s`，但当前环境缺失：

1. `riscv32-unknown-elf-as`
2. `riscv32-unknown-elf-ld`

因此改用仓库内预构建 Linux 镜像进行页表相关路径回归：

```bash
timeout 40s ./obj_dir/VTop --perfc test_programs/linux/linux_image.elf
```

在 `orig` 与 `pw_arb` 两种实现下，均稳定进入 OpenSBI 启动阶段（输出一致，未见 crash/panic），40 秒由 `timeout` 主动截断。

这说明本次 PageWalker 请求仲裁改动未破坏虚拟内存慢路径的基础可启动性。

### 4.4 Linux `--perfc` 对比（`bp_opt_1` vs `pw_opt`）

对比输入：

1. `docs/logs/linux_perfc_current_bp_opt_1.log`
2. `docs/logs/linux_perfc_current_pw_opt.log`

两份日志的窗口数均为 12，采用同行号一一对齐比较。

#### 4.4.1 样本规模与均值

| 指标 | `bp_opt_1` 均值 | `pw_opt` 均值 | 变化量（pw-bp） | 相对变化 |
| --- | ---: | ---: | ---: | ---: |
| IPC | 1.098689 | 1.098185 | -0.000504 | -0.0459% |
| MPKI | 14.529316 | 14.481026 | -0.048290 | -0.3324% |
| 分支误判率 | 6.593743% | 6.577399% | -0.016343% | -0.2479% |

#### 4.4.2 逐窗口方向统计（12 对齐窗口）

1. IPC：5 升 / 7 降
2. MPKI：4 升 / 8 降
3. 分支误判率：5 升 / 7 降

#### 4.4.3 结果解读

`pw_opt` 相对于 `bp_opt_1` 的主要变化是：

1. IPC 基本持平，均值轻微回落（-0.0459%）。
2. MPKI 与分支误判率均值均下降（分别 -0.3324%、-0.2479%）。

从这组 12 窗口数据看，请求仲裁显式化没有引入明显性能退化，同时在分支相关失效率指标上呈现小幅改善。考虑到窗口规模仍有限，该结论应定位为阶段性结果，后续仍建议补长窗口采样做最终判定。

---

## 5. 结论与后续

本轮 P0-2 已完成以下交付：

1. 请求选择策略从隐式覆盖升级为显式仲裁（轮转起点扫描）。
2. 保留原文件并提供可切换实现，支持同仓库 A/B 构建。
3. 补齐微测试与顶层双实现构建验证。
4. 完成页表相关端到端回归（Linux 镜像启动路径）。

后续建议：

1. 在 Linux `--perfc` 长窗口上补做 `orig/pw_arb` 的 IPC 与 stalled 指标对比，形成性能层面的最终结论。
