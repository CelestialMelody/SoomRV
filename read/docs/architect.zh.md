# Architecture Overview（架构概览）

![img](architect.png)

架构图展示了一个 **4-wide（四路超标量）、乱序执行（Out-of-Order）** 的 RISC-V 处理器流水线。

------

## 一、 Frontend（前端）：取指与预测

这是处理器的入口，负责从内存拉取指令流并猜测执行路径。

### 1. Branch Predictor（分支预测器）

**3 个输入源（用于更新预测历史）**

- **Branch Targets（来自 Branch Handler）：** 当指令刚被取回并进行预解码时，如果发现是跳转指令且预测器没预测到，`Branch Handler` 会立即反馈修正目标。

- **Branch Direction（来自 ROB）：** 来自重排序缓冲区（ROB）。这是最终的提交阶段反馈，告诉预测器之前的预测到底是对是错（用于更新 TAGE 表）。

- **Indirect Branch Targets（来自 ALU）：** 间接跳转（如 `jalr x1`）的目标地址只能在执行阶段（ALU 计算出寄存器值后）才能确定，由执行单元反馈。
**内部模块**

- `Branch Target Buffer (4096 entry)`：记录跳转目标地址。
- `Direction Predictor (tagged geometric)`：即 TAGE 预测器，预测跳转方向。
- `Return Stack (+ recovery queue)`：预测函数返回地址。

**输出：** `fetch PC`，将预测的下一个 PC 地址发送给 ITLB 和 Instruction Cache。

### 2. Instruction Cache & ITLB

- **ITLB：** 负责指令地址翻译（虚拟 -> 物理）。
- **Instruction Cache (16 KiB 4-way VIPT)：** 指令缓存。
- **输入 (16B)：** 来自右侧的 **Memory Interface**。这意味着当缓存未命中（Cache Miss）时，通过 AXI 总线从主存一次性读取 **16字节（128位）** 的数据填充缓存行。
- **输出 (128-bit Fetch Packet)：** 每个周期输出 128 位（16字节）的原始指令数据包。这个包包含了多条指令的原始字节流。

### 3. Fetch Packet 的去向（分流）

`128-bit Fetch Packet` 出来后，分流到了三个模块，同时传递了 `1x IF_Instr` 结构体（SystemVerilog 结构体，定义了取指包的数据格式）：

**Branch Handler (分支处理器)：**

- **功能：** 它在原始字节流中扫描分支指令（比如 `JAL`）。如果发现了跳转指令，但上面的 Branch Predictor 漏报了，它会立即触发修正。
- **输出：** `Branch Targets` 信号反馈回预测器。

**Pre-Decoder Buffer (预解码缓冲)：**

- **规格：** `32x16-bit FIFO`。
- **功能：**  这个模块负责“切分”字节流，找到每条指令的边界。
- **输出：** `4x PD_Instr`。这代表预解码指令（Pre-Decoded Instruction），包含指令位和长度信息，发送给解码器。

**PC/BP File (PC与分支预测文件)：**

- **功能：** 这是一个元数据仓库。它不存指令内容，而是存储这批指令对应的 **PC地址** 和当时的 **分支预测元数据**。
- **输出：** `2x PCFile Entry`。当指令进入解码或执行阶段时，如果需要知道这条指令的 PC（例如计算相对跳转偏移），就从这里读取。

### 4. Instruction Decoder (指令解码器)

- **输入：** `4x PD_Instr`（来自预解码缓冲）。
- **功能：** 将 RISC-V 机器码翻译成 SoomRV 内部的微操作。支持 `4-wide`（每周期解码4条）。
- **输出：** `4x D_UOp` (Decoded UOp)。这是解码后的微操作结构体。

### 5. Rename & Eliminate (重命名与消除)

- **输入：** `4x D_UOp`。
- **Register Alias Table (RAT)：** 保存虚拟寄存器（x1-x31）到物理寄存器（Tag 0-63）的映射。
- **Re-Order Buffer (64 entry FIFO / indexed queue)：** 分配 `sqN` (序列号) 和 ROB 条目。
- **功能：**
  - 分配物理目标寄存器 Tag。
  - **Eliminate：** 如果是 `MV` (移动) 或 `Load Immediate` (加载立即数)，可能直接在此阶段处理，不进入后端。
- **输出：** `R_UOp` (Renamed UOp)。带有物理寄存器标签和序列号的微操作。

------

## 二、 Execution Engine（执行引擎）

### 1. Issue Queues (发射队列)

- **输入：** `R_UOp`。
- **结构：** 4个通用发射队列 + 2个存储数据队列。
- **Collapsing Queue：** “塌缩队列”。中间指令发射后，后面的会自动前移填补空缺。
- **输出：** `IS_UOp` (Issued UOp)。当操作数准备好时，指令被发射。

### 2. Operand Lookup & Forwarding (操作数读取与前推)

- **输入：** `IS_UOp`。
- **输入：** `2x PCFile Entry`（来自 PC/BP File，获取指令对应的 PC）。
- **Physical Register File (64x 32-bit 8R4W)：** 物理寄存器堆。8个读端口支持 4 条指令同时读取（每条2个源操作数）。
- **Forwarding Network：** 也就是 Bypass Network。如果操作数刚被计算出来还没写入寄存器堆，通过这个网络直接“短路”给下一条指令。
- **Store Data Queue (右侧)：** 发送 `StData LookupUOp` 到寄存器堆，读取用于存储的数据（例如 `sw x1, 0(x2)` 中的 `x1` 的值）。
- **输出：** `EX_UOp` (Execute UOp)。这是携带了完整源操作数值（srcA, srcB）的微操作，准备好被执行。

### 3. Execution Units (执行单元)

- **左侧 (ALU/Branch/CSR)：** 执行整数运算和分支。
  - **输出：** `Indirect Branch Targets` 反馈给前端预测器。
- **中间 (AGU - Address Generation Unit)：** 地址生成单元。
  - **功能：** 计算 Load/Store 的内存地址。
  - **Address Translation / Data TLB：** 将计算出的虚拟地址翻译为物理地址。
  - **输出：** `AGU_UOp`。包含物理地址的微操作，送往内存子系统。
- **右侧 (Store Data)：** 处理存储数据的准备。
  - **输出：** `StData UOp`。包含实际要写入内存的数据，送往 Store Queue。

------

## 三、 Memory Subsystem（内存子系统）

### 1. Load Queue (加载队列)

- **规格：** `16 entry indexed queue`。
- **输入 1：** `AGU_UOp`（来自 AGU，提供地址）。
- **输入 2：** `2x StFwd Result`（来自 Store Queue）。**关键点：** 这是 Store-to-Load Forwarding。Load 指令会检查 Store Queue，看有没有未写入内存但地址匹配的 Store 指令，如果有，直接拿数据，不用去 Cache。
- **输出：** `2x LD_UOp`。发送给 Load/Store Unit 进行实际的 Cache 读取。

### 2. Store Queue (存储队列)

- **规格：** `16 entry indexed queue`。
- **输入 1：** `AGU_UOp`（来自 AGU，提供地址）。
- **输入 2：** `StData UOp`（来自 Store Data Unit，提供数据）。请注意，Store 操作分为“算地址”和“准备数据”两个微操作，在这里汇合。
- **功能：** 缓冲 Store 指令，直到它们 **Commit (提交)**。未提交的 Store 绝不能写入 Cache。
- **输出：** `2x SQ_UOp`。当 Store 指令安全提交后，发送给 Store Issue Queue。

### 3. Store Issue Queue & LSU

- **Store Issue Queue：** `4 entry unordered`。接收已提交的 Store，进行合并（Fuse，例如将两个相邻的 32位写合并为一个 64位写），然后发射。
  - **输出：** `1x ST_UOp`。
- **Load/Store Unit (LSU)：**
  - **输入：** `2x LD_UOp` (加载) + `1x ST_UOp` (存储)。
  - **功能：** 实际操作 Data Cache。处理 Cache Miss。
  - **输出：** `2x 16B`。这里指 LSU 与 Data Cache 之间的接口带宽，支持宽位宽存取。

### 4. Data Cache

- **规格：** `16 KiB 4-way VIPT`。
- **连接：** 下方的双向箭头 `16B` 连接到右侧的 Memory Interface。处理 Cache Line 的填充（Read from Mem）和写回（Writeback to Mem）。

### 5.Memory Interface

- **AXI 4 128-bit：** 使用 AXI4 协议，数据总线宽度 128 位（16字节）。
- **4 in-flight transactions：** 支持 4 个并发的内存请求。
- **功能：** 它是 CPU 核与外部世界（DDR 控制器、外设）的桥梁。
  - 上方箭头 `16B`：给 Instruction Cache 供货。
  - 下方箭头 `16B`：给 Data Cache 供货或写回数据。
  - **MMIO：** 处理非缓存的设备访问（Memory Mapped I/O）。

------

## 数据结构流向

1. **IF_Instr：** 取指包（原始数据）。
2. **PD_Instr：** 预解码指令（切分好的指令）。
3. **D_UOp：** 解码微操作（内部格式）。
4. **R_UOp：** 重命名微操作（分配了 Tag 和 SqN）。
5. **IS_UOp：** 发射微操作（在队列中等待）。
6. **EX_UOp：** 执行微操作（读到了源操作数）。
7. **AGU_UOp / StData UOp：** 内存微操作（地址/数据分离）。
8. **LD_UOp / SQ_UOp / ST_UOp：** 后端内存操作。
