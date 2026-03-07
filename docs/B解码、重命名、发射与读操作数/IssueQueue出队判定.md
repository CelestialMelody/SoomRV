# IssueQueue 出队判定说明

本文档说明 SoomRV 中 **IssueQueue** 在何时允许一条 UOp **出队（issue）**，即从队列中弹出并输出为 `IS_UOp`。出队判定可归纳为三类：**操作数就绪**、**端口与资源限制**、**分支冲刷**。代码见 [src/IssueQueue.sv](../../src/IssueQueue.sv)。

---

## 1. 总览：谁可以出队

每个周期，IssueQueue 从**有效队列项**（`i < insertIndex`）中选出一个**可出队候选**，用 `PriorityEncoder` 按下标优先选**最老**的一条。某条 `queue[i]` 能成为候选，当且仅当同时满足：

1. **就绪**：所有源操作数（tag）已就绪（见 §2）。  
2. **端口/资源限制**：下游未 stall、FU 可用、Load/Store/CSR/SC 等顺序与容量满足（见 §3）。  
3. **未被分支冲刷**：本周期若发生分支误预测，队列内和已输出的 UOp 会按 sqN 被废弃或保留（见 §4）。

下面分节展开。

---

## 2. 操作数就绪（avail）

### 2.1 就绪的含义

队列中每条目保存的是**物理寄存器 tag**（`tags[0]`、`tags[1]`），不是数值。某操作数“就绪”表示：该 tag 对应的值已经产生（要么已提交在 RF，要么本周期或之前某周期写回/前递）。

- **avail 的存储**：`queue[i].avail[k]` 表示第 k 个操作数是否就绪（k=0,1 对应 tagA/tagB）。  
- **avail 的更新**：入队时从 R_UOp 带入 `availA/availB`；入队后每个周期用写回/前递总线的 tag 做匹配，匹配则置位 `newAvail_c[*][i][k]`，再与 `queue[i].avail` 合并得到 `queueAvail_c[*][i]`。

### 2.2 合并后的就绪：queueAvail_c

```text
queueAvail_c[0][i] = queue[i].avail | newAvail_c[0][i]
queueAvail_c[1][i] = queueAvail_c[0][i] | newAvail_c[1][i]
```

- **queueAvail_c[0][i]**：当前周期“立即可用”的就绪（入队时已有 + 本拍写回/前递）。  
- **queueAvail_c[1][i]**：在 [0] 基础上再并上 **newAvail_c[1][i]**，用于**延迟 1 拍**才就绪的情况（见下）。  
- 出队判定用的是 **queueAvail_c[0][i]**（见代码 `&(queueAvail_c[0][i])`）；更新到 `queue[i].avail` 时用的是 **queueAvail_c[1][i]**，保证下一拍状态正确。

### 2.3 newAvail 的来源（何时置位就绪）

**（1）写回总线 IN_flagUOp**

- 若 `IN_flagUOp[j].valid` 且 `queue[i].tags[k] == IN_flagUOp[j].tagDst`，则 `newAvail_c[0][i][k] = 1`。  
- 表示：本周期某条指令写回该 tag，依赖它的本条目的第 k 个操作数本拍就绪。

**（2）本周期发射的 UOp：IN_issueUOps（前递）**

- 若某端口 j 本拍发射了 UOp，且 `IN_issueUOps[j].tagDst == queue[i].tags[k]`，则根据 **FU 类型**决定该操作数何时“算就绪”：
  - **FU_INT / FU_BRANCH / FU_BITMANIP**：本拍就绪 → `newAvail_c[0][i][k] = 1`。  
  - **FU_FPU / FU_FMUL**：延迟 1 拍就绪 → `newAvail_c[1][i][k] = 1`。  
  - **FU_MUL**：延迟 4 拍就绪 → `newAvail_c[4][i][k] = 1`（且仅当 `i < insertIndex`，即该条目已在队列中）。

因此，不同功能单元的**写回延迟**反映在“几拍后 newAvail 置位”上。

### 2.4 出队对就绪的要求

```systemverilog
deqCandidate_c[i] = ... && &(queueAvail_c[0][i]) && ...
```

即：**所有操作数**（对 2 操作数 IQ 即 avail[0] 与 avail[1]）在 **queueAvail_c[0][i]** 中都必须为 1，该条目才能参与本拍出队候选。

---

## 3. 端口与资源限制

除“操作数全就绪”外，出队还受下游与各类顺序/容量约束限制。下面按代码中的条件逐条说明。

### 3.1 下游 Stall：IN_stall

