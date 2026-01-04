## 一、 Frontend（前端）：取指与预测

前端的目标是：**在不知道程序往哪走的情况下，尽可能准确地抓取指令。**

### 1. Branch Predictor (分支预测器)

* **Branch Target Buffer (4096 entry):** 这是一个拥有 4096 个条目的数据库。它记录了过去跳转过的指令地址。如果 PC 匹配到其中的条目，处理器就会直接去“预测的目的地”取指。
* **Direction Predictor (tagged geometric):** 采用 TAGE 算法（目前公认最强的预测算法之一）。它根据历史规律预测 `if` 语句是执行还是跳过。
* **Return Stack (+ recovery queue):** 专门针对 `ret` 指令。函数调用时压栈，返回时弹栈。`recovery queue` 用于在分支预测错误时快速恢复栈状态。
* **fetch PC (箭头):** 预测器生成的地址送往指令缓存。

### 2. 指令缓存与转换

* **ITLB:** 指令转换后备缓冲区。负责将程序使用的虚拟地址翻译成物理地址。
* **Instruction Cache (16 KiB 4-way VIPT):**
* **VIPT (Virtually Indexed, Physically Tagged):** 一种加速技术，允许在翻译地址的同时并行查找缓存，极大地减少了延迟。
* **16B (箭头):** 每次从缓存取回 16 字节（即 128 位，可包含 4 条 32 位指令）。



### 3. 指令预处理

* **Pre-Decoder Buffer (32x16-bit FIFO):** * **小字解释:** 寻找指令边界。因为 RISC-V 支持 16 位压缩指令（C扩展），指令长度不固定，这个缓冲区负责把乱糟糟的字节流切分成标准的指令格式。
* **PC/BP File:** 这是一个元数据仓库。它记录了每一条正在处理的指令的 PC 地址和当时预测器的状态，用于后续“对账”。
* **1x IF_Instr / 4x PD_Instr (箭头):** 表示流水线的宽度。经过预解码后，每时钟周期可以送出 4 条指令。

---

## 二、 Execution Engine（执行引擎）：乱序的核心

在这里，指令不再按程序原来的顺序执行，而是“谁的操作数先准备好，谁就先执行”。

### 1. 指令解码与重命名

* **Instruction Decoder (4-wide, RV32IMAC+):** * **4-wide:** 4路并行解码。
* **RV32IMAC+:** 支持 32 位基础整数、乘除、原子操作、压缩指令等。它将指令转成内部的 **uOps (微操作)**。


* **Rename & Eliminate:** * **Eliminate:** 消除掉一些没意义的操作（比如 `x = x + 0`）。
* **重命名:** 将有限的 31 个架构寄存器映射到 64 个物理寄存器（Physical Registers），从而消除“伪相关”。


* **Register Alias Table (RAT):** 存储“谁是谁”的实时映射表。
* **Re-Order Buffer (ROB, 64 entry):** * **核心功能:** 它是处理器的“账本”。指令在这里排队等候，即使它们是乱序执行完的，最后也必须在这里**按顺序**确认（Commit）写回内存，以保证程序不出错。

### 2. 发射与执行

* **Issue Queue (8 entry collapsing queue):** * 共有 6 个队列。**Collapsing** 意味着当一条指令离开队列，后面的指令会自动“补位”，始终保持紧凑。
* **IS_UOp (箭头):** 发射微操作。


* **Forwarding Network (前推网络):** 极其关键！如果 ALU 刚算完一个数，下一条指令马上要用，不需要等它存入寄存器，直接通过这层物理连线“空投”过去。
* **Physical Register File (64x 32-bit 8R4W):** * **8R4W:** 8个读端口，4个写端口。这意味着一个周期内可以同时读取 4 条指令所需的操作数（每条指令通常需 2 个读操作数）。
* **执行单元组:**
* **ALU/Branch/CSR:** 处理算术逻辑、跳转判断、系统状态寄存器。
* **AGU (Address Generation Unit):** 专门负责计算内存地址（基址+偏移量）。



---

## 三、 Memory Subsystem（内存子系统）

负责与外面的世界（内存、设备）打交道。

* **Address Translation / Data TLB:** 数据地址翻译。
* **Load Queue / Store Queue (16 entry indexed):** * **Indexed:** 支持快速索引查找。
* **Store Forwarding (2x StFwd Result):** 如果你刚写了一个数到内存，还没写完，紧接着又要读这个数，处理器会直接从 Store Queue 把数给 Load Queue，而不去翻 D-Cache。


* **Load/Store Unit:** 负责管理复杂的缓存缺失、未对齐访问等。
* **Data Cache (16 KiB 4-way VIPT):** 数据的高速缓存，与指令缓存结构类似。

---

## 四、 右侧长条：Memory Interface (存储接口)

这是处理器的“出入口”。

* **AXI 4 128-bit:** 使用业界标准的 AXI4 总线，宽度为 128 位。
* **4 in-flight transactions:** 允许同时有 4 个内存访问请求在路上（不阻塞）。
* **MMIO:** 内存映射输入输出，用于控制外设（如串口、屏幕等）。

---

### 箭头的特殊标记说明：

* **R_UOp / IS_UOp / EX_UOp:** 分别代表重命名后 (Renamed)、发射后 (Issued)、执行中 (Executing) 的微操作。
* **128-bit Fetch Packet:** 前端抓取的大数据包。
* **Monospace are SystemVerilog structs:** 图中等宽字体（如 `IF_Instr`）表示硬件描述语言中的结构体定义，意味着这些可以直接对应到代码。