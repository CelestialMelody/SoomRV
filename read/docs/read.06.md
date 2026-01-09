`src/Core.sv` 是 SoomRV 处理器的**顶层核心模块**。如果把 CPU 比作一台复杂的机器，`Config.sv` 是规格说明书，`Include.sv` 是零件字典，而 `Core.sv` 就是**总装配图**。

在这个文件中，你看不到具体的加法或乘法逻辑，但你能看到所有子模块（取指、解码、重命名、ALU、ROB 等）是如何被实例化并物理连接在一起的。

以下是 `Core.sv` 的**数据流向导读**，我们将沿着指令的生命周期，从上到下梳理各个模块的连接。

---

### 1. 顶层接口 (Ports & Interfaces)

`Core` 模块对外暴露了处理器核心与外界交互的“触角”：

* **指令/数据 Cache 接口** (`IF_Cache`, `IF_ICache`, `IF_CTable`...): 连接到 SRAM。
* **MMIO 接口** (`IF_MMIO`): 连接到外设总线。
* **内存控制器接口** (`OUT_memc`): 发送 Cache Miss 请求到主存控制器。
* **中断信号** (`IN_irq`): 外部中断输入。

---

### 2. 前端：取指与预解码 (Frontend)

指令的旅程从这里开始。

#### 实例化模块：`IFetch`

```systemverilog
IFetch ifetch
(
    .clk(clk), .rst(rst),
    .IN_branch(BP_branch),        // 接收后端的分支纠正信号 (Branch Misprediction)
    .IN_stall(IF_stall),          // 前端停顿信号
    .OUT_instrs(IF_instrs),       // 【关键输出】取到的指令包 (128-bit)
    // ... 连接 Cache 接口 ...
);

```

* **关键数据流：** `IF_instrs` (类型 `IF_Instr`)。这是我们在 `Include.sv` 里看过的原始指令包。
* **逻辑：** `IFetch` 负责操作 I-Cache，根据分支预测器（内部集成）生成的 PC 抓取指令。

#### 实例化模块：`InstrDecoder`

```systemverilog
InstrDecoder dec
(
    .IN_instrs(IF_instrs),        // 【关键输入】来自 IFetch 的指令包
    .OUT_uop(DEC_uop),            // 【关键输出】解码后的微操作 (D_UOp)
    // ...
);

```

* **关键数据流：** `IF_instrs` -> `DEC_uop`。
* **变化：** 原始的 0101 比特流在这里变成了 `D_UOp` 结构体（包含 `opcode`, `rs1`, `rd` 等逻辑寄存器号）。

---

### 3. 乱序引擎入口：重命名 (Renaming)

这是处理器从“有序”进入“乱序”的边界。

#### 实例化模块：`Rename`

```systemverilog
Rename rename
(
    .IN_uop(DEC_uop),             // 【关键输入】解码后的 UOp
    .OUT_uop(RN_uop),             // 【关键输出】重命名后的 UOp (R_UOp)
    .OUT_stall(RN_stall),         // 如果物理寄存器不够，发出停顿
    // ... 连接 RenameTable 和 ROB ...
);

```

* **关键数据流：** `DEC_uop` -> `RN_uop`。
* **变化：** 逻辑寄存器 (`x1`) 被替换为物理 Tag (`p15`)。指令被分配了 `sqN` (序列号)。

---

### 4. 调度与发射 (Issue Queues)

指令带着 Tag 进入发射队列排队。`Core.sv` 中实例化了多个 `IssueQueue`，分别对应不同的端口。

```systemverilog
// 对应 Config.sv 中的端口定义
IssueQueue#(.SIZE(PORT_IQ_SIZE[0]), .PORT_IDX(0), ...) iq0 ( ... ); // AGU Port
IssueQueue#(.SIZE(PORT_IQ_SIZE[1]), .PORT_IDX(1), ...) iq1 ( ... ); // AGU Port
IssueQueue#(.SIZE(PORT_IQ_SIZE[2]), .PORT_IDX(2), ...) iq2 ( ... ); // ALU Port
// ... iq3, iq4 ...

```

* **输入：** `RN_uop` (来自 Rename)。
* **输出：** `IS_uop` (发射微操作)。当操作数准备好时，队列将其弹出。

---

### 5. 寄存器读取与执行 (RegRead & Execute)

这是流水线最宽的地方（4-wide）。

#### 实例化模块：`RegFileRTL` (物理寄存器堆)

```systemverilog
RegFileRTL rf
(
    .IN_read(rfReadReqs),         // 来自 IssueQueue 的读取请求 (Tag)
    .OUT_src(rfReadData),         // 【关键输出】读出的 32位 源数据
    .IN_write(wbUOps)             // 写回数据 (来自 ALU/LSU 结果)
);

```

#### 实例化模块：执行单元 (`IntALU`, `AGU` 等)

读取到数据后，组装成 `EX_UOp` 送入执行单元。

```systemverilog
IntALU#(.PORT_IDX(2)) alu2
(
    .IN_uop(EX_uop[2]),           // 【关键输入】包含真实数据的 UOp
    .OUT_uop(RES_uop[2])          // 【关键输出】计算结果 (ResultUOp)
);
// ... alu3, alu4, agu0, agu1 ...

```

---

### 6. 内存子系统 (Memory Subsystem)

处理 Load/Store 指令的复杂逻辑。

#### 实例化模块：`LoadStoreUnit`

```systemverilog
LoadStoreUnit lsu
(
    .IN_agu(AGU_uop),             // 来自 AGU 的地址计算结果
    .IN_stData(SQ_stDataUOp),     // 来自 StoreData 单元的写数据
    .OUT_ldAck(LSU_ldAck),        // Load 完成确认
    // ... 连接 D-Cache ...
);

```

* 这里还连接了 `StoreQueue` 和 `LoadBuffer`，用于处理乱序访存的一致性。

---

### 7. 提交与恢复 (Commit & Recovery)

这是指令生命的终点。

#### 实例化模块：`ROB` (重排序缓冲区)

```systemverilog
ROB rob
(
    .IN_uop(RN_uop),              // 在 Rename 阶段就分配条目
    .IN_branch(branch),           // 【关键信号】分支误预测信号
    .OUT_comUOp(comUOps),         // 【关键输出】提交的指令 (告诉 RAT 锁定映射)
    .OUT_mispredFlush(mispredFlush) // 触发流水线刷新
);

```

* **核心逻辑：** 如果 `IN_branch` 报错，ROB 会触发 `mispredFlush`，你可以看到这个信号连接到了 `IFetch`、`Rename`、`IssueQueue` 等几乎所有模块，用于一键清空流水线。

---

### 总结：`Core.sv` 阅读技巧

1. **不要看逻辑，看连线：** 忽略 `always` 块中的胶水逻辑，专注于 `module instantiation`（模块实例化）。
2. **追踪 `UOp` 的变身：** 在文件中搜索 `_uop` 变量，你会清晰地看到 `DEC_uop` -> `RN_uop` -> `IS_uop` -> `EX_uop` 的变量名变化，这就是数据流。
3. **关注反压信号 (Backpressure)：** 搜索 `stall` 或 `full`。你会看到下游模块（如 `IssueQueue`）如何告诉上游（`Rename`）“我满了，别发了”，从而实现流水线流控。