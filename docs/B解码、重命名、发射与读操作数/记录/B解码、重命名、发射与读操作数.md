# 任务单 B：解码、重命名、发射与读操作数

本文档说明 SoomRV 从预译码指令到执行级操作数的整条数据路径，并完成以下三项说明：

1. **讲清 PD_Instr → D_UOp → R_UOp → IS_UOp → EX_UOp**：各阶段 UOp 的字段含义、转换模块与数据流。
2. **讲清 tag/avail 的依赖与就绪传播**：物理 tag 表示依赖、avail 表示就绪，在 Rename 与 IssueQueue 中如何产生与更新。
3. **讲清“发射后读操作数”的动机与代价**：为何在 Load 级才读操作数数值，以及带来的延迟、面积与关键路径影响。

相关概述见 [Overview.zh.md](../../Overview.zh.md)。UOp 及流水线字段定义在 [src/Include.sv](../../../src/Include.sv)。

---

## 1. 流水线中的位置

```
取指(IFetch) → 预译码(PreDecode) → 译码(InstrDecoder) → 重命名(Rename) → 发射队列(IssueQueue) → 读操作数(Load) → 执行(Execute)
                    ↓                      ↓                    ↓                    ↓                    ↓
                IF_Instr              PD_Instr               D_UOp               R_UOp               IS_UOp               EX_UOp
```

- **PD_Instr**：预译码后的单条指令（带 PC、预测信息、原始指令字）。
- **D_UOp**：译码后的内部格式（架构寄存器号 rs1/rs2/rd、操作码、FU、立即数等）。
- **R_UOp**：重命名后（物理 tag、avail、sqN、storeSqN/loadSqN），送入各 IssueQueue。
- **IS_UOp**：从某个 IssueQueue 发射出的 UOp（仍为 tag，无数值）。
- **EX_UOp**：Load 级读寄存器/前递/PC 后得到的 UOp（含 srcA、srcB、pc 等），供执行级使用。

---

## 2. UOp 数据流：PD_Instr → D_UOp → R_UOp → IS_UOp → EX_UOp

本节讲清整条链上**每一级 UOp 的形态与转换**：预译码输出单条指令（PD_Instr），译码得到架构寄存器格式（D_UOp），重命名得到物理 tag 与就绪位（R_UOp），发射队列就绪后输出仍带 tag 的 IS_UOp，最后在 Load 级读出操作数数值得到 EX_UOp。

### 2.1 PD_Instr（预译码输出）

定义见 `Include.sv` 中 `PD_Instr`：

- **instr**：32 位原始指令。
- **pc, fetchID, fetchStartOffs, fetchPredOffs**：取指/预测相关，供恢复与调试。
- **predTarget, predTaken**：分支预测结果。
- **is16bit, valid**：是否压缩、有效位。

PreDecode 将 IFetch 的 16 字节束拆成多条 16/32 位指令，按 `DEC_WIDTH`（4）路输出到 InstrDecoder。

### 2.2 D_UOp（译码输出）

定义见 `Include.sv` 中 `D_UOp`：

- **rs1, rs2, rd**：架构寄存器号（5 位）。
- **opcode**：内部操作码（如 INT_ADD、LSU_LW 等）。
- **fu**：功能单元（FuncUnit）：FU_INT、FU_BRANCH、FU_AGU、FU_MUL、FU_DIV、FU_CSR 等。
- **imm, imm12, immB**：立即数；immB 为 1 表示第二操作数用立即数。
- **fetchID, fetchOffs, compressed, valid**：取指/有效信息。

**InstrDecoder**（[src/InstrDecoder.sv](../../src/InstrDecoder.sv)）根据 RISC-V 的 opcode/funct3/funct7 等解析出上述字段，并处理 NOP、非法指令、解码时陷阱等。

### 2.3 R_UOp（重命名输出）

定义见 `Include.sv` 中 `R_UOp`：

- **tagA, tagB, tagC**：源操作数对应的物理寄存器 Tag；tagC 用于原子指令第三操作数。
- **availA, availB, availC**：对应 tag 是否已就绪（来自提交态或已写回）。
- **tagDst, rd**：目标物理 Tag 与架构 rd（提交时用）。
- **sqN**：序列号，用于 ROB 顺序与误预测废弃。
- **storeSqN, loadSqN**：在 StoreQueue / LoadBuffer 中的逻辑位置。
- **validIQ[NUM_PORTS_TOTAL]**：该 UOp 可进入哪些发射队列的掩码（多端口、多队列）。

