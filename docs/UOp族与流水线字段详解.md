# UOp 族与流水线各阶段字段详解

本文结合 `src/Include.sv` 中的定义，说明一条指令在 SoomRV 中如何以不同 UOp 形态流经各阶段，以及各阶段用到的关键字段（pc、fetchID、sqN、tagDst、loadSqN/storeSqN 等）。

---

## 一、基础类型（先搞清楚“语言”）

在理解 UOp 之前，先弄清 `Include.sv` 里这些贯穿各阶段的基础类型（约 1–20 行及配置相关）：

| 类型 | 含义 | 典型用途 |
|------|------|----------|
| `RegNm` | 5 位，架构寄存器编号 (x0–x31) | rd / rs1 / rs2 |
| `Tag` | 物理寄存器/结果标签，`RF_SIZE_EXP+1` 位 | 重命名后的“目标/源”标识，写回与转发匹配 |
| `RFTag` | 同上但少 1 位，实际索引用 | RegFile/TagBuffer 索引 |
| `SqN` | 序列号，`ROB_SIZE_EXP+1` 位 | 程序顺序、mispred 时比较“先后”、提交顺序 |
| `FetchID_t` | 取指包 ID | 同一次取指的一批指令共享，用于 flush/恢复 |
| `FetchOff_t` | 该包内指令偏移 | 定位到具体一条指令（含 16/32 位边界） |
| `FuncUnit` | 功能单元枚举 (FU_INT, FU_BRANCH, FU_AGU, …) | 决定进哪个 IssueQueue、哪个 FU 执行 |

`TAG_ZERO` 表示“常 0”，对应 x0，不参与重命名写回。

---

## 二、UOp 在流水线中的流向（总览）

```
 取指                预解码/对齐           解码              重命名              发射              读操作数/执行
 (Fetch)             (Align)              (Decode)
 IF_Instr     →      PD_Instr        →    D_UOp → R_UOp → IS_UOp → EX_UOp → (各 FU)
 ↑                        ↑                      ↓                ↓         ↓
 I-Cache/ITLB          InstrAligner           RenameTable      IssueQueue   Load (读 RegFile/PC/forward)
 等                    指令边界、单条切分            ↓                ↓         ↓
                                                    ROB 入口        就绪即出队   AGU → AGU_UOp → ...
                                                                                  IntALU/Mul/Div/FPU → RES_UOp
                                                                                  Store 数据路径 → SQ_UOp → ST_UOp
```

**取指与预解码是否有先后顺序？为什么图中常写在一起？**

- **有先后顺序**：流水线中**先取指、再预解码**。  
  - **取指**：从 I-Cache/ITLB 得到一包原始数据（若干 16 位半字），输出为 **IF_Instr**（见 `Include.sv` 第 532–544 行）。其中：**FETCH_WORDS**（`Config.sv` 第 19 行：`1<<(FSIZE_E-1)`，默认 8）表示一包内半字个数，即 `instrs[FETCH_WORDS-1:0][15:0]` 为 8 个 16 位半字；**fetchID**（类型 `FetchID_t`，`Include.sv` 第 6 行，5 位）为本包取指的唯一 ID，用于 flush/恢复时区分不同取指包；**firstValid**、**lastValid**（类型 `FetchOff_t`，`Include.sv` 第 7 行，约 3 位）为本包内**有效半字的起、止下标**（0 到 FETCH_WORDS-1），即只有 `instrs[firstValid]..instrs[lastValid]` 有效，其余可能因边界或 stall 未填。  
  - **预解码/对齐**：把一包 **IF_Instr** 按 RISC-V 的 16/32 位边界切成**一条条指令**，每条对应一个 **PD_Instr**（见 `Include.sv` 第 546–556 行：单条指令 `instr`、`pc`、`fetchStartOffs`、`fetchID`、`fetchFault` 等）。  
