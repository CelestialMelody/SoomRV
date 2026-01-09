`src/Include.sv` 是 SoomRV 的**数据字典**。它定义了所有模块之间通信用的“语言”——包括数据类型（Typedefs）、枚举（Enums）、结构体（Structs）和接口（Interfaces）。

在一个大型 Verilog/SystemVerilog 项目中，理解了这个文件，你就理解了数据是如何在流水线中流动的。

我将它分为**五个核心部分**进行详细解读。

---

### 第一部分：原子数据类型 (Basic Typedefs)

这些是构建整个处理器的“乐高积木块”。

```systemverilog
typedef logic[4:0] RegNm;         // 逻辑寄存器名 (x0-x31)，即 RISC-V 里的 rs1, rd
typedef logic[`RF_SIZE_EXP:0] Tag;// 物理寄存器标签 (Tag)。
                                  // 注意它比 RF_SIZE 多一位，通常用于标记 "Tag有效性" 或 "特殊Tag"
typedef logic[`ROB_SIZE_EXP:0] SqN;// 序列号 (Sequence Number)。
                                  // 用于在 ROB 中追踪指令的先后顺序，处理回滚。
typedef logic[31:0] RegT;         // 寄存器数据 (32位实际数值)

```

**关键点解读：**

* `Tag` vs `RegNm`: 这是乱序执行的核心。`RegNm` 是程序员眼中的 `x1`，`Tag` 是硬件实际分配的 `p15`。重命名模块负责将 `RegNm` 翻译为 `Tag`。
* `SqN`: 时间戳。因为执行是乱序的，ROB 必须依靠 `SqN` 来知道哪条指令更老，哪条更年轻。

---

### 第二部分：微操作码枚举 (OpCode Enum)

这是处理器内部的指令集。解码器会将 RISC-V 机器码翻译成这些内部操作码。

```systemverilog
typedef enum logic[6:0] // 你刚才修改过的位宽
{
    INT_ADD, INT_SUB, ... // 整数运算
    INT_LSU_LB, INT_LSU_SW, ... // 内存访问
    INT_BEQ, INT_JAL, ... // 分支跳转
    INT_CSR, INT_MRET, ... // 系统指令
    // ... 这里就是你需要添加浮点指令的地方 ...
} OpCode;

```

**分类：**

* **`INT_*`**: 也就是 ALU 操作。
* **`LSU_*`**: 加载存储单元操作。
* **`CSR/TRAP`**: 特权级操作。

---

### 第三部分：流水线数据包 (Pipeline Data Structures)

这是**最重要的部分**。随着指令在流水线中流动，它携带的信息（Struct）会发生变化。

#### 1. 取指阶段 (`IF_Instr`)

```systemverilog
typedef struct packed
{
    logic[15:0] instr;   // 原始指令位 (16位，因为可能是压缩指令)
    logic[31:0] pc;      // 这条指令的 PC
    logic predTaken;     // 预测器是否预测跳转？
    FetchID_t fetchID;   // 取指包 ID
    // ...
    TrapCause_t excCause;// 取指阶段是否发生了异常（如缺页）
} IF_Instr;

```

* **作用：** 此时处理器只知道这是一串 0101，还不知道它具体要干嘛。

#### 2. 解码阶段 (`D_UOp` - Decoded Micro-Op)

```systemverilog
typedef struct packed
{
    logic[31:0] pc;
    OpCode opcode;       // 终于知道是 ADD 还是 SUB 了
    RegNm rd;            // 逻辑目标寄存器 (例如 x1)
    RegNm rs1, rs2;      // 逻辑源寄存器 (例如 x2, x3)
    logic[31:0] imm;     // 立即数已经提取出来了
    // ...
} D_UOp;

```

* **作用：** 此时指令身份已确立，但还在使用逻辑寄存器名。

#### 3. 重命名阶段 (`R_UOp` - Renamed Micro-Op)

```systemverilog
typedef struct packed
{
    // 逻辑寄存器 (rs1, rs2) 消失了，变成了 Tag！
    Tag tagA;            // 源操作数 A 的物理标签
    Tag tagB;            // 源操作数 B 的物理标签
    Tag tagDst;          // 目标寄存器的物理标签
    SqN sqN;             // 分配了序列号
    OpCode opcode;
    logic[31:0] imm;
    // ...
} R_UOp;

```

* **作用：** 这里的变化标志着进入了**乱序域**。指令不再关心“x1的值”，而是关心“Tag 45产生了吗”。

#### 4. 发射阶段 (`IS_UOp` - Issue Micro-Op)

这个结构体驻留在发射队列（Issue Queue）中。

```systemverilog
typedef struct packed
{
    Tag tagA;
    Tag tagB;
    Tag tagDst;
    SqN sqN;
    OpCode opcode;
    // ...
    // 注意：这里没有 32-bit 的 rs1/rs2 数据。发射队列只存 Tag，不存数据（为了省面积）。
} IS_UOp;

```

#### 5. 执行阶段 (`EX_UOp` - Execute Micro-Op)

当指令被发射后，它去寄存器堆读取了数据，变成了这个形态：

```systemverilog
typedef struct packed
{
    logic[31:0] srcA;    // Tag 变成了真实的 32-bit 数据！
    logic[31:0] srcB;
    Tag tagDst;          // 结果要写回哪里
    SqN sqN;
    OpCode opcode;
    logic[31:0] imm;
} EX_UOp;

```

* **作用：** ALU 拿到这个结构体，直接做 `res = srcA + srcB` 即可。

---

### 第四部分：内存子系统专用结构

内存操作比 ALU 操作复杂，因为涉及地址计算和数据读写分离。

#### 1. AGU 微操作 (`AGU_UOp`)

```systemverilog
typedef struct packed
{
    logic[31:0] addr;    // 计算出来的内存地址
    OpCode opcode;       // 是读(LB) 还是 写(SW)？
    Tag tagDst;          // 如果是读，结果存哪？
    SqN sqN;
    // ...
} AGU_UOp;

```

#### 2. 存储数据微操作 (`StData_UOp`)

注意：Store 操作在 SoomRV 中被拆分为两个微操作：一个算地址 (AGU)，一个提供数据 (StoreData)。

```systemverilog
typedef struct packed
{
    logic[31:0] data;    // 要写入内存的数据
    SqN sqN;
} StData_UOp;

```

#### 3. 加载/存储队列条目 (`LD_UOp`, `SQ_UOp`)

这些结构体用于 Load Buffer 和 Store Queue 内部管理，包含诸如“是否已提交”、“是否触发了转发”等状态位。

---

### 第五部分：结果与写回 (Result Bus)

这是 Common Data Bus (CDB) 上跑的数据结构。

```systemverilog
typedef struct packed
{
    logic[31:0] result;  // 计算结果
    Tag tagDst;          // 这个结果属于哪个物理寄存器？
    logic doWB;          // 是否需要写回 (有的指令不产生结果，如 Branch)
} Result;

```

* **作用：** 这个结构体被广播到所有发射队列。队列里的指令看到 `tagDst` 匹配自己的 `tagA`，就会把操作数抓进来标记为 Ready。

---

### 第六部分：接口 (Interfaces)

文件末尾定义了模块间的物理连接方式。

* **`IF_Cache`**: 定义了 CPU 和 L1 Cache 之间的握手信号（地址、数据、Ready/Valid）。
* **`IF_CTable`**: 可能是用于分支预测器中的计数器表接口。

### 总结

在阅读代码时，如果你迷失了，请回到 `Include.sv`：

1. 看到 `uop.tagA` -> 你知道这是在处理依赖关系。
2. 看到 `uop.srcA` -> 你知道这已经拿到了数据，准备计算。
3. 看到 `uop.sqN` -> 你知道这涉及顺序和恢复。

**对于您的浮点修改：**
您必须确保 `OpCode` 枚举中包含了所有新加入的 `INT_F*` 指令，并且位宽足够（例如从 `logic[5:0]` 改为 `logic[6:0]`）。这是让解码器和执行单元“听得懂”浮点指令的第一步。