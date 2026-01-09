// 处理器核心顶层模块
module Core
(
    input wire clk,              // 时钟信号
    input wire rst,              // 复位信号 (高电平有效)
    input wire en,               // 核心使能信号

    input wire IN_irq,           // 外部中断输入

    // Cache 接口 (指令和数据)
    IF_Cache.HOST IF_cache,      // 数据 Cache 物理接口 (读写 SRAM)
    IF_CTable.HOST IF_ct,        // 数据 Cache 标签表接口 (Tag RAM)
    IF_MMIO.HOST IF_mmio,        // MMIO 总线接口 (用于外设)
    IF_CSR_MMIO.CSR IF_csr_mmio, // CSR 专用 MMIO (如 mtime, mtimecmp)

    IF_ICTable.HOST IF_ict,      // 指令 Cache 标签表接口
    IF_ICache.HOST IF_icache,    // 指令 Cache 数据接口

    // 内存控制器接口 (用于处理 Cache Miss)
    // 数组大小为 3，分别对应 IFetch(0), LSU(1), BypassLSU(2)
    output MemController_Req OUT_memc[2:0],
    input MemController_Res IN_memc,

    // 调试信息输出 (不影响逻辑，用于波形观察)
    output DebugInfo OUT_dbg
);

// 将各子模块的内存请求连接到输出端口
assign OUT_memc[0] = PC_MC_if;    // 取指单元的内存请求
assign OUT_memc[1] = LSU_MC_if;   // 加载存储单元的内存请求
assign OUT_memc[2] = BLSU_MC_if;  // Bypass LSU 的内存请求

// 连接调试信号
assign OUT_dbg.stallPC = TH_stallPC;   // 当前停顿的 PC (Trap Handler)
assign OUT_dbg.sqNStall = sqNStall;    // 因 ROB 满而停顿
assign OUT_dbg.stSqNStall = 0;         // (未使用)
assign OUT_dbg.rnStall = RN_stall;     // 因重命名资源不足而停顿
assign OUT_dbg.memBusy = MEM_busy;     // 内存系统忙
assign OUT_dbg.sqBusy = !SQ_empty || SQB_uop.valid; // Store Queue 忙
assign OUT_dbg.lsuBusy = 0; // (注释掉的逻辑)
assign OUT_dbg.ldNack = 0;  // (注释掉的逻辑)
assign OUT_dbg.stNack = 0;  // (注释掉的逻辑)

// 提交微操作数组 (ROB 输出)，暴露给 Verilator 用于仿真
CommitUOp comUOps[`DEC_WIDTH-1:0] /*verilator public*/;

// 取指使能信号 (除非 Trap Handler 禁止，否则一直取指)
wire ifetchEn = en && !TH_disableIFetch;

// 分支相关参数定义
localparam NUM_BRANCHES = NUM_BRANCH_PORTS + 2; // 分支源总数 (ALU端口 + LoadQueue + TrapHandler)
localparam LQ_BRANCH_PORT = NUM_BRANCHES-2;     // Load Queue 分支端口索引 (处理内存顺序违规)
localparam TH_BRANCH_PORT = NUM_BRANCHES-1;     // Trap Handler 分支端口索引 (处理异常跳转)

// 分支提供者数组 (各个模块产生的分支请求)
BranchProv branchProvs[NUM_BRANCH_PORTS+1:0]; // 注意这里定义大小可能有点小瑕疵，应该是 NUM_BRANCHES-1:0
// 全局分支信号 (最终选出的获胜分支，会触发冲刷)
BranchProv branch /*verilator public*/;
// 误预测冲刷信号 (由 ROB 产生)
wire mispredFlush /*verilator public*/;
// 性能计数器：分支误预测
wire BS_PERFC_branchMispr;

// 分支选择器 (Branch Selector)
// 从多个可能产生分支重定向的源中选出一个优先级最高的
BranchSelector#(4) bsel
(
    .clk(clk),
    .rst(rst),

    .IN_isUOps(IS_uop[NUM_BRANCH_PORTS-1:0]), // 发射阶段的分支信息

    .IN_branches(branchProvs[3:0]), // 输入各个端口的分支请求
    .OUT_branch(branch),            // 输出最终选定的分支请求

    .OUT_PERFC_branchMispr(BS_PERFC_branchMispr),

    .IN_ROB_curSqN(ROB_curSqN),    // 当前 ROB 指针 (用于判断分支新旧)
    .IN_RN_nextSqN(RN_nextSqN),    // 下一个分配的 SqN
    .IN_mispredFlush(mispredFlush) // 是否发生了误预测冲刷
);

// BTB 更新信号数组 (执行单元反馈给前端)
BTUpdate BP_btUpdates[NUM_ALUS-1:0];

// PC File 读请求和读数据接口 (后端根据 FetchID 查 PC)
PCFileReadReq PC_readReq[NUM_BRANCH_PORTS-1:0];
PCFileEntry PC_readData[NUM_BRANCH_PORTS-1:0];
// Trap Handler 专用的高优先级 PC File 读接口
PCFileReadReqTH PC_readReqTH;
PCFileEntry PC_readDataTH;

// 取指单元的内存请求和页表漫游请求
MemController_Req PC_MC_if;
PageWalk_Req PC_PW_rq;

// 取指单元 (Instruction Fetch) 模块实例化
IFetch ifetch
(
    .clk(clk),
    .rst(rst),
    .IN_en(ifetchEn),

    .IN_interruptPending(CSR_trapControl.interruptPending), // 中断挂起信号
    .IN_MEM_busy(MEM_busy), // 内存系统忙 (可能需要暂停预取)

    .IF_ict(IF_ict),       // I-Cache Tag 接口
    .IF_icache(IF_icache), // I-Cache Data 接口

    .IN_ROB_curFetchID(ROB_curFetchID), // ROB 当前提交的 FetchID
    .IN_branch(branch),     // 后端传来的分支重定向
    .IN_decBranch(decBranch), // 解码阶段传来的简单分支 (如 JAL)

    .IN_clearICache(TH_clearICache), // 清空 I-Cache 请求
    .IN_flushTLB(TH_flushTLB),       // 刷新 TLB 请求
    .IN_btUpdates(BP_btUpdates[NUM_BRANCH_PORTS-1:0]), // BTB 更新信息
    .IN_bpUpdate(ROB_bpUpdate),      // 分支预测器更新信息 (从 ROB)

    .IN_pcRead(PC_readReq),          // PC File 读请求
    .OUT_pcReadData(PC_readData),    // PC File 读数据
    .IN_pcReadTH(PC_readReqTH),      // Trap Handler PC 读请求
    .OUT_pcReadDataTH(PC_readDataTH),

    // 反压信号：如果 Rename 没停顿且前端使能，则可以输出指令
    .IN_ready(!RN_stall && frontendEn),
    .OUT_instrs(PD_instrs),          // 输出预解码指令包

    .IN_vmem(CSR_vmem),              // 虚拟内存配置 (satp)
    .OUT_pw(PW_reqs[0]),             // 输出 Page Walker 请求
    .IN_pw(PW_res),                  // 接收 Page Walker 响应

    .OUT_memc(PC_MC_if),             // 输出内存控制器请求 (Cache Miss)
    .IN_memc(IN_memc)                // 接收内存控制器响应
);

// 下一个要分配的序列号 (来自 Rename)
SqN RN_nextSqN;
// 当前最老的未提交序列号 (来自 ROB)
SqN ROB_curSqN /*verilator public*/;

// 预解码指令包 (连接 IFetch 和 Decoder)
PD_Instr PD_instrs[`DEC_WIDTH-1:0] /*verilator public*/;

