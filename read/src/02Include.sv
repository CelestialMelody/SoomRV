// ============================================================================
// 基础类型定义 (Basic Typedefs) - 处理器的"原子"单位
// ============================================================================

// 逻辑寄存器名 (Register Name, 5位)。即 RISC-V 架构定义的 x0-x31。
typedef logic[4:0] RegNm;

// 物理寄存器标签 (Tag)。
// 用于乱序执行中的重命名。
// RF_SIZE_EXP 通常为 6 (64个物理寄存器)。
// 注意：Tag 比索引多一位，最高位通常用于标记 "特殊Tag" (如 TAG_ZERO) 或 "无效"。
typedef logic[`RF_SIZE_EXP:0] Tag;

// 纯物理寄存器索引 (Register File Tag)。
// 去掉了 Tag 的最高位特殊标志，直接用于索引物理寄存器堆 RAM。
typedef logic[`RF_SIZE_EXP-1:0] RFTag;

// 序列号 (Sequence Number)。
// 这是指令在 ROB (重排序缓冲区) 中的索引。
// 它是乱序执行的时间戳，用于在提交阶段恢复程序的原始顺序。
typedef logic[`ROB_SIZE_EXP:0] SqN;

// 寄存器数据。实际的 32 位数值。
typedef logic[31:0] RegT;

// 取指包 ID (Fetch ID)。
// 标识一组同时取出的指令 (Fetch Packet)，用于追踪前端流水线中的指令组。
typedef logic[4:0] FetchID_t;

// 取指偏移量 (Fetch Offset)。
// 指示某条指令在 16字节取指包中的具体位置 (0-7，因为每条指令最短2字节)。
typedef logic[`FSIZE_E-2:0] FetchOff_t;

