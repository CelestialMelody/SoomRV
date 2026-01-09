// 重命名模块 (Rename)
// 作用：将逻辑寄存器 (Architectural Register) 映射到物理寄存器 (Physical Tag)，消除 WAW/WAR 相关。
module Rename
#(
    parameter WIDTH_ISSUE = `DEC_WIDTH,   // 发射宽度 (4)
    parameter WIDTH_COMMIT = `DEC_WIDTH,  // 提交宽度 (4)
    parameter WIDTH_WR = `DEC_WIDTH       // 写回宽度 (4)
)
(
    input wire clk,
    input wire frontEn,           // 前端使能 (如果没有停顿且没有 Flush)
    input wire rst,

    // 来自发射队列的反压信号 (Stall)
    input wire[NUM_PORTS_TOTAL-1:0][WIDTH_ISSUE-1:0] IN_stalls,
    output reg OUT_stall,         // 输出给 Decoder 的停顿信号

    // 输入：刚刚解码的指令 (带有逻辑寄存器号 x1, x2...)
    input D_UOp IN_uop[WIDTH_ISSUE-1:0],

    // 输入：ROB 提交的指令 (用于更新 RAT 的 Committed Map)
    input CommitUOp IN_comUOp[WIDTH_COMMIT-1:0],

    // 输入：写回阶段的标志 (用于更新 Scoreboard 的 Ready 位)
    // 即使指令未提交，其结果也是 speculatively available 的
    input FlagsUOp IN_flagsUOps[WIDTH_WR-1:0],

    // 输入：分支冲刷信号 (用于回滚状态)
    input BranchProv IN_branch,
    input wire IN_mispredFlush,

    // 输出：重命名后的微操作 (带有物理 Tag p5, p6...)
    output R_UOp OUT_uop[WIDTH_ISSUE-1:0],

    // 输出：指令分派到发射队列的顺序 (用于负载均衡)
    output IntUOpOrder_t OUT_uopOrdering[WIDTH_ISSUE-1:0],

    // 输出：下一个分配的序列号 (全局 SqN, Load SqN, Store SqN)
    output SqN OUT_nextSqN,
    output SqN OUT_nextLoadSqN,
    output SqN OUT_nextStoreSqN
);

// SC (Store Conditional) 预留结构
typedef struct packed
{
    SqN sqN;
    logic valid;
} LrScRsv;

// 1. 计算停顿信号 (Stall Logic)
// 如果任何一个目标发射队列满了，整个 Rename 阶段都要停顿。
reg[WIDTH_ISSUE-1:0] portStall;
always_comb begin
    for (integer i = 0; i < WIDTH_ISSUE; i=i+1) begin
        portStall[i] = 0;
        // 检查所有端口的停顿位，按位或
        for (integer j = 0; j < NUM_PORTS_TOTAL; j=j+1)
            portStall[i] |= IN_stalls[j][i];
    end
end

// 2. 准备 RAT (Register Alias Table) 的接口信号
wire RAT_lookupAvail[2*WIDTH_ISSUE-1:0];      // 查表结果：Tag 是否就绪
Tag RAT_lookupSpecTag[2*WIDTH_ISSUE-1:0];     // 查表结果：物理 Tag
reg[4:0] RAT_lookupIDs[2*WIDTH_ISSUE-1:0];    // 查表输入：源寄存器 ID (rs1, rs2)

reg[4:0] RAT_issueIDs[WIDTH_ISSUE-1:0];       // 发射输入：目标寄存器 ID (rd)
reg RAT_issueValid[WIDTH_ISSUE-1:0];          // 发射有效
reg RAT_issueAvail[WIDTH_ISSUE-1:0];          // 新分配 Tag 的初始 Ready 状态
SqN RAT_issueSqNs[WIDTH_ISSUE-1:0];           // 分配的序列号

// Tag Buffer (Free List) 接口信号
reg TB_issueValid[WIDTH_ISSUE-1:0];           // 请求分配新 Tag
reg TB_tagNeeded[WIDTH_ISSUE-1:0];            // 该指令是否真的需要 Tag (写寄存器?)

reg RAT_commitValid[WIDTH_COMMIT-1:0];
reg TB_commitValid[WIDTH_COMMIT-1:0];

reg[4:0] RAT_commitIDs[WIDTH_COMMIT-1:0];
Tag RAT_commitTags[WIDTH_COMMIT-1:0];
Tag RAT_commitPrevTags[WIDTH_COMMIT-1:0];     // 提交时被覆盖的旧 Tag (释放回 Free List)

reg RAT_wbValid[WIDTH_WR-1:0];
Tag RAT_wbTags[WIDTH_WR-1:0];

SqN nextCounterSqN; // 下一个周期要用的 SqN

// SC (Store Conditional) 特殊处理状态
reg isSc[WIDTH_ISSUE-1:0];
reg scSuccessful[WIDTH_ISSUE-1:0];

// 3. 组合逻辑：预处理与控制流 (Control Logic)
always_comb begin

    // 默认停顿：如果任何下游队列反压
    OUT_stall = |portStall;
    nextCounterSqN = counterSqN;

    // --- 逐指令分析 ---
    for (integer i = 0; i < WIDTH_ISSUE; i=i+1) begin

        // 如果发生误预测冲刷，且当前有有效指令，强制停顿 (等待 Flush 完成)
        if (IN_mispredFlush && IN_uop[i].valid)
            OUT_stall = 1;

        // SC (Store Conditional) 指令检测
        // SC 是原子操作，如果之前的 LR (Load Reserved) 失败，SC 也应该失败。
        isSc[i] = IN_uop[i].fu == FU_AGU && IN_uop[i].opcode == LSU_SC_W;
        // 如果是包里的第一条指令且发生了 failSc (LR/SC 失败)，则标记失败
        scSuccessful[i] = !(i == 0 && failSc);

        // 判断是否需要分配新 Tag (TB_tagNeeded)
        // 条件：(写 rd 且 rd!=0) 或者 (是原子操作)
        // 且：不是重命名消除指令 (FU_RN) 不是异常 (FU_TRAP) 不是 SC
        TB_tagNeeded[i] = (IN_uop[i].rd != 0 || IN_uop[i].fu == FU_ATOMIC) &&
            // 这些指令不写寄存器，或者写操作被消除了
            IN_uop[i].fu != FU_RN && IN_uop[i].fu != FU_TRAP && !isSc[i];

        // 如果需要 Tag 但是 FreeList (TagBuffer) 没有提供有效的 Tag，则停顿
        if ((!TB_tagsValid[i]) && IN_uop[i].valid && frontEn && TB_tagNeeded[i])
            OUT_stall = 1;
    end

    // --- 准备查表与发射信号 ---
    for (integer i = 0; i < WIDTH_ISSUE; i=i+1) begin

        // 查表输入：源寄存器 rs1, rs2
        RAT_lookupIDs[2*i+0] = IN_uop[i].rs1;
        RAT_lookupIDs[2*i+1] = IN_uop[i].rs2;

        // 更新表输入：目标寄存器 rd
        RAT_issueIDs[i] = IN_uop[i].rd;
        RAT_issueSqNs[i] = nextCounterSqN; // 分配 SqN

        // 指令是否有效发射？
        // 条件：未复位、无分支冲刷、前端使能、无停顿、指令本身有效
        RAT_issueValid[i] = !rst && !IN_branch.taken && frontEn && !OUT_stall && IN_uop[i].valid;

        // 新 Tag 的初始 Ready 状态：
        // 通常为 0 (Busy)。但如果是 FU_RN (如 MV, LUI) 或 SC，则立即可用。
        RAT_issueAvail[i] = IN_uop[i].fu == FU_RN || isSc[i];

        // 向 TagBuffer 请求分配 Tag
        TB_issueValid[i] = RAT_issueValid[i] && TB_tagNeeded[i];

        // 如果成功发射了一条指令，SqN 计数器 +1
        if (RAT_issueValid[i])
            nextCounterSqN = nextCounterSqN + 1;
    end

    // --- 准备写回信号 (更新 Scoreboard) ---
    for (integer i = 0; i < WIDTH_WR; i=i+1) begin
        // 忽略 TAG_ZERO (最高位为1)
        RAT_wbValid[i] = IN_flagsUOps[i].valid && !IN_flagsUOps[i].tagDst[$bits(Tag)-1];
        RAT_wbTags[i] = IN_flagsUOps[i].tagDst;
    end

    // --- 准备提交信号 (更新 RAT 的 Committed Map) ---
    for (integer i = 0; i < WIDTH_COMMIT; i=i+1) begin
        // 只有写 rd!=0 的有效指令才更新 RAT
        RAT_commitValid[i] = (IN_comUOp[i].valid && (IN_comUOp[i].rd != 0));
        TB_commitValid[i] = IN_comUOp[i].valid;

        RAT_commitIDs[i] = IN_comUOp[i].rd;
        RAT_commitTags[i] = IN_comUOp[i].tagDst;
    end

end

// 4. 实例化寄存器别名表 (RAT)
RenameTable
#(
    .NUM_LOOKUP(WIDTH_ISSUE*2),
    .NUM_ISSUE(WIDTH_ISSUE),
    .NUM_COMMIT(WIDTH_COMMIT),
    .NUM_WB(WIDTH_WR)
)
rt
(
    .clk(clk),
    .rst(rst),
    .IN_mispred(IN_branch.taken),       // 误预测信号
    .IN_mispredFlush(IN_mispredFlush),  // 冲刷信号

    // 查表
    .IN_lookupIDs(RAT_lookupIDs),
    .OUT_lookupAvail(RAT_lookupAvail),
    .OUT_lookupSpecTag(RAT_lookupSpecTag),

    // 更新推测状态
    .IN_issueValid(RAT_issueValid),
    .IN_issueIDs(RAT_issueIDs),
    .IN_issueTags(newTags),             // 分配的新 Tag
    .IN_issueAvail(RAT_issueAvail),

    // 更新提交状态
    .IN_commitValid(RAT_commitValid),
    .IN_commitIDs(RAT_commitIDs),
    .IN_commitTags(RAT_commitTags),
    .OUT_commitPrevTags(RAT_commitPrevTags), // 获取被覆盖的旧 Tag

    // 写回更新
    .IN_wbValid(RAT_wbValid),
    .IN_wbTag(RAT_wbTags)
);

// 5. Tag 分配逻辑与 Tag Buffer 实例化
reg failSc;
RFTag TB_tags[WIDTH_ISSUE-1:0];         // TagBuffer 吐出的空闲 Tag (索引)
Tag newTags[WIDTH_ISSUE-1:0];           // 最终使用的完整 Tag
reg TB_tagsValid[WIDTH_ISSUE-1:0];      // 吐出的 Tag 是否有效

always_comb begin
    for (integer i = 0; i < WIDTH_ISSUE; i=i+1) begin
        // 正常分配：使用 TagBuffer 提供的物理 Tag
        if (TB_issueValid[i]) newTags[i] = {1'b0, TB_tags[i]};

        // 消除操作 (Rename Move)：不需要物理寄存器，直接把立即数编码进 Tag?
        // 或者是引用特殊的 Tag
        else if (IN_uop[i].fu == FU_RN) newTags[i] = {1'b1, RFTag'(IN_uop[i].imm)};

        // SC 操作：不需要分配物理寄存器，结果是成功/失败标志 (0/1)
        // 将结果编码在 Tag 的最低位
        else if (isSc[i]) newTags[i] = {1'b1, {($bits(Tag)-2){1'b0}}, !scSuccessful[i]};

        // 不需要 Tag (如 Branch, Store)：分配 TAG_ZERO
        else newTags[i] = TAG_ZERO;
    end
end

// 实例化空闲 Tag 列表 (Free List)
TagBuffer#(.NUM_ISSUE(WIDTH_ISSUE), .NUM_COMMIT(WIDTH_COMMIT)) tb
(
    .clk(clk),
    .rst(rst),
    .IN_mispr(IN_branch.taken),
    .IN_mispredFlush(IN_mispredFlush),

    .IN_issueValid(TB_issueValid),    // 请求分配
    .OUT_issueTags(TB_tags),          // 返回空闲 Tag
    .OUT_issueTagsValid(TB_tagsValid),// Tag 有效性 (如果不为1则说明空闲表空了 -> Stall)

    .IN_commitValid(TB_commitValid),  // 提交回收
    .IN_commitNewest(isNewestCommit), // 是否是该寄存器的最新映射?
    .IN_RAT_commitPrevTags(RAT_commitPrevTags), // 回收旧 Tag
    .IN_commitTagDst(RAT_commitTags)
);

// 6. 计算提交时哪些 Tag 应该被回收
// 只有当提交的指令覆盖了之前的映射时，之前的映射 Tag 才能被回收。
// 如果同一个周期内有多条指令写同一个寄存器 (WAW)，只有最新的一条才更新状态，中间的 Tag 都要回收。
reg isNewestCommit[WIDTH_COMMIT-1:0];
always_comb begin
    for (integer i = 0; i < WIDTH_COMMIT; i=i+1) begin

        // 默认有效：如果指令有效且写 rd!=0
        isNewestCommit[i] = IN_comUOp[i].valid && IN_comUOp[i].rd != 0;

        // 检查同一个提交包中，后面有没有指令写同一个寄存器
        if (IN_comUOp[i].valid)
            for (integer j = i + 1; j < WIDTH_COMMIT; j=j+1)
                // 如果后面有指令写同一个 rd，那我就不是最新的，我的 Tag 可以立即回收?
                // 或者这里是控制 RAT 更新逻辑?
                // 注：TagBuffer 的逻辑通常是回收 `prevTag`。
                if (IN_comUOp[j].valid && (IN_comUOp[j].rd == IN_comUOp[i].rd))
                    isNewestCommit[i] = 0;
    end
end

wire cycleValid = !IN_branch.taken && frontEn && !OUT_stall;

// 7. 生成序列号 (Sequence Numbers)
SqN counterSqN;        // 全局指令序列号计数器
SqN counterStoreSqN;   // Store 序列号计数器
SqN counterLoadSqN;    // Load 序列号计数器
assign OUT_nextSqN = counterSqN; // 输出给 Core

SqN loadSqNs[WIDTH_ISSUE:0];
SqN storeSqNs[WIDTH_ISSUE:0];

always_comb begin
    loadSqNs[0] = counterLoadSqN;
    storeSqNs[0] = counterStoreSqN;

    // 为当前周期的每条指令分配 Load/Store SqN
    for (integer i = 0; i < WIDTH_ISSUE; i=i+1) begin
        loadSqNs[i+1] = loadSqNs[i];
        storeSqNs[i+1] = storeSqNs[i];

        if (cycleValid && IN_uop[i].valid && !(isSc[i] && !scSuccessful[i])) begin
            // 只有 Load 和 Atomic 指令消耗 Load SqN
            if (IN_uop[i].fu == FU_ATOMIC || (IN_uop[i].fu == FU_AGU && IN_uop[i].opcode <  LSU_SC_W))
                loadSqNs[i+1] = loadSqNs[i] + 1;
            // 只有 Store 和 Atomic 指令消耗 Store SqN
            if (IN_uop[i].fu == FU_ATOMIC || (IN_uop[i].fu == FU_AGU && IN_uop[i].opcode >= LSU_SC_W))
                storeSqNs[i+1] = storeSqNs[i] + 1;
        end
    end
end

// 8. 调度器 (Scheduler)
// 决定指令该去哪个发射队列 (Port)。这通常是静态的 (基于 Opcode)，也可能是动态的 (负载均衡)。
IntUOpOrder_t SCHED_uopOrder[WIDTH_ISSUE-1:0];
Scheduler scheduler
(
    .clk(clk),
    .rst(rst),

    .IN_valid(cycleValid),
    .IN_uopSqN(RAT_issueSqNs),
    .IN_uopLoadSqN(loadSqNs[WIDTH_ISSUE:1]),
    .IN_uopStoreSqN(storeSqNs[WIDTH_ISSUE:1]),
    .IN_uop(IN_uop),
    .OUT_order(SCHED_uopOrder)
);

// 时序逻辑：更新输出寄存器和全局计数器
always_ff@(posedge clk /*or posedge rst*/) begin

    // --- 1. 复位逻辑 ---
    if (rst) begin
        counterSqN <= 0;           // 全局序列号清零
        counterStoreSqN <= -1;     // Store 序列号初始化 (预减1，因为使用时会先+1)
        counterLoadSqN <= 0;       // Load 序列号清零

        OUT_nextStoreSqN <= 0;
        OUT_nextLoadSqN <= 0;
        failSc <= 0;               // SC 失败标志清零

        // 清空输出微操作寄存器
        for (integer i = 0; i < WIDTH_ISSUE; i=i+1) begin
            OUT_uop[i] <= R_UOp'{valid: 0, validIQ: 0, default: 'x};
            OUT_uopOrdering[i] <= 'x;
        end
    end
    else begin
        // --- 2. 分支误预测恢复 (Branch Recovery) ---
        // 优先级最高：如果检测到分支预测错误，立即回滚状态
        if (IN_branch.taken) begin
            // 恢复全局序列号到分支指令时的快照 + 1
            counterSqN <= IN_branch.sqN + 1;

            // 恢复 Load/Store 序列号
            counterLoadSqN <= IN_branch.loadSqN;
            counterStoreSqN <= IN_branch.storeSqN;

            OUT_nextLoadSqN <= IN_branch.loadSqN;
            OUT_nextStoreSqN <= IN_branch.storeSqN + 1;

            // 恢复原子操作状态 (是否处于失败的 LR/SC 序列中)
            failSc <= IN_branch.isSCFail;

            // 冲刷输出寄存器 (Flush Pipeline Register)
            // Rename 阶段可能正卡着(Stall)一些比较新的指令，如果它们比分支指令年轻，必须杀掉。
            for (integer i = 0; i < WIDTH_ISSUE; i=i+1) begin
                // 如果输出寄存器里的指令 SqN 比分支指令大 (更年轻)，说明它是在错误路径上的，置为无效
                if ($signed(OUT_uop[i].sqN - IN_branch.sqN) > 0) begin
                    OUT_uop[i] <= R_UOp'{valid: 0, validIQ: 0, default: 'x};
                end
            end
        end
        else begin
            // --- 3. 正常计数器更新 ---
            // 如果没有误预测，更新为组合逻辑计算出的新值 (loadSqNs/storeSqNs 是在组合逻辑里累加好的)
            counterLoadSqN <= loadSqNs[WIDTH_ISSUE];
            counterStoreSqN <= storeSqNs[WIDTH_ISSUE];
            OUT_nextLoadSqN <= loadSqNs[WIDTH_ISSUE];
            OUT_nextStoreSqN <= storeSqNs[WIDTH_ISSUE] + 1;
        end

        // --- 4. 停顿时的就绪位监听 (Stall Handling & Snooping) ---
        // 如果 Rename 被下游 (Issue Queue) 反压停顿了，OUT_uop 里的指令会滞留。
        // 在滞留期间，如果有旧指令执行完毕并广播结果 (Writeback)，我们需要更新滞留指令的 avail 位。
        if (|portStall) begin
            // 遍历所有写回端口
            for (integer i = 0; i < WIDTH_WR; i=i+1) begin
                // 如果有有效的写回，且不是写 x0
                if (IN_flagsUOps[i].valid && !IN_flagsUOps[i].tagDst[$bits(Tag)-1]) begin
                    // 检查所有滞留在输出寄存器中的指令
                    for (integer j = 0; j < WIDTH_ISSUE; j=j+1) begin
                        if (|OUT_uop[j].validIQ) begin
                            // 如果滞留指令的源操作数 Tag 匹配写回的 Tag，将 avail 标记为 1
                            if (OUT_uop[j].tagA == IN_flagsUOps[i].tagDst)
                                OUT_uop[j].availA <= 1;
                            if (OUT_uop[j].tagB == IN_flagsUOps[i].tagDst)
                                OUT_uop[j].availB <= 1;
                            if (OUT_uop[j].tagC == IN_flagsUOps[i].tagDst)
                                OUT_uop[j].availC <= 1;
                        end
                    end
                end
            end
        end

        // --- 5. 正常指令发射 (Issue) ---
        // cycleValid 表示：无分支冲刷、前端有数据、无停顿
        if (cycleValid) begin
            // 遍历每个发射槽位
            for (integer i = 0; i < WIDTH_ISSUE; i=i+1) begin
                // 默认置为无效
                OUT_uop[i] <= R_UOp'{valid: 0, validIQ: 0, default: 'x};

                if (IN_uop[i].valid) begin

                    failSc <= 0; // 重置 SC 失败标志 (新的 LR 会开启新序列)

                    // 组装 R_UOp 结构体 (从 D_UOp + RAT 查表结果)
                    OUT_uop[i] <= R_UOp'{
                        imm:        IN_uop[i].imm,
                        imm12:      IN_uop[i].imm12,

                        // 源操作数 A: 填入物理 Tag 和当前的 Ready 状态
                        availA:     RAT_lookupAvail[2*i+0],
                        tagA:       RAT_lookupSpecTag[2*i+0],
                        // 源操作数 B
                        availB:     RAT_lookupAvail[2*i+1],
                        tagB:       RAT_lookupSpecTag[2*i+1],

                        // 源操作数 C (默认无效，Atomic 特用)
                        tagC:       TAG_ZERO,
                        availC:     1'b1,

                        // 填入分配的序列号和目标 Tag
                        sqN:        RAT_issueSqNs[i],
                        tagDst:     newTags[i],
                        rd:         IN_uop[i].rd,

                        opcode:     IN_uop[i].opcode,
                        fu:         IN_uop[i].fu,
                        fetchID:    IN_uop[i].fetchID,
                        fetchOffs:  IN_uop[i].fetchOffs,
                        storeSqN:   storeSqNs[i+1], // 填入 Store 序列号
                        loadSqN:    loadSqNs[i],    // 填入 Load 序列号
                        immB:       IN_uop[i].immB,
                        compressed: IN_uop[i].compressed,

                        valid:      1'b1,
                        // validIQ 是一个掩码，指示该指令应该去哪个发射队列。初始全为 1。
                        validIQ:    {NUM_PORTS_TOTAL{1'b1}},
                        default:    'x
                    };

                    // --- 特殊指令处理 ---

                    // TRAP 指令：将异常原因编码在 rd 字段中，节省空间
                    if (IN_uop[i].fu == FU_TRAP)
                        OUT_uop[i].rd <= IN_uop[i].opcode[4:0];

                    // SC (Store Conditional) 优化：
                    // 如果已知 SC 必然失败 (即之前没有配对的 LR，或 LR 被覆盖)，
                    // 将其转换为 FU_RN (Rename Move/Nop)，这样它不会去 LSU 执行，直接返回 1 (失败)。
                    if (isSc[i] && !scSuccessful[i])
                        OUT_uop[i].fu <= FU_RN;

                    // 原子操作 (Atomic) 特殊处理：
                    // 原子操作需要 3 个源：
                    // 1. 地址 (rs1 -> tagA)
                    // 2. 寄存器数据 (rs2 -> tagB)
                    // 3. 内存里的旧数据 (由 LSU 加载回来，放入 tagDst)
                    // 所以对于 ALU 部分，tagDst 既是结果也是第 3 个源 (tagC)。
                    if (IN_uop[i].fu == FU_ATOMIC) begin
                        OUT_uop[i].tagC <= newTags[i]; // tagC 指向目标寄存器
                        OUT_uop[i].availC <= 0;        // 初始肯定不 Ready，要等 LSU 读回来
                    end

                    // 记录调度信息
                    OUT_uopOrdering[i] <= SCHED_uopOrder[i];
                end
            end

            // 更新全局序列号
            counterSqN <= nextCounterSqN;
        end
        else begin
            // --- 6. 停顿或空闲时的 Valid 位处理 ---
            // 如果当前不是有效发射周期 (可能停顿了，或者前端没数据)，我们需要管理 valid 信号。

            // "valid": 用于 ROB 和 Store Queue。这两个模块吞吐量大，不反压，所以 valid 只维持一个周期。
            // "validIQ": 用于发射队列。每个队列有独立的 stall 信号。如果某队列反压，对应的 validIQ 位必须保持高，直到该队列接收。
            for (integer i = 0; i < WIDTH_ISSUE; i++) begin
                OUT_uop[i].valid <= 0; // 全局 valid 在一周期后拉低

                // 针对每个发射队列：如果该队列没有反压 (IN_stalls == 0)，说明它吃掉了指令，
                // 我们可以拉低对应的 validIQ 位。否则保持高电平继续请求。
                for (integer j = 0; j < NUM_PORTS_TOTAL; j=j+1) begin
                    if (!IN_stalls[j][i]) OUT_uop[i].validIQ[j] <= 0;
                end
            end
        end
    end
end
endmodule