// 解码后微操作数组
D_UOp DE_uop[`DEC_WIDTH-1:0] /*verilator public*/;
// 解码阶段识别的分支信息
DecodeBranch decBranch;

// 指令解码器模块实例化
InstrDecoder idec
(
    .clk(clk),
    .rst(rst),
    .en(!RN_stall && frontendEn), // 使能：Rename 不停顿且前端开启
    .IN_branch(branch),           // 分支冲刷信号

    .IN_dec(CSR_dec),             // 解码配置 (如允许自定义指令)
    .IN_instrs(PD_instrs),        // 输入预解码指令

    .IN_enCustom(1'b1),           // 启用自定义指令

    .OUT_uop(DE_uop),             // 输出解码微操作
    .OUT_decBranch(decBranch)     // 输出解码分支信息
);

// 序列号停顿信号：检查 ROB 是否已满
// 计算：(NextSqN - CurSqN) > (Max - Width)
// 简单说就是飞行中的指令数快接近 ROB 容量上限了
wire sqNStall = ($signed((RN_nextSqN) - ROB_maxSqN) > -(`DEC_WIDTH));

// 前端使能信号
wire frontendEn /*verilator public*/ =
    !sqNStall &&      // ROB 没满
    !branch.taken &&  // 没有正在发生的分支跳转 (正在处理 Flush)
    !SQ_flush;        // 没有 Store Queue 刷新

// 重命名微操作数组 (Rename -> Issue)
R_UOp RN_uop[`DEC_WIDTH-1:0] /*verilator public*/;
// 微操作顺序信息 (用于指令拆分)
IntUOpOrder_t RN_uopOrdering[`DEC_WIDTH-1:0];
// 下一个 Load/Store 序列号 (用于 LSU 排序)
SqN RN_nextLoadSqN;
SqN RN_nextStoreSqN;
// 重命名阶段停顿信号 (物理寄存器耗尽等)
wire RN_stall /*verilator public*/;

// 重命名模块实例化
Rename#(.WIDTH_WR(NUM_PORTS)) rn
(
    .clk(clk),
    .frontEn(frontendEn),
    .rst(rst),

    .IN_stalls(IQ_stalls),       // 输入各个发射队列的停顿信号 (反压)
    .OUT_stall(RN_stall),        // 输出 Rename 总停顿信号

    .IN_uop(DE_uop),             // 输入解码微操作

    .IN_comUOp(comUOps),         // 输入提交微操作 (用于释放旧 Tag)

    .IN_flagsUOps(flagUOps[NUM_PORTS-1:0]), // 输入执行单元的标志更新

    .IN_branch(branch),          // 分支冲刷信号
    .IN_mispredFlush(mispredFlush), // 误预测冲刷

    .OUT_uop(RN_uop),            // 输出重命名微操作
    .OUT_uopOrdering(RN_uopOrdering),
    .OUT_nextSqN(RN_nextSqN),
    .OUT_nextLoadSqN(RN_nextLoadSqN),
    .OUT_nextStoreSqN(RN_nextStoreSqN)
);

// 发射微操作数组 (Issue -> Execute)
IS_UOp IS_uop[NUM_PORTS-1:0] /*verilator public*/;
// 各端口停顿信号
wire stall[NUM_PORTS-1:0] /*verilator public*/;

