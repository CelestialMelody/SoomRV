# `VTop --perfc` 输出实现分析

本文说明如下输出是如何在 SoomRV 中实现的：

```text
cycles:             ...
instret:            ... # ... IPC
mispredicts:        ... # ... MPKI
branch mispredicts: ... # ...%
branches:           ...
frontend stalled:   ... # ...%
backend stalled:    ... # ...%
store stalled:      ... # ...%
load stalled:       ... # ...%
ROB stalled:        ... # ...%
      ... # .. ORD | ... # .. BTK | ... # .. BNT
      ... # .. RET | ... # .. IBR | ... # .. MEM
... cycles
```

## 1. 入口与触发时机

### 1.1 `--perfc` 参数解析

- `--perfc`/`-p` 在 `ParseArgs()` 中解析为 `args.logPerformance=1`。
- 代码位置：`sim/Top_tb.cpp:488-513`。

### 1.2 周期性打印与最终打印

- 采样间隔按 `minstret` 计：`perfInterval = 8 * 1024 * 1024` 指令。
- 运行时若 `minstret >= nextMinstretPerf` 且 `args.logPerformance` 为真，则调用 `LogPerf()`。
- 仿真结束后会无条件再调用一次 `LogPerf()`，然后打印总仿真周期 `main_time/2`。
- 代码位置：`sim/Top_tb.cpp:767-827`。

结论：

- `--perfc` 控制的是“中途周期性打印”。
- 不带 `--perfc` 时，结束时仍会打印一次 `LogPerf()`（当前代码行为）。

## 2. 输出数据从哪里来

### 2.1 C++ 侧直接读取 Verilated CSR

- `TopWrapper` 保存了 `VTop_CSR* csr` 指针，`LogPerf()` 直接读 `csr->mcycle/minstret/mhpmcounter[]`。
- 代码位置：`sim/TopWrapper.hpp:23-25`，`sim/Top_tb.cpp:644-655`。

### 2.2 `LogPerf()` 的“差分窗口”机制

- `LogPerf()` 维护 `static lastCounters`。
- 每次输出的是 `current = counters - lastCounters`，即“自上次 `LogPerf()` 以来”的增量，而不是全程累计值。
- 代码位置：`sim/Top_tb.cpp:657-661,685`。

## 3. 每一行输出的公式与硬件来源

### 3.1 基础计数器

- `cycles` = `current[0]` = `mcycle` 增量
- `instret` = `current[1]` = `minstret` 增量
- `branches` = `current[2]` = `mhpmcounter[3]` 增量

`CSR` 中更新逻辑：

- `mcycle` 每拍自增：`src/CSR.sv:749-751`
- `minstret` 按 ROB 每拍退休条目数累加：`src/CSR.sv:756-761`
- `mhpmcounter[3]` 按退休分支条目数累加：`src/CSR.sv:763-768`

ROB 提供退休信息：

- `validRetire[i]` / `branchRetire[i]` 在提交阶段生成。
- 代码位置：`src/ROB.sv:318-319`。

### 3.2 比率类字段

`LogPerf()` 中公式如下（`sim/Top_tb.cpp:663-683`）：

- `IPC = instret / cycles`
- `MPKI = mispredicts / (instret / 1000.0)`
- `branch mispredicts(%) = branch_mispredicts / branches * 100`

对应计数器映射：

- `branch mispredicts`（输出第 4 行）= `current[3]` = `mhpmcounter[4]`
- `mispredicts`（输出第 3 行）= `current[4]` = `mhpmcounter[5]`

`CSR` 中更新逻辑：

- `mhpmcounter[4]`：`IN_branchMispr` 置位时 +1（`src/CSR.sv:770-771`）
- `mhpmcounter[5]`：`IN_branch.taken` 时 +1（`src/CSR.sv:773-774`）

注意：

- 名称上 `mispredicts` 容易误解，它实际对应 `IN_branch.taken` 事件计数（所有被选中的跳转/重定向事件），并非仅“分支预测错误”。

### 3.3 Stall 行（frontend/backend/store/load/ROB）

输出映射（`sim/Top_tb.cpp:672-676`）：

- `frontend stalled`  <- `mhpmcounter[12]`
- `backend stalled`   <- `mhpmcounter[13]`
- `store stalled`     <- `mhpmcounter[14]`
- `load stalled`      <- `mhpmcounter[15]`
- `ROB stalled`       <- `mhpmcounter[16]`

计数更新（`src/CSR.sv:781-783`）：

- `mhpmcounter[11 + stallCause] += stallWeight + 1`

其中 `stallCause` 枚举定义在 `src/Include.sv:316-324`，
`stallWeight/stallCause` 由 ROB 在无法继续提交时给出（`src/ROB.sv:390-401`）。

输出百分比统一按 `100 * stalled / (4 * cycles)` 计算（`DEC_WIDTH=4`，`src/Config.sv:20`）。

### 3.4 `ORD/BTK/BNT/RET/IBR/MEM` 两行

`BranchProv.cause` 类型为 `FlushCause`（`src/Include.sv:306-314,450-465`）：

- `0 FLUSH_ORDERING` -> `ORD`
- `1 FLUSH_BRANCH_TK` -> `BTK`
- `2 FLUSH_BRANCH_NT` -> `BNT`
- `3 FLUSH_RETURN` -> `RET`
- `4 FLUSH_IBRANCH` -> `IBR`
- `5 FLUSH_MEM_ORDER` -> `MEM`

`CSR` 中对 cause 分桶计数（`src/CSR.sv:776-778`）：

- `mhpmcounter[6 + IN_branch.cause] += 1`（条件：`IN_branch.taken`）

`LogPerf()` 映射打印（`sim/Top_tb.cpp:678-683`）：

- `ORD..MEM` 分别对应 `mhpmcounter[6]..mhpmcounter[11]` 增量
- 各项百分比除数是 `current[4]`（即上面的 `mispredicts` 行）

## 4. `branch mispredicts` 信号来源

- `IN_branchMispr` 由 `Core` 中 `BranchSelector` 产生并送入 CSR。
- 代码位置：`src/Core.sv:47,59,478-479`。
- `BranchSelector` 中 `OUT_PERFC_branchMispr_c` 的置位逻辑见 `src/BranchSelector.sv:43-61`。

## 5. 容易困惑的点

### 5.1 为什么 stall 百分比可能超过 100%

主要由两点叠加：

- 分母是 `4 * cycles`（按 4-wide 归一化），不是 `cycles`
- `cycles` 使用的是带复位偏移的 `mcycle` 差分口径；短程序下分母偏小，比例会被放大

所以会看到如 `frontend stalled: ... 192%` 的现象。

### 5.3 `riscv32-unknown-elf-ld: warning: section '.data' type changed to PROGBITS` 来自哪里

当输入是 `.s/.S` 时，仿真器会先执行：

1. `as ... -o temp.o <asm>`
2. `ld ... -Tlinker.ld test_programs/entry.o temp.o`

然后把 `a.out` 载入内存（`sim/Top_tb.cpp:549-561`）。

这条 warning 是工具链 `ld` 的输出，不是 `--perfc` 逻辑输出。
