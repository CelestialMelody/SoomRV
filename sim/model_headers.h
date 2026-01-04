// 顶层核心头文件（必须保留）
#include "VTop.h"
#include "VTop_Top.h"

// 根模块和全局单元头文件
#include "VTop___024root.h"
#include "VTop___024unit.h"

// 核心模块相关
#include "VTop_Core.h"
#include "VTop_CSR.h"

// 分支预测相关
#include "VTop_BranchPredictor__N3.h"
#include "VTop_ReturnStack.h"

// SoC 和外部模块
#include "VTop_SoC.h"
#include "VTop_ExternalAXISim.h"

// 取指阶段相关
#include "VTop_IFetch.h"
#include "VTop_IFetchPipeline.h"
#include "VTop_IF_Cache.h"
#include "VTop_IF_CTable.h"
#include "VTop_IF_ICache.h"
#include "VTop_IF_ICTable.h"
#include "VTop_IF_MMIO.h"

// 存储模块相关
#include "VTop_MemRTL__W200_N40.h"
#include "VTop_MemRTL__W200_N100_WB80.h"
#include "VTop_MemRTL1RW__W2_N40_WB2.h"
#include "VTop_MemRTL1RW__W54_N40_WB15.h"
#include "VTop_StoreQueue.h"
#include "VTop_ROB.h"

// 寄存器文件和重命名相关
#include "VTop_RegFile__S40_N8_NB5_A1.h"
#include "VTop_RegFile__W23_S20_N3_NB1.h"
#include "VTop_RegFile__W50_S20_N1_NB1.h"
#include "VTop_RenameTable__N8_ND5.h"
#include "VTop_Rename__WC5.h"
#include "VTop_TagBuffer.h"

// 其他辅助头文件
#include "VTop__Dpi.h"
#include "VTop__Syms.h"