- **代码中的顺序**：  
  - 取指在 **IFetchPipeline**（在 IFetch 内部）中完成，得到 **IF_Instr**（如 `IFetchPipeline.sv` 中的 `packet`、经 FIFO 后的 `FIFO_out`）。  
  - **InstrAligner** 的输入是 **IF_Instr**（`InstrAligner.sv` 第 17 行 `input IF_Instr IN_op`），输出是 **PD_Instr**（第 20 行 `output PD_Instr OUT_instr[NUM_INSTRS-1:0]`）；即「IF_Instr → InstrAligner → PD_Instr」。  
  - **InstrDecoder** 的输入是 **PD_Instr**（`InstrDecoder.sv` 第 205 行），输出是 **D_UOp**。  
  因此数据流是：**取指(IF_Instr) → 预解码/对齐(PD_Instr) → 解码(D_UOp)**。
- **为什么常写在一起**：在“阶段级”总览里，解码阶段（D_UOp）的**直接输入**是 **PD_Instr**，而 PD_Instr 是「取指 + 预解码」整段前端流水线的**最终输出**；中间形态 IF_Instr 只在前端内部使用。因此图中常把「取指/预解码」合并为一段，用「IF_Instr/PD_Instr」表示：前者是这段的中间格式，后者是这段对外的输出，一起指向解码阶段。