**Rename**（[src/Rename.sv](../../src/Rename.sv)）对 D_UOp 做：
- 用 **RenameTable** 查 rs1/rs2 → specTag，并得到 avail（见下节）。
- 用 **TagBuffer** 分配新物理寄存器得到 tagDst。
- 递增 sqN、loadSqN、storeSqN；原子指令等会设置 tagC/availC。
- 输出 R_UOp 并配合 **Scheduler** 的 OUT_uopOrdering 决定进入哪几个 IssueQueue（validIQ）。

### 2.4 IS_UOp（发射输出）

定义见 `Include.sv` 中 `IS_UOp`：

- 与 R_UOp 相比**没有 rd、没有 validIQ、没有 tagC/availC**（原子指令的第三操作数在 StoreDataIQ 等路径单独处理）。
- 仍为 **tag + avail** 形式，**不携带操作数数值**；立即数在 imm/imm12 中。

**IssueQueue**（[src/IssueQueue.sv](../../src/IssueQueue.sv)）在队列内根据 tag 与写回/前递结果更新每条目的 avail；当所有操作数 avail 且满足 FU/顺序约束时，将该条 R_UOp 出队并输出为 **IS_UOp**（即“发射”）。

### 2.5 EX_UOp（执行级输入）

定义见 `Include.sv` 中 `EX_UOp`：

- **srcA, srcB**：32 位操作数**数值**（来自寄存器文件或前递）。
- **pc, fetchOffs, fetchStartOffs, fetchPredOffs**：PC 相关，供分支、异常。
- **imm**：立即数。
- **opcode, fu, tagDst, sqN, storeSqN, loadSqN, fetchID, bpi**：与 IS_UOp 一致或从 PCFile 补全。

**Load**（[src/Load.sv](../../src/Load.sv)）在发射后的下一拍：根据 IS_UOp 的 tagA/tagB 从 **寄存器文件** 或 **写回/前递总线** 取数，填成 srcA/srcB，并从 PCFile 取 PC/分支预测信息，得到 EX_UOp 送给各执行单元。

---

## 2.6 字段流转表

下表给出各 UOp 阶段中**关键字段的有无与来源**，便于对照代码与画图。

| 字段 / 概念 | PD_Instr | D_UOp | R_UOp | IS_UOp | EX_UOp |
|-------------|----------|-------|-------|--------|--------|
| **原始指令** | `instr`（32b） | — | — | — | — |
| **PC 相关** | `pc`, `fetchStartOffs`, `fetchPredOffs` | — | — | — | `pc`, `fetchOffs`, `fetchStartOffs`, `fetchPredOffs`（Load 从 PCFile 读回） |
| **取指标识** | `fetchID` | `fetchID`（透传） | `fetchID`（透传） | `fetchID`（透传） | `fetchID`（透传） |
| **指令内偏移** | — | `fetchOffs` | `fetchOffs` | `fetchOffs` | `fetchOffs` |
| **分支预测** | `predTarget`, `predTaken` | — | — | — | `bpi`（Load 从 PCFile 读回） |
| **源寄存器（架构）** | — | `rs1`, `rs2`（5b） | — | — | — |
| **源操作数（物理/tag）** | — | — | `tagA`, `tagB`, `tagC`（原子） | `tagA`, `tagB` | — |
| **源操作数就绪** | — | — | `availA`, `availB`, `availC` | `availA`, `availB`（IQ 内用，出队后不再需要） | — |
| **源操作数数值** | — | — | — | — | `srcA`, `srcB`（Load 级 RF + 前递得到） |
| **目标（架构）** | — | `rd`（5b） | `rd`（透传，提交用） | — | — |
| **目标（物理）** | — | — | `tagDst` | `tagDst` | `tagDst` |
| **立即数** | — | `imm`（32b）, `imm12`（jalr 等）, `immB` | `imm`, `imm12`, `immB` | `imm`, `imm12`, `immB` | `imm` |
| **操作码** | — | `opcode`（6b） | `opcode` | `opcode` | `opcode` |
| **功能单元** | — | `fu` | `fu` | `fu` | `fu` |
| **序列号** | — | — | `sqN` | `sqN` | `sqN` |
| **Store/Load 序号** | — | — | `storeSqN`, `loadSqN` | `storeSqN`, `loadSqN` | `storeSqN`, `loadSqN` |
| **压缩标志** | `is16bit` | `compressed` | `compressed` | `compressed` | `compressed` |
| **有效位** | `valid` | `valid` | `valid`, `validIQ[]`（各 IQ 端口） | `valid` | `valid` |
| **其它** | `fetchFault` | — | — | — | — |

**流转要点简述：**