// 发射队列停顿信号矩阵 (每个端口对每个解码槽位的反压)
wire[NUM_PORTS_TOTAL-1:0][`DEC_WIDTH-1:0] IQ_stalls;
// 除法器/浮点除法器反压信号 (防止非流水化的除法器接收新请求)
wire DIV_doNotIssue[NUM_PORTS-1:0];
wire FDIV_doNotIssue[NUM_PORTS-1:0];

// 生成发射队列 (每个执行端口一个)
generate for (genvar i = 0; i < NUM_PORTS; i=i+1)
    IssueQueue#(
        .SIZE(PORT_IQ_SIZE[i]),    // 队列深度 (来自 Config.sv)
        .NUM_ENQUEUE(2),           // 每周期最大入队数
        .PORT_IDX(i),              // 端口索引
        .NUM_OPERANDS((i<NUM_ALUS) ? 2 : 1), // 操作数数量 (ALU=2, AGU=1)
        .NUM_UOPS(`DEC_WIDTH),     // 输入宽度
        .RESULT_BUS_COUNT(NUM_PORTS), // 结果总线宽度 (用于监听唤醒)
        .IMM_BITS((i<NUM_ALUS) ? 36 : 12), // 立即数存储位宽
        .FUS(PORT_FUS[i])          // 支持的功能单元位掩码
    ) iq (
        .clk(clk),
        .rst(rst),

        // 输入反压：如果这是 AGU 队列，可能还要考虑 StoreQueue 的反压
        .IN_defer((i<NUM_ALUS) ? '0 : IQ_stalls[i+NUM_AGUS]),
        .OUT_stall(IQ_stalls[i]),  // 输出该队列是否满

        .IN_stall(stall[i]),       // 执行单元是否忙 (无法发射)
        .IN_doNotIssueDiv((i < NUM_ALUS) ? DIV_doNotIssue[i] : 1'b0), // 除法器忙
        .IN_doNotIssueFDiv((i < NUM_ALUS) ? FDIV_doNotIssue[i] : 1'b0), // 浮点除法器忙

        .IN_uop(RN_uop),           // 输入重命名微操作 (入队)
        .IN_uopOrdering(RN_uopOrdering),

        .IN_flagUOp(flagUOps[NUM_PORTS-1:0]), // 执行结果广播 (唤醒队列中的指令)

        .IN_branch(branch),        // 分支冲刷 (清除队列中的错误指令)

        .IN_issueUOps(IS_uop),     // 其他端口发射的指令 (用于检查冲突?)

        .IN_maxStoreSqN(SQ_maxStoreSqN), // 当前最大 Store SqN (内存依赖检查)
        .IN_maxLoadSqN(LB_maxLoadSqN),   // 当前最大 Load SqN
        .IN_commitSqN(ROB_curSqN),       // 提交 SqN

        .OUT_uop(IS_uop[i])        // 输出发射的微操作
    );
endgenerate

// ============================================================================
// 存储数据发射队列 (Store Data Issue Queue)
// ============================================================================
// SoomRV 采用 "Store Data" 和 "Store Address" 分离发射的设计。
// 这里生成 AGU 数量的存储数据查找请求。

StDataLookupUOp stLookupUOp[NUM_AGUS-1:0];   // 输出：存储数据查找微操作
wire stLookupUOp_ready[NUM_AGUS-1:0];        // 输入：查找单元准备好接收
ComLimit stCommitLimit[NUM_AGUS-1:0];        // 输出：存储提交限制 (告诉 SQB 可以提交到哪)

generate for (genvar i = 0; i < NUM_AGUS; i=i+1) begin
    StoreDataIQ #(
        .SIZE(PORT_IQ_SIZE[i+NUM_AGUS]), // 队列大小
        .NUM_ENQUEUE(2),                 // 入队带宽
        .PORT_IDX(i),                    // AGU 端口索引
        .NUM_UOPS(`DEC_WIDTH),           // 输入带宽
        .RESULT_BUS_COUNT(NUM_PORTS)     // 结果总线宽度 (用于监听唤醒)
    ) iqStD
    (
        .clk(clk),
        .rst(rst),

        // 停顿信号：对应 IQ_stalls 的高位部分 (NUM_PORTS+i)
        .OUT_stall(IQ_stalls[NUM_PORTS+i]),
        .IN_uop(RN_uop),                 // 来自 Rename 的微操作

        // 监听执行结果广播 (唤醒数据依赖)
        .IN_flagUOp(flagUOps[NUM_PORTS-1:0]),

        .IN_branch(branch),              // 分支冲刷

        .IN_issueUOps(IS_uop),           // 其他端口发射信息 (可能用于冲突检测)

        // 输入 AGU 发射的微操作 (用于匹配 Store Address 和 Store Data)
        .IN_aguUOps(LD_uop[NUM_ALUS+:NUM_AGUS]),
        .IN_maxStoreSqN(SQ_maxStoreSqN), // 最大 Store SqN

        .OUT_comLimit(stCommitLimit[i]), // 输出提交限制

        .IN_ready(stLookupUOp_ready[i]), // 下级 (StoreDataLoad) 是否准备好
        .OUT_uop(stLookupUOp[i])         // 输出发射的请求
    );
end endgenerate

// ============================================================================
// 物理寄存器堆写口逻辑 (Register File Write Logic)
// ============================================================================
// 将执行单元的计算结果 (resultUOps) 映射到寄存器堆写端口。

logic[NUM_RF_WRITES-1:0] RF_writeEnable;
RFTag[NUM_RF_WRITES-1:0] RF_writeAddress;
RegT[NUM_RF_WRITES-1:0] RF_writeData;

always_comb begin
    for (integer i = 0; i < NUM_RF_WRITES; i=i+1) begin
        // 取 Tag 的低位作为物理地址索引
        RF_writeAddress[i] = RFTag'(resultUOps[i].tagDst);
        RF_writeData[i] = resultUOps[i].result;
        // 写使能条件：结果有效 且 目标 Tag 不是 TAG_ZERO (最高位为 0)
        RF_writeEnable[i] = resultUOps[i].valid && !resultUOps[i].tagDst[$bits(Tag)-1];
    end
end

// ============================================================================
// 物理寄存器堆读口复用 (Register File Read Mux)
// ============================================================================
// 只有有限的物理读端口 (NUM_RF_READS_PHY)，但可能有更多的逻辑读请求 (NUM_RF_READS)。
// RFReadMux 负责仲裁和分配读端口。

RF_ReadReq[NUM_RF_READS-1:0] RFMUX_reads;    // 来自 Load 单元的所有读请求
logic[NUM_RF_READS-1:0] RFMUX_readReady;     // 哪些请求被允许读取
RegT[NUM_RF_READS-1:0] RFMUX_readData;       // 读回的数据

RFReadMux#(NUM_RF_READS, NUM_RF_READS_PHY) rfMux
(
    .clk(clk),

    .IN_read(RFMUX_reads),           // 输入：所有逻辑读请求
    .OUT_readReady(RFMUX_readReady), // 输出：哪些请求成功拿到端口
    .OUT_readData(RFMUX_readData),   // 输出：分配到的数据

    // 连接到物理 RF 的接口
    .OUT_readEnable(RF_readEnable),
    .OUT_readAddress(RF_readAddress),
    .IN_readData(RF_readDataRaw)
);

// 物理寄存器堆实例化
logic[NUM_RF_READS_PHY-1:0] RF_readEnable;
RFTag[NUM_RF_READS_PHY-1:0] RF_readAddress;
RegT[NUM_RF_READS_PHY-1:0] RF_readDataRaw;

RegFile#(32, 1 << $bits(RFTag), NUM_RF_READS_PHY, NUM_RF_WRITES, 1) rf
(
    .clk(clk),

    .IN_re(RF_readEnable),
    .IN_raddr(RF_readAddress),
    .OUT_rdata(RF_readDataRaw),

    .IN_we(RF_writeEnable),
    .IN_waddr(RF_writeAddress),
    .IN_wdata(RF_writeData)
);

// ============================================================================
// 加载单元 (Load Unit - Operand Fetch)
// ============================================================================
// 负责从 RF 读取源操作数，将 IS_UOp (Tag) 转换为 LD_uop (Data)。
// 实现 "Load-after-Issue" 逻辑。

EX_UOp LD_uop[NUM_PORTS-1:0] /*verilator public*/; // 输出到执行单元的 UOp

ZCForward LD_zcFwd[NUM_ALUS-1:0]; // 零周期前推信号 (Zero Cycle Forwarding)

Load#(
    .NUM_UOPS(NUM_PORTS),
    .NUM_WBS(NUM_PORTS),
    .NUM_ZC_FWDS(NUM_ALUS),
    .NUM_PC_READS(NUM_BRANCH_PORTS)
) ld
(
    .clk(clk),
    .rst(rst),

    .IN_uop(IS_uop), // 输入：发射队列出来的 UOp (带 Tag)

    .IN_resultUOps(resultUOps[NUM_PORTS-1:0]), // 输入：写回结果 (用于 Bypass/Forwarding)

    .IN_branch(branch),
    .IN_stall(stall), // 反压信号

    .IN_zcFwd(LD_zcFwd), // 接收零周期前推

    // PC 读取接口 (用于分支跳转计算)
    .OUT_pcRead(PC_readReq),
    .IN_pcReadData(PC_readData),

    // 连接到 RF Mux 的读请求
    .OUT_rfReadReq(RFMUX_reads[0 +: 2*NUM_ALUS + NUM_AGUS]),
    .IN_rfReadData(RFMUX_readData[0 +: 2*NUM_ALUS + NUM_AGUS]),

    .OUT_uop(LD_uop) // 输出：准备好执行的 UOp (带 Data)
);

// ============================================================================
// 存储数据加载 (Store Data Load)
// ============================================================================
// 专门负责读取 Store 指令要写入内存的数据 (rs2)。

AMO_Data_UOp SDL_amoData[NUM_ALUS-1:0];   // 原子操作数据
StDataUOp SDL_stDataUOp[NUM_AGUS-1:0];    // 输出：Store Data UOp

StoreDataLoad#(NUM_AGUS) stDataLd
(
    .clk(clk),
    .rst(rst),

    .IN_branch(branch),

    .IN_uop(stLookupUOp),             // 来自 StoreDataIQ 的请求
    .OUT_ready(stLookupUOp_ready),    // 反压信号

    .IN_atomicUOp(SDL_amoData[NUM_AGUS-1:0]), // 原子操作数据输入

    // 连接到 RF Mux 的最后几个读端口 (专门留给 Store)
    .OUT_readReq(RFMUX_reads[NUM_RF_READS-1 -: NUM_AGUS]),
    .IN_readReady(RFMUX_readReady[NUM_RF_READS-1 -: NUM_AGUS]),
    .IN_readData(RFMUX_readData[NUM_RF_READS-1 -: NUM_AGUS]),

    .OUT_uop(SDL_stDataUOp)           // 输出到 LSU 的 Store Data
);

// CSR 状态信号
TrapControlState CSR_trapControl /*verilator public*/;
wire[2:0] CSR_fRoundMode; // 浮点舍入模式
DecodeState CSR_dec;      // 解码配置
VirtMemState CSR_vmem;    // 虚拟内存配置

// 结果总线定义
ResultUOp resultUOps[NUM_PORTS-1:0] /*verilator public*/;
FlagsUOp flagUOps[NUM_PORTS_TOTAL-1:0] /*verilator public*/;

// ============================================================================
// 整数执行端口生成 (Integer Execution Ports Generation)
// ============================================================================
// 遍历所有 ALU 端口，根据 Config.sv 中的 PORT_FUS 配置实例化相应的功能单元。

generate for (genvar i = 0; i < NUM_ALUS; i=i+1) begin : intPortsGen
    // 临时信号：存储各类型 FU 的输出结果
    // verilator lint_off UNDRIVEN
    RES_UOp[(1<<$bits(FuncUnit))-1:0] resUOps;
    // verilator lint_on UNDRIVEN

    // ALU 端口通常不停顿 (单周期)
    assign stall[i] = 1'b0;

    // --- 整数 ALU (INT / BRANCH / BITMANIP / ATOMIC) ---
    if ((PORT_FUS[i] & (FU_INT_OH|FU_BRANCH_OH|FU_BITMANIP_OH|FU_ATOMIC_OH)) != 0) begin
        BranchProv ialuBranch;

        // 实例化 IntALU
        IntALU#(PORT_FUS[i] & (FU_INT_OH|FU_BRANCH_OH|FU_BITMANIP_OH|FU_ATOMIC_OH)) ialu
        (
            .clk(clk),
            .rst(rst),

            .IN_uop(LD_uop[i]),
            .IN_branch(branch),

            .OUT_branch(ialuBranch),      // 分支重定向
            .OUT_btUpdate(BP_btUpdates[i]), // BTB 更新

            .OUT_zcFwd(LD_zcFwd[i]),      // 产生零周期前推

            .OUT_amoData(SDL_amoData[i]), // 原子操作数据输出
            .OUT_uop(resUOps[FU_INT])     // 结果输出
        );
        // 如果是支持分支的端口，连接到分支选择器
        if (i < NUM_BRANCH_PORTS)
            assign branchProvs[i] = ialuBranch;
    end

    // --- 除法器 (DIV) ---
    if ((PORT_FUS[i] & FU_DIV_OH) != 0) begin
        wire DIV_busy;
        Divide div
        (
            .clk(clk),
            .rst(rst),
            .en(LD_uop[i].valid && LD_uop[i].fu == FU_DIV), // 使能

            .OUT_busy(DIV_busy), // 忙信号

            .IN_branch(branch),
            .IN_uop(LD_uop[i]),
            .OUT_uop(resUOps[FU_DIV])
        );
        // 如果除法器忙，或者当前指令是除法，则阻塞发射
        assign DIV_doNotIssue[i] = DIV_busy ||
            (LD_uop[i].valid && LD_uop[i].fu == FU_DIV) ||
            (IS_uop[i].valid && IS_uop[i].fu == FU_DIV);
    end
    else assign DIV_doNotIssue[i] = 1'b1;


    // --- 浮点单元 (FPU) ---
    if ((PORT_FUS[i] & FU_FPU_OH) != 0)
        FPU fpu
        (
            .clk(clk),
            .rst(rst),
            .en(LD_uop[i].valid && LD_uop[i].fu == FU_FPU),

            .IN_branch(branch),
            .IN_uop(LD_uop[i]),

            .IN_fRoundMode(CSR_fRoundMode),
            .OUT_uop(resUOps[FU_FPU])
        );

    // --- 整数乘法 (MUL) ---
    if ((PORT_FUS[i] & FU_MUL_OH) != 0)
        Multiply mul
        (
            .clk(clk),
            .rst(rst),
            .en(LD_uop[i].valid && LD_uop[i].fu == FU_MUL),

            .OUT_busy(), // 乘法通常流水化，不忙

            .IN_branch(branch),
            .IN_uop(LD_uop[i]),
            .OUT_uop(resUOps[FU_MUL])
        );

    // --- 浮点乘法 (FMUL) ---
    if ((PORT_FUS[i] & FU_FMUL_OH) != 0)
        FMul fmul
        (
            .clk(clk),
            .rst(rst),
            .en(LD_uop[i].valid && LD_uop[i].fu == FU_FMUL),

            .IN_branch(branch),
            .IN_uop(LD_uop[i]),

            .IN_fRoundMode(CSR_fRoundMode),
            .OUT_uop(resUOps[FU_FMUL])
        );

    // --- 浮点除法 (FDIV) ---
    if ((PORT_FUS[i] & FU_FDIV_OH) != 0) begin
        wire FDIV_busy;
        FDiv fdiv
        (
            .clk(clk),
            .rst(rst),
            .en(LD_uop[i].valid && LD_uop[i].fu == FU_FDIV),

            .IN_wbAvail(1'b1),
            .OUT_busy(FDIV_busy),

            .IN_branch(branch),
            .IN_uop(LD_uop[i]),
            .IN_fRoundMode(CSR_fRoundMode),
            .OUT_uop(resUOps[FU_FDIV])
        );
        assign FDIV_doNotIssue[i] = FDIV_busy ||
            (LD_uop[i].valid && LD_uop[i].fu == FU_FDIV) ||
            (IS_uop[i].valid && IS_uop[i].fu == FU_FDIV);
    end
    else assign FDIV_doNotIssue[i] = 1;

    // --- CSR 单元 ---
    if ((PORT_FUS[i] & FU_CSR_OH) != 0) begin
        CSR csr
        (
            .clk(clk),
            .rst(rst),
            .en(LD_uop[i].valid && LD_uop[i].fu == FU_CSR),

            .IN_irq(IN_irq), // 中断输入

            .IN_uop(LD_uop[i]),
            .IN_branch(branch),
            .IN_fpNewFlags(ROB_fpNewFlags), // 浮点异常标志更新

            .IN_perfcInfo(ROB_perfcInfo),   // 性能计数器信息
            .IN_branchMispr(BS_PERFC_branchMispr),

            .IF_mmio(IF_csr_mmio),          // 连接 CSR MMIO 接口

            .IN_tvalState(TVS_tvalState),   // 异常值 (TVAL)

            .IN_trapInfo(TH_trapInfo),      // Trap Handler 信息
            .OUT_trapControl(CSR_trapControl), // 输出 Trap 控制信号
            .OUT_fRoundMode(CSR_fRoundMode),

            .OUT_dec(CSR_dec),
            .OUT_vmem(CSR_vmem),

            .OUT_uop(resUOps[FU_CSR])
        );
    end

    // --- 结果选择逻辑 (Result Mux) ---
    // 一个端口可能支持多种操作 (如 ALU+MUL)，这里选择有效的那个输出
    RES_UOp wbUOp;
    always_comb begin
        wbUOp = RES_UOp'{valid: 0, default: 'x};
        for (integer j = 0; j < (1 << $bits(FuncUnit)); j=j+1) begin
            // 检查配置是否支持该 FU 且 结果是否有效
            if ((PORT_FUS[i] & (1 << j)) != 0 && resUOps[j].valid)
                wbUOp = resUOps[j];
        end
    end

    // 将宽结果拆分为 标志 (Flag) 和 数据 (Result) 两个总线
    // FlagUOp 用于 ROB 和 IssueQueue 唤醒
    // ResultUOp 用于 RF 写回
    ResultFlagsSplit wbUOpSplit(wbUOp, flagUOps[i], resultUOps[i]);
end endgenerate

// ============================================================================
// 异常值选择逻辑 (TVal Select)
// ============================================================================
// 当发生异常时，某些异常需要记录导致异常的值 (mtval/stval)，例如错误的内存地址。
// 这个模块负责从多个 AGU 中收集潜在的异常值。

TValProv TVS_tvalProvs[NUM_AGUS-1:0]; // 输入：来自各个 AGU 的异常值提供者
TValState TVS_tvalState;             // 输出：最终选定的异常状态

TValSelect#(NUM_AGUS) tvalSelect
(
    .clk(clk),
    .rst(rst),
    .IN_branch(branch),          // 分支冲刷信号
    .IN_commitSqN(ROB_curSqN),   // 当前提交的序列号 (用于确定哪个指令是最老的异常)
    .IN_tvalProvs(TVS_tvalProvs),
    .OUT_tvalState(TVS_tvalState)
);

// ============================================================================
// 页表漫游器 (Page Walker)
// ============================================================================
// 当 TLB 缺失时，硬件自动遍历页表。

PageWalk_Req PW_reqs[(NUM_AGUS+1)-1:0]; // 请求来源：取指单元(1) + AGU(2)
PageWalk_Res PW_res;                    // 漫游结果 (PTE)
wire CC_PW_LD_stall[NUM_AGUS-1:0];      // 漫游器发出的 Load 请求被阻塞信号
PW_LD_UOp PW_LD_uop[NUM_AGUS-1:0];      // 漫游器发出的 Load 微操作 (读页表)

// 初始化漫游器 Load 信号 (目前 PageWalker 只使用端口 0 发起 Load)
generate
for (genvar i = 1; i < NUM_AGUS; i=i+1)
    assign PW_LD_uop[i] = PW_LD_UOp'{valid: 0, default: 'x};
endgenerate

PageWalker#(NUM_AGUS+1) pageWalker
(
    .clk(clk),
    .rst(rst),

    .IN_rqs(PW_reqs),           // 输入：TLB Miss 请求
    .OUT_res(PW_res),           // 输出：填入 TLB 的页表项

    // Page Walker 自身也需要访问内存 (读页表)，它复用 LSU 的端口
    .IN_ldStall(CC_PW_LD_stall[0]),       // Load 请求被反压
    .OUT_ldUOp(PW_LD_uop[0]),             // 发出的 Load 请求
    .IN_ldAck(LSU_ldAck),                 // Load 完成确认
    .IN_ldResUOp(resultUOps[NUM_ALUS+:NUM_AGUS]) // Load 返回数据
);

// ============================================================================
// 加载请求选择器 (Load Selector)
// ============================================================================
// 仲裁谁可以使用 LSU 的加载端口。
// 优先级通常是：PageWalker (最优先，为了尽快填 TLB) > LoadBuffer (重试) > AGU (新请求)

wire LS_AGULD_uopStall[NUM_AGUS-1:0]; // 告诉 LoadBuffer/AGU 被反压了
LD_UOp LS_uopLd[NUM_AGUS-1:0];        // 最终送入 LSU 的加载请求

LoadSelector loadSelector
(
    .IN_aguLd(LB_uopLd),              // 来自 LoadBuffer 的请求
    .OUT_aguLdStall(LS_AGULD_uopStall),

    .IN_pwLd(PW_LD_uop),              // 来自 PageWalker 的请求
    .OUT_pwLdStall(CC_PW_LD_stall),

    .IN_ldUOpStall(CC_loadStall),     // LSU 给出的反压信号
    .OUT_ldUOp(LS_uopLd)              // 胜出者
);

// ============================================================================
// 数据 TLB (Data TLB)
// ============================================================================

TLB_Req TLB_rqs[NUM_AGUS-1:0]; // AGU 发出的查找请求
TLB_Res TLB_res[NUM_AGUS-1:0]; // TLB 返回的物理地址/权限

TLB#(NUM_AGUS, `DTLB_SIZE, `DTLB_ASSOC) dtlb
(
    .clk(clk),
    .rst(rst),
    .clear(TH_flushTLB), // 刷新 TLB (sfence.vma)
    .IN_pw(PW_res),      // Page Walker 填入的新条目
    .IN_rqs(TLB_rqs),
    .OUT_res(TLB_res)
);

// ============================================================================
// 地址生成单元 (AGU - Address Generation Unit)
// ============================================================================

AGU_UOp AGU_uop[NUM_AGUS-1:0];       // AGU 计算出的完整操作
ELD_UOp AGU_eLdUOp[NUM_AGUS-1:0];    // Early Load (VIPT 优化，提前发 Index)

generate for (genvar i = 0; i < NUM_AGUS; i=i+1) begin : aguPortsGen
    AGU#(.RQ_ID(1+i)) agu
    (
        .clk(clk),
        .rst(rst),
        .IN_stall(LSU_AGUStall[i]),      // LSU 是否太忙无法接收新地址
        .OUT_stall(stall[NUM_ALUS+i]),   // 告诉 IssueQueue 是否停顿

        .OUT_TMQ_free(), // (未连接? TLB Miss Queue 状态)

        .IN_branch(branch),
        .IN_vmem(CSR_vmem),              // 虚拟内存配置 (Sv32等)
        .OUT_pw(PW_reqs[i+1]),           // 发送 Page Walker 请求
        .IN_pw(PW_res),

        .OUT_tvalProv(TVS_tvalProvs[i]), // 产生异常值 (如非对齐地址)

        .OUT_tlb(TLB_rqs[i]),            // 查 TLB
        .IN_tlb(TLB_res[i]),

        .IN_uop(LD_uop[NUM_ALUS+i]),     // 输入微操作 (包含基址和偏移)
        .OUT_aguOp(AGU_uop[i]),          // 输出 AGU 微操作
        .OUT_eldOp(AGU_eLdUOp[i]),       // 输出早期 Load
        .OUT_uop(flagUOps[NUM_ALUS+NUM_AGUS+i]) // 输出标志位 (如异常)
    );
end endgenerate

// ============================================================================
// 加载缓冲区 (Load Buffer)
// ============================================================================
// 跟踪所有在飞的 Load 指令，处理乱序访存冲突和一致性。

SqN LB_maxLoadSqN;              // 当前分配到的最大 Load SqN
LD_UOp LB_uopLd[NUM_AGUS-1:0];  // LoadBuffer 发出的重试/新请求
LD_UOp LB_aguUOpLd[NUM_AGUS-1:0]; // 经过处理的 AGU 请求

ComLimit LB_ldComLimit; // 提交限制

LoadBuffer lb
(
    .clk(clk),
    .rst(rst),
    .IN_memc(IN_memc),      // 监听内存响应
    .IN_LSU_memc(LSU_MC_if),
    .IN_comLoadSqN(ROB_comLoadSqN), // 已提交的 Load 序号
    .IN_comSqN(ROB_curSqN),

    .IN_stall(LS_AGULD_uopStall),   // 是否被 LoadSelector 阻塞
    .IN_uop(AGU_uop),               // 新进入的 AGU 请求

    .IN_ldAck(LSU_ldAck),           // LSU 确认收到 Load
    .IN_SQ_done(SQ_done),           // Store Queue 有指令完成 (可能触发 Load 重试)

    .OUT_uopAGULd(LB_aguUOpLd),     // 输出处理后的 AGU 请求
    .OUT_uopLd(LB_uopLd),           // 输出重试请求

    .IN_branch(branch),
    .OUT_branch(branchProvs[LQ_BRANCH_PORT]), // 发现内存顺序违规，触发冲刷

    .OUT_maxLoadSqN(LB_maxLoadSqN),
    .OUT_comLimit(LB_ldComLimit)
);

// ============================================================================
// 存储队列 (Store Queue & Backend)
// ============================================================================
// Store Queue 分为两部分：前端 SQ (缓冲、前推) 和 后端 SQB (合并写、提交)。

wire SQ_empty;
wire SQ_done; // 指示 SQ 有写操作完成

StFwdResult SQ_fwd[NUM_AGUS-1:0];  // SQ 前推结果
StFwdResult SQB_fwd[NUM_AGUS-1:0]; // SQB 前推结果 (正在写的 Store)

SqN SQ_maxStoreSqN;
wire SQ_flush; // 刷新流水线信号
SQ_UOp SQ_uops[SQ_DEQ_PORTS-1:0]; // 从 SQ 流向 SQB 的已提交 Store
wire SQ_stall[SQ_DEQ_PORTS-1:0];  // SQB 反压 SQ

StoreQueue#(.NUM_OUT(SQ_DEQ_PORTS)) sq
(
    .clk(clk),
    .rst(rst),

    .OUT_empty(SQ_empty),
    .OUT_done(SQ_done),

    .IN_uopLd(CC_SQ_uopLd), // Load 指令来查前推
    .OUT_fwd(SQ_fwd),       // 返回前推结果

    .IN_uopSt(AGU_uop),     // 新进入的 Store 地址
    .IN_rnUOp(RN_uop),      // Rename 阶段分配条目
    .IN_stDataUOp(SDL_stDataUOp), // Store 数据到达

    .IN_curSqN(ROB_curSqN),       // 当前提交指针
    .IN_comStSqN(ROB_comStoreSqN),

    .IN_branch(branch),     // 分支冲刷 (清除非提交的 Store)

    .OUT_uop(SQ_uops),      // 发送已提交的 Store 给后端
    .IN_stall(SQ_stall),

    .OUT_flush(SQ_flush),   // 如果 SQ 满且无法分配，可能触发 Flush
    .OUT_maxStoreSqN(SQ_maxStoreSqN)
);

ST_UOp SQB_uop; // 最终发给 LSU 的合并后的写操作
wire SQB_busy;

StoreQueueBackend#(.NUM_IN(SQ_DEQ_PORTS)) sqb
(
    .clk(clk),
    .rst(rst),

    .OUT_busy(SQB_busy),

    .IN_uopLd(CC_SQ_uopLd), // 同样支持 Load 前推
    .OUT_fwd(SQB_fwd),

    .IN_uop(SQ_uops),       // 接收已提交 Store
    .OUT_stall(SQ_stall),

    .IN_stallSt(CC_storeStall), // LSU 反压
    .OUT_uopSt(SQB_uop),        // 输出合并写请求
    .IN_stAck(LSU_stAck)        // 写完成确认
);

// ============================================================================
// 8. 加载存储单元 (Load Store Unit - LSU)
// ============================================================================
// 统一管理对 D-Cache 的访问。

wire CC_loadStall[NUM_AGUS-1:0]; // LSU 反压 Load
wire CC_storeStall;              // LSU 反压 Store
wire LSU_AGUStall[NUM_AGUS-1:0]; // LSU 反压 AGU
LD_UOp CC_SQ_uopLd[NUM_AGUS-1:0]; // 送去 SQ 查前推的 Load
LD_Ack LSU_ldAck[NUM_AGUS-1:0];   // Load 确认

MemController_Req LSU_MC_if;  // LSU 发出的内存请求
MemController_Req BLSU_MC_if; // Bypass LSU 发出的内存请求 (MMIO)
ST_Ack LSU_stAck;             // Store 确认

CacheLineSetDirty LSU_setDirty; // 设置 Cache 行脏位
CacheMiss LSU_cacheMiss;        // Cache 缺失信号

LoadStoreUnit lsu
(
    .clk(clk),
    .rst(rst),

    .IN_enable(1'b1),// TODO: register

    .IN_branch(branch),
    .OUT_ldAGUStall(LSU_AGUStall),
    .OUT_ldStall(CC_loadStall),
    .OUT_stStall(CC_storeStall),

    .IN_uopELd(AGU_eLdUOp),    // 早期 Load (VIPT)
    .IN_aguLd(LB_aguUOpLd),    // 常规 Load

    .IN_uopLd(LS_uopLd),       // 选中的 Load 请求
    .OUT_uopLdSq(CC_SQ_uopLd), // 发送给 SQ 查前推
    .OUT_ldAck(LSU_ldAck),

    .IN_uopSt(SQB_uop),        // 输入 Store 请求

    .IF_cache(IF_cache),       // 连接 D-Cache SRAM
    .IF_mmio(IF_mmio),         // 连接 MMIO 总线

    // 访问 Tag RAM (CacheLineManager 管理)
    .IN_ctReadReady(CLM_ctReadReady),
    .OUT_ctRead(CLM_ctRead),
    .IN_ctResult(CLM_ctResult),

    .OUT_setDirty(LSU_setDirty),
    .OUT_miss(LSU_cacheMiss),  // 报告 Cache Miss
    .IN_missReady(CLM_missReady),

    .IN_sqStFwd(SQ_fwd),       // 接收 SQ 前推数据
    .IN_sqbStFwd(SQB_fwd),     // 接收 SQB 前推数据
    .OUT_stAck(LSU_stAck),

    .OUT_BLSU_memc(BLSU_MC_if),// MMIO 内存请求
    .LSU_memc(LSU_MC_if),      // Cache 填充请求
    .IN_memc(IN_memc),

    .IN_ready({NUM_AGUS{1'b1}}),
    .OUT_resultUOp(resultUOps[NUM_ALUS+:NUM_AGUS]), // 输出 Load 结果
    .OUT_flagsUOp(flagUOps[NUM_ALUS+:NUM_AGUS])     // 输出异常标志
);

// ============================================================================
// 缓存行管理器 (Cache Line Manager)
// ============================================================================
// 负责处理 Cache Miss、替换策略、Dirty 位管理以及 Tag RAM 的访问仲裁。

wire CLM_busy;
wire CLM_ctReadReady[NUM_CT_READS-1:0];
CacheTableRead CLM_ctRead[NUM_CT_READS-1:0];
CacheTableResult CLM_ctResult[NUM_CT_READS-1:0];
wire CLM_missReady;

CacheLineManager cacheLineManager
(
    .clk(clk),
    .rst(rst),

    .IF_ct(IF_ct),             // 连接 Tag RAM

    .IN_flush(TH_startFence),  // 缓存刷新请求 (Fence.i)
    .IN_storeBusy(STORE_busy),
    .OUT_busy(CLM_busy),

    .IN_setDirty(LSU_setDirty),

    .IN_ctRead(CLM_ctRead),    // 处理 Tag 读请求
    .OUT_ctReadReady(CLM_ctReadReady),
    .OUT_ctResult(CLM_ctResult),

    .IN_miss(LSU_cacheMiss),   // 处理 Miss 请求
    .OUT_missReady(CLM_missReady),

    .IN_prefetch(prefetch),    // 处理预取请求
    .OUT_prefetchReady(prefetchReady),
    .OUT_prefetchAck(prefetchAck),

    .OUT_memc(LSU_MC_if),      // 发出内存填充请求
    .IN_memc(IN_memc)
);

// ============================================================================
// 数据预取器 (Data Prefetcher)
// ============================================================================

Prefetch prefetch;
logic prefetchReady;
Prefetch_ACK prefetchAck;

DataPrefetch dataPrefetch
(
    .clk(clk),
    .rst(rst),
    .IN_aguOps(AGU_uop),       // 监听所有访存地址
    .IN_miss(LSU_cacheMiss),   // 监听 Miss 事件
    .OUT_prefetch(prefetch),   // 发出预取请求
    .IN_prefetchReady(prefetchReady),
    .IN_prefetchAck(prefetchAck)
);

// ============================================================================
// 重排序缓冲区 (ROB - Re-Order Buffer)
// ============================================================================
// 负责指令的有序提交和误预测恢复。

SqN ROB_maxSqN;        // 当前 ROB 窗口的最大 SqN
FetchID_t ROB_curFetchID; // 当前提交指令的 FetchID
wire[4:0] ROB_fpNewFlags; // 累积的浮点异常标志
ROB_PERFC_Info ROB_perfcInfo /*verilator public*/;

BPUpdate ROB_bpUpdate; // 分支预测更新
Trap_UOp ROB_trapUOp /*verilator public*/; // 陷阱微操作 (提交时触发异常)
SqN ROB_comLoadSqN;    // 提交的 Load SqN
SqN ROB_comStoreSqN;   // 提交的 Store SqN

ROB rob
(
    .clk(clk),
    .rst(rst),
    .IN_uop(RN_uop),           // 新指令分配条目
    .IN_flagUOps(flagUOps),    // 接收执行完成标志

    .IN_interruptPending(CSR_trapControl.interruptPending), // 检查中断
    .OUT_perfcInfo(ROB_perfcInfo),

    .IN_branch(branch),        // 处理分支冲刷

    .IN_stComLimit(stCommitLimit), // Store 提交限制
    .IN_ldComLimit(LB_ldComLimit), // Load 提交限制

    .OUT_maxSqN(ROB_maxSqN),   // 限制前端发射 (流控)
    .OUT_curSqN(ROB_curSqN),   // 广播当前提交指针
    .OUT_lastLoadSqN(ROB_comLoadSqN),
    .OUT_lastStoreSqN(ROB_comStoreSqN),

    .OUT_comUOp(comUOps),      // 广播提交信息
    .OUT_fpNewFlags(ROB_fpNewFlags),
    .OUT_curFetchID(ROB_curFetchID),

    .OUT_trapUOp(ROB_trapUOp), // 输出触发的异常
    .OUT_bpUpdate(ROB_bpUpdate), // 更新分支预测器

    .OUT_mispredFlush(mispredFlush) // 输出误预测冲刷信号
);

// 系统忙信号 (用于禁止 Trap Handler 某些操作)
wire STORE_busy = !SQ_empty || SQB_busy;
wire MEM_busy = STORE_busy || CLM_busy;

// ============================================================================
// 异常处理单元 (Trap Handler)
// ============================================================================
// 处理 ROB 提交的异常和中断，控制流水线跳转到异常向量。

wire TH_flushTLB;
wire TH_startFence;
wire TH_disableIFetch;
wire TH_clearICache;
TrapInfoUpdate TH_trapInfo;
wire[31:0] TH_stallPC;

TrapHandler trapHandler
(
    .clk(clk),
    .rst(rst),

    .IN_trapInstr(ROB_trapUOp),    // 输入 ROB 提交的异常
    .OUT_pcRead(PC_readReqTH),     // 读取异常指令 PC
    .IN_pcReadData(PC_readDataTH),
    .IN_trapControl(CSR_trapControl), // 读取 CSR 配置 (mtvec等)
    .OUT_trapInfo(TH_trapInfo),    // 写回异常信息 (mcause/mepc)
    .OUT_branch(branchProvs[TH_BRANCH_PORT]), // 发出异常跳转 (重定向前端)

    .IN_MEM_busy(MEM_busy),        // 等待内存空闲

    .OUT_flushTLB(TH_flushTLB),    // 刷新 TLB
    .OUT_fence(TH_startFence),     // 执行 Fence
    .OUT_clearICache(TH_clearICache), // 清空 I-Cache
    .OUT_disableIFetch(TH_disableIFetch), // 暂停取指
    .OUT_dbgStallPC(TH_stallPC)
);

endmodule