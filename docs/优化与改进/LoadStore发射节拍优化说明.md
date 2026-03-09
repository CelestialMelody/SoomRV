# Load/Store 发射节拍优化说明

## 1. 背景

在当前实现中，`StoreQueueBackend` 的 store 发射通道在下游持续 backpressure（`IN_stallSt=1`）时会出现节拍空泡：

1. 已经发出的 `OUT_uopSt.valid` 在下一拍被清零。
2. 再下一拍重新 re-issue 同一条 store。
3. 导致 `valid` 呈现 `1/0/1/0` 抖动，而不是连续保持。

这会降低访存压力场景下的发射连续性，也与标准 ready/valid 保持语义不一致。

---

## 2. 设计目标

1. 修复持续 backpressure 下的 `OUT_uopSt.valid` 抖动。
2. 保持原始实现可回切，支持 A/B 构建验证。
3. 不改动外部接口协议，不引入新的功能路径。

---

## 3. 实现改动

## 3.1 新增优化副本

新增文件：`src/StoreQueueBackend_issue_opt.sv`（保留原 `src/StoreQueueBackend.sv` 不变）。

核心行为调整：

1. 仅在 `OUT_uopSt.valid && !IN_stallSt` 时清空输出（下游已接受）。
2. 当 `OUT_uopSt.valid && IN_stallSt` 时保持输出稳定，不再把对应 entry 重新标记为 `issued=0`。
3. 仅当发射口可用（`!OUT_uopSt.valid || !IN_stallSt`）时，才允许 `reIssue` 或“新插入即发射”覆盖输出。

## 3.2 顶层开关接入

`Makefile` 新增：

```bash
make soomrv LS_ISSUE_IMPL=orig
make soomrv LS_ISSUE_IMPL=issue_opt
```

映射关系：

1. `orig` -> `src/StoreQueueBackend.sv`
2. `issue_opt` -> `src/StoreQueueBackend_issue_opt.sv`

---

## 4. 测试与验证

本节验证时间为 **2026-03-08**。

## 4.1 新增定向微测试

新增：

1. `test_programs/dev/store_queue_backend_issue_tb.sv`
2. `make -C test_programs/dev compare-sqb-issue`

覆盖场景：

1. 注入 1 条 store。
2. 下游持续 `IN_stallSt=1`。
3. 检查 `OUT_uopSt.valid` 是否出现节拍空泡。

结果：

1. `orig RESULT_SQB_ISSUE=FAIL_GAP`
2. `issue_opt RESULT_SQB_ISSUE=PASS`

结论：优化版在持续 stall 下可保持 `valid` 连续有效。

## 4.2 既有回归

执行：

```bash
make -C test_programs/dev compare
make -C test_programs/dev compare-super
make -C test_programs/dev compare-tmq-param
```

结果：全部通过。

## 4.3 顶层双实现构建

串行 `clean -> build` 验证：

```bash
make clean && make soomrv LS_ISSUE_IMPL=orig TLBMISSQ_IMPL=tmq_param HARDCODE4_IMPL=param TLB_IMPL=fixed_sp_dedup BRANCH_PRED_IMPL=bt_arb PAGEWALKER_IMPL=pw_arb
make clean && make soomrv LS_ISSUE_IMPL=issue_opt TLBMISSQ_IMPL=tmq_param HARDCODE4_IMPL=param TLB_IMPL=fixed_sp_dedup BRANCH_PRED_IMPL=bt_arb PAGEWALKER_IMPL=pw_arb
```

结果：两条命令均通过。

---

## 5. 结论

1. 完成“Store 发射节拍”关键问题修复：去除了持续 backpressure 下的无谓发射空泡。
2. 实现按 `orig/issue_opt` 双路径接入，具备可回滚和可对照验证能力。
3. 微测试与顶层构建均通过，可作为后续 Linux/压力程序性能对比的基线实现。
