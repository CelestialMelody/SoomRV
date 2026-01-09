module RenameTable
#(
    parameter NUM_LOOKUP=8,           // 查表端口数 (对应解码宽度的源操作数总数，例如 4指令 * 2源 = 8)
    parameter NUM_ISSUE=4,            // 发射/分配端口数 (对应解码宽度，即目的寄存器数)
    parameter NUM_COMMIT=4,           // 提交端口数 (用于更新提交状态)
    parameter NUM_WB=4,               // 写回端口数 (用于更新 Ready 位)
    parameter NUM_REGS=32,            // 逻辑寄存器数量 (RISC-V 为 32 个)
    parameter ID_SIZE=$clog2(NUM_REGS), // 逻辑寄存器索引位宽 (5 bits)
    parameter TAG_SIZE=$bits(Tag)     // 物理寄存器 Tag 位宽 (6 or 7 bits)
)
(
    input wire clk,
    input wire rst,
    input wire IN_mispred,            // 误预测信号：触发回滚恢复机制
    input wire IN_mispredFlush,       // 误预测冲刷信号

    // --- 查表接口 (Lookup) ---
    // 输入：源寄存器 ID (rs1, rs2)
    input wire[ID_SIZE-1:0] IN_lookupIDs[NUM_LOOKUP-1:0],
    // 输出：该寄存器数据是否就绪 (Ready bit)
    output reg OUT_lookupAvail[NUM_LOOKUP-1:0],
    // 输出：该寄存器对应的物理 Tag
    output reg[TAG_SIZE-1:0] OUT_lookupSpecTag[NUM_LOOKUP-1:0],

    // --- 发射/分配接口 (Issue/Allocation) ---
    // 输入：新指令是否有效
    input wire IN_issueValid[NUM_ISSUE-1:0],
    // 输入：新指令写哪个逻辑寄存器 (rd)
    input wire[ID_SIZE-1:0] IN_issueIDs[NUM_ISSUE-1:0],
    // 输入：为该指令分配的新物理 Tag
    input wire[TAG_SIZE-1:0] IN_issueTags[NUM_ISSUE-1:0],
    // 输入：新 Tag 的初始 Ready 状态 (通常为 0，除非是立即数移动)
    input wire IN_issueAvail[NUM_ISSUE-1:0],

    // --- 提交接口 (Commit) ---
    // 输入：指令是否提交
    input wire IN_commitValid[NUM_COMMIT-1:0],
    // 输入：提交指令写的逻辑寄存器 (rd)
    input wire[ID_SIZE-1:0] IN_commitIDs[NUM_COMMIT-1:0],
    // 输入：提交指令对应的物理 Tag (新 Tag)
    input wire[TAG_SIZE-1:0] IN_commitTags[NUM_COMMIT-1:0],
    // 输出：被覆盖的旧物理 Tag (用于释放回空闲列表)
    output reg[TAG_SIZE-1:0] OUT_commitPrevTags[NUM_COMMIT-1:0],

    // --- 写回接口 (Writeback) ---
    // 来自 CDB (Common Data Bus)，通知哪些 Tag 的数据计算完成了
    input wire IN_wbValid[NUM_WB-1:0],
    input wire[TAG_SIZE-1:0] IN_wbTag[NUM_WB-1:0]
);

    // 计算物理 Tag 总数 (忽略最高位特殊标记位)
    localparam NUM_TAGS = (1 << (TAG_SIZE - 1));

    // =========================================================
    // 核心存储结构
    // =========================================================

    // Committed Map: 记录已提交的架构状态 (Architecture State)
    // 只有指令安全退休时才更新，用于误预测恢复的“存档点”
    logic[TAG_SIZE-1:0] comTag[NUM_REGS-1:0] /*verilator public*/;

    // Speculative Map: 记录当前的推测状态 (Speculative State)
    // 指令发射时立即更新，供后续指令查依赖
    logic[TAG_SIZE-1:0] specTag[NUM_REGS-1:0] /*verilator public*/;

    // Availability Scoreboard: 记录物理 Tag 的数据是否就绪
    // 1 = 数据已在寄存器中 (Ready), 0 = 数据还在计算中 (Busy)
    reg[NUM_TAGS-1:0] tagAvail /*verilator public*/;

    // =========================================================
    // 组合逻辑：查表与旁路 (Lookup Logic)
    // =========================================================
    always_comb begin
        // 遍历所有查表请求 (所有源操作数)
        for (integer i = 0; i < NUM_LOOKUP; i=i+1) begin
            // 1. 默认从推测表 (specTag) 读取物理 Tag
            OUT_lookupSpecTag[i] = specTag[IN_lookupIDs[i]];

            // 2. 检查就绪状态
            // 查 tagAvail 表。注意：如果 Tag 最高位为 1 (TAG_ZERO)，则永远视为就绪
            OUT_lookupAvail[i] = tagAvail[OUT_lookupSpecTag[i][TAG_SIZE-2:0]] | OUT_lookupSpecTag[i][TAG_SIZE-1];

            // 3. 写回旁路 (Writeback Forwarding)
            // 如果某条指令在当前周期刚刚写回结果 (Result Bus)，
            // 那么虽然 tagAvail 寄存器还没更新 (要下个周期)，但我们应立即视为就绪。
            for (integer j = 0; j < NUM_WB; j=j+1) begin
                if (IN_wbValid[j] && IN_wbTag[j] == OUT_lookupSpecTag[i])
                    OUT_lookupAvail[i] = 1;
            end

            // 4. 组内依赖检查 (Intra-group Dependency Check) -- 关键逻辑！
            // 处理同一发射包内的 RAW (Read-after-Write) 依赖。
            // 例如：Instr 0: ADD x1, x2, x3;  Instr 1: SUB x4, x1, x5
            // Instr 1 读取 x1 时，必须读到 Instr 0 刚刚分配的新 Tag，而不是 specTag 里的旧 Tag。
            // (i / 2) 的意思是：第 i 个源操作数属于第 (i/2) 条指令。我们只看它前面的指令 (j < i/2)。
            for (integer j = 0; j < (i / 2); j=j+1) begin
                // 如果前面的指令有效，且写入的目标 (issueIDs) 等于我们要读的源 (lookupIDs)
                if (IN_issueValid[j] && IN_issueIDs[j] == IN_lookupIDs[i] && IN_issueIDs[j] != 0) begin
                    // 旁路：直接使用该指令新分配的 Tag
                    OUT_lookupSpecTag[i] = IN_issueTags[j];
                    // 旁路：使用该指令的初始 Ready 状态 (通常是 0，除非是 MV 立即数等)
                    OUT_lookupAvail[i] = IN_issueAvail[j];
                end
            end
        end

        // 读取提交指令覆盖掉的旧 Tag (用于释放回 FreeList)
        for (integer i = 0; i < NUM_COMMIT; i=i+1) begin
            OUT_commitPrevTags[i] = comTag[IN_commitIDs[i]];
        end
    end

    // =========================================================
    // 时序逻辑：状态更新 (State Update)
    // =========================================================
    always_ff@(posedge clk /*or posedge rst*/) begin

        if (rst) begin
            // 复位：所有映射指向 TAG_ZERO
            for (integer i = 0; i < NUM_REGS; i=i+1) begin
                comTag[i] <= TAG_ZERO;
                specTag[i] <= TAG_ZERO;
            end
            // 复位：所有物理寄存器标记为就绪 (避免死锁)
            tagAvail <= {NUM_TAGS{1'b1}};
        end
        else begin
            // 1. 处理写回 (Writeback): 更新 Scoreboard
            // 当执行单元完成计算广播 Tag 时，将对应的 tagAvail 置 1
            for (integer i = 0; i < NUM_WB; i=i+1) begin
                if (IN_wbValid[i] && !IN_wbTag[i][TAG_SIZE-1]) begin // 忽略特殊 Tag
                    tagAvail[IN_wbTag[i][TAG_SIZE-2:0]] <= 1;
                end
            end

            // 2. 处理误预测 (Misprediction Recovery)
            if (IN_mispred) begin
                for (integer i = 1; i < NUM_REGS; i=i+1) begin
                    // 发生误预测时，Speculative 状态已经污染。
                    // 必须将 specTag 重置为 comTag (已提交的正确状态)。
                    // 也就是 "Walkback" 机制。之后 ROB 会重放那些正确路径上未提交的指令来重建 specTag。
                    specTag[i] <= comTag[i];
                end
            end
            else begin
                // 3. 正常发射 (Normal Issue): 更新推测表
                for (integer i = 0; i < NUM_ISSUE; i=i+1) begin
                    // 如果指令有效且不是写 x0
                    if (IN_issueValid[i] && IN_issueIDs[i] != 0) begin
                        // 更新推测映射表：x(rd) 现在映射到 newTag
                        specTag[IN_issueIDs[i]] <= IN_issueTags[i];

                        // 更新 Scoreboard：新分配的 Tag 尚未计算完成，标记为 Busy (0)
                        if (!IN_issueTags[i][TAG_SIZE-1]) begin
                            tagAvail[IN_issueTags[i][TAG_SIZE-2:0]] <= 0;
                            // 断言：分配时它确实应该是 Busy 的
                            assert(IN_issueAvail[i] == 0);
                        end
                    end
                end
            end

            // 4. 处理提交 (Commit): 更新退休表
            for (integer i = 0; i < NUM_COMMIT; i=i+1) begin
                if (IN_commitValid[i] && IN_commitIDs[i] != 0) begin
                    // 这里的逻辑有点微妙，处理 Flush 期间的提交行为
                    if (IN_mispredFlush) begin
                        if (!IN_mispred) begin
                            // 在 Flush 期间，如果是正确的指令提交，仍需更新 specTag
                            // (这部分逻辑通常用于处理 ROB Walk 重建期间的状态?)
                            specTag[IN_commitIDs[i]] <= IN_commitTags[i];
                        end
                    end
                    else begin
                        // 正常提交：更新存档点 comTag
                        comTag[IN_commitIDs[i]] <= IN_commitTags[i];

                        // 这是一个极其罕见的边界情况处理：
                        // 如果同时发生提交和误预测？通常 mispred 优先级更高。
                        if (IN_mispred)
                            specTag[IN_commitIDs[i]] <= IN_commitTags[i];
                    end
                end
            end
        end
    end

endmodule