# SoomRV 全局总干

---

## 第1页：架构总览（Architecture Overview）

```text
+---------------------- SoomRV 核心（Core） ----------------------+
| 前端（Frontend） | 执行引擎（Execution Engine） | 内存子系统（Memory Subsystem） |
|                    |                              |                                  |
| 分支预测/取指（BP/ITLB/I$） -> 解码/重命名（Decode/Rename）      |
| -> 发射/执行（Issue/Execute） -> 访存（LSU/D$）                  |
+-------------------------------|-----------------------------------+
                                v
                    内存接口（Memory Interface, AXI4 128-bit）
                     （4 个在途事务 4 in-flight + MMIO）
```

- 这是一个四发射（4-wide）、乱序执行（Out-of-Order, OoO）的 RISC-V 核。
- 四大分区：前端（Frontend）、执行引擎（Execution Engine）、内存子系统（Memory Subsystem）、内存接口（Memory Interface）。
- 关键规格：重排序缓冲（Re-Order Buffer, `ROB`）64 项，加载/存储队列（Load/Store Queue, `LQ/SQ`）各 16 项，指令/数据缓存（I/D Cache）16KiB 4 路组相联（4-way VIPT），AXI4 128-bit。

先看总览。SoomRV 是四路超标量、乱序执行内核。前端负责取指和预测，执行引擎负责重命名、发射和执行，内存子系统负责 load/store 排队与访问，最右侧内存接口通过 AXI4 与外部内存和设备通信。

---

## 第2页：主线数据流（Main Dataflow: IF_Instr -> Commit）

```text
取指包（IF_Instr）
 -> 预解码指令（PD_Instr）
 -> 解码微操作（Decoded UOp, D_UOp）
 -> 重命名微操作（Renamed UOp, R_UOp）
 -> 发射微操作（Issued UOp, IS_UOp）
 -> 执行微操作（Execute UOp, EX_UOp）
 -> （地址微操作/存储数据微操作：AGU_UOp / StData UOp）
 -> （加载/存储队列微操作：LD_UOp / SQ_UOp / ST_UOp）
 -> 写回（Writeback）
 -> 按序提交（In-order Commit, ROB Commit）
```

- `R_UOp`：完成逻辑寄存器到物理寄存器映射，并绑定序列号（SqN）。
- `EX_UOp`：源操作数就绪，可直接进入功能单元执行。
- 访存类指令在执行后分叉为地址流（AGU_UOp）和数据流（StData UOp），最终在访存单元（LSU）与提交路径收口。

这一页讲主线。指令从 IF_Instr 开始，经过预解码、解码、重命名、发射和执行，最后写回并由 ROB 按序提交。每个模块本质上都是“数据结构转换器”，把上一阶段格式转成下一阶段可消费格式。

---

## 第3页：前端闭环（Frontend Loop）

```text
分支预测器（Branch Predictor）
   | 取指 PC（fetch PC）
   v
指令地址转换 + 指令缓存（ITLB + I-Cache, 16KiB 4-way VIPT）
   | 128 位取指包（128-bit fetch packet）
   v
分支处理器 / 预解码缓冲 / PC-预测文件
（Branch Handler / Pre-Decoder Buffer / PC-BP File）
   |                    |               |
   +---- 分支目标（Branch Target）-----+
   +--------------------> 指令解码器（Instruction Decoder, 4-wide）

回写到预测器（Feedback to Predictor）:
- 分支处理器（Branch Handler）: 分支目标（Branch Targets）
- 重排序缓冲（ROB）: 分支方向（Branch Direction）
- 算术逻辑单元（ALU）: 间接分支目标（Indirect Branch Targets）
```

- 前端输出不仅有指令字节流，还有 PC 与预测元数据（PC/BP File）。
- 预解码缓冲（Pre-Decoder Buffer）负责指令边界切分，向解码器提供 `4x PD_Instr`。
- 分支预测更新是三源反馈：取指早期修正、提交阶段校正、执行阶段间接分支目标补充。

前端不是单向取指，而是闭环系统。预测器给 PC，I-Cache 返回 128-bit 取指包，再分流到分支处理、预解码和 PC/BP 元数据。关键是三源反馈：Branch Handler、ROB、ALU 共同更新预测器，持续修正前端路径。

---

## 第4页：中后段主干（Rename/Issue/Execute/Commit）

```text
解码器（Decoder）
 -> 重命名与消除（Rename & Eliminate）
 -> 发射队列（Issue Queues）
 -> 操作数读取与旁路（Operand Lookup / Forwarding）
 -> ALU/分支单元/控制状态寄存器（ALU/Branch/CSR）+ 地址生成单元（AGU）+ Store Data
 -> 写回（Writeback）
 -> 重排序缓冲（ROB, 64-entry）
 -> 按序提交（In-order Commit）

关键资源（Key Resources）:
- 寄存器别名表（Register Alias Table, RAT）
- 物理寄存器文件（Physical Register File, PRF: 64x32-bit, 8R4W）
- 发射队列（Issue: 4 通用 + 2 Store-data）
```