- **rs1/rs2 → tagA/tagB**：在 Rename 中通过 RenameTable 查表得到；R_UOp 起只带 tag，不再带架构寄存器号（rd 保留供提交用）。
- **avail**：Rename 查表得到初值；IQ 内由写回/前递按 tag 匹配更新；出队为 IS_UOp 后不再传 avail，Load 级直接用 tag 读 RF/前递。
- **pc / bpi**：PD 阶段有 pc 与预测信息；D/R/IS 为省面积不存，只保留 fetchID；EX 阶段由 Load 用 fetchID 访问 PCFile 读回 pc 与 bpi。
- **srcA/srcB**：仅在 EX_UOp 出现，由 Load 根据 tagA/tagB 从 RF 或前递结果填写。

---

## 3. tag / avail 的依赖与就绪传播

本节讲清**依赖如何用 tag 表示、就绪如何用 avail 表示**，以及从 Rename 查表到 IssueQueue 内写回/前递匹配的**就绪传播路径**。

### 3.1 概念

- **Tag**：物理寄存器编号（或“无寄存器”的特殊编码，如 TAG_ZERO、立即数编码）。每条写寄存器的指令在重命名时被分配一个 tagDst；依赖该结果的指令的源用 tagA/tagB（及原子指令的 tagC）表示。
- **avail**：该 tag 对应的值是否“已就绪”。就绪即要么来自已提交的架构状态（RenameTable 中 comTag + tagAvail），要么来自本周期或之前某周期的写回/前递。

依赖关系：指令的源 tag 指向某条前序指令的 tagDst；当那条指令写回后，该 tag 变为就绪，依赖它的指令的 avail 被置位。

### 3.2 重命名阶段：RenameTable 查表与 TagBuffer 分配

**RenameTable**（[src/RenameTable.sv](../../src/RenameTable.sv)）维护：

- **specTag[rs1/rs2]**：当前推测的“该架构寄存器对应的物理 Tag”。
- **comTag**：已提交的映射（提交时从 ROB 写回）。
- **tagAvail**：每个物理 Tag 是否已就绪（写回时置位，新分配时清零）。

对每条 D_UOp 的 rs1/rs2：
- **OUT_lookupSpecTag** = specTag[rs1/rs2]；
- **OUT_lookupAvail** = tagAvail[该 tag] 或该 tag 为“特殊立即数”高位（如 TAG_ZERO 的 MSB），或本周期写回总线上有该 tag。

同一拍内多条指令按顺序：后面指令的查表会考虑本拍前面指令的 issue（IN_issueValid/IN_issueIDs/IN_issueTags），从而得到正确的新分配 tag 与 avail（见 RenameTable 中 “Later lookups are affected by previous ops” 的循环）。

**TagBuffer**（[src/TagBuffer.sv](../../src/TagBuffer.sv)）维护物理寄存器池的 **free/freeCom** 位图；重命名时从 free 中分配 tagDst，提交时根据 IN_commitNewest 与 IN_RAT_commitPrevTags 释放旧物理寄存器。

### 3.3 发射队列内：avail 的更新与就绪判断

**IssueQueue** 内部每条目存 **tags[]** 与 **avail[]**（以及 imm、sqN、fu 等）。就绪传播来源：

1. **入队时**：R_UOp 的 availA/availB 直接写入队列项的 avail。
2. **写回/前递**：每个周期 **IN_flagUOp**（即 ResultUOp/FlagsUOp）和 **IN_issueUOps**（本周期发射出去的 UOp）按 tag 匹配；若 queue[i].tags[k] == 某写回/发射 tag，则 **newAvail_c[0][i][k] = 1**（或对 MUL/FP 等延迟写回用 newAvail_c[1~4] 延迟若干拍）。
3. **queueAvail**：queue[i].avail | newAvail_c[*]，合并后用于判断该条目是否可发射。

可发射条件（简化）：**queueAvail 全为 1**，且 FU 空闲、load/store 顺序允许、CSR/SC 顺序等满足。满足则 deq 该条并输出为 IS_UOp。

**StoreDataIQ**（[src/StoreDataIQ.sv](../../src/StoreDataIQ.sv)）类似：只关心 store 数据源的一个 tag，根据 IN_flagUOp 与 IN_aguUOps（AGU 算出 store 地址后提供 storeSqN 等）更新 avail，并在就绪时把 store 数据 UOp 交给 **StoreDataLoad** 读寄存器或前递。

### 3.4 小结：就绪传播路径

| 阶段         | 谁产生/更新 avail                 | 谁消费 tag/avail              |
|--------------|-----------------------------------|-------------------------------|
| Rename       | RenameTable（查表）+ 本拍 WB      | R_UOp 的 availA/B/C            |
| IssueQueue   | IN_flagUOp、IN_issueUOps（前递）  | 队列内条目，决定是否发射      |
| Load         | 不更新 avail；用 tag 读 RF/前递   | 得到 srcA/srcB 数值 → EX_UOp  |