- 若 `IN_stall == 1`，本端口**本拍不做出队**（不更新 OUT_uop，也不做 collapse）。  
- 表示 Load 或执行级忙，本 IQ 端口不能继续送 UOp。

### 3.2 除法单元忙：IN_doNotIssueDiv / IN_doNotIssueFDiv

- `IN_doNotIssueDiv`：整数除法器忙或本拍已有 DIV 在发射/执行，则**不能再发一条 DIV**。  
- `IN_doNotIssueFDiv`：浮点除法同理。  
- 条件：`(!HasFU(FU_DIV) || queue[i].fu != FU_DIV || !IN_doNotIssueDiv)`，即：本端口不支持 DIV、或本条不是 DIV、或允许发 DIV 时，才不因 DIV 被挡。FDIV 类似。

### 3.3 写回端口预留：reservedWBs[0]

- INT/BRANCH/BITMANIP/FPU/FMUL 等“单拍或短延迟”的 FU 在**出队时**会占用 `reservedWBs` 的某一位（DIV 约 33 拍、MUL 若干拍），用于避免后续周期写回冲突。  
- 若 `reservedWBs[0] == 1`，表示当前已有一个“占用了第 0 位”的指令尚未写回，则**不能再发**一条会占用同一资源的 INT/BRANCH/BITMANIP/FPU/FMUL 类指令。  
- 条件：`!((queue[i].fu == FU_INT || ... || queue[i].fu == FU_FMUL) && reservedWBs[0])`。

### 3.4 CSR 按序

- CSR 指令必须**按程序序**提交，因此只能当“队头且其 sqN 等于当前提交 sqN”时才允许出队。  
- 条件：`(!HasFU(FU_CSR) || queue[i].fu != FU_CSR || (i == 0 && queue[i].sqN == IN_commitSqN))`。  
- 即：本端口不接 CSR、或本条不是 CSR、或是队头且 sqN 已轮到提交时，才不因 CSR 被挡。

### 3.5 Load 顺序与 LoadBuffer 容量：IN_maxLoadSqN

- Load（以及原子指令的 load 部分）需要占 **LoadBuffer** 条目；LB 有容量上限。  
- 只有 `queue[i].loadSqN <= IN_maxLoadSqN` 时，该 load 才有“在 LB 中的位置”，才允许出队。  
- 条件（化简）：若本条是 AGU load 或原子，则要求 `$signed(queue[i].loadSqN - IN_maxLoadSqN) <= 0`。Store-only（如 opcode >= LSU_SC_W 且非原子）不占 loadSqN，不检查。

### 3.6 Store 顺序与 StoreQueue 容量：IN_maxStoreSqN

- Store 需要占 **StoreQueue** 条目；SQ 有容量上限。  
- 只有 `queue[i].storeSqN <= IN_maxStoreSqN` 时，该 store 才有“在 SQ 中的位置”，才允许出队。  
- 条件（化简）：若本条是 AGU store（opcode >= LSU_SC_W），则要求 `$signed(queue[i].storeSqN - IN_maxStoreSqN) <= 0`。纯 load 不占 storeSqN，不检查。

### 3.7 SC 严格按序

- SC（Store Conditional）没有 reservation 恢复机制，必须**按程序序**执行，因此只有“队头且 sqN 等于当前提交 sqN”时才能出队。  
- 条件：`(!HasFU(FU_AGU) || queue[i].fu != FU_AGU || queue[i].opcode != LSU_SC_W || (i == 0 && queue[i].sqN == IN_commitSqN))`。

### 3.8 小结：端口/资源相关条件一览

| 条件 | 含义 |
|------|------|
| `!IN_stall` | 下游未 stall |
| DIV/FDIV 未占满 | `IN_doNotIssueDiv` / `IN_doNotIssueFDiv` 不阻止本条 |
| `!reservedWBs[0]`（对 INT/BR/BM/FPU/FMUL） | 写回预留位未占满 |
| CSR 队头且 sqN 轮到提交 | CSR 按序 |
| `loadSqN <= IN_maxLoadSqN` | LoadBuffer 有空间 |
| `storeSqN <= IN_maxStoreSqN` | StoreQueue 有空间 |
| SC 队头且 sqN 轮到提交 | SC 按序 |

---

## 4. 分支冲刷（IN_branch.taken）

当发生**分支误预测**时，`IN_branch.taken == 1`，IssueQueue 要做两件事：  
（1）**队列内容**：只保留“在误预测之前”的条目（按 sqN 判断），相当于丢弃误预测之后入队的 UOp。  
（2）**本拍输出**：若当前输出的 `OUT_uop` 的 sqN 在误预测之后，则清空输出。

### 4.1 BranchProv 中的相关字段

