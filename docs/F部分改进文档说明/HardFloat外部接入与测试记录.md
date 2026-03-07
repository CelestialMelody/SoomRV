# HardFloat 外部接入与测试记录

日期：2026-03-07

## 1. 目标

1. 阅读 `src`、`docs`、`README`，确认 `make soomrv` 是否已经接入“外部 HardFloat”。
2. 若未接入，给出并落实接入方案。
3. 检查 `test_programs` 是否有相应测试；若缺失，在 `test_programs/dev` 补充。
4. 将执行过程单独记录。

## 2. 阅读范围

1. 构建与说明：
   - `README.md`
   - `Makefile`
   - `docs/README.zh.md`
2. FPU 与 HardFloat 关联源码：
   - `src/FPU.sv`
   - `src/FMul.sv`
   - `src/FDiv.sv`
   - `hardfloat/`
3. 测试目录：
   - `test_programs/float.s`
   - `test_programs/float_flags.s`
   - `test_programs/float_round_mode.s`
   - `test_programs/dev/`

## 3. 阅读结论（改造前）

1. `make soomrv` 已接入 HardFloat 功能，但是“仓库内固定路径接入”，不是“可配置外部路径接入”。
2. 证据：
   - `Makefile` 固定使用 `-Ihardfloat`。
   - `Makefile` 在 `SRC_FILES` 中写死了 `hardfloat/*.v` 的文件列表。
   - `src/FPU.sv` / `src/FMul.sv` / `src/FDiv.sv` 通过 `` `include "../hardfloat/HardFloat_consts.vi" `` 固定相对路径引用。
3. `test_programs` 根目录已有浮点程序测试（`float*.s`），但 `test_programs/dev` 下缺少“HardFloat 接入链路”的独立 smoke test。

## 4. 接入改造内容

### 4.1 顶层构建（外部目录可配置）

在 `Makefile` 中新增并启用：

1. `HARDFLOAT_DIR ?= hardfloat`
2. `HARDFLOAT_SRC := $(wildcard $(HARDFLOAT_DIR)/*.v)`
3. 当未找到 `.v` 源时直接报错。
4. 将 `VERILATOR_CFG` 中 `-Ihardfloat` 改为 `-I$(HARDFLOAT_DIR)`。
5. 将 `SRC_FILES` 中写死的 HardFloat 文件列表改为 `$(HARDFLOAT_SRC)`。

使用方式：

```bash
make soomrv
make soomrv HARDFLOAT_DIR=/abs/path/to/hardfloat
```

### 4.2 FPU include 路径去硬编码

修改以下文件首行 include：

1. `src/FPU.sv`
2. `src/FMul.sv`
3. `src/FDiv.sv`

从：

```systemverilog
`include "../hardfloat/HardFloat_consts.vi"
```

改为：

```systemverilog
`include "HardFloat_consts.vi"
```

配合 `-I$(HARDFLOAT_DIR)` 实现外部路径可切换。

## 5. test_programs/dev 补充测试

新增/更新内容：

1. 新增 `test_programs/dev/hardfloat_ext_tb.sv`
   - 直接实例化 HardFloat 关键模块并做基础断言：
   - `addRecFN`、`mulRecFN`、`iNToRecFN`、`recFNToIN`、`compareRecFN`、`divSqrtRecFN_small`
2. 更新 `test_programs/dev/Makefile`
   - 新增 `HARDFLOAT_DIR`、`HARDFLOAT_SRCS`
   - 新增 `build-hardfloat` / `run-hardfloat` 目标
3. 更新 `test_programs/dev/README.md`
   - 增加运行说明与外部目录参数示例

执行命令：

```bash
make -C test_programs/dev run-hardfloat
make -C test_programs/dev run-hardfloat HARDFLOAT_DIR=/abs/path/to/hardfloat
```

## 6. 执行过程记录

1. 先阅读 `README.md`、`docs/`、`Makefile`、`src/FPU.sv`、`src/FMul.sv`、`src/FDiv.sv`，确认当前 HardFloat 接入方式。
2. 做全量构建链路检查：`make clean && make soomrv`，确认现有链路可编译。
3. 尝试直接运行浮点程序 `./obj_dir/VTop test_programs/float_flags.s`，环境缺少 `riscv32-unknown-elf-as`，因此改为在 `test_programs/dev` 增加不依赖该工具链的 Verilator 级 smoke test。
4. 完成外部 HardFloat 可配置接入改造与 `test_programs/dev` 测试补充。
5. 根据用户最新指示，最终验证步骤由用户自行执行，本记录不重复触发验证命令。

