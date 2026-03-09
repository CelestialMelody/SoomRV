# BranchPredictor BT 更新仲裁改进说明

## 1. 背景与需求

在 SoomRV 现有前端链路中，`BranchPredictor` 会接收多个来源的 `BTUpdate`。原始实现位于 `src/BranchPredictor.sv`，其仲裁方式是循环覆盖：同拍若有多个 `valid`，后写值覆盖先写值。该实现的优势是逻辑短、时序简单，但在高并发分支更新场景下有两个实际问题：

1. 更新可能丢失。同拍多源有效时，只有最后一次覆盖留下，其他更新不会进入后续周期。
2. 行为依赖输入排列。
   仲裁语义隐含在循环顺序中，不具备显式协议，排查前端抖动时很难从接口层直接确认优先级策略。

这类问题并不一定立即表现为功能错误，但会影响预测结构收敛效率，进而放大 IPC 波动。基于这一观察，本次改进目标不是“改写整个预测器”，而是聚焦在 BT 更新入口上，构建可验证、可回滚的最小改动路径。

本次实现采用与 `TLB.sv / TLB_fixed.sv` 同样的组织方式：**原实现保留，改进实现独立文件承载，通过 Makefile 开关选择**。

---

## 2. 总体设计

### 2.1 代码组织策略

为保证实验可复现与对比可追溯，采用以下结构：

- 保留原文件：`src/BranchPredictor.sv`
- 新增改进版：`src/BranchPredictor_bt_arb.sv`
- 新增仲裁子模块：`src/BTUpdateArbiter.sv`
- 在顶层 `Makefile` 增加实现开关 `BRANCH_PRED_IMPL`

该策略相对“直接改原文件”的主要收益是：

1. 可以在同一仓库内直接做 A/B 构建，不需要手工打补丁回滚。
2. 回归脚本可显式记录“本次结果对应哪一版前端仲裁”。
3. 后续若出现性能回退，定位范围可以快速收缩到“实现切换”而不是“大面积代码变更”。

### 2.2 仲裁策略设计

改进版仲裁由 `BTUpdateArbiter` 负责，策略分两层：

1. **显式优先级**：按输入数组索引优先级仲裁（当前实现为高索引优先）。
2. **未选中缓存**：同拍未被选中的更新进入 pending（每个源 1 槽位），在后续周期继续输出，避免当拍丢失。

这里有过一个取舍：是否引入全局 FIFO。
最终没有采用 FIFO，而是选择“每源单槽 pending”，原因是本场景更关注“同拍并发更新不丢失”，而非大规模排队。每源单槽位可以在保持逻辑简单的同时覆盖核心问题，且不改变 `BranchPredictor` 其余时序路径。

---

## 3. 详细实现

### 3.1 原始与改进文件并存

- 原始实现文件：`src/BranchPredictor.sv`（未改动，保留基线行为）
- 改进实现文件：`src/BranchPredictor_bt_arb.sv`
  - 在原有逻辑基础上，将 BTUpdate 覆盖式选择替换为 `BTUpdateArbiter` 实例。

这种实现方式确保两版功能边界清晰：除 BT 更新入口仲裁外，预测器其他数据路径保持一致。

### 3.2 `BTUpdateArbiter` 核心逻辑

`src/BTUpdateArbiter.sv` 的核心流程如下：

1. 先检查 pending，有则优先输出 pending。
2. 若 pending 为空，再从当拍输入中按优先级选择一个输出。
3. 对当拍输入中“未被消费”的更新，若对应 pending 空闲则写入 pending。
4. 每拍更新 pending 状态。

这样做的直接效果是：

- 同拍多源更新不再只能保留 1 条；
- 仲裁语义由“循环覆盖”变为“可读、可测的显式协议”。

### 3.3 Makefile 开关

在 `Makefile` 增加：

- `BRANCH_PRED_IMPL ?= bt_arb`
- `BRANCH_PRED_IMPL=orig` 选择 `src/BranchPredictor.sv`
- `BRANCH_PRED_IMPL=bt_arb` 选择 `src/BranchPredictor_bt_arb.sv`

示例：

```bash
make soomrv BRANCH_PRED_IMPL=orig
make soomrv BRANCH_PRED_IMPL=bt_arb
```

这与现有 `TLB_IMPL=orig/fixed` 的使用模式一致，降低团队使用成本。

---

## 4. 测试与验证

### 4.1 单元级验证：同拍多更新与 pending 行为

新增测试：