- **IN_branch.taken**：本周期发生分支误预测（需要冲刷）。  
- **IN_branch.sqN**：误预测分支指令的 sqN；用于比较“之前/之后”。  
- **IN_branch.flush**：区分冲刷模式（见下）。

### 4.2 队列索引收缩：重算 insertIndex

分支发生时，不再信任“误预测之后”的条目，因此**收缩有效队列**，只保留 sqN 在分支“之前”的条目：

- 若 **IN_branch.flush == 1**：保留 `queue[i].sqN < IN_branch.sqN` 的条目（**严格小于**）。  
- 若 **IN_branch.flush == 0**：保留 `queue[i].sqN <= IN_branch.sqN` 的条目（**小于等于**，即包含分支指令本身）。

实现方式：遍历 `i < insertIndex`，找到满足上述比较的**最大** `i`，令 `newInsertIndex = i+1`，然后 `insertIndex <= newInsertIndex`。这样大于 newInsertIndex 的槽位在逻辑上被“废弃”（后续入队会覆盖，或通过 collapse 被前面有效条目填满）。

### 4.3 本拍输出清零

若本拍正在输出一条 UOp（`OUT_uop.valid == 1`），且该 UOp 的 `sqN > IN_branch.sqN`（说明它在误预测之后），则必须视为无效：

```systemverilog
if (IN_branch.taken) begin
    ...
    if (!IN_stall || $signed(OUT_uop.sqN - IN_branch.sqN) > 0) begin
        OUT_uop <= 'x;
        OUT_uop.valid <= 0;
    end
end
```

即：**要么**下游在 stall（此时不更新 OUT_uop），**要么**当前 OUT_uop 的 sqN 在分支之后，则强制清空输出。

### 4.4 入队侧对分支的屏蔽

入队时，Rename 送来的 `IN_uop` 是否被接收，受 `IN_opValid` 控制；`IN_opValid` 中会屏蔽 `IN_branch.taken`（见 OpDownsample 的 `IN_opValid(~(defer | {NUM_UOPS{IN_branch.taken}}))`）。因此**分支发生的那一拍，不会从 Rename 再收新 UOp**，与队列内“按 sqN 收缩”一起，保证误预测之后的指令不会留在 IQ 中。

---

## 5. 出队判定逻辑汇总（deqCandidate_c）

将 §2～§4 合在一起，`queue[i]` 能成为**可出队候选**的完整条件为：

```text
deqCandidate_c[i] = true  当且仅当：

  (1) i < insertIndex
      —— 该槽位是有效队列项

  (2) &(queueAvail_c[0][i])
      —— 所有源操作数已就绪（§2）

  (3) !IN_stall
      —— 下游未 stall（§3.1）

  (4) DIV/FDIV 允许
      —— (!HasFU(FU_DIV)  || queue[i].fu != FU_DIV  || !IN_doNotIssueDiv)  &&
         (!HasFU(FU_FDIV) || queue[i].fu != FU_FDIV || !IN_doNotIssueFDiv)  （§3.2）

  (5) 写回预留
      —— 非 (INT/BR/BM/FPU/FMUL 且 reservedWBs[0])  （§3.3）

  (6) CSR 按序
      —— (!HasFU(FU_CSR) || queue[i].fu != FU_CSR || (i==0 && queue[i].sqN==IN_commitSqN))  （§3.4）

  (7) Load 容量
      —— 非 load 或 非 AGU/原子 或 loadSqN <= IN_maxLoadSqN  （§3.5）

  (8) Store 容量
      —— 非 store 或 非 AGU/原子 或 storeSqN <= IN_maxStoreSqN  （§3.6）

  (9) SC 按序
      —— 非 AGU 或 非 SC 或 (i==0 && queue[i].sqN==IN_commitSqN)  （§3.7）
```

**分支冲刷**不改变某条是否“是候选”的布尔值，而是：  
- 在 `IN_branch.taken` 时**先**按 §4 收缩 `insertIndex` 并清空不合法的 `OUT_uop`；  
- 下一拍起，已被收缩掉的条目不再满足 `i < insertIndex`，自然不会再被选为候选。

最终，**PriorityEncoder** 在 `deqCandidate_c` 中选出一个下标最小的候选作为本拍出队项 `deq.idx`，若存在则 `deq.valid == 1`，否则本拍无出队。

---

## 6. 与主文档的关系

- 入队条件、R_UOp 到队列项的映射见 [B解码、重命名、发射与读操作数.md](./B解码、重命名、发射与读操作数.md)。  
- tag/avail 的全局含义与 RenameTable 查表见同文档及 [字段流转表.md](./字段流转表.md)。
