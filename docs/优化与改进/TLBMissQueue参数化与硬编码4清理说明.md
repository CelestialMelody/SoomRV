# TLBMissQueue 参数化与硬编码 4 清理说明

## 1. 背景与目标

本轮对应优化清单中的两项工作：

1. P0-4：修复 `TLBMissQueue` 在 `SIZE!=4` 下的 `OUT_free` 统计错误。
2. P1-5：清理关键路径中的“硬编码 4”，统一改为参数/位宽驱动。

工程目标保持与前序改造一致：

1. 保留原文件，新增改进副本。
2. 顶层 `Makefile` 提供实现开关，支持 A/B 构建。
3. 补充微测试并给出系统级构建验证。

---

## 2. P0-4：`TLBMissQueue` 参数化修正

## 2.1 问题说明

原始 `src/TLBMissQueue.sv` 的 `OUT_free` 逻辑固定按 4 项统计：

1. 只对 `queue[0..3]` 做两级求和。
2. 当 `SIZE=8` 等非 4 配置时，空位计数上限仍会被截在 4。

这会导致：

1. `OUT_free` 与真实空位不一致。
2. 依赖 `OUT_free` 的上层行为在参数化配置下出现偏差。

## 2.2 实现改动

新增 `src/TLBMissQueue_param.sv`，核心改动如下：

1. 用 `for (i=0; i<SIZE; i++)` 循环统计空位。
2. 使用 `logic[$clog2(SIZE):0] freeCnt` 保存计数结果。
3. 保留原有 “若 `OUT_uop.valid` 则预扣减 1” 语义，不改变协议行为。

顶层接入开关：

```bash
make soomrv TLBMISSQ_IMPL=orig
make soomrv TLBMISSQ_IMPL=tmq_param
```

---

## 3. P1-5：清理“硬编码 4”

## 3.1 改造范围

新增以下副本文件：

1. `src/Scheduler_param.sv`
2. `src/StoreQueue_param.sv`
3. `src/ExternalAXISim_param.sv`
4. `src/BranchSelector_param.sv`

## 3.2 关键替换点

1. `Scheduler`：循环上界由固定 `4` 改为 `NUM_ALUS` / ``DEC_WIDTH``。
2. `StoreQueue`：字节循环由固定 `4` 改为 `$bits(wmask)`。
3. `ExternalAXISim`：`fifoAW` 插入索引扫描由固定 `4` 改为 `NUM_TFS`。
4. `BranchSelector`：固定端口下标 `2/3` 改为 `NUM_BRANCHES` 推导索引。

顶层接入开关：

```bash
make soomrv HARDCODE4_IMPL=orig
make soomrv HARDCODE4_IMPL=param
```

---

## 4. 验证结果

本节验证时间为 **2026-03-08**。

## 4.1 TLBMissQueue 参数化微测试

执行：

```bash
make -C test_programs/dev compare-tmq-param
```

结果：

1. `orig size4 RESULT_TMQ_PARAM=PASS`
2. `orig size8 RESULT_TMQ_PARAM=FAIL`
3. `tmq_param size4 RESULT_TMQ_PARAM=PASS`
4. `tmq_param size8 RESULT_TMQ_PARAM=PASS`

判定：`tmq_param` 正确修复了 `SIZE!=4` 的 free-count 问题。

## 4.2 既有回归（防回归）

执行：

```bash
make -C test_programs/dev compare
make -C test_programs/dev compare-super
```

结果：两组均通过。

## 4.3 顶层双实现构建

为避免 `obj_dir` 竞争，采用串行 `clean -> build`：

```bash
make clean && make soomrv TLBMISSQ_IMPL=orig HARDCODE4_IMPL=orig TLB_IMPL=fixed_sp_dedup BRANCH_PRED_IMPL=bt_arb PAGEWALKER_IMPL=pw_arb
make clean && make soomrv TLBMISSQ_IMPL=tmq_param HARDCODE4_IMPL=param TLB_IMPL=fixed_sp_dedup BRANCH_PRED_IMPL=bt_arb PAGEWALKER_IMPL=pw_arb
```

结果：两条命令均通过。

---

## 5. 结论

1. `TLBMissQueue` 的 `SIZE` 参数化缺陷已被微测试稳定复现并修复。
2. 关键“硬编码 4”已替换为参数/位宽驱动，并通过顶层构建验证。
3. 当前实现支持 `orig` 与 `param` 双路径并行维护，可持续用于后续性能/稳定性 A/B 对照。
