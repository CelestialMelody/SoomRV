// ==========================================
// 前端与分支预测配置 (Frontend & Prediction)
// ==========================================

// Branch Target Buffer (分支目标缓冲)
// 用于记录跳转指令的目标地址，减少跳转带来的流水线气泡
`define BTB_ENTRIES 4096      // BTB 条目数：4096项 (相当大，能记住很多跳转目标)
`define BTB_TAG_SIZE 16       // BTB 标签大小：16位 (用于验证是否命中)

// TAGE Predictor (TAGE 分支方向预测器)
// 一种高性能的条件跳转预测算法
`define BP_BASEP_ID_LEN 12    // 基础预测器的索引长度
`define TAGE_CLEAR_ENABLE     // 启用 TAGE 表的定期清理机制
`define TAGE_CLEAR_INTERVAL 20 // 清理间隔
`define TAGE_BASE 4           // TAGE 基础参数
`define TAGE_STAGES 6         // TAGE 历史表的级数 (使用不同长度的历史进行多级预测)
`define TAGE_TABLE_SIZE 256   // 每个 TAGE 表的大小：256项
`define RETURN_SIZE 32        // 返回栈 (RAS) 深度：32 (用于预测函数返回地址)
`define RETURN_RQ_SIZE 8      // RAS 恢复队列大小：8 (用于预测错误时恢复 RAS)