// 返回栈索引 (Return Stack Index)。用于 RAS (Return Address Stack)。
typedef logic[$clog2(`RETURN_SIZE)-1:0] RetStackIdx_t;

// 存储指令 ID (Store ID)。用于 Store Queue 内部追踪。
typedef logic[1:0] StID_t;

// Cache ID。用于区分不同的缓存实例 (如果存在)。
typedef logic[0:0] CacheID_t;

// 存储偏移量。
typedef logic[1:0] StOff_t;

// 存储操作的随机数/唯一标识 (Nonce)。防止存储队列中的混淆。
typedef logic[2:0] StNonce_t;

// TAGE 预测器 ID。用于索引 TAGE 表。
typedef logic[3:0] TageID_t;

// 分支历史记录 (Branch History)。
// TAGE 预测器使用的全局历史记录，位数较长。
typedef logic[`TAGE_BASE*(1<<(`TAGE_STAGES-2))-1:0] BHist_t;

// 整数微操作次序。当一条指令被拆分为多个微操作时，标记其顺序。
typedef logic[$clog2(NUM_ALUS)-1:0] IntUOpOrder_t;

// 异常原因代码 (Trap Cause)。
typedef logic[4:0] TrapCause_t;

// 预取流索引。用于硬件预取器。
typedef logic[1:0] PFStreamIdx_t;

// Cache 组相联索引。标记数据在 Cache 的哪一路 (Way)。
typedef logic[$clog2(`CASSOC)-1:0] AssocIdx_t;

// 定义一个特殊的常量 Tag：TAG_ZERO。
// 对应逻辑寄存器 x0。它的值永远是 0，且不需要物理寄存器存储。
// 最高位为 1 表示它是一个特殊 Tag。
localparam Tag TAG_ZERO = {1'b1, RFTag'(0)};

// ============================================================================
// 微操作码枚举 (Micro-Opcode Enums)
// ============================================================================

// ---------------------------------------------------------
// 整数算术操作码 (Integer Ops)
// ---------------------------------------------------------
typedef enum logic[5:0]
{
    INT_ADD,     // 加法
    INT_XOR,     // 异或
    INT_OR,      // 或
    INT_AND,     // 与
    INT_SLL,     // 逻辑左移 (Shift Left Logical)
    INT_SRL,     // 逻辑右移 (Shift Right Logical)
    INT_SLT,     // 小于置位 (Set Less Than, Signed)
    INT_SLTU,    // 无符号小于置位 (Unsigned)
    INT_SUB,     // 减法
    INT_SRA,     // 算术右移 (Shift Right Arithmetic)
    INT_LUI,     // 加载高位立即数 (Load Upper Immediate)
    INT_SYS,     // 系统指令占位符

    // Zba 扩展 (地址生成加速)
    INT_SH1ADD,  // (rs1 << 1) + rs2
    INT_SH2ADD,  // (rs1 << 2) + rs2
    INT_SH3ADD,  // (rs1 << 3) + rs2

    // Zbb 扩展 (位操作基础)
    INT_XNOR,    // 同或 (NOT XOR)
    INT_ANDN,    // AND NOT (rs1 & ~rs2)
    INT_ORN,     // OR NOT (rs1 | ~rs2)
    INT_MAX,     // 最大值 (Signed)
    INT_MAXU,    // 最大值 (Unsigned)
    INT_MIN,     // 最小值 (Signed)
    INT_MINU,    // 最小值 (Unsigned)

    // 符号扩展指令
    INT_SE_B,    // 字节符号扩展 (Sign Extend Byte)
    INT_SE_H,    // 半字符号扩展 (Sign Extend Half)
    INT_ZE_H     // 半字零扩展 (Zero Extend Half)
} OPCode_INT;

// ---------------------------------------------------------
// 分支跳转操作码 (Branch Ops)
// ---------------------------------------------------------
typedef enum logic[5:0]
{
    BR_AUIPC,    // PC + Immediate (虽然不是跳转，但由 Branch Unit 计算)
    BR_JAL,      // 直接跳转并链接 (Jump and Link)
    BR_BEQ,      // 等于跳转
    BR_BNE,      // 不等跳转
    BR_BLT,      // 小于跳转 (Signed)
    BR_BGE,      // 大于等于跳转 (Signed)
    BR_BLTU,     // 小于跳转 (Unsigned)
    BR_BGEU,     // 大于等于跳转 (Unsigned)

    // 内部优化的跳转类型
    BR_V_RET,    // 虚拟返回指令 (用于 RAS 优化)
    BR_V_JALR,   // 虚拟间接跳转 (JALR)
    BR_V_JR      // 虚拟寄存器跳转 (JR)
} OPCode_Branch;

// ---------------------------------------------------------
// 位操作扩展操作码 (Bitmanip Ops)
// ---------------------------------------------------------
typedef enum logic[5:0]
{
    BM_CLZ,      // 计数前导零 (Count Leading Zeros)
    BM_CTZ,      // 计数后缀零 (Count Trailing Zeros)
    BM_CPOP,     // 统计置位位 (Population Count)
    BM_ROL,      // 循环左移 (Rotate Left)
    BM_ROR,      // 循环右移 (Rotate Right)
    BM_ORC_B,    // 按字节或合并 (Bitwise OR-Combine)
    BM_REV8,     // 字节反转 (Byte Reverse)
    BM_BCLR,     // 单个位清除 (Bit Clear)
    BM_BEXT,     // 单个位提取 (Bit Extract)
    BM_BINV,     // 单个位翻转 (Bit Invert)
    BM_BSET      // 单个位设置 (Bit Set)

`ifdef ENABLE_FP
    // 浮点符号注入指令 (Zfinx: 浮点数存整数寄存器)
    ,
    BM_FSGNJ_S,  // 注入符号 (Float Sign Injection)
    BM_FSGNJN_S, // 注入反符号 (Negated)
    BM_FSGNJX_S  // 注入异或符号 (XOR)
`endif

} OPCode_Bitmanip;

// ---------------------------------------------------------
// 乘法操作码 (Multiplier Ops)
// ---------------------------------------------------------
typedef enum logic[5:0]
{
    MUL_MUL,     // 低位乘法 (Signed * Signed)
    MUL_MULH,    // 高位乘法 (Signed * Signed)
    MUL_MULSU,   // 高位乘法 (Signed * Unsigned)
    MUL_MULU     // 高位乘法 (Unsigned * Unsigned)
} OPCode_MUL;

// ---------------------------------------------------------
// 除法操作码 (Divider Ops)
// ---------------------------------------------------------
typedef enum logic[5:0]
{
    DIV_DIV,     // 除法 (Signed)
    DIV_DIVU,    // 除法 (Unsigned)
    DIV_REM,     // 求余 (Signed)
    DIV_REMU     // 求余 (Unsigned)
} OPCode_DIV;

// ---------------------------------------------------------
// 地址生成单元操作码 (AGU Ops) - 负责 Load/Store
// ---------------------------------------------------------
typedef enum logic[5:0]
{
    LSU_LB,      // Load Byte (Signed)
    LSU_LH,      // Load Half (Signed)
    LSU_LW,      // Load Word

    LSU_LBU,     // Load Byte (Unsigned)
    LSU_LHU,     // Load Half (Unsigned)
    LSU_LR_W,    // Load Reserved (原子操作预留)

    LSU_SC_W,    // Store Conditional (原子操作条件存)
    LSU_SB,      // Store Byte
    LSU_SH,      // Store Half
    LSU_SW,      // Store Word

    // 缓存管理指令 (Zicbom)
    LSU_CBO_CLEAN, // 清理缓存行
    LSU_CBO_INVAL, // 作废缓存行
    LSU_CBO_FLUSH  // 刷新缓存行
} OPCode_AGU;

// ---------------------------------------------------------
// 浮点基础操作码 (FPU Ops)
// ---------------------------------------------------------
typedef enum logic[2:0]
{
    // 这里的指令通常有 Rounding Mode 字段
    // 融合乘加指令 (FMA) 这里的定义被注释掉了，可能在其他地方处理或暂未启用
    //FPU_FMADD_S,
    //FPU_FMSUB_S,
    //FPU_FNMSUB_S,
    //FPU_FNMADD_S,

    FPU_FADD_S,  // 浮点加法
    FPU_FSUB_S,  // 浮点减法
    FPU_FCVTWS,  // 浮点转整数 (Signed)
    FPU_FCVTWUS, // 浮点转整数 (Unsigned)
    FPU_FCVTSW,  // 整数转浮点 (Signed)
    FPU_FCVTSWU  // 整数转浮点 (Unsigned)
} OPCode_FPU;

// ---------------------------------------------------------
// 浮点比较与分类操作码 (FPU Ops 2)
// ---------------------------------------------------------
typedef enum logic[5:0]
{
    // 这些操作码的高3位固定为 'b101 以区分
    //FPU_FMVXW,
    //FPU_FMVWX,
    FPU_FEQ_S = 6'b101000, // 浮点等于
    FPU_FLE_S,             // 浮点小于等于
    FPU_FLT_S,             // 浮点小于
    FPU_FMIN_S,            // 浮点最小值
    FPU_FMAX_S,            // 浮点最大值
    FPU_FCLASS_S           // 浮点分类 (检查是否为 NaN, Inf 等)
} OPCode_FPU2;

// ---------------------------------------------------------
// 浮点除法操作码 (FDIV Ops)
// ---------------------------------------------------------
typedef enum logic[2:0]
{
    FDIV_FDIV_S,  // 浮点除法
    FDIV_FSQRT_S  // 浮点开方
} OPCode_FDIV;

// ---------------------------------------------------------
// 浮点乘法操作码 (FMUL Ops)
// ---------------------------------------------------------
typedef enum logic[2:0]
{
    FMUL_FMUL_S   // 浮点乘法
} OPCode_FMUL;

// ---------------------------------------------------------
// 原子操作码 (Atomic Ops)
// ---------------------------------------------------------
typedef enum logic[5:0]
{
    // 指定了特定的枚举值以匹配解码逻辑
    ATOMIC_AMOSWAP_W=55, // 原子交换
    ATOMIC_AMOADD_W=56,  // 原子加
    ATOMIC_AMOXOR_W,     // 原子异或
    ATOMIC_AMOAND_W,     // 原子与
    ATOMIC_AMOOR_W,      // 原子或
    ATOMIC_AMOMIN_W,     // 原子取最小 (Signed)
    ATOMIC_AMOMAX_W,     // 原子取最大 (Signed)
    ATOMIC_AMOMINU_W,    // 原子取最小 (Unsigned)
    ATOMIC_AMOMAXU_W     // 原子取最大 (Unsigned)
} OPCode_FU_ATOMIC;

// ---------------------------------------------------------
// 控制状态寄存器操作码 (CSR Ops)
// ---------------------------------------------------------
typedef enum logic[5:0]
{
    CSR_R,    // 读 CSR
    CSR_RW,   // 读写 CSR (Read/Write)
    CSR_RS,   // 读并置位 CSR (Read/Set)
    CSR_RC,   // 读并清除 CSR (Read/Clear)

    CSR_RW_I, // 立即数版读写
    CSR_RS_I, // 立即数版置位
    CSR_RC_I, // 立即数版清除

    CSR_SRET, // 监管模式返回 (Supervisor Return)
    CSR_MRET  // 机器模式返回 (Machine Return)
} OPCode_FU_CSR;

// ---------------------------------------------------------
// 异常原因编码 (Trap Causes)
// ---------------------------------------------------------
// 直接对应 RISC-V 特权级规范中的 mcause/scause 编码
typedef enum logic[4:0]
{
    RVP_TRAP_IF_MA   = 0,  // 取指地址未对齐
    RVP_TRAP_IF_AF   = 1,  // 取指访问错误
    RVP_TRAP_ILLEGAL = 2,  // 非法指令
    RVP_TRAP_BREAK   = 3,  // 断点
    RVP_TRAP_LD_MA   = 4,  // 加载地址未对齐
    RVP_TRAP_LD_AF   = 5,  // 加载访问错误
    RVP_TRAP_ST_MA   = 6,  // 存储地址未对齐
    RVP_TRAP_ST_AF   = 7,  // 存储访问错误
    RVP_TRAP_ECALL_U = 8,  // 用户态系统调用
    RVP_TRAP_ECALL_S = 9,  // 监管态系统调用
    RVP_TRAP_IF_PF   = 12, // 取指页错误 (Page Fault)
    RVP_TRAP_LD_PF   = 13, // 加载页错误
    RVP_TRAP_ST_PF   = 15, // 存储页错误
    TRAP_CUSTOM_HANG = 24  // 自定义挂起异常
} RVPTrapCause;

// ---------------------------------------------------------
// 内部异常操作码 (Internal Trap Opcodes)
// ---------------------------------------------------------
// 用于在解码阶段将异常传递给 ROB
// 对于解码时陷阱，我们使用FLAGS_TRAP/FU_TRAP作为一个转义标志。
//（未使用的）rd字段随后会存储这些字段中的一个，以指定遇到的解码时异常。
// 所有其他异常都作为结果标志从功能单元传递到ROB。
typedef enum logic[5:0]
{
    // 标准异常
    TRAP_I_ACC_MISAL = 0,
    TRAP_I_ACC_FAULT = 1,
    TRAP_ILLEGAL_INSTR = 2,
    TRAP_BREAK = 3,
    TRAP_ECALL_U = 8,
    TRAP_ECALL_S = 9,
    TRAP_ECALL_M = 11,
    TRAP_I_PAGE_FAULT = 12,

    // 非标准/虚拟异常
    TRAP_V_SFENCE_VMA = 15, // 虚拟内存屏障
    TRAP_V_INTERRUPT = 16   // 中断
} OPCode_FU_TRAP;

// ---------------------------------------------------------
// 功能单元枚举 (Functional Unit Types)
// ---------------------------------------------------------
// 决定指令被分派到哪个类型的执行单元
typedef enum logic[3:0]
{
    FU_INT,      // 简单整数 ALU
    FU_BRANCH,   // 分支单元
    FU_BITMANIP, // 位操作单元
    FU_AGU,      // 地址生成单元 (访存)
    FU_MUL,      // 乘法器
    FU_DIV,      // 除法器
    FU_FPU,      // 浮点单元
    FU_FMUL,     // 浮点乘法
    FU_FDIV,     // 浮点除法
    FU_RN,       // 随机数/其他
    FU_ATOMIC,   // 原子指令单元
    FU_CSR,      // CSR 单元
    FU_TRAP      // 异常处理单元
} FuncUnit /* public */;

// ---------------------------------------------------------
// 执行结果标志位 (Execution Flags)
// ---------------------------------------------------------
// 这些标志位随结果广播，ROB 根据这些标志决定是否触发 Flush 或 Trap
typedef enum logic[3:0]
{
    // 无副作用
    FLAGS_NONE,
    FLAGS_BRANCH,         // 标记这是一条分支指令

    // 分支预测更新
    FLAGS_PRED_TAKEN,     // 实际结果：跳转 (Taken)
    FLAGS_PRED_NTAKEN,    // 实际结果：不跳转 (Not Taken)

    // 需要刷新流水线
    FLAGS_FENCE,          // 内存屏障
    FLAGS_ORDERING,       // 强序要求 (通常用于 IO)

    // 触发异常
    FLAGS_ILLEGAL_INSTR,  // 非法指令
    FLAGS_TRAP,           // 通用异常

    // 内存异常
    FLAGS_LD_MA, FLAGS_LD_AF, FLAGS_LD_PF, // Load 异常 (对齐/访问/缺页)
    FLAGS_ST_MA, FLAGS_ST_AF, FLAGS_ST_PF, // Store 异常

    // 从异常返回
    FLAGS_XRET,           // xRET 指令

    // 无效/未执行标志
    FLAGS_NX = 4'b1111

} Flags /* public */;

// ============================================================================
// 浮点异常标志 (Floating Point Flags)
// ============================================================================
// 浮点指令使用不同的编码来存储浮点异常。
// 为了节省 ROB 中的存储位宽，这里复用 (Overload) 了普通 Load/Store 指令的异常标志位。
// 只有当 Opcode 是浮点操作时，这些位才代表浮点异常。
typedef enum logic[3:0]
{
    FLAGS_FP_NX = FLAGS_LD_MA, // 不精确 (Inexact) - 复用 Load Misaligned
    FLAGS_FP_UF = FLAGS_LD_AF, // 下溢 (Underflow) - 复用 Load Access Fault
    FLAGS_FP_OF = FLAGS_LD_PF, // 上溢 (Overflow) - 复用 Load Page Fault
    FLAGS_FP_DZ = FLAGS_ST_MA, // 除以零 (Divide by Zero) - 复用 Store Misaligned
    FLAGS_FP_NV = FLAGS_ST_AF  // 无效操作 (Invalid Op) - 复用 Store Access Fault

} FlagsFP;

// ============================================================================
// 特权级与前端故障 (Privilege & Fetch Faults)
// ============================================================================

// RISC-V 特权模式定义
typedef enum logic[1:0]
{
    PRIV_USER=0,       // 用户模式 (U-Mode)
    PRIV_SUPERVISOR=1, // 监管模式 (S-Mode)
    PRIV_MACHINE=3     // 机器模式 (M-Mode)
} PrivLevel;

// 取指阶段可能发生的异常类型
typedef enum logic[1:0]
{
    IF_FAULT_NONE = 0, // 无故障
    IF_INTERRUPT,      // 发生中断 (Interrupt) - 注意：这里包含了硬件中断的处理
    IF_ACCESS_FAULT,   // 访问错误 (PMP/PMA 检查失败)
    IF_PAGE_FAULT      // 页错误 (Page Fault) - 缺页
} IFetchFault /* public */;

// ============================================================================
// 流水线控制：冲刷与停顿 (Flush & Stall)
// ============================================================================

// 冲刷原因 (Flush Cause) - 决定了流水线为何要被清空
// 同时也用于性能计数器统计
typedef enum logic[2:0]
{
    FLUSH_ORDERING,    // 强序要求 (Fence / CSR 写 / 序列化指令)
    FLUSH_BRANCH_TK,   // 分支预测错误：应该跳转但没跳 (Taken)
    FLUSH_BRANCH_NT,   // 分支预测错误：应该不跳但跳了 (Not Taken)
    FLUSH_RETURN,      // 返回地址预测错误 (RAS 修正)
    FLUSH_IBRANCH,     // 间接跳转目标错误 (JALR 修正)
    FLUSH_MEM_ORDER    // 内存顺序冲突 (Load 违规，检测到更早的 Store 写入了相同地址)
} FlushCause /* public */;

// 停顿原因 (Stall Cause) - 主要用于性能分析，指示哪个阶段阻塞了流水线
typedef enum logic[2:0]
{
    STALL_NONE,        // 无停顿
    STALL_FRONTEND,    // 前端阻塞 (取指慢 / Cache Miss)
    STALL_BACKEND,     // 后端阻塞 (ROB 满 / 发射队列满)
    STALL_STORE,       // 存储队列满
    STALL_LOAD,        // 加载相关阻塞
    STALL_ROB          // ROB 满 (具体区分)
} StallCause;

// ============================================================================
// 内存控制器接口 (Memory Controller Interface)
// ============================================================================
// 这部分定义了 Core 和内存控制器之间的通信协议。
// 看起来是一个自定义的总线/命令接口。

// 内存控制器命令
typedef enum logic[3:0]
{
    MEMC_NONE,          // 空操作

    // --- Cache 行操作 (突发传输) ---
    MEMC_REPLACE,         // 替换/填充 Cache Line (读主存)
    MEMC_CP_CACHE_TO_EXT, // 将 Cache Line 拷贝到外部 (Writeback / Evict)
    MEMC_CP_EXT_TO_CACHE, // 从外部拷贝到 Cache (DMA 或其他)

    // --- 单次访问操作 (通常用于 MMIO 或非缓存访问) ---
    MEMC_READ_BYTE,
    MEMC_READ_HALF,
    MEMC_READ_WORD,
    MEMC_WRITE_BYTE,
    MEMC_WRITE_HALF,
    MEMC_WRITE_WORD
} MemC_Cmd /* public */;

// 单次加载响应 (Single Load Result) - 用于 MMIO 读取返回
typedef struct packed
{
    logic[31:0] data;            // 读取的数据
    logic[`CACHE_SIZE_E-3:0] id; // 事务 ID (复用了 Cache 地址位宽)
    logic valid;                 // 数据有效
} MemController_SglLdRes /* public */;

// 单次存储响应 (Single Store Result) - 确认 MMIO 写完成
typedef struct packed
{
    logic[`CACHE_SIZE_E-3:0] id; // 事务 ID
    logic valid;                 // 写完成确认
} MemController_SglStRes /* public */;

// 加载数据前推 (Load Data Forward) - 可能指从总线直接返回数据
typedef struct packed
{
    logic[`AXI_WIDTH-1:0] data;  // 宽总线数据 (128 bit)
    logic[31:0] addr;            // 地址
    logic valid;
} MemController_LdDataFwd /* public */;

// 传输状态跟踪 (Transfer Status) - 内存控制器内部使用
typedef struct packed
{
    logic[31:0] writeAddr;       // 写地址
    logic[31:0] readAddr;        // 读地址
    logic[`CACHE_SIZE_E-3:0] cacheAddr; // Cache 内部地址
    logic[`CLSIZE_E-2:0] progress; // 传输进度 (计数器)
    CacheID_t cacheID;           // 涉及哪个 Cache
    logic active;                // 传输是否激活
    logic valid;
} MemController_Transf;

// 内存控制器请求 (Request) - CPU 发给 MemController
typedef struct packed
{
    logic[`AXI_WIDTH/8-1:0] mask; // 写掩码 (Byte Mask)
    logic[`AXI_WIDTH-1:0] data;   // 写数据

    logic[`CACHE_SIZE_E-3:0] cacheAddr; // Cache 地址 (对于 MMIO 用作 ID)
    logic[31:0] readAddr;         // 读主存地址
    logic[31:0] writeAddr;        // 写主存地址
    CacheID_t cacheID;            // 目标 Cache ID
    MemC_Cmd cmd;                 // 命令类型 (见 MemC_Cmd 枚举)
} MemController_Req /* public */;

// 内存控制器响应 (Response) - MemController 发给 CPU
typedef struct packed
{
    MemController_LdDataFwd ldDataFwd; // 数据前推
    MemController_Transf[`AXI_NUM_TRANS-1:0] transfers; // 当前所有传输的状态
    MemController_SglLdRes sglLdRes;   // 单次加载结果
    MemController_SglStRes sglStRes;   // 单次存储结果

    logic[2:0] stall;             // 停顿信号 (可能对应不同类型的请求)
    logic busy;                   // 控制器忙
} MemController_Res /* public */;

// ============================================================================
// 分支预测相关 (Branch Prediction)
// ============================================================================

// 分支类型
typedef enum logic[1:0]
{
    BT_JUMP,   // 无条件跳转 (JAL)
    BT_CALL,   // 函数调用 (JAL/JALR, rd=x1/x5)
    BT_BRANCH, // 条件分支 (BEQ/BNE...)
    BT_RETURN  // 函数返回 (JALR, rd=x0, rs1=x1/x5)
} BranchType /* public */;

// 预测的分支信息 (PredBranch) - 预测器输出的原始判断
typedef struct packed
{
    logic[30:0] dst;      // 预测的目标地址
    FetchOff_t offs;      // 分支指令在 Fetch Packet 中的偏移
    logic compr;          // 是否是压缩指令
    BranchType btype;     // 分支类型
    logic multiple;       // 包中是否有多个分支？(或多重命中)
    logic taken;          // 预测是否跳转
    logic dirOnly;        // 仅预测了方向 (Direction Only)，目标未知
    logic valid;          // 预测有效
} PredBranch /* public */;

// 简化的预测信息 (BranchPredInfo) - 随流水线携带
// 注意：在这个版本中，这里非常精简，只携带了 taken 位。
// 复杂的历史信息可能被移到了 BPBackup 中存储。
typedef struct packed
{
    logic taken;          // 当时的预测结果：是否跳转
} BranchPredInfo /* public */;

// BTB 更新包 (BTUpdate) - 用于训练 BTB
typedef struct packed
{
    logic[31:0] src;      // 分支指令 PC
    logic[31:0] dst;      // 实际目标地址
    FetchOff_t fetchStartOffs; // 取指包起始偏移
    BranchType btype;     // 类型
    FetchOff_t multipleOffs;
    logic multiple;
    logic compressed;     // 压缩指令
    logic clean;          // 可能是清除 BTB 条目的请求
    logic valid;
} BTUpdate;

// RAS (返回栈) 动作
typedef enum logic[1:0]
{
    RET_NONE, RET_PUSH, RET_POP
} RetStackAction /* public */;

// 全局历史 (History) 动作 - 更新 GHR
typedef enum logic[2:0]
{
    HIST_NONE,     // 不更新
    HIST_APPEND_0, // 追加 0 (不跳转)
    HIST_APPEND_1, // 追加 1 (跳转)
    HIST_WRITE_0,  // 写入 0 (覆盖?)
    HIST_WRITE_1   // 写入 1
} HistoryAction /* public */;

// 分支目标计算方式 (Branch Target Specification)
// 用于告诉前端下一次取指应该去哪里
typedef enum logic[1:0]
{
    // 一般存储的是指令后半字的 PC。
    BR_TGT_MANUAL, // 手动指定目标地址 (使用 dstPC)
    BR_TGT_NEXT,   // 下一条指令 (PC + 指令长度)
    BR_TGT_CUR16,  // 当前 PC (16位指令重取?)
    BR_TGT_CUR32   // 当前 PC (32位指令重取?)
} BranchTargetSpec /* public */;

// ============================================================================
// 冲刷与恢复 (Branch Recovery / Provider)
// ============================================================================

// 分支提供者 (Branch Provider)
// 这是从后端 (ROB/ALU) 发送到前端的信号，用于触发 Flush 和重定向。
typedef struct packed
{
    FlushCause cause;         // 冲刷原因 (性能计数器用)
    BranchTargetSpec tgtSpec; // 目标地址计算方式
    logic isSCFail;           // 是否是 SC (Store Conditional) 失败
    FetchOff_t fetchOffs;     // 导致冲刷的指令在包中的偏移
    RetStackAction retAct;    // 需要对 RAS 做的修正动作
    HistoryAction histAct;    // 需要对历史记录做的修正动作
    logic[31:0] dstPC;        // 重定向的目标 PC
    SqN sqN;                  // 指令序列号 (用于清除比它年轻的指令)
    SqN storeSqN;             // Store 序列号快照
    SqN loadSqN;              // Load 序列号快照
    logic flush;              // 触发冲刷的使能信号
    FetchID_t fetchID;        // 对应的 Fetch ID
    logic taken;              // 实际是否跳转
} BranchProv /* public */;

// 分支预测备份 (BP Backup)
// 这是一个快照，用于在预测错误时恢复预测器的状态 (Checkpoint)。
typedef struct packed
{
    TageID_t tageID;      // TAGE 表索引
    logic altPred;        // TAGE 的备用预测结果 (Alt Prediction)

    BHist_t history;      // 全局历史寄存器 (GHR) 快照
    RetStackIdx_t rIdx;   // RAS 指针快照
    logic isRegularBranch;// 是否是常规分支
    logic predTaken;      // 当时的预测结果
    FetchOff_t predOffs;  // 预测偏移
    logic pred;           // 最终预测值
} BPBackup /* public */;

// 前端分支提供者 (Fetch Branch Provider)
// 来自 Fetch 阶段的重定向请求 (例如 BTB 命中，需要立即跳到目标)。
typedef struct packed
{
    logic isFetchBranch;      // 是否是取指阶段发现的分支
    BranchTargetSpec tgtSpec; // 目标类型
    FetchOff_t fetchOffs;
    RetStackAction retAct;    // RAS 动作
    HistoryAction histAct;    // 历史更新动作
    logic[30:0] dst;          // 目标地址
    FetchID_t fetchID;
    logic wfi;                // 是否是 WFI (Wait For Interrupt)
    logic taken;              // 是否跳转
} FetchBranchProv;

// ============================================================================
// 前端辅助结构 (Frontend Helpers)
// ============================================================================

// 返回栈解码更新 (Return Stack Decode Update)
// 在解码阶段，如果发现是 CALL/RET 指令，可能需要修正返回栈。
typedef struct packed
{
    logic[30:0] addr;      // 目标地址
    RetStackIdx_t idx;     // 返回栈索引
    logic valid;
} ReturnDecUpdate;

// PC 文件条目 (PC File Entry)
// PC File 是一个关键组件。为了节省流水线寄存器宽度，指令在后端流转时不携带完整的 32位 PC。
// 而是只携带 FetchID。当需要知道 PC 时（如分支计算、异常），用 FetchID 去查 PC File。
typedef struct packed
{
    logic[30:0] pc;        // 指令 PC
    FetchOff_t branchPos;  // 分支指令在包中的偏移
    BranchPredInfo bpi;    // 分支预测元数据 (用于恢复)
} PCFileEntry;

// PC 文件读取请求 (PC File Read Request)
typedef struct packed
{
    FetchID_t addr;        // 要读取的 FetchID
    logic valid;
} PCFileReadReq;

// PC 文件读取请求 (Trap Handler 专用)
// Trap Handler 需要高优先级读取 PC 以处理异常。
typedef struct packed
{
    logic prio;            // 优先级位
    FetchID_t addr;
    logic valid;
} PCFileReadReqTH;

// ============================================================================
// 取指阶段 (Fetch Stage)
// ============================================================================

// 取指操作包 (IFetch Op) - 描述“我要取什么”
// 发送给 ICache Controller 的请求。
typedef struct packed
{
    logic[31:0] pc;        // 请求地址
    FetchID_t fetchID;     // 包 ID
    IFetchFault fetchFault;// 此时已知的异常 (如地址错误)
    FetchOff_t lastValid;  // 包内最后一个有效字节的偏移

    PredBranch predBr;     // 携带的分支预测结果 (如果有)

    logic[30:0] predRetAddr; // 预测的返回地址 (RAS)
    RetStackIdx_t rIdx;    // RAS 索引

    logic valid;           // 请求有效
} IFetchOp /* public */;

// 取指数据包 (IF_Instr) - 描述“我取到了什么”
// 从 ICache 返回的原始 128位数据。
typedef struct packed
{
    logic[31-`FSIZE_E:0] pc; // 高位 PC (Cache Line 地址)
    FetchID_t fetchID;       // 包 ID
    IFetchFault fetchFault;  // 取指过程中的异常
    FetchOff_t firstValid;   // 第一个有效字节偏移 (处理非对齐起始)
    FetchOff_t lastValid;    // 最后一个有效字节偏移
    FetchOff_t predPos;      // 预测跳转发生的位置
    logic predTaken;         // 预测跳转方向
    logic[30:0] predTarget;  // 预测跳转目标
    logic[FETCH_WORDS-1:0][15:0] instrs; // 原始指令数据 (8个16位半字)

    logic valid;
} IF_Instr /* public */;

// 预解码指令 (PD_Instr) - 描述“切分后的指令”
// Pre-Decoder 将 128位数据切分为独立的指令。
typedef struct packed
{
    logic[31:0] instr;     // 32位指令字 (如果是压缩指令，高位无效)
    logic[30:0] pc;        // 精确 PC
    FetchOff_t fetchStartOffs; // 指令起始偏移
    FetchOff_t fetchPredOffs;  // 预测信息偏移
    logic[30:0] predTarget;    // 预测目标
    logic predTaken;           // 预测方向
    FetchID_t fetchID;
    IFetchFault fetchFault;
    logic is16bit;         // 是否为 16位压缩指令
    logic valid;
} PD_Instr /* public */;

// ============================================================================
// 解码与重命名 (Decode & Rename)
// ============================================================================

// 解码分支信息 (Decode Branch)
// 解码阶段提取的简单分支信息。
typedef struct packed
{
    FetchID_t fetchID;
    FetchOff_t fetchOffs;
    logic wfi;             // Wait For Interrupt 指令
    logic taken;           // 静态预测结果?
} DecodeBranch;

// 解码微操作 (D_UOp - Decoded UOp)
// Decoder 输出。此时知道是哪个逻辑寄存器 (x1, x2)。
typedef struct packed
{
    logic[31:0] imm;       // 32位立即数 (I/S/U-type)
    logic[11:0] imm12;     // 12位立即数 (JALR 专用优化)
    logic[4:0] rs1;        // 逻辑源寄存器 1
    logic[4:0] rs2;        // 逻辑源寄存器 2
    logic immB;            // 操作数 B 是否使用立即数?
    logic[4:0] rd;         // 逻辑目标寄存器
    logic[5:0] opcode;     // 内部操作码
    FuncUnit fu;           // 功能单元类型 (ALU, AGU...)
    FetchID_t fetchID;
    FetchOff_t fetchOffs;
    logic compressed;      // 压缩指令标志
    logic valid;
} D_UOp /* public */;

// 重命名微操作 (R_UOp - Renamed UOp)
// Rename 输出。逻辑寄存器被替换为物理 Tag。
typedef struct packed
{
    logic[31:0] imm;
    logic[11:0] imm12;     // JALR 优化

    // --- 操作数 A ---
    logic availA;          // 是否就绪 (Scoreboard)
    Tag tagA;              // 物理 Tag

    // --- 操作数 B ---
    logic availB;          // 是否就绪
    Tag tagB;              // 物理 Tag

    logic immB;            // 使用立即数作为 B?

    // --- 操作数 C (原子操作/浮点) ---
    logic availC;
    Tag tagC;

    SqN sqN;               // 序列号 (ROB Index)
    Tag tagDst;            // 结果写入的目标 Tag
    RegNm rd;              // 保留逻辑目标名 (用于提交时更新 RAT)

    logic[5:0] opcode;
    FetchID_t fetchID;
    FetchOff_t fetchOffs;

    SqN storeSqN;          // 关联的 Store Queue 序号 (如果是存)
    SqN loadSqN;           // 关联的 Load Queue 序号 (如果是取)

    FuncUnit fu;
    logic compressed;
    logic[NUM_PORTS_TOTAL-1:0] validIQ; // 位掩码：该指令可以进入哪些发射队列?
    logic valid;
} R_UOp /* public */;

// ============================================================================
// 发射与执行 (Issue & Execute)
// ============================================================================

// 发射队列微操作 (IS_UOp - Issue UOp)
// 驻留在发射队列中。为了省面积，不包含 32位源数据，只包含 Tag。
// "Load-after-Issue" 架构特征。
typedef struct packed
{
    logic[31:0] imm;       // 立即数是唯一携带的数据
    logic[11:0] imm12;

    logic availA; Tag tagA;// 源 A
    logic availB; Tag tagB;// 源 B
    logic immB;

    SqN sqN;
    Tag tagDst;            // 目标 Tag

    logic[5:0] opcode;
    FetchID_t fetchID;
    FetchOff_t fetchOffs;
    SqN storeSqN; SqN loadSqN;
    FuncUnit fu;
    logic compressed;
    logic valid;
} IS_UOp /* public */;

// 操作数文件请求 (OpFile Request)
// 发射后，去"静态参数文件" (OpFile) 读取不常变的信息 (如 imm, opcode)。
typedef struct packed
{
    SqN sqN;               // 用 SqN 索引
    logic valid;
} OpFile_Req;

// 操作数文件响应 (OpFile Response)
typedef struct packed
{
    logic[11:0] imm12;     // 不同端口可能只取部分立即数
    logic[31:0] imm;

    // 只有整数端口需要知道 LD/ST SqN
    SqN storeSqN;
    SqN loadSqN;

    logic[5:0] opcode;
    logic immB;
    logic compressed;
    FetchOff_t fetchOffs;
} OpFile_Res;

// 物理寄存器读取请求 (RF Read Request)
typedef struct packed
{
    RFTag tag;             // 物理寄存器索引
    logic valid;
} RF_ReadReq;

// 执行微操作 (EX_UOp - Execute UOp)
// 此时指令已读取了物理寄存器堆。
// 关键：Tag 变成了真实的 srcA/srcB 数据。ALU 拿到的就是这个包。
typedef struct packed
{
    logic[31:0] srcA;      // 真实的源数据 A
    logic[31:0] srcB;      // 真实的源数据 B

    logic[31:0] pc;        // PC (从 PC File 读回)

    FetchOff_t fetchOffs;
    FetchOff_t fetchStartOffs;
    FetchOff_t fetchPredOffs;

    logic[31:0] imm;
    logic[5:0] opcode;
    Tag tagDst;            // 结果写回哪里
    SqN sqN;
    FetchID_t fetchID;
    BranchPredInfo bpi;    // 分支预测信息 (用于检查预测是否正确)
    SqN storeSqN; SqN loadSqN;
    FuncUnit fu;
    logic compressed;
    logic valid;
} EX_UOp /* public */;

// ============================================================================
// 结果写回 (Writeback)
// ============================================================================

// 结果总线微操作 (RES_UOp / Result)
// 广播到 CDB。包含结果数据和 Flags。
typedef struct packed
{
    logic[31:0] result;    // 计算结果
    Tag tagDst;            // 目标 Tag
    SqN sqN;
    Flags flags;           // 执行标志 (异常、分支方向等)
    logic doNotCommit;     // 特殊标志 (例如推测失败的路径上的指令)
    logic valid;
} RES_UOp /* public */;

// 标志微操作 (Flags UOp)
// 某些指令 (如无结果的分支) 只广播 Flags，不广播 32位结果。
typedef struct packed
{
    Tag tagDst;
    SqN sqN;
    Flags flags;           // 仅包含标志
    logic doNotCommit;
    logic valid;
} FlagsUOp /* public */;

// ============================================================================
// 结果写回 (Result Writeback)
// ============================================================================

// 通用结果微操作 (Result UOp)
// 用于 ALU/LSU 将计算结果写回寄存器堆 (Register File) 并广播到 CDB。
typedef struct packed
{
    logic[31:0] result;    // 写入的数据
    Tag tagDst;            // 目标物理寄存器 Tag
    logic doNotCommit;     // 特殊标志：结果有效但不提交 (例如推测路径上的指令)
    logic valid;
} ResultUOp /* public */;

// 原子操作数据微操作 (AMO Data UOp)
// 原子指令 (Atomic Memory Operation) 需要读-改-写。
// 这个结构体用于传输原子操作读取到的旧值 (用于写回寄存器) 和相关的控制流信息。
typedef struct packed
{
    logic[31:0] result;    // 原子操作读取的内存旧值
    SqN storeSqN;          // 关联的 Store 序列号 (用于原子写的顺序)
    SqN sqN;               // 指令序列号
    logic valid;
} AMO_Data_UOp;

// ============================================================================
// 地址生成与存储数据 (AGU & Store Data)
// ============================================================================

// AGU 微操作 (AGU UOp)
// 由 AGU 单元产生，发送给 Load/Store Unit。
// 包含了访问内存所需的所有“地址侧”信息。
typedef struct packed
{
    logic[31:0] addr;      // 计算出的虚拟地址
    // could union some of these fields
    logic[3:0] wmask;      // 写掩码 (例如 SB 只有 1位是 1)
    logic signExtend;      // 加载结果是否符号扩展
    logic[1:0] size;       // 访问大小 (0=Byte, 1=Half, 2=Word)
    logic isStore;         // 是存储操作? (原子操作既是 Load 也是 Store)
    logic isLoad;          // 是加载操作?
    logic isLrSc;          // 是 LR/SC 指令?
    logic earlyLoadFailed; // 早期加载推测失败 (需要重放)
    Tag tagDst;            // Load 的结果写回哪里
    SqN sqN;               // 指令序列号
    SqN storeSqN;          // Store 序列号 (用于 Store Queue 排序)
    SqN loadSqN;           // Load 序列号 (用于 Load Buffer 排序)
    FetchOff_t fetchOffs;
    FetchID_t fetchID;
    logic doNotCommit;
    logic compressed;
    logic valid;
} AGU_UOp;

// 存储数据微操作 (Store Data UOp)
// Store 操作的数据部分。由 "Store Data Unit" 产生，发送给 Store Queue。
// SoomRV 将 Store 的“地址计算”和“数据准备”解耦，允许乱序执行。
typedef struct packed
{
    logic[31:0] data;      // 要写入内存的数据
    SqN storeSqN;          // 必须匹配 AGU 发出的 storeSqN
    logic valid;
} StDataUOp;

// 存储数据查找请求 (Store Data Lookup UOp)
// 用于去寄存器堆读取 Store 指令所需的源数据 (rs2)。
typedef struct packed
{
    StOff_t offs;          // 偏移量
    Tag tag;               // 源寄存器 Tag (rs2)
    SqN storeSqN;          // Store 序列号
    logic valid;
} StDataLookupUOp;

// ============================================================================
// 加载结果与前推 (Load Result & Forwarding)
// ============================================================================

// 加载结果微操作 (Load Result UOp)
// 从 LSU 返回给执行引擎的数据包。
// 数据来源可能是 Cache，也可能是 Store-to-Load Forwarding。
typedef struct packed
{
    logic[31:0] data;      // 读取的数据
    logic[3:0] fwdMask;    // 前推掩码：指示哪些字节是直接从 Store Queue 前推的
                           // (未被前推的字节来自 Cache)
    logic[31:0] addr;      // 访问地址 (用于调试或冲突检测)
    logic[1:0] size;
    logic sext;
    logic dataAvail;       // 数据是否有效 (Cache Miss 时为 0)

    Tag tagDst;            // 写回目标
    SqN sqN;
    logic external;        // 是否来自外部 MMIO
    logic doNotCommit;
    logic valid;
} LoadResUOp;

// ============================================================================
// 虚拟内存与页表漫游 (Virtual Memory & Page Walker)
// ============================================================================

// 页表漫游请求 (Page Walk Request)
// 当 TLB Miss 时，发送给硬件 Page Walker。
typedef struct packed
{
    logic[31:0] addr;      // 导致 Miss 的虚拟地址
    logic[21:0] rootPPN;   // 页表根物理页号 (satp.ppn)
    logic valid;
} PageWalk_Req;

// 页表漫游响应 (Page Walk Response)
// Page Walker 遍历页表后返回的结果，用于填充 TLB。
typedef struct packed
{
    logic[19:0] vpn;       // 虚拟页号
    logic[21:0] ppn;       // 物理页号

    logic pageFault;       // 是否发生缺页异常
    logic isSuperPage;     // 是否是大页 (Superpage)

    logic globl;           // Global 位 (所有 ASID 共享)
    logic user;            // User 位 (用户态可访问)

    logic[2:0] rwx;        // 读/写/执行 权限位
    logic[1:0] rqID;       // 请求 ID (用于匹配并发请求)

    logic busy;            // Walker 忙标志
    logic valid;
} PageWalk_Res;

// TLB 查找请求 (TLB Request)
typedef struct packed
{
    logic[19:0] vpn;       // 虚拟页号
    logic valid;
} TLB_Req;

// TLB 查找响应 (TLB Response)
typedef struct packed
{
    logic[19:0] ppn;       // 物理页号
    logic pageFault;       // 缺页
    logic accessFault;     // 访问权限错误
    logic[2:0] rwx;        // 权限
    logic isSuper;         // 大页
    logic user;            // 用户页
    logic hit;             // TLB 命中 (Hit)
} TLB_Res;

// Page Walker 加载操作 (PW Load UOp)
// Page Walker 本身也需要读取内存 (读页表项 PTE)，这通过 LSU 进行。
typedef struct packed
{
    logic[31:0] addr;      // 页表项物理地址
    logic valid;
} PW_LD_UOp;

// ============================================================================
// 内部加载/存储操作 (Internal LSU Ops)
// ============================================================================

// 加载单元微操作 (LD UOp)
// LSU 内部处理 Cache 访问的核心结构。
typedef struct packed
{
    logic[31:0] data;      // Store Data (如果是 Store)
    logic dataValid;       // 数据有效性
    logic[31:0] addr;      // 物理地址 (TLB 翻译后)
    logic signExtend;
    logic[1:0] size;
    SqN storeSqN;          // 依赖检查用
    SqN loadSqN;
    Tag tagDst;
    SqN sqN;
    logic atomic;          // 原子操作
    logic doNotCommit;
    logic external;        // 外部操作 (MMIO)，不提交 SqN
    logic isMMIO;          // 标记为 MMIO 访问
    logic valid;
} LD_UOp /* public */;

// 早期加载地址 (Early Load UOp) - VIPT 优化关键
// SoomRV 使用 VIPT (虚拟索引物理标签)。
// 在 TLB 翻译完成前，先用虚拟地址的低 12 位 (Index) 去查 Cache RAM。
typedef struct packed
{
    logic[11:0] addr;      // 虚拟地址低 12 位 (Page Offset)
    logic valid;
} ELD_UOp;

// ============================================================================
// 缓存结构与缺失处理 (Cache Structures & Miss Handling)
// ============================================================================

// Cache 表项 (Cache Table Entry)
// 存储 Cache Tag (物理地址的高位)。
typedef struct packed
{
    logic[32-`VIRT_IDX_LEN-1:0] addr; // Tag 部分
    logic valid;
} CTEntry;

// Cache 表读取请求
typedef struct packed
{
    logic[`VIRT_IDX_LEN-1:0] addr;    // Index 部分
    logic valid;
} CacheTableRead;

// Cache 表读取结果
// 一次读出 4 路 (4-way) 的 Tag，用于比较。
typedef struct packed
{
    AssocIdx_t assocCnt;          // 命中哪一路 (Associativity Count)
    CTEntry[`CASSOC-1:0] data;    // 4路的所有 Tag 数据
} CacheTableResult;

// Cache 缺失类型 (Miss Type)
typedef enum logic[3:0]
{
    REGULAR,           // 普通缺失
    REGULAR_NO_EVICT,  // 不驱逐 (用于特殊操作)
    TRANS_IN_PROG,     // 传输进行中 (MSHR 命中)
    MGMT_CLEAN,        // 管理操作：Clean
    MGMT_INVAL,        // 管理操作：Invalidate
    MGMT_FLUSH,        // 管理操作：Flush
    CONFLICT           // 冲突 (资源不足)
} MissType;

// Cache 缺失描述符 (Cache Miss)
// 描述一个需要去主存处理的 Cache Miss 事件。
typedef struct packed
{
    logic[31:0] writeAddr; // 如果需要驱逐旧行 (Evict)，这是回写地址
    logic[31:0] missAddr;  // 导致 Miss 的新地址
    logic[$clog2(`CASSOC)-1:0] assoc; // 替换哪一路 (Way ID)
    MissType mtype;        // 缺失类型
    logic valid;
} CacheMiss;

// Cache 行索引
typedef logic[`CACHE_SIZE_E-`CLSIZE_E-1:0] CacheLineIdx;

// 设置 Dirty 位请求
typedef struct packed
{
    CacheLineIdx idx;      // 哪一行
    logic valid;
} CacheLineSetDirty;

// ============================================================================
// 加载确认与存储队列 (Load Ack & SQ)
// ============================================================================

// 加载确认 (Load Acknowledge)
// LSU 告诉 Load Buffer 该加载操作的状态。
typedef struct packed
{
    logic[31:0] addr;      // 物理地址
    SqN loadSqN;           // Load 序列号
    logic fail;            // 加载失败 (例如内存顺序冲突，需要重放)
    logic doNotReIssue;    // 不重发
    logic external;
    logic valid;
} LD_Ack;

// 存储队列微操作 (SQ UOp)
// 从 Store Queue 发出，准备写入 Cache 的已提交 Store 指令。
typedef struct packed
{
    RegT data;             // 写数据
    logic[31:0] addr;      // 写地址
    logic[3:0] wmask;      // 写掩码
    logic isMgmt;          // 是缓存管理指令?
    logic valid;
} SQ_UOp;

// ============================================================================
// 存储执行接口 (Store Execution Interface)
// ============================================================================

// 存储微操作 (ST UOp)
// 这是 Store Queue 发送给外部总线或 L1 Cache 控制器的实际写请求。
typedef struct packed
{
    logic[31:0] addr;          // 物理写地址
    logic[`AXI_WIDTH-1:0] data;// 写数据 (通常是 Cache Line 宽度或总线宽度)
    logic[`AXI_WIDTH/8-1:0] wmask; // 写掩码 (Byte Mask)
    logic isMMIO;              // 标记为 MMIO 访问 (不可缓存，需强序)
    logic isMgmt;              // 缓存管理操作 (如 Flush/Clean)
    StNonce_t nonce;           // 唯一标识符 (防止 Store Queue 混淆)
    StID_t id;                 // Store Queue ID
    logic valid;
} ST_UOp /* public */;

// 存储确认 (ST Ack)
// 内存系统反馈给 Store Queue 的信号，告知写操作是否完成。
typedef struct packed
{
    logic[31:0] addr;          // 完成的地址
    logic[`AXI_WIDTH-1:0] data;
    logic[`AXI_WIDTH/8-1:0] wmask;
    StNonce_t nonce;           // 匹配请求的 Nonce
    StID_t idx;
    logic fail;                // 写入失败 (例如总线错误)
    logic valid;
} ST_Ack;

// ============================================================================
// 提交与限制 (Commit & Limits)
// ============================================================================

// 提交限制更新 (Commit Limit)
// 用于更新 "已提交序列号" (Committed SqN) 指针。
typedef struct packed
{
    SqN sqN;                   // 所有小于等于此 SqN 的指令都已确认为“提交”
    logic valid;
} ComLimit;

// 取指限制更新 (Fetch Limit)
// 用于限制前端取指，防止覆盖未提交的指令数据。
typedef struct packed
{
    FetchID_t fetchID;
    logic valid;
} FetchLimit;

// 提交微操作 (Commit UOp)
// ROB 广播的退休信息。RAT (Register Alias Table) 接收此信号后，
// 将对应的物理寄存器映射标记为“非推测”(Non-speculative)，并释放旧的物理标签。
typedef struct packed
{
    RegNm rd;                  // 逻辑目标寄存器
    Tag tagDst;                // 提交的物理标签
    SqN sqN;                   // 提交的序列号
    logic isBranch;            // 是否为分支
    logic branchTaken;         // 分支是否跳转
    logic compressed;          // 是否为压缩指令
    logic valid;
} CommitUOp /* public */;

// ============================================================================
// 异常与陷阱 (Traps & Exceptions)
// ============================================================================

// 异常微操作 (Trap UOp)
// 当流水线中某条指令触发异常时，ROB 会生成此包发送给 Trap Handler。
typedef struct packed
{
    logic timeout;             // 发生死锁/超时
    Flags flags;               // 异常标志
    Tag tag;                   // 相关寄存器 Tag
    SqN sqN;                   // 触发异常的指令序列号
    SqN loadSqN;               // 关联的 Load 序号
    SqN storeSqN;              // 关联的 Store 序号
    RegNm rd;                  // 目标寄存器
    FetchOff_t fetchOffs;      // 指令偏移
    FetchID_t fetchID;         // 指令 ID (用于定位 PC)
    logic compressed;
    logic valid;
} Trap_UOp /* public */;

// 分支预测更新 (BP Update)
// 提交阶段再次确认分支结果，用于更新预测器历史。
typedef struct packed
{
    FetchOff_t fetchOffs;
    FetchID_t fetchID;
    logic branchTaken;         // 最终确认的跳转方向
    logic valid;
} BPUpdate;

// 零周期前推 (Zero Cycle Forward)
// 一种激进的优化，允许某些简单的结果在生成的同一个周期内被后续指令使用。
typedef struct packed
{
    logic[31:0] result;
    Tag tag;
    logic valid;
} ZCForward;

// ============================================================================
// CSR 与系统状态 (CSR & System State)
// ============================================================================

// 异常控制状态 (Trap Control State)
// 从 CSR 模块输出，告诉流水线如何处理异常 (跳转到哪、权限检查等)。
typedef struct packed
{
    logic[30:0] retvec;        // 返回地址向量
    logic[29:0] mtvec;         // 机器模式异常向量基址 (Machine Trap Vector)
    logic mvectord;            // mtvec 模式位
    logic[29:0] stvec;         // 监管模式异常向量基址 (Supervisor Trap Vector)
    logic svectord;
    logic[15:0] medeleg;       // 机器异常委托屏蔽码 (Delegate to S-mode)
    logic[15:0] mideleg;       // 机器中断委托屏蔽码
    PrivLevel priv;            // 当前特权级 (U/S/M)

    logic interruptPending;    // 有中断挂起?
    TrapCause_t interruptCause;// 中断原因
    logic interruptDelegate;   // 该中断是否应委托给 S-mode?

} TrapControlState;

// Trap Value 状态 (mtval/stval)
typedef struct packed
{
    logic[31:0] tval;          // 导致异常的值 (如错误地址)
} TValState;

// 异常信息更新 (Trap Info Update)
// Trap Handler 写回 CSR 的信息。
typedef struct packed
{
    logic[31:0] trapPC;        // 发生异常的 PC (写入 mepc/sepc)
    logic[31:0] finalHalfwPC;  // 最终半字 PC
    logic isInterrupt;         // 是中断?
    TrapCause_t cause;         // 异常原因 (写入 mcause/scause)
    logic delegate;            // 是否委托
    logic valid;
} TrapInfoUpdate;

// 浮点标志更新 (Float Flags Update)
// FPU 完成计算后，累加异常标志到 fcsr 寄存器。
typedef struct packed
{
    logic[4:0] flags;          // NX, UF, OF, DZ, NV
    SqN sqN;
    logic valid;
} FloatFlagsUpdate;

// ============================================================================
// 配置与控制 (Configuration & Control)
// ============================================================================

// 虚拟内存状态 (Virtual Memory State)
// 从 CSR (satp) 发送给 AGU/TLB，控制地址翻译模式。
typedef struct packed
{
    logic sv32en;              // 启用 Sv32 分页模式
    logic sv32en_ifetch;       // 取指是否启用分页
    logic[21:0] rootPPN;       // 页表根目录物理页号 (satp.ppn)
    logic makeExecReadable;    // MXR 位：可执行页面是否可读?
    logic supervUserMemory;    // SUM 位：监管模式是否可访问用户页?
    logic[1:0] cbie;           // Cache Block Invalidate Enable
    logic cbcfe;               // Cache Block Clean/Flush Enable
    PrivLevel priv;            // 当前特权级
} VirtMemState;

// 解码器状态 (Decode State)
// 控制解码行为的静态配置信号。
typedef struct packed
{
    logic allowCustom;         // 允许自定义指令?
    logic allowWFI;            // 允许 WFI 指令? (受 mstatus.tw 控制)
    logic allowSFENCE;         // 允许 SFENCE.VMA?
} DecodeState;

// Trap Value 提供者 (TVal Provider)
// 流水线中谁负责提供 tval 的值 (通常是 AGU 或 Decode)。
typedef struct packed
{
    logic[31:0] tval;
    SqN sqN;
    logic valid;
} TValProv;

// ============================================================================
// 物理存储接口 (Physical Memory Interfaces)
// ============================================================================

// 数据 Cache 接口 (Data Cache Interface)
// 直接连接到实现 Cache Tag/Data 的 SRAM (Block RAM)。
typedef struct packed
{
    logic ce;                  // Chip Enable (片选)
    logic we;                  // Write Enable (写使能)
    logic[4*`CWIDTH-1:0] wm;   // Write Mask (写掩码)
    logic[`CACHE_SIZE_E-3:0] addr; // SRAM 地址
    logic[32*`CWIDTH-1:0] data;    // 读写数据
} CacheIF;

// 指令 Cache 接口 (Instruction Cache Interface)
typedef struct packed
{
    logic ce;
    logic we;
    logic[(FETCH_BITS/`AXI_WIDTH)-1:0] wm;
    logic[`CACHE_SIZE_E-3:0] addr;
    logic[FETCH_BITS-1:0] data;
} ICacheIF;

// ============================================================================
// 性能计数器 (Performance Counters)
// ============================================================================

// ROB 性能监控信息
// 用于驱动 `hpmcounter` 等硬件性能计数器。
typedef struct packed
{
    logic[1:0] stallWeigth;    // 停顿权重 (Stall Weight)
    StallCause stallCause;     // 停顿原因 (如 Cache Miss, Branch Mispred)
    logic[3:0] branchRetire;   // 本周期退休的分支数
    logic[3:0] validRetire;    // 本周期退休的总指令数 (IPC 计算基础)
} ROB_PERFC_Info;

// ============================================================================
// 硬件预取器 (Hardware Prefetcher)
// ============================================================================

// 预取步长类型
typedef enum logic[1:0] {STRIDE_M_TWO, STRIDE_M_ONE, STRIDE_ONE, STRIDE_TWO} PFStride_t;
typedef logic[31-`CLSIZE_E:0] PFAddr_t; // 预取地址 (Cache Line 对齐)

// 预取模式 (Prefetch Pattern)
// 记录检测到的内存访问模式。
typedef struct packed
{
    PFStride_t stride;         // 步长 (Stride)
    PFAddr_t addr;             // 基地址
    logic valid;
} PrefetchPattern;

// 预取缺失 (Prefetch Miss)
// 记录 Cache Miss 事件，用于训练预取器。
typedef struct packed
{
    PFAddr_t addr;
    logic read;
    logic write;
    logic valid;
} PrefetchMiss;

// 预取访问 (Prefetch Access)
typedef struct packed
{
    PFAddr_t addr;
    logic w;                   // 写访问?
    logic r;                   // 读访问?
    logic valid;
} PrefetchAccess;

// 预取请求 (Prefetch Request)
// 预取器决定发出的加载请求。
typedef struct packed
{
    logic[31:0] addr;          // 预取地址
    logic valid;
} Prefetch;

// 预取确认 (Prefetch ACK)
typedef struct packed
{
    logic existing;            // 预取的地址已经在 Cache 中了 (避免重复)
    logic valid;
} Prefetch_ACK;

// ============================================================================
// CSR 与 MMIO 专用接口
// ============================================================================

// CSR MMIO 接口
// 专门用于传递 mtime 和 mtimecmp 这两个内存映射的计时器寄存器。
// 在 RISC-V 中，这两个寄存器通常位于 CLINT (Core Local Interruptor) 中。
interface IF_CSR_MMIO;
    logic[63:0] mtime;      // 机器时间计数器
    logic[63:0] mtimecmp;   // 机器时间比较器 (用于触发时钟中断)

    modport CSR
    (
        input mtime,
        input mtimecmp
    );
    modport MMIO
    (
        output mtime,
        output mtimecmp
    );
endinterface

// ============================================================================
// 通用内存接口 (Memory Interfaces)
// ============================================================================

// 通用内存接口 (IF_Mem)
// 一个简单的双向握手内存总线，用于连接片上 SRAM 或简单的内存模型。
interface IF_Mem();

    localparam ADDR_LEN=30; // 地址宽度 (30位字地址 = 32位字节地址)

    logic we;               // 写使能
    logic[ADDR_LEN-1:0] waddr; // 写地址
    logic[31:0] wdata;      // 写数据
    logic[3:0] wmask;       // 写掩码

    logic re;               // 读使能
    logic[ADDR_LEN-1:0] raddr; // 读地址
    logic[31:0] rdata;      // 读数据

    logic rbusy;            // 读忙 (SRAM 忙，无法处理新请求)
    logic wbusy;            // 写忙

    modport HOST // 主机端 (CPU/LSU)
    (
        output we, waddr, wdata, wmask, re, raddr,
        input rdata, rbusy, wbusy
    );

    modport MEM // 从机端 (SRAM/Memory)
    (
        input we, waddr, wdata, wmask, re, raddr,
        output rdata, rbusy, wbusy
    );
endinterface

// ============================================================================
// 数据 Cache 物理接口 (D-Cache Physical Interface)
// ============================================================================

// 数据 Cache RAM 接口 (IF_Cache)
// 直接控制存储数据的 Block RAM。支持多端口读写。
interface IF_Cache();

    // 读端口 (多端口)
    logic[NUM_CT_READS-1:0] re;
    logic[NUM_CT_READS-1:0] we;
    logic[NUM_CT_READS-1:0][`VIRT_IDX_LEN-1:0] addr; // 索引 (Index)

    // 读出数据：每个 AGU 端口都能读出 4路 (Way) 的数据，供后续 Tag 比较选择
    logic[NUM_AGUS-1:0][`CASSOC-1:0][31:0] rdata;

    // 写端口
    logic[NUM_CT_READS-1:0][$clog2(`CASSOC)-1:0] wassoc; // 写入哪一路 (Way ID)
    logic[NUM_CT_READS-1:0][`AXI_WIDTH-1:0] wdata;       // 写入整行数据
    logic[NUM_CT_READS-1:0][`AXI_WIDTH/8-1:0] wmask;     // 写入掩码
    logic[NUM_CT_READS-1:0] busy;

    modport HOST
    (
        output we, wassoc, wdata, wmask, re, addr,
        input rdata, busy
    );

    modport MEM
    (
        input we, wassoc, wdata, wmask, re, addr,
        output rdata, busy
    );
endinterface

// 存储前推结果 (Store Forwarding Result)
// 当 Load 指令在 Store Queue 中找到匹配地址的未提交 Store 时，
// 使用此结构体返回数据。
typedef struct packed
{
    logic[31:0] data;     // 前推的数据
    logic[3:0] mask;      // 哪些字节是有效的 (部分前推)
    logic conflict;       // 冲突标志 (例如：需要的字节 StoreQueue 没全覆盖，需要等待 Store 提交)
    logic valid;          // 找到了匹配
} StFwdResult;

// 数据 Cache 标签表接口 (IF_CTable)
// 控制存储 Tag 的 RAM。
interface IF_CTable();

    // 写端口 (通常只有一个，用于 Cache Fill/Replace)
    logic we;
    logic[`VIRT_IDX_LEN-1:0] waddr;      // 写索引
    logic[$clog2(`CASSOC)-1:0] wassoc;   // 写路 (Way)
    CTEntry wdata;                       // 写 Tag 内容
    AssocIdx_t widx;                     // 写关联索引

    // 读端口 (多个，每个 AGU 一个)
    logic re[NUM_CT_READS-1:0];
    logic[`VIRT_IDX_LEN-1:0] raddr[NUM_CT_READS-1:0];
    CTEntry[NUM_CT_READS-1:0][`CASSOC-1:0] rdata; // 读出所有路的 Tag
    AssocIdx_t[NUM_CT_READS-1:0] ridx;

    modport HOST
    (
        output we, waddr, wassoc, wdata, widx, re, raddr,
        input rdata, ridx
    );

    modport MEM
    (
        input we, waddr, wassoc, wdata, widx, re, raddr,
        output rdata, ridx
    );
endinterface

// ============================================================================
// MMIO 接口 (Memory Mapped I/O)
// ============================================================================

// MMIO 总线接口
// 用于连接外设。包含 rsize 以支持不同宽度的读取 (Byte/Half/Word)。
interface IF_MMIO();

    localparam ADDR_LEN=32;

    logic we;
    logic[ADDR_LEN-1:0] waddr;
    logic[31:0] wdata;
    logic[3:0] wmask;

    logic re;
    logic[ADDR_LEN-1:0] raddr;
    logic[1:0] rsize;       // 读取大小 (1, 2, 4 字节)
    logic[31:0] rdata;

    logic rbusy;
    logic wbusy;

    modport HOST
    (
        output we, waddr, wdata, wmask, re, raddr, rsize,
        input rdata, rbusy, wbusy
    );

    modport MEM
    (
        input we, waddr, wdata, wmask, re, raddr, rsize,
        output rdata, rbusy, wbusy
    );
endinterface

// ============================================================================
// 指令 Cache 接口 (I-Cache Interface)
// ============================================================================

// I-Cache 标签表接口
// 与 D-Cache 类似，但通常端口较少 (取指通常是单端口的)。
interface IF_ICTable();

    logic we;
    logic[`VIRT_IDX_LEN-1:0] waddr;
    logic[$clog2(`CASSOC)-1:0] wassoc;
    CTEntry wdata;

    logic re;
    logic[`VIRT_IDX_LEN-1:0] raddr;
    CTEntry[`CASSOC-1:0] rdata;

    modport HOST
    (
        output we, waddr, wassoc, wdata, re, raddr,
        input rdata
    );

    modport MEM
    (
        input we, waddr, wassoc, wdata, re, raddr,
        output rdata
    );
endinterface

// I-Cache 数据 RAM 接口
interface IF_ICache();

    logic re;
    logic[11:0] raddr;
    logic[`CASSOC-1:0][FETCH_BITS-1:0] rdata; // 读出一行数据 (128 bits)
    logic busy;

    modport HOST
    (
        output re, raddr,
        input rdata, busy
    );

    modport MEM
    (
        input re, raddr,
        output rdata, busy
    );
endinterface

// ============================================================================
// 调试信息 (Debug Info)
// ============================================================================

// 核心调试信息
// 这些信号不参与逻辑控制，仅用于波形观察或性能计数器，分析流水线停顿原因。
typedef struct packed
{
    logic[31:0] stallPC;   // 当前停顿的 PC

    logic sqNStall;        // 因序列号耗尽停顿 (ROB 满)
    logic stSqNStall;      // 因 Store 序列号耗尽停顿

    logic rnStall;         // Rename 阶段停顿 (物理寄存器满?)
    logic memBusy;         // 内存系统忙

    logic sqBusy;          // Store Queue 忙
    logic lsuBusy;         // Load/Store Unit 忙
    logic ldNack;          // Load 被拒绝 (Negative Acknowledge，需重试)
    logic stNack;          // Store 被拒绝

} DebugInfo;

// 内存控制器调试信息
// 跟踪内存控制器的事务状态。
typedef struct packed
{
    logic[3:0] transfValid;     // 事务有效
    logic[3:0] transfReadDone;  // 读完成
    logic[3:0] transfWriteDone; // 写完成
    logic[3:0] transfIsMMIO;    // 是 MMIO 事务
} DebugInfoMemC;