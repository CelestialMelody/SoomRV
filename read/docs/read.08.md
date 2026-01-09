这是对 SoomRV 乱序执行引擎核心部分——**重命名（Renaming）** 模块的深度解析。

这两个文件 (`Rename.sv` 和 `RenameTable.sv`) 共同完成了将程序员眼中的**逻辑寄存器 (x1-x31)** 转换为硬件使用的**物理寄存器标签 (Tag)** 的工作，从而消除了 Write-after-Write (WAW) 和 Write-after-Read (WAR) 伪相关，释放了指令级并行度。

---

### 1. `RenameTable.sv`: 寄存器别名表 (RAT)

这是处理器的“地图”。它负责记录当前 `x1` 到底对应哪个物理寄存器 `Tag`。

#### **核心数据结构**

它维护了三套关键状态：

1. **`specTag` (Speculative Map)**:
* **作用：** 记录**最新**的寄存器映射（推测状态）。前端发射指令时查这张表。
* **更新：** 每当有指令发射（Issue）并写入寄存器时更新。


2. **`comTag` (Committed Map)**:
* **作用：** 记录**已确认**的寄存器映射（退休状态）。只有指令在 ROB 中安全退休时才更新。
* **用途：** **作为“存档点”**。当分支预测失败时，处理器会把 `specTag` 重置为 `comTag`，瞬间撤销所有错误路径上的修改。


3. **`tagAvail` (Availability Scoreboard)**:
* **作用：** 记录每个物理 Tag 的数据是否**就绪**。
* **逻辑：**
* **分配时 (Issue):** 设为 `0`（忙碌，数据正在计算中）。
* **写回时 (Writeback):** 设为 `1`（就绪，数据已算出）。


* **意义：** 这就是为什么 `R_UOp` 里有 `avail` 位。后续指令根据这个位决定是直接去读寄存器，还是去 IssueQueue 排队等广播。



#### **关键逻辑：错误恢复 (Recovery)**

```systemverilog
if (IN_mispredFlush) begin
    // 发生误预测！紧急回滚
    for (integer i = 1; i < NUM_REGS; i=i+1) begin
        // 将推测状态重置为已提交状态 (Arch State)
        specTag[i] <= comTag[i];
    end
end

```

SoomRV 采用的是 **"Walkback" (回滚到提交态)** 策略。这比某些架构的 Checkpoint 机制更节省面积，但恢复惩罚稍大（需要重放 ROB 中正确的指令来重建状态，虽然代码中主要展示了重置部分，但 SoomRV 文档提到有重放机制）。

---

### 2. `Rename.sv`: 重命名流水级 (The Stage)

这是流水线中的物理模块，它协调 `RAT` 和 `TagBuffer`（空闲列表）来处理指令包。

#### **内部子模块**

* **`RenameTable rat`**: 刚刚分析的映射表。
* **`TagBuffer tagBuf`**: **空闲物理标签池 (Free List)**。它像一个 FIFO，存储着当前没被使用的物理 Tag。每当需要写寄存器，就从这里 `pop` 一个 Tag；当指令提交覆盖了旧 Tag，旧 Tag 就会被 `push` 回去。

#### **核心处理流程 (Per Cycle)**

对于输入的 4 条解码指令 (`IN_uop[0..3]`)，`Rename` 模块在一个周期内并行完成以下操作：

1. **查表 (Lookup):**
* 将所有指令的源寄存器 (`rs1`, `rs2`) 送入 `rat`，获取它们目前对应的 Tag。


2. **分配新标签 (Allocation):**
* 统计这 4 条指令中有几条需要写寄存器。
* 向 `tagBuf` 请求对应数量的新 Tag (`newTags`)。
* 如果有指令写 `x0`，则强制分配特殊的 `TAG_ZERO`，不消耗物理资源。


3. **组内依赖检查 (Intra-group Dependency Check) —— 最烧脑的部分**
* **问题：** 在同一个取指包中，如果指令 2 依赖指令 1 的结果（例如：`ADD x1, ...` 然后 `SUB ..., x1`），此时指令 1 还没写入 RAT，指令 2 查 RAT 会查到旧的 Tag。
* **解决：** 代码中包含一个复杂的组合逻辑循环，进行**旁路 (Forwarding)**。
* **逻辑：**
```systemverilog
// 伪代码逻辑
Tag sourceTag = rat_lookup_result; // 默认查表结果
// 检查前面的指令是否写入了我的源寄存器
for (k < current_instr) {
    if (uop[k].rd == current_instr.rs1) {
        sourceTag = uop[k].newTag; // 直接使用前面刚分配的新 Tag
    }
}

```


* 这确保了超标量发射的正确性。


4. **组装输出 (Output Assembly):**
* 将查到的源 Tag (`tagA`, `tagB`) 和分配的目标 Tag (`tagDst`) 填入 `R_UOp`。
* 从 `rat` 获取 `avail` 位。
* 分配序列号 `sqN`。
* 发送给 `IssueQueue`。



#### **停顿机制 (Stall)**

* **如果 `TagBuffer` 空了**（物理寄存器耗尽）：`Rename` 模块会拉高 `OUT_stall`，阻塞上游的解码器。这就是为什么 `Config.sv` 中 `RF_SIZE` 太小会严重影响性能的原因。

### 总结：数据流向

1. **Input:** `ADD x1, x2, x3` (逻辑寄存器)
2. **Lookup:** RAT 告诉我们 `x2`=`p5` (Ready), `x3`=`p8` (Not Ready).
3. **Allocate:** TagBuffer 给 `x1` 分配了新 Tag `p12`.
4. **Check:** 确认同周期前面的指令没改写 `x2` 或 `x3`。
5. **Update:** 将 `x1`=`p12` (Not Ready) 写入 RAT 的 `specTag`。
6. **Output:** 发出 `R_UOp` -> `{opcode: ADD, tagDst: p12, tagA: p5, tagB: p8, availA: 1, availB: 0, sqN: 100}`.

至此，指令完全摆脱了对 `x` 寄存器的依赖，变成了纯粹的 Tag 数据流操作。