- 重命名（Rename）建立真实依赖并分配物理资源，支撑 OoO 执行。
- 发射 + 旁路（Issue + Forwarding）决定何时可发射、是否可绕过回写等待。
- 执行可以乱序完成，提交必须按序，由 ROB 保证精确异常（Precise Exception）。

中后段核心是“乱序执行，按序提交”。重命名先处理依赖，IssueQueue 只发射就绪指令，Forwarding 解决短期数据相关。即使执行完成顺序不同，ROB 仍按程序顺序提交，保证异常与架构状态一致。

---

## 第5页：访存闭环（Memory Loop: AGU/LQ/SQ/LSU/Cache）

```text
地址微操作（AGU_UOp） ----------> 加载队列（Load Queue, LQ, 16）
   |                                 ^
   |                                 | 2x 存储前递结果（Store-Forward Result, StFwd）
   +--> 存储队列（Store Queue, SQ, 16） -> 存储发射队列（Store Issue Queue, 4） -> ST_UOp
                                       |
加载微操作（LD_UOp） -----------------+----> 访存单元（Load/Store Unit, LSU）
                                                  -> 数据缓存（Data Cache, D$, 16KiB, 4-way）
                                                        |
                                                        v
                                        内存接口（Memory Interface, 16B path）
```

- Load 和 Store 在队列层拆分管理，Store 地址与数据在 SQ 汇合。
- 存储到加载前递（Store-to-Load Forwarding）是访存关键优化路径。
- LSU 处理命中/未命中（hit/miss）和请求仲裁，miss 通过内存接口回填。

AGU 先算地址，load/store 分别入队；store 提交后进入 Store Issue Queue 发射。Load 优先尝试 SQ 前递命中，命中就绕过 cache 慢路径。若 miss，则由 LSU 发起外部请求并等待回填，这就是访存闭环。

---

## 第6页：三条反馈环（Three Feedback Loops）

```text
环路1：分支反馈（Branch Feedback）
Branch Handler + ROB + ALU  ---> Branch Predictor

环路2：内存前递（Memory Forwarding）
Store Queue (SQ) -----------> Load Queue (LQ) [StFwd]

环路3：停顿传播（Stall/Ready Backpressure）
Issue/LQ/SQ/LSU 的 stall/ready 信号 ---> 上游减速或停发
```

- 分支反馈环：降低错误路径成本，提升预测质量。
- 前递反馈环：降低数据相关导致的访存等待。
- 停顿传播环：通过 `stall/ready` 握手把拥塞向上游传播，避免局部堵塞扩散成全局失稳。
- 术语口径：源码中几乎不用单词 `backpressure`，但使用了等价机制 `IN_ready/OUT_ready`、`IN_stall/OUT_stall`、`RN_stall`、`SQ_stall`，因此本页建议使用“停顿传播（stall/ready 反压）”而不是只写 Backpressure。

这三条环路解释系统为什么稳定。第一，分支反馈持续修正前端路径；第二，存储前递优先复用最新数据；第三，通过 stall/ready 把拥塞向上游传播，系统自动减速并在资源恢复后继续推进。

---

## 第7页：总结（Summary）

```text
SoomRV 全局主干（Global Backbone）=
1) 主线（Main Pipeline）：IF -> Decode -> Rename -> Issue -> Execute -> Commit
2) 分支闭环（Branch Loop）：三源反馈修正前端
3) 访存闭环（Memory Loop）：LQ/SQ/LSU + miss + 回填
4) 停顿传播（Stall/Ready Loop）：拥塞上推，节拍自稳
```

- 主线回答“指令如何完成”。
- 分支闭环回答“错误路径如何纠正”。
- 访存闭环回答“内存等待如何保持正确与吞吐”。
- 停顿传播回答“系统如何在压力下稳定运行”。

简单来说：第一，主线是从取指到按序提交。第二，分支预测依靠多源反馈持续修正。第三，访存通过 LQ/SQ/LSU 处理前递、miss 与回填。第四，系统通过 stall/ready 停顿传播维持整体稳定。

---

## 术语速查（Glossary）

- 前端（Frontend）：分支预测、取指、预解码相关模块。
- 执行引擎（Execution Engine）：重命名、发射、执行、写回和提交控制。
- 内存子系统（Memory Subsystem）：LQ/SQ/LSU/Cache 组成的访存路径。
- 重排序缓冲（ROB）：保证按序提交与精确异常。
- 寄存器别名表（RAT）：逻辑寄存器到物理寄存器映射。
- 物理寄存器文件（PRF）：保存物理寄存器值，支持多端口读写。
- 停顿传播（stall/ready 反压）：下游拥塞时，上游通过握手信号减速或停发。
