# HardFloat 库中文说明文档

## 概述

[HardFloat ](https://www.jhauser.us/arithmetic/HardFloat.html)是伯克利大学开发的 IEEE 浮点算术包（Release 1），由 John R. Hauser 开发。这是一个用 SystemVerilog 编写的高性能硬件浮点运算库，提供了完整的 IEEE 754 浮点运算功能。

## 许可证

HardFloat 在 3-Clause BSD 许可证下发布，版权属于加州大学董事会。

## 库特性

### 支持的浮点格式

- 支持可配置的指数宽度 (expWidth) 和尾数宽度 (sigWidth)
- 兼容 IEEE 754 标准
- 支持 NaN、无穷大、零等特殊值处理

### 舍入模式

库支持以下 IEEE 舍入模式：

- `round_near_even` - 就近舍入（偶数）
- `round_minMag` - 向零舍入
- `round_min` - 向下舍入（负无穷）
- `round_max` - 向上舍入（正无穷）
- `round_near_maxMag` - 就近舍入（远离零）
- `round_odd` - 向奇数舍入

### 浮点控制选项

- 溢出检测时机选择（舍入前/舍入后）
- 子 normal 数处理选项
- NaN 传播配置

## 模块功能详解

### 1. 基础模块

#### `HardFloat_consts.vi`

定义了库中使用的各种常数和宏：

- 舍入模式定义
- 浮点控制位宽定义
- 舍入选项配置

#### `HardFloat_specialize.vi`

提供了库的特化和配置选项：

- 默认控制值设置
- NaN 默认值配置
- 条件编译选项

#### `HardFloat_localFuncs.vi`

包含库内部使用的辅助函数

### 2. 浮点运算模块

#### `addRecFN.v` - 浮点加法

提供浮点数的加法和减法运算：

- `addRecFNToRaw` - 将加法结果转换为原始格式
- 支持操作数对齐
- 处理特殊值（NaN、无穷大）
- 可配置舍入模式

**主要功能：**

- 指数对齐
- 尾数相加/相减
- 规范化处理
- 异常检测

#### `mulRecFN.v` - 浮点乘法

实现浮点数的乘法运算：

- `mulRecFNToFullRaw` - 产生完整的原始乘法结果
- 支持大尾数乘法
- 处理溢出和下溢

**主要功能：**

- 指数相加
- 尾数相乘
- 规范化处理
- 特殊值处理

#### `mulAddRecFN.v` - 浮点乘加

实现 fused multiply-add 操作：

- 一次性完成 a×b+c 的计算
- 提高计算精度和性能
- 减少舍入误差

#### `divSqrtRecFN_small.v` - 浮点除法和开方

提供浮点除法和开方运算：

- 支持小指数宽度配置
- 迭代算法实现
- 高精度结果

### 3. 比较模块

#### `compareRecFN.v` - 浮点比较

实现浮点数的比较操作：

- 小于 (lt)
- 等于 (eq)
- 大于 (gt)
- 无序 (unordered)
- 异常标志输出

**特性：**

- 支持信号化比较
- 正确处理 NaN
- 产生比较异常

### 4. 数据类型转换模块

#### `iNToRecFN.v` - 整数到浮点转换

将整数转换为浮点数：

- `iNToRawFN` - 转换为原始浮点格式
- `iNToRecFN` - 转换为标准浮点格式
- 支持有符号和无符号整数
- 自动检测输入宽度

#### `fNToRecFN.v` - 浮点格式转换

不同浮点格式之间的转换：

- 指数宽度调整
- 尾数宽度调整
- 精度转换

#### `recFNToFN.v` - 浮点到浮点转换

在不同的浮点表示之间转换

#### `recFNToIN.v` - 浮点到整数转换

将浮点数转换为整数：

- 截断和舍入
- 溢出检测
- 异常处理

#### `recFNToRecFN.v` - 浮点内部转换

浮点数的内部格式转换

### 5. 特殊值检测模块

#### `isSigNaNRecFN.v` - 显著 NaN 检测

检测显著 NaN（Signaling NaN）：

- 区分静默 NaN 和信号化 NaN
- 用于异常处理

#### `HardFloat_rawFN.v` - 原始浮点处理

处理原始浮点格式的辅助模块

#### `HardFloat_primitives.v` - 基本原语

提供底层的基本操作原语

## 使用方法

### 基本参数配置

大多数模块支持以下参数：

- `expWidth` - 指数位宽度
- `sigWidth` - 尾数位宽度（不包括隐含位）
- `intWidth` - 整数输入宽度（用于转换模块）

### 标准浮点格式示例

```systemverilog
// 单精度 (IEEE 754 binary32)
parameter expWidth = 8;
parameter sigWidth = 23;

// 双精度 (IEEE 754 binary64)
parameter expWidth = 11;
parameter sigWidth = 52;
```

### 使用示例

#### 浮点加法

```systemverilog
addRecFNToRaw#(8, 23) add_instance (
    .control(control_signal),
    .subOp(1'b0),  // 加法操作
    .a(operand_a),
    .b(operand_b),
    .roundingMode(rounding_mode),
    .invalidExc(invalid_exception),
    .out_isNaN(is_nan_output),
    .out_isInf(is_inf_output),
    .out_isZero(is_zero_output),
    .out_sign(sign_output),
    .out_sExp(exponent_output),
    .out_sig(significand_output)
);
```

#### 浮点比较

```systemverilog
compareRecFN#(8, 23) compare_instance (
    .a(operand_a),
    .b(operand_b),
    .signaling(1'b0),  // 非信号化比较
    .lt(less_than),
    .eq(equal),
    .gt(greater_than),
    .unordered(unordered),
    .exceptionFlags(exception_flags)
);
```

## 异常处理

库提供完整的 IEEE 754 异常处理：

- **无效操作 (Invalid Operation)** - 处理 NaN 相关操作
- **除以零 (Division by Zero)** - 无穷大结果
- **溢出 (Overflow)** - 结果超出表示范围
- **下溢 (Underflow)** - 非零结果太小
- **不精确 (Inexact)** - 舍入后精度损失

## 性能特点

### 优势

1. **硬件加速** - 所有运算在硬件中并行执行
2. **高精度** - 完全符合 IEEE 754 标准
3. **可配置** - 支持各种浮点格式
4. **模块化** - 每个运算独立实现，便于集成
5. **高性能** - 优化的算法实现

### 应用场景

- 处理器浮点单元 (FPU)
- 数字信号处理器 (DSP)
- 图形处理单元 (GPU)
- 科学计算加速器
- 嵌入式系统浮点运算

## 集成注意事项

### 依赖关系

- 需要包含 `HardFloat_consts.vi`
- 需要包含 `HardFloat_specialize.vi`
- 需要包含 `HardFloat_localFuncs.vi`

### 时钟和复位

大多数模块使用组合逻辑，但建议在系统级设计中：

- 添加适当的流水线寄存器
- 实现时钟使能控制
- 处理异步复位

### 参数化设计

- 根据应用需求选择合适的 expWidth 和 sigWidth
- 考虑面积和性能的权衡
- 为特殊应用启用/禁用特定功能

## 扩展和定制

库设计为高度可配置的：

- 可以通过 `HardFloat_specialize.vi` 启用/禁用特定功能
- 支持自定义默认配置
- 可以添加新的浮点格式支持

## 总结

HardFloat 库提供了一个完整、高效、符合 IEEE 754 标准的浮点运算硬件实现。其模块化设计和丰富的功能使其适用于各种需要浮点运算的硬件项目，特别是在高性能计算和嵌入式系统中发挥重要作用。