- `test_programs/dev/bt_update_arb_tb.sv`
- `test_programs/dev/Makefile` 增加 `run-bt-arb` 目标

执行命令：

```bash
make -C test_programs/dev run-bt-arb
```

测试覆盖两类关键场景：

1. 三源同拍有效，验证优先级与“逐拍排空”行为。
2. pending 正在消费时，同源新更新到达，验证不会被覆盖丢失。

结果：

- 输出 `RESULT_BT_ARB=PASS`
- 细分检查点 `same_cycle_*`、`pending_replace_*`、`drain` 全部通过。

### 4.2 构建级验证：双实现可编译

执行：

```bash
make soomrv BRANCH_PRED_IMPL=orig
make soomrv BRANCH_PRED_IMPL=bt_arb
```

结果：两种实现均可通过 Verilator 全量构建，说明开关接入正确，且未破坏工程构建链路。

### 4.3 端到端回归：`branch_pred_test.s`

在当前环境下，`branch_pred_test.s` 已可运行，样例输出如下：

```bash
./obj_dir/VTop --perfc test_programs/branch_pred_test.s
...
instret:            4530 # 2.053490 IPC
mispredicts:        8 # 1.766004 MPKI
branch mispredicts: 8 # 0.399600%
...
```

这一结果说明改造后前端路径在分支微基准上可正常工作，未出现功能性退化。

### 4.4 Linux `--perfc` 日志对比（`current` vs `current_bp_opt_1`）

本节数据来源：

- baseline：`docs/logs/linux_perfc_current.log`
- 优化后：`docs/logs/linux_perfc_current_bp_opt_1.log`

两份日志的样本规模不同（46 vs 12），因此采用两层口径：

1. 全量口径：用于说明样本规模，不直接做性能优劣判定。
2. 同行号口径：取 baseline 前 12 个样本，与优化后 12 个样本逐行对齐比较。

#### 4.4.1 样本规模

| 日志                                 | IPC 样本数 | MPKI 样本数 | 分支误判率样本数 |
| ------------------------------------ | ---------: | ----------: | ---------------: |
| `linux_perfc_current.log`          |         46 |          46 |               46 |
| `linux_perfc_current_bp_opt_1.log` |         12 |          12 |               12 |

#### 4.4.2 同行号对齐结果（前 12 个样本）

| 指标           | baseline（前12） | bp_opt_1（12） |     变化量 | 相对变化 |
| -------------- | ---------------: | -------------: | ---------: | -------: |
| IPC 均值       |         1.095505 |       1.098689 |  +0.003184 | +0.2906% |
| MPKI 均值      |        14.508991 |      14.529316 |  +0.020326 | +0.1401% |
| 分支误判率均值 |        6.600536% |      6.593743% | -0.006794% | -0.1029% |

逐窗口方向统计（逐行一一对齐）：

- IPC：12 个窗口中 8 个上升、4 个下降。
- MPKI：12 个窗口中 3 个上升、9 个下降。
- 分支误判率：12 个窗口中 3 个上升、9 个下降。

#### 4.4.3 结果解读

从同行号对齐结果看，本次仲裁改动未引入明显负向影响，IPC 均值小幅上升，分支误判率均值小幅下降。
MPKI 呈现“多数窗口下降，但均值略升”的表象，说明少数窗口的上升幅度较大，抵消了多数窗口的小幅下降。这类现象在 Linux 启动/初始化阶段常见，通常与阶段性工作负载切换有关。

因此，这一版对比更适合作为“工程安全性确认”而非“性能显著提升结论”。若需要形成更稳定的性能判断，建议将优化后日志补齐到与 baseline 接近的窗口数量，再进行同口径统计。

---

## 5. 总结与后续方向

本次改进完成了三件关键事情：

1. 在不破坏原始代码基线的前提下，建立了前端 BT 仲裁的改进实现。
2. 将仲裁语义从“隐式覆盖”提升为“显式优先级 + 可观察缓存行为”。
3. 通过 Makefile 开关把实现选择工程化，形成与 `TLB_IMPL` 一致的实验与回滚路径。

当前仍有两项值得继续推进的工作：

1. 扩展优化后 Linux `--perfc` 采样窗口数量，与 baseline 保持接近规模，降低阶段性噪声对均值的影响。
2. 若后续出现 pending 溢出场景（每源单槽不足），再评估是否从“单槽 pending”升级到小深度 FIFO；该升级应以压力测试数据为依据，不建议提前复杂化。

整体上，这一版改动已经建立了可复现、可切换、可验证的前端仲裁改进基础。
