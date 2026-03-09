# BHT写后读forwarding优化说明

## 1. 背景

在当前实现中，`BranchPredictionTable` 的训练路径分为两拍：

1. 第 1 拍读取当前计数器到 `writeTempReg`。
2. 第 2 拍基于 `writeTempReg` 更新 `pred/hist`。

当连续多个周期对同一索引进行训练时，第 1 拍读取到的是数组中的旧值；同拍即将写回的新值未被转发，导致训练收敛滞后。

---

## 2. 设计目标

1. 修复同索引连续训练时的写后读滞后。
2. 保留原实现可回切，支持 A/B 构建与验证。
3. 不改变外部接口与模块时序边界。

---

## 3. 实现改动

## 3.1 新增优化副本

新增文件：`src/BranchPredictionTable_bht_fwd.sv`（保留原 `src/BranchPredictionTable.sv` 不变）。

核心行为调整：

1. 抽取统一的 2-bit 饱和计数器更新函数 `nextCounter`。
2. 当 `write_r.valid && write_c.valid && write_r.addr == write_c.addr` 时，将本拍写回结果 forward 到 `writeTempReg` 采样路径。
3. 其他场景保持原有两拍训练流程。

## 3.2 顶层开关接入

`Makefile` 新增：

```bash
make soomrv BHT_IMPL=orig
make soomrv BHT_IMPL=bht_fwd
```

映射关系：

1. `orig` -> `src/BranchPredictionTable.sv`
2. `bht_fwd` -> `src/BranchPredictionTable_bht_fwd.sv`

---

## 4. 测试与验证

本节验证时间为 **2026-03-08**。

## 4.1 新增定向微测试

新增：

1. `test_programs/dev/bht_write_read_forward_tb.sv`
2. `make -C test_programs/dev compare-bht-fwd`

覆盖场景：

1. 对同一 BHT 索引连续多拍执行 `taken=1` 训练。
2. 训练结束后读取该索引预测位，检查是否及时收敛为 taken。

结果：

1. `orig RESULT_BHT_FWD=FAIL_STALE`
2. `bht_fwd RESULT_BHT_FWD=PASS`

结论：优化版消除了同索引连续训练时的写后读滞后。

## 4.2 既有回归

执行：

```bash
make -C test_programs/dev compare
make -C test_programs/dev compare-super
make -C test_programs/dev compare-tmq-param
make -C test_programs/dev compare-sqb-issue
```

结果：全部通过。

## 4.3 顶层双实现构建

串行 `clean -> build` 验证：

```bash
make clean && make soomrv BHT_IMPL=orig LS_ISSUE_IMPL=issue_opt TLBMISSQ_IMPL=tmq_param HARDCODE4_IMPL=param TLB_IMPL=fixed_sp_dedup BRANCH_PRED_IMPL=bt_arb PAGEWALKER_IMPL=pw_arb
make clean && make soomrv BHT_IMPL=bht_fwd LS_ISSUE_IMPL=issue_opt TLBMISSQ_IMPL=tmq_param HARDCODE4_IMPL=param TLB_IMPL=fixed_sp_dedup BRANCH_PRED_IMPL=bt_arb PAGEWALKER_IMPL=pw_arb
```

结果：两条命令均通过。

## 4.4 Linux perfc 对比补充（`current` vs `current_final`）

输入日志：

1. baseline：`docs/logs/linux_perfc_current.log`
2. 优化后：`docs/logs/linux_prefc_current_final.log`

对比口径：

1. baseline 为 46 个窗口，优化后为 12 个窗口。
2. 按“之前同样方式”采用同行号对齐：`baseline` 前 12 窗口 vs 优化后 12 窗口。
3. 指标：IPC、MPKI、branch mispredict rate。

统计结果（对齐 12 窗口）：

1. IPC：`1.095505 -> 1.097209`，`+0.001703`（`+0.1555%`）
2. MPKI：`14.508991 -> 14.413941`，`-0.095050`（`-0.6551%`）
3. 分支误判率：`6.600536% -> 6.544629%`，`-0.055907%`（`-0.8470%`）

逐窗口方向统计：

1. IPC：9 升 / 3 降
2. MPKI：2 升 / 10 降
3. 分支误判率：2 升 / 10 降

结论：

1. 在对齐窗口口径下，`current_final` 相比 `current` 呈现“IPC 小幅提升、MPKI 与分支误判率下降”。
2. 当前优化后窗口数仍少于 baseline，建议后续补长窗口以确认长期稳定性。

---

## 5. 结论

1. 本轮已完成第 8 项“BHT 写后读 forwarding”优化，消除了连续同索引训练下的滞后。
2. 优化实现按 `orig/bht_fwd` 双路径接入，可回滚、可对照。
3. 定向微测试、既有回归与顶层构建均通过，可作为后续分支预测性能对比基线。
