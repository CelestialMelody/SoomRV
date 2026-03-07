“契约”指流水线对 tag 和 sqN 的一致约定：所有模块都按同一套规则使用它们，否则会错。

### tag 契约

- 唯一生产者：每条写寄存器的指令在重命名时被分配一个唯一的 tagDst（物理寄存器号）；同一 tag 只对应一条未提交指令的结果。

- 依赖表示：所有消费该结果的指令用 tagA/tagB（及 tagC） 表示“等谁”；不出现两个不同的 tag 指向“同一逻辑结果”。

- 就绪语义：avail 表示“该 tag 对应的值是否已就绪”；就绪来源只有两种：

- 已提交到架构态（RenameTable 的 comTag + tagAvail），或

- 本周期或之前某周期的写回/前递（IN_flagUOp / IN_resultUOps）。

- 生命周期：tag 在重命名时由 TagBuffer 分配，在该条指令提交时由 ROB 通知释放（RenameTable 更新 comTag，TagBuffer 回收旧物理寄存器）。

因此，“明确 tag 契约” = 在文档/设计里写清：tag 唯一标识一个生产者、全流水线用 tag 表示依赖、就绪只由提交或写回/前递更新。
sqN 契约
全局顺序：重命名阶段为每条指令分配单调递增的 sqN；数值越小越早。
比较方式：sqN 比 ROB 索引多一位，用有符号差比较顺序，例如：
$signed(IN_uop.sqN - IN_branch.sqN) <= 0 → 该指令在分支之前或等于分支（保留）；
$signed(IN_uop.sqN - IN_branch.sqN) > 0 → 在分支之后（误预测要 flush）。

##用途：
作为 ROB 索引（sqN 的低位）；
分支/异常时判断“哪些指令要无效”；
load/store 顺序用 loadSqN、storeSqN 在 LoadBuffer/StoreQueue 里排队。
因此，“明确 sqN 契约” = 约定 sqN 的分配单调、用有符号差比较先后、以及在各处（ROB、flush、load/store）的用法一致。