- **D_UOp**：解码器输出，仍是“架构寄存器名”（rd/rs1/rs2）+ 立即数 + opcode/fu。
- **R_UOp**：重命名后，有了 **tagDst/tagA/tagB**、**sqN**、**storeSqN/loadSqN**，进入 ROB 和各个 IssueQueue。其中 **sqN** 为全局程序顺序序列号（每指令唯一，用于 ROB 排序与 mispred 比较）；**storeSqN** 表示「到本条为止的 store 计数」、**loadSqN** 表示「到本条为止的 load 计数」，用于 load/store 顺序与 LoadBuffer/StoreQueue 容量检查；详见 `docs/名词解释.md` 中「sqN、storeSqN、loadSqN」。
- **IS_UOp**：从某个 IssueQueue 被选中发射的 uop，仍是“tag 版”操作数：**tagA/tagB** 表示第一/第二源操作数依赖的物理 tag（rs1→tagA，rs2→tagB），**availA/availB** 表示该操作数是否已就绪（1=可从前递或 RegFile 取到值）；只有 avail 全为 1 的条目才会被发射，Load 阶段用 tagA/tagB 查 forward 或 RegFile 得到 srcA/srcB。详见 `docs/名词解释.md` 中「availA/tagA、availB/tagB」。
- **EX_UOp**：Load 阶段读 RegFile + **forward**（数据前递/旁路）后得到**真实 srcA/srcB/pc**，送入 ALU/**AGU** 等。**AGU**（Address Generation Unit，地址生成单元）负责 Load/Store 的地址计算（如 addr=srcA+srcB）、访问宽度与 DTLB 翻译，输出 **AGU_UOp** 给 LoadBuffer/StoreQueue；详见 `docs/名词解释.md` 中「AGU」与「forward（前递/旁路）」。
- **AGU_UOp**：AGU 算完地址（含 TLB）后的访存请求；Load 路径再变成 **LD_UOp** 进 LoadBuffer/**LSU**，Store 路径经 StoreQueue 成 **SQ_UOp** 再成 **ST_UOp**，由 **LSU** 写 **D-Cache** 或 **MMIO**。**LSU**（Load Store Unit）是执行实际访存的模块（读/写 D-Cache，未命中访问内存；**MMIO** 为内存映射 I/O，访问设备寄存器不经过 cache，走 BypassLSU）；详见 `docs/名词解释.md` 中「LSU」「MMIO」。

下面按阶段列出各 UOp 的字段及含义。

---

## 三、D_UOp（解码阶段）

**定义位置**：`Include.sv` 约 561–586 行。

```systemverilog
typedef struct packed
{
    logic[31:0] imm;
    logic[11:0] imm12;   // only used for jalr
    logic[4:0] rs1;
    logic[4:0] rs2;
    logic immB;          // imm from B-type
    logic[4:0] rd;
    logic[5:0] opcode;
    FuncUnit fu;
    FetchID_t fetchID;
    FetchOff_t fetchOffs;
    logic compressed;
    logic valid;
} D_UOp;
```

| 字段 | 含义 |
|------|------|
| **rs1, rs2, rd** | 架构寄存器编号，解码器从指令中解析。 |
| **imm / imm12 / immB** | 立即数（不同编码格式）；jalr 用 imm12。 |
| **opcode** | 内部 opcode 枚举（如 INT_ADD, BR_JAL, LSU_LW 等），不是 ISA 的 opcode。 |
| **fu** | 功能单元，决定进哪类 IssueQueue（整数/分支/AGU/乘除/FP 等）。 |
| **fetchID, fetchOffs** | 来自取指包，用于定位指令、异常时报告 PC、分支恢复时 flush。 |
| **compressed** | 是否为 16 位压缩指令。 |
| **valid** | 该槽是否有效（解码宽度内可能不足 4 条）。 |

**谁产生**：`InstrDecoder.sv` 由 `PD_Instr` 生成 `D_UOp`。  
**谁消费**：`Rename.sv` 读 D_UOp，写 ROB 入口并生成 R_UOp；`Scheduler.sv` 也看到 D_UOp（调度/背压）。

此阶段**还没有** tag、sqN、storeSqN、loadSqN；这些都在重命名阶段才出现。

---

## 四、R_UOp（重命名阶段）

**定义位置**：`Include.sv` 约 588–611 行。

```systemverilog
typedef struct packed
{
    logic[31:0] imm;
    logic[11:0] imm12;
    logic availA;
    Tag tagA;
    logic availB;
    Tag tagB;
    logic immB;
    logic availC;
    Tag tagC;        // used for atomics
    SqN sqN;
    Tag tagDst;
    RegNm rd;
    logic[5:0] opcode;
    FetchID_t fetchID;
    FetchOff_t fetchOffs;
    SqN storeSqN;
    SqN loadSqN;
    FuncUnit fu;
    logic compressed;
    logic[NUM_PORTS_TOTAL-1:0] validIQ;  // 进哪些 IQ 的 valid
    logic valid;
} R_UOp;
```

| 字段 | 含义 |
|------|------|
| **tagDst** | 本指令写回结果对应的物理 tag，由 Rename 分配；提交前该 tag 代表“这条指令的结果”。 |
| **tagA, tagB, tagC** | 操作数来源的物理 tag：rs1→tagA，rs2→tagB，原子指令等用 tagC。来自 RenameTable 查表（D_UOp 的 rs1/rs2）。 |
| **availA, availB, availC** | 该操作数是否已就绪（已提交或已写回）。若就绪，IssueQueue 可立即用；否则等 tag 写回。 |
| **sqN** | 本指令的序列号，全局顺序唯一。用于：ROB 排序、mispred 时比较“是否在错误路径上”、提交顺序。 |
| **storeSqN** | “最近已分配 store 的 sqN”。Load 用：若 loadSqN ≤ storeSqN，需考虑与前面 store 的顺序/依赖。 |
| **loadSqN** | “最近已分配 load 的 sqN”。Store 用：保证 store 在程序顺序上晚于该 load。 |
| **rd** | 仍保留架构 rd，提交时写回架构寄存器文件、释放 tag。 |
| **fetchID, fetchOffs** | 与 D_UOp 一致，贯穿到提交/异常。 |
| **validIQ** | 每一位表示该 uop 是否进入对应 IssueQueue（多端口可能进多个 IQ）。 |

**谁产生**：`Rename.sv` 根据 D_UOp + RenameTable 分配 tag、查 rs1/rs2 的 tag、分配 sqN、维护 storeSqN/loadSqN。  
**谁消费**：`ROB.sv` 入队用 R_UOp；各 `IssueQueue.sv` 入队用 R_UOp；StoreQueue 等用 R_UOp 的 storeSqN/loadSqN。

这里已经把“指令级并行”和“乱序”的基础铺好：依赖用 **tag** 表示，顺序用 **sqN** 表示。

---

## 五、IS_UOp（发射阶段，从 IssueQueue 选出）

**定义位置**：`Include.sv` 约 613–632 行。

```systemverilog
typedef struct packed
{
    logic[31:0] imm;
    logic[11:0] imm12;
    logic availA;
    Tag tagA;
    logic availB;
    Tag tagB;
    logic immB;
    SqN sqN;
    Tag tagDst;
    logic[5:0] opcode;
    FetchID_t fetchID;
    FetchOff_t fetchOffs;
    SqN storeSqN;
    SqN loadSqN;
    FuncUnit fu;
    logic compressed;
    logic valid;
} IS_UOp;
```

与 R_UOp 相比，IS_UOp **去掉了** rd、imm12 的“多份”、availC/tagC、validIQ；**保留了** 所有 tag、sqN、storeSqN、loadSqN、fetchID、fetchOffs。也就是说，发射时仍只带“标签”，不带实际寄存器值。

| 字段 | 含义 |
|------|------|
| **tagA, tagB** | 源操作数 tag，下一阶段（Load）用它们去 RegFile/TagBuffer/forward 取真实值。 |
| **availA, availB** | 就绪位，发射时已为 1（否则不会从 IQ 被选中）。 |
| **sqN, storeSqN, loadSqN** | 继续传到执行与访存，用于 load/store 顺序、mispred 比较。 |
| **tagDst** | 本 uop 写回时写哪个 tag，用于写回与转发。 |

**谁产生**：各 `IssueQueue.sv` 在“操作数就绪 + FU 可用”时输出 IS_UOp。  
**谁消费**：`Load.sv` 把 IS_UOp 转成 EX_UOp（读 RegFile、PCFile、forward）。

---

## 六、EX_UOp（执行阶段入口：已有真实操作数）

**定义位置**：`Include.sv` 约 655–680 行。

```systemverilog
typedef struct packed
{
    logic[31:0] srcA;
    logic[31:0] srcB;
    logic[31:0] pc;
    FetchOff_t fetchOffs;
    FetchOff_t fetchStartOffs;
    FetchOff_t fetchPredOffs;
    logic[31:0] imm;
    logic[5:0] opcode;
    Tag tagDst;
    SqN sqN;
    FetchID_t fetchID;
    BranchPredInfo bpi;
    SqN storeSqN;
    SqN loadSqN;
    FuncUnit fu;
    logic compressed;
    logic valid;
} EX_UOp;
```

| 字段 | 含义 |
|------|------|
| **srcA, srcB** | 真实操作数。Load 阶段用 tagA/tagB 从 RegFile + forward 读出，或来自立即数。 |
| **pc** | 当前指令 PC，从 PCFile 用 fetchID/fetchOffs 取；分支、异常、BP 更新要用。 |
| **fetchOffs, fetchStartOffs, fetchPredOffs** | 取指包内半字偏移：fetchOffs=本条当前/最后半字，fetchStartOffs=本条起始半字，fetchPredOffs=预测器记录的分支位置；用于拼 PC、BTUpdate、mispred 判定。详见 `docs/名词解释.md`「fetchOffs、fetchStartOffs、fetchPredOffs 与 bpi」。 |
| **bpi** | 分支方向预测（BranchPredInfo，仅 taken 一位）；取指阶段预测的跳/不跳，执行时与实际结果比较。详见同上。 |
| **tagDst, sqN, storeSqN, loadSqN** | 继续向下传递：写回用 tagDst；顺序与依赖用 sqN/storeSqN/loadSqN。 |

**谁产生**：`Load.sv` 由 IS_UOp + RegFile + forward + PCFile 生成 EX_UOp。  
**谁消费**：`IntALU.sv`、`AGU.sv`、`Multiply.sv`、`Divide.sv`、`FPU.sv` 等所有功能单元；AGU 再产出 AGU_UOp。

---

## 七、AGU_UOp（地址生成与 TLB 之后）

**定义位置**：`Include.sv` 约 709–737 行。

```systemverilog
typedef struct packed
{
    logic[31:0] addr;
    logic[3:0] wmask;
    logic signExtend;
    logic[1:0] size;
    logic isStore;
    logic isLoad;
    logic isLrSc;
    logic earlyLoadFailed;
    Tag tagDst;
    SqN sqN;
    SqN storeSqN;
    SqN loadSqN;
    FetchOff_t fetchOffs;
    FetchID_t fetchID;
    logic doNotCommit;
    logic compressed;
    logic valid;
} AGU_UOp;
```

| 字段 | 含义 |
|------|------|
| **addr** | 已计算好的虚地址（AGU 用 srcA+imm 等算完，且可能已过 TLB 得到物理地址，视实现而定）。 |
| **wmask, size, signExtend** | **wmask**：Store 的按字节写掩码（4 位，wmask[i]=1 表示写第 i 字节；SB/SH/SW 对应 1/2/4 位为 1）。**size**：访问宽度（0/1/2=byte/halfword/word）；**signExtend**：Load 是否符号扩展。详见 `docs/名词解释.md`「wmask」。 |
| **isStore, isLoad, isLrSc** | 访存类型：isStore/isLoad 表示 Store/Load；**isLrSc** 表示本条为 **LR**（Load Reserved）或 **SC**（Store Conditional），用于无锁原子对，LoadBuffer 据此做保留跟踪与 SC 失败处理。详见 `docs/名词解释.md`「isLrSc / LR-SC」。 |
| **tagDst, sqN, storeSqN, loadSqN** | 继续传给 LoadBuffer/StoreQueue：写回用 tagDst，顺序与冲突检测用 sqN/storeSqN/loadSqN。 |
| **fetchID, fetchOffs** | 异常、trap 时定位指令。 |
| **doNotCommit** | 本 uop 不参与提交（如 speculative 失败、重放）。 |

**谁产生**：`AGU.sv` 由 EX_UOp 计算地址并做 TLB 查询后输出。  
**谁消费**：Load 路径 → `LoadBuffer.sv` → 转为 LD_UOp 进 LSU；Store 路径 → `StoreQueue.sv`；预取等见 `DataPrefetch.sv`。

---

## 八、LD_UOp（进入 LoadBuffer / LSU 的 Load 请求）

**定义位置**：`Include.sv` 约 818–834 行。

```systemverilog
typedef struct packed
{
    logic[31:0] data;
    logic dataValid;
    logic[31:0] addr;
    logic signExtend;
    logic[1:0] size;
    SqN storeSqN;
    SqN loadSqN;
    Tag tagDst;
    SqN sqN;
    logic atomic;
    logic doNotCommit;
    logic external;
    logic isMMIO;
    logic valid;
} LD_UOp;
```

| 字段 | 含义 |
|------|------|
| **addr, size, signExtend** | 与 AGU_UOp 一致，LSU 用其访问 D-Cache 或 MMIO。 |
| **data, dataValid** | 若在 LoadBuffer/StoreQueue 里从 store 转发得到数据，则直接带 data；否则由 LSU 读 cache 后填。 |
| **tagDst, sqN** | 写回时写哪个 tag、ROB 中哪条指令完成。 |
| **storeSqN, loadSqN** | Load 与前面 Store 的顺序、冲突检测（LoadBuffer 内会用到）。 |
| **atomic, isMMIO, external** | 原子、MMIO、外部访问等特殊路径。 |

**来源**：多路汇总（AGU 的 Load 出 LoadBuffer、Store 转发、PageWalk 等）在 `LoadStoreUnit.sv` 中选成最终的 LD_UOp。

---

## 九、SQ_UOp（Store 数据与地址就绪，准备写 Cache/MMIO）

**定义位置**：`Include.sv` 约 865–899 行。

```systemverilog
typedef struct packed
{
    RegT data;
    logic[31:0] addr;
    logic[3:0] wmask;
    logic isMgmt;
    logic valid;
} SQ_UOp;
```

| 字段 | 含义 |
|------|------|
| **data** | Store 要写的值（来自 StoreDataIQ/StoreDataLoad 等）。 |
| **addr, wmask** | 地址与字节掩码，与 AGU 算出的结果一致。 |
| **isMgmt** | 是否为 cache 管理类（如 CBO.inval）。 |

SQ_UOp 是“已可写”的 store 形态，再往后会变成 **ST_UOp** 等与 MemoryController/MMIO 的接口。Store 的 **sqN/storeSqN/loadSqN** 在 StoreQueue/StoreQueueBackend 内部维护，用于顺序与提交。

---

## 十、关键字段在各阶段的出现与传递

| 字段 | D_UOp | R_UOp | IS_UOp | EX_UOp | AGU_UOp | LD_UOp | SQ_UOp |
|------|-------|-------|--------|--------|---------|--------|--------|
| **pc** | — | — | — | ✓ | — | — | — |
| **fetchID** | ✓ | ✓ | ✓ | ✓ | ✓ | — | — |
| **fetchOffs** | ✓ | ✓ | ✓ | ✓ | ✓ | — | — |
| **sqN** | — | ✓ | ✓ | ✓ | ✓ | ✓ | (内部) |
| **tagDst** | — | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| **tagA/tagB** | — | ✓(tagA/B) | ✓ | —(已变 srcA/B) | — | — | — |
| **storeSqN** | — | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| **loadSqN** | — | ✓ | ✓ | ✓ | ✓ | ✓ | — |
| **rd** | ✓(rd) | ✓ | — | — | — | — | — |
| **opcode** | ✓ | ✓ | ✓ | ✓ | — | — | — |

- **pc**：只在执行阶段需要（分支、异常、BP），由 PCFile 根据 fetchID/fetchOffs 提供，故仅 EX_UOp 有。
- **fetchID/fetchOffs**：从解码一直传到 AGU，用于异常、flush、BP 更新。
- **sqN**：从重命名开始贯穿到完成/提交，用于顺序、mispred 比较、ROB 提交。
- **tagDst**：重命名分配后一直传到写回；**tagA/tagB** 在 Load 阶段被解析成 **srcA/srcB**，故 EX_UOp 及之后不再带 tagA/B。
- **storeSqN/loadSqN**：在 R_UOp 由 Rename 分配后，一路传到 LoadBuffer/StoreQueue，用于 load-store 顺序与冲突检测。

---

## 十一、小结：按“阶段”记

1. **D_UOp**：架构寄存器名 + imm + opcode/fu + fetchID/fetchOffs，无 tag、无 sqN。  
2. **R_UOp**：加上 tagDst、tagA/tagB、sqN、storeSqN、loadSqN，进入 ROB 与各 IQ。  
3. **IS_UOp**：从 IQ 出来的“tag 版” uop，仍无实际操作数值。  
4. **EX_UOp**：已有 srcA/srcB/pc，进入各 FU；仍带 tagDst、sqN、storeSqN、loadSqN。  
5. **AGU_UOp**：地址 + 访存类型 + tagDst/sqN/storeSqN/loadSqN，分发给 LoadBuffer/StoreQueue。  
6. **LD_UOp**：Load 请求的最终形态，带地址/数据/tagDst/sqN/storeSqN/loadSqN。  
7. **SQ_UOp**：Store 数据与地址就绪，准备写 Cache/MMIO。

结合 `Include.sv` 中上述行号对照阅读，即可把“每条指令在各阶段用哪些字段”和代码一一对应起来。