// IFetch (取指单元)
`define FSIZE_E 4             // 取指宽度的指数 (2^4 = 16)
// FETCH_BITS = 16 << 3 = 128 bit (16字节)。每个周期从 Cache 取 16 字节指令。
parameter FETCH_BITS = 16 << (`FSIZE_E - 1);
// FETCH_WORDS = 1 << 3 = 8 个 16位半字 (因为 RISC-V 最小指令是 16位)
parameter FETCH_WORDS = 1 << (`FSIZE_E - 1);

`define DEC_WIDTH 4           // 解码宽度：4 (核心参数，代表这是 4-wide 超标量处理器)
`define PD_BUF_SIZE 4         // 预解码缓冲大小：4 (用于处理指令边界对齐)
`define WFI_DELAY 1024        // WFI (Wait For Interrupt) 指令的延迟周期
`define RESET_DELAY 4096      // 复位后的延迟周期

// ==========================================
// 内存子系统配置 (Memory Subsystem)
// ==========================================

// 队列大小
`define SQ_SIZE 16            // 存储队列 (Store Queue) 深度：16 (缓冲未提交的写操作)
`define LB_SIZE 16            // 加载队列 (Load Buffer) 深度：16 (用于检测访存顺序冲突)
`define LRB_SIZE 4            // 加载结果缓冲大小

// TLB (页表缓冲)
`define ITLB_SIZE 8           // 指令 TLB 大小：8项 (全相联)
`define ITLB_ASSOC 4          // 指令 TLB 关联度：4路

`define DTLB_SIZE 8           // 数据 TLB 大小：8项
`define DTLB_ASSOC 4          // 数据 TLB 关联度：4路
`define DTLB_MISS_QUEUE_SIZE 4 // TLB 缺失处理队列大小

// ==========================================
// 核心资源配置 (Core Resources)
// ==========================================

// ROB Size (重排序缓冲区大小)
// 决定了处理器的乱序执行窗口大小
`define ROB_SIZE_EXP 6        // ROB 大小指数：2^6 = 64项 (中等偏小，限制了并发指令数)
`define RF_SIZE_EXP 6         // 物理寄存器堆大小指数：2^6 = 64个
                              // 注意：RISC-V 逻辑寄存器有 32 个，所以只有 32 个额外的物理寄存器用于重命名

// PC at reset (复位向量)
`define ENTRY_POINT (32'h8000_0000) // 处理器复位后从 0x80000000 开始执行

// ==========================================
// 地址空间映射 (Address Map / PMAs)
// ==========================================

// 判断是否为 MMIO (内存映射I/O) 地址
// 小于 0x80000000 的地址被视为 I/O 设备
`define IS_MMIO_PMA(addr) \
    ((addr) < 32'h8000_0000)

// 宽字版本的 MMIO 检查
`define IS_MMIO_PMA_W(addr) \
    `IS_MMIO_PMA({(addr), 2'b0})

// 内部 MMIO 地址定义
`define SYSCON_ADDR 32'h1110_0000    // 系统控制器地址
`define MTIME_ADDR 32'h1100_bff8     // 机器时间寄存器地址
`define MTIMECMP_ADDR 32'h1100_4000  // 时间比较器地址

// Cache 配置
`define VIRT_IDX_LEN 12       // 虚拟索引长度：12位 (对应 4KB 页大小，用于 VIPT Cache)
`define CASSOC 4              // Cache 关联度：4路组相联
// Cache 大小指数计算
`define CACHE_SIZE_E (`VIRT_IDX_LEN + $clog2(`CASSOC)) // $clog2含义：计算以2为底的对数
`define CLSIZE_E 6            // Cache Line 大小指数：2^6 = 64 字节

`define CBANKS 4              // Cache Bank 数量
`define CWIDTH 4              // Cache 宽度

// 总线配置 (AXI)
`define AXI_NUM_TRANS 4       // AXI 并发传输数
`define AXI_WIDTH 128         // AXI 总线数据位宽：128位 (与取指带宽匹配)
`define AXI_ID_LEN $clog2(`AXI_NUM_TRANS)

// 外部 MMIO 范围定义
`define ENABLE_EXT_MMIO 1     // 启用外部 MMIO
`define EXT_MMIO_START_ADDR 32'h1000_0000
`define EXT_MMIO_END_ADDR   32'h1100_0000

// 判断是否为合法的主存地址 (DRAM)
// 范围：0x80000000 ~ 0x90000000 (256MB 空间)
`define IS_MEM_PMA(addr) \
    ((addr) >= 32'h80000000 && (addr) < 32'h90000000)

// 判断地址是否合法 (主存 或 MMIO)
`define IS_LEGAL_ADDR(addr) \
    (`IS_MEM_PMA(addr) || \
    (`IS_MMIO_PMA(addr) && (addr) >= 32'h10000000))

// ==========================================
// 指令集功能扩展 (Extensions)
// ==========================================

// `define ENABLE_FP           // 浮点支持 (当前注释掉，未启用)
`define ENABLE_INT_DIV        // 启用整数除法
`define ENABLE_INT_MUL        // 启用整数乘法
`define ENABLE_ZCB            // 启用 Zcb 压缩指令扩展
`define SQ_LINEAR             // 存储队列线性模式 (可能简化实现)

//`define DEBUG               // 调试模式开关

// ==========================================
// 执行单元与端口分配 (Execution Engine)
// ==========================================

parameter HANG_COUNTER_LEN = 16; // 死锁检测计数器长度

// 功能单元数量定义
parameter NUM_AGUS = 2;          // 地址生成单元数量 (用于 Load/Store)
parameter NUM_ALUS = 3;          // 算术逻辑单元数量 (用于计算)

// 有多少个 ALU 端口支持分支指令？
parameter NUM_BRANCH_PORTS = 2;  // 只有 2 个端口能处理跳转

// 总端口数计算
parameter NUM_PORTS = NUM_AGUS + NUM_ALUS; // 总共 5 个发射端口 (2 AGU + 3 ALU)
parameter NUM_PORTS_TOTAL = NUM_ALUS + 2 * NUM_AGUS;

// 寄存器堆读写端口计算
// 8R4W (8读4写) 的由来：
// 读端口 = 3个ALU * 2操作数 + 2个AGU * 1操作数 = 8个读端口
// 写端口 = 3个ALU + 2个AGU = 5个写端口 (但通常 AGU 不写回通用寄存器，或者共享写入端口)
parameter NUM_RF_READS = NUM_ALUS * 2 + NUM_AGUS * 2;
parameter NUM_RF_READS_PHY = NUM_ALUS * 2 + NUM_AGUS * 1;
parameter NUM_RF_WRITES = NUM_ALUS + NUM_AGUS;
parameter NUM_CT_READS = NUM_AGUS + 1; // 还有一个端口用于存储

parameter SQ_DEQ_PORTS = 2; // Store Queue 出队端口数

// 发射队列大小配置
// 每个端口都有独立的队列，深度均为 8
parameter int PORT_IQ_SIZE[NUM_PORTS-1:0] = '{
    8, // Port 4 (ALU)
    8, // Port 3 (ALU)
    8, // Port 2 (ALU)
    8, // Port 1 (AGU)
    8  // Port 0 (AGU)
};

// ==========================================
// 功能单元掩码定义 (Function Unit Bitmasks)
// ==========================================
// 使用 One-Hot 编码定义每种运算类型

localparam[15:0] FU_INT_OH      = 1 << FU_INT;      // 普通整数运算
localparam[15:0] FU_BRANCH_OH   = 1 << FU_BRANCH;   // 分支跳转
localparam[15:0] FU_BITMANIP_OH = 1 << FU_BITMANIP; // 位操作扩展
localparam[15:0] FU_AGU_OH      = 1 << FU_AGU;      // 地址生成
localparam[15:0] FU_MUL_OH      = 1 << FU_MUL;      // 乘法
localparam[15:0] FU_DIV_OH      = 1 << FU_DIV;      // 除法
localparam[15:0] FU_FPU_OH      = 1 << FU_FPU;      // 浮点运算
localparam[15:0] FU_FMUL_OH     = 1 << FU_FMUL;     // 浮点乘法
localparam[15:0] FU_FDIV_OH     = 1 << FU_FDIV;     // 浮点除法
localparam[15:0] FU_RN_OH       = 1 << FU_RN;       // 随机数/其他
localparam[15:0] FU_ATOMIC_OH   = 1 << FU_ATOMIC;   // 原子指令
localparam[15:0] FU_CSR_OH      = 1 << FU_CSR;      // CSR 系统指令
localparam[15:0] FU_TRAP_OH     = 1 << FU_TRAP;     // 异常处理

// ==========================================
// 端口功能映射表 (Port Mapping)
// ==========================================
// 决定了每条指令可以去哪个端口执行 (这是乱序调度的核心依据)

// verilator lint_off WIDTHEXPAND
parameter logic[15:0] PORT_FUS[NUM_PORTS-1:0] = '{

    // --- AGU 端口 (处理内存访问) ---
    // Port 0 & 1: 支持地址生成和原子操作
    FU_AGU_OH|FU_ATOMIC_OH,
    FU_AGU_OH|FU_ATOMIC_OH,

    // --- ALU 端口 (处理计算) ---
    // Port 2: 整数 + 乘法 + 位操作 (这是最简单的计算端口)
    FU_INT_OH|FU_MUL_OH|FU_BITMANIP_OH,

    // Port 3: 整数 + 分支 + 乘法 + 原子 (支持分支预测更新)
    FU_INT_OH|FU_BRANCH_OH|FU_MUL_OH/*|FU_FDIV_OH|FU_FMUL_OH*/|FU_ATOMIC_OH,

    // Port 4: 整数 + 分支 + 除法 + CSR (最复杂的端口，处理长延迟指令如除法和系统操作)
    FU_INT_OH|FU_BRANCH_OH|FU_DIV_OH/*|FU_FPU_OH*/|FU_CSR_OH|FU_ATOMIC_OH
};
// verilator lint_on WIDTHEXPAND