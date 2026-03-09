# 外部测试去 COSIM 依赖改进记录（2026-03-09）

## 1. 背景

当前仓库外部测试入口为：

- `make external-tests-smoke`
- `make external-tests-run`

两者都通过 `scripts/test_suite.py` 调用 `./obj_dir/VTop -t <test>` 执行单测，并以进程输出中是否包含 `PASSED test with return code ...` 作为通过判定（`scripts/test_suite.py:199-200`）。

在实际使用中，出现了以下现象：

- `rv32mi-p-breakpoint` / `rv32ui-p-add` 等用例长时间无结束；
- 脚本只打印心跳（例如 `... 15s`），最终常被人工 `Ctrl+C` 中断；
- 直观体验上像“测试卡住”。

## 2. 原因

根因是“外部测试退出协议”在旧实现中实际绑定到了 COSIM 路径：

1. `Makefile` 默认 `COSIM ?= 0`（`Makefile:6`）。
2. `tohost` 结束判定在 `sim/Simif.cpp` 的对拍写回路径里执行（`sim/Simif.cpp:224` 附近）。
3. `PASSED/FAILED test with return code ...` 与 `Exit(0)` 也在 `#ifdef COSIM` 的提交逻辑里（`sim/Top_tb.cpp:194` 附近）。

因此在 `COSIM=0` 构建下，`-t` 模式虽然会运行程序，但无法触发与 `riscv-tests` 协议一致的退出打印与退出动作，测试进程只能等待脚本超时。

## 3. 方法

### 3.1 目标

- 让 `external-tests-*` 在 `COSIM=0` 下也能按 `tohost` 协议自动退出；
- 保持 `COSIM=1` 原有行为不变；
- 保持对 `scripts/test_suite.py` 的输出契约不变（继续打印 `PASSED/FAILED test with return code ...`）。

### 3.2 关键实现

改动文件：`sim/Top_tb.cpp`

#### A) 新增非 COSIM 下的 store 数据提取函数

- 新增 `ExtractStoreWord(const ST_UOp&, uint32_t, uint32_t&)`（`sim/Top_tb.cpp:121`）。
- 作用：从 `StoreQueue Backend` 发出的 `ST_UOp`（包含 `addr/wmask/data`）中提取某个 32-bit 目标地址对应的数据字。
- 约束：
  - 仅处理有效、非 MMIO、非 mgmt store；
  - 目标地址必须 4-byte 对齐；
  - 对应 4 个字节必须都在 `wmask` 中有效。

#### B) 在 `run_sim()` 增加 `#ifndef COSIM` 退出检测

位置：`sim/Top_tb.cpp:932-978`

- 在 `args.testMode` 下初始化待检测 `tohost` 地址集合：
  - 优先使用 ELF 解析得到的动态地址 `simif.riscvTestTohostAddr`；
  - 否则回退 `0x80001000 / 0x80002000 / 0x80003000`。
- 每个时钟上升沿读取 `core->__PVT__SQB_uop`（`ST_UOp`），检测两类写入：
  1. 写 `tohost`：记录返回码；
  2. 写 `tohost+4` 且数据为 `0`：判定测试结束。
- 结束时打印与历史完全兼容的文案并退出：
  - `PASSED test with return code 00000001`
  - 或 `FAILED test with return code <code>`

### 3.3 设计取舍

本次最终采用 `ST_UOp` 路径识别结束协议，而不是轮询外部内存阵列。

原因是 `ST_UOp` 直接携带“已发出的 store 地址 + 掩码 + 数据”，语义更贴近 `tohost` 协议本身，不依赖缓存/写回可见性时序。

## 4. 结果

在 `COSIM=0` 条件下完成以下验证：

1. 构建：
   - `make soomrv COSIM=0` 成功。
2. 单测：
   - `timeout 20s ./obj_dir/VTop -t external-tests/riscv-tests/isa/rv32mi-p-breakpoint`
   - 输出 `PASSED test with return code 00000001`，返回码 `0`。
3. Smoke：
   - `make external-tests-smoke EXTERNAL_TEST_TIMEOUT=60 EXTERNAL_TEST_HEARTBEAT=10`
   - `all selected tests passed (18 total)`。
4. 全量：
   - `make external-tests-run EXTERNAL_TEST_TIMEOUT=60 EXTERNAL_TEST_HEARTBEAT=10`
   - `all selected tests passed (198 total)`；
   - 已知边界项仍按既有策略跳过（`instret_overflow`、`pmpaddr`）。

结论：`external-tests-smoke` 与 `external-tests-run` 已不再依赖 `COSIM=1` 才能正常退出。

## 5. 复现命令

```bash
# 1) 非 COSIM 构建
make soomrv COSIM=0

# 2) 单测快速验证
timeout 20s ./obj_dir/VTop -t external-tests/riscv-tests/isa/rv32mi-p-breakpoint

# 3) 外部测试 smoke
make external-tests-smoke EXTERNAL_TEST_TIMEOUT=60 EXTERNAL_TEST_HEARTBEAT=10

# 4) 外部测试全量
make external-tests-run EXTERNAL_TEST_TIMEOUT=60 EXTERNAL_TEST_HEARTBEAT=10
```

## 6. 影响与后续建议

- 影响范围：仅 `#ifndef COSIM` 分支新增退出检测；`COSIM=1` 路径保持不变。
- 风险点：当前实现读取了 Verilator 生成对象中的内部字段 `core->__PVT__SQB_uop`。如果后续 RTL/生成命名发生较大变化，可能需要同步调整该读取点。
- 建议：后续可考虑在顶层暴露稳定的“测试协议观察口”（如 `tohost` 观测信号），减少对内部命名细节的依赖。