---

## 4. “发射后读操作数”的动机与代价

本节讲清为何采用**“先发射（只带 tag）、再在 Load 级读操作数数值”**的设计，以及由此带来的**收益（面积、前递集中）与代价（延迟、Load 复杂度、RF 端口）**。

### 4.1 设计：操作数在 Load 级才读

SoomRV 在 **IssueQueue 中只保存 tag（和 imm）**，不保存操作数数值。指令从队列**发射**后，在紧接着的 **Load** 级才：

- 用 tagA/tagB 去 **RFReadMux → RegFile** 读寄存器；
- 与 **IN_resultUOps**（写回）、**IN_zcFwd**（零周期前递）比较 tag，若匹配则用前递值代替 RF 读。

因此，**IS_UOp 仍只有 tag，EX_UOp 才有 srcA/srcB 数值**。

### 4.2 动机

1. **面积与功耗**：发射队列只存 tag（和 imm、sqN、fu 等），不存 32 位×2 的源操作数。队列深度×宽度×端口数较大时，省下的存储和端口可观的。
2. **前递逻辑集中**：前递只在 Load 一级做：比较 tag，选 RF 或某条写回/前递结果。若在 IQ 内保存数值，则每条写回都要广播到所有队列条目并更新，逻辑更复杂、时序更紧。
3. **与“tag 索引物理寄存器”一致**：全流水线用 tag 表示依赖；数值仅在“真正要用”的那一级（Load→Execute 边界）读取，语义清晰。

### 4.3 代价

1. **延迟**：从“发射”到“执行”至少多 **1 拍**（Load 级）。若执行单元本身多拍，总延迟 = 1 + 执行拍数。
2. **Load 级复杂度**：Load 要同时完成 RF 读、多路前递比较、PCFile 读；端口数与前递路数较多，可能成为关键路径。
3. **RF 读端口**：每周期需要 2×NUM_ALUS + NUM_AGUS 等读请求；**RFReadMux**（[src/RFReadMux.sv](../../src/RFReadMux.sv)）将“虚读端口”映射到更少的物理读端口（含复用以节省 RegFile 端口），可能带来冲突与 1 拍等待（store 数据路径的 StoreDataLoad 同样通过 RF 读端口取数）。

文档中“load after issue”即指：**先按 tag 在队列里等就绪并发射，再在 Load 级按 tag 读 RF/前递得到数值**；这是典型的“tag-based OoO、issue 时只带 tag”的设计取舍。

---

## 5. 相关模块与代码索引

| 模块 | 文件 | 作用简述 |
|------|------|----------|
| InstrDecoder | [src/InstrDecoder.sv](../../src/InstrDecoder.sv) | PD_Instr → D_UOp |
| Rename | [src/Rename.sv](../../src/Rename.sv) | D_UOp → R_UOp；调 RenameTable、TagBuffer、Scheduler |
| RenameTable | [src/RenameTable.sv](../../src/RenameTable.sv) | 架构寄存器→物理 tag 查表，tagAvail 维护 |
| TagBuffer | [src/TagBuffer.sv](../../src/TagBuffer.sv) | 物理寄存器分配/释放 |
| Scheduler | [src/Scheduler.sv](../../src/Scheduler.sv) | 为 D_UOp 分配端口顺序 OUT_order，供 Rename 填 validIQ |
| IssueQueue | [src/IssueQueue.sv](../../src/IssueQueue.sv) | 存 R_UOp（tag+avail），就绪则输出 IS_UOp |
| StoreDataIQ | [src/StoreDataIQ.sv](../../src/StoreDataIQ.sv) | store 数据源 tag 的队列，就绪后交给 StoreDataLoad |
| StoreDataLoad | [src/StoreDataLoad.sv](../../src/StoreDataLoad.sv) | 按 tag 读 RF/前递，得到 store 数据与偏移 |
| Load | [src/Load.sv](../../src/Load.sv) | IS_UOp → EX_UOp：RF + 前递 + PCFile |
| RFReadMux | [src/RFReadMux.sv](../../src/RFReadMux.sv) | 虚读端口→物理读端口，复用以减少 RegFile 端口 |
| RegFile | [src/RegFileRTL.sv](../../src/RegFileRTL.sv) | 物理寄存器堆，多读多写 |

以上内容覆盖任务单 B 要求：**PD_Instr→D_UOp→R_UOp→IS_UOp→EX_UOp** 的流程、**tag/avail** 的依赖与就绪传播、以及**发射后读操作数**的动机与代价；可直接作为 PPT 与组内报告的文档基础，并据此在代码中做针对性优化（如 RF 端口与 Load 前递路径的平衡、StoreDataIQ/StoreDataLoad 的延迟与面积等）。
