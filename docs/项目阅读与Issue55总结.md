# SoomRV 项目阅读与 Issue #55 总结

## 一、项目整体理解

### 1. 项目是什么

- **SoomRV**：基于标签的 **RV32IMAC+ 超标量乱序** RISC-V 核，每周期最多 4 条指令，可启动 Linux。
- 文档与源码重点在 **src/**（RTL）和 **docs/**（架构与问题记录）。

### 2. 核心架构（src + docs）

- **前端**：IFetch（16B 取指、TAGE 方向预测、BTB、ReturnStack）、PreDecode、InstrDecoder。
- **重命名**：Rename + RenameTable，分配 `sqN`（序列号）和 `tagDst`（物理标签）；部分指令在重命名阶段消除（如 NOP、小立即数）。
- **调度与执行**：IssueQueue → Load（读寄存器/转发）→ 执行单元（IntALU、AGU、FPU、StoreData 等）。
- **内存**：LoadBuffer、StoreQueue、StoreQueueBackend、LSU、BypassLSU（MMIO）；VIPT I/D Cache。
- **提交与恢复**：ROB 顺序提交、异常/错误预测时通过全局 branch 信号 + ROB 重放恢复重命名状态。
- 数据流：`IF_Instr → PD_Instr → D_UOp → R_UOp → IS_UOp → EX_UOp → AGU/LD/SQ/ST_UOp`，定义在 `Include.sv`。

### 3. 仿真与 Linux（sim/ + test_programs/linux）

- **sim/**：Verilator  testbench（`Top_tb.cpp`）、**COSIM**（`Simif.cpp`/`Simif.hpp` 与 Spike 逐指令比对）、Inst/Registers 等。
- **COSIM**：仅在编译时定义 `COSIM` 时启用；每提交一条指令调用 `cosim_instr(inst)`，比对 PC、指令、GPR、minstret 等，不一致则报 ERROR 1–6。
- **Linux 镜像**：`test_programs/linux/` 用 Buildroot 构建；当前 Makefile 使用 `BUILDROOT_VERSION=2025.11` 和 `qemu_riscv32_virt_defconfig`，并依赖 `kernel.config` / `busybox.config`。

---

## 二、Issue #55 要点与根因

### 1. Buildroot / Linux 构建

- **问题 1**：Buildroot 2023.05-rc2 在 Arch（GCC 15）上编译 host-m4 时，`_GL_ATTRIBUTE_NODISCARD` 与 GCC 15 不兼容。
- **问题 2**：升级到 2025.11 后，host-util-linux 编译报错 `pidfd_open` / `pidfd_send_signal` 隐式声明（与 host 环境/glibc 有关）。
- **当前状态**：你已改为用 `qemu_riscv32_virt_defconfig` 生成 `.config`；若 2025.11 的 host 工具链仍有问题，可考虑固定使用较新且已知可用的 Buildroot 版本，或禁用/替换有问题的 host 包。

### 2. COSIM 不匹配（核心）

- **现象**：开启 COSIM 时，首错为 `mismatch x30`，指令为 `csrr s0, 0x7a4`（即 **CSR TINFO**）。
- **根因**：
  - **Spike**：在 `trigger_count == 0` 时把 TINFO 实现为只读常量 0（`const_csr_t(..., 0)`），读 TINFO 不 trap。
  - **SoomRV RTL**：此前未实现 0x7A4，落入 `default: invalidCSR = 1`，读 TINFO 会触发**非法指令异常**，PC 跳到 mtvec，内核 trap 处理可能把 4（如 trigger 类型数）写入 x30。
  - 因此同一句 `csrr s0, tinfo` 后：RTL 在 trap 里、x30=4；Spike 在下一句、x30=0 → COSIM 报 ERROR 4（GPR 不一致）。你强制把 x30 同步到 Spike 后，下一拍 RTL 的提交 PC 是 trap 入口、Spike 的 PC 是下一条，又触发 ERROR 1（PC 不一致）。

结论：**要让 COSIM 一致，必须在 RTL 里实现 TINFO，行为与 Spike 一致（只读、返回 0），这样 RTL 也不 trap，PC 与 GPR 自然对齐。**

---

## 三、已做的修改（COSIM TINFO 修复）

在 **src/CSR.sv** 中：

1. **枚举**：增加 `CSR_tinfo=12'h7A4`（与 Spike 的 CSR_TINFO 一致）。
2. **读**：在“只读且恒为 0”的 CSR 列表中加入 `CSR_tinfo`，与 tselect/tdata1/tdata2/tdata3 一样 `rdata = 0`。
3. **写**：未单独处理，仍走 default → `invalidCSR = 1`，写 TINFO 会非法指令，符合只读 CSR 语义。

这样，Linux 读 TINFO 时 RTL 与 Spike 都返回 0 且都不 trap，COSIM 不再因 TINFO 产生 x30 或 PC 不一致。若你之前为 TINFO 在 Simif 里做过临时 workaround（如强制写 x30、忽略 minstret），可以撤掉，直接开 COSIM 重测。

---

## 四、后续可做的工作建议

1. **COSIM**
   - 用当前仓库重新 `make soomrv`（若启用 COSIM 需在 Makefile 中加 `-DCOSIM`，并去掉或保留 `-DNOCOVERAGE` 按需），然后跑 Linux：  
     `./obj_dir/VTop --perfc --device-tree=test_programs/linux/device_tree.dtb test_programs/linux/linux_image.elf`
   - 若仍有其它 CSR 或指令导致 COSIM 报错，可同样采用“在 RTL 中实现与 Spike 一致”的方式，必要时在 `Simif.cpp` 的 `is_pass_thru_inst()` 里对已知差异做只读/非关键 CSR 的 pass-thru（慎用，避免掩盖 RTL 错误）。

2. **Buildroot / 配置**
   - 若 2025.11 的 host 包仍失败：可尝试固定到 2024.02 或 2024.08 等已知在 GCC 15 下能过的版本；或查 Buildroot 邮件列表/issue 里对 `pidfd_*`、host-util-linux 的讨论。
   - `buildroot.config` / `kernel.config` / `busybox.config`：通常由 `make savedefconfig` 或 Buildroot 的 `make menuconfig` 后保存得到；`device_tree.dts` 多为 SoC/板级描述，可由 Buildroot 的 board 配置或内核 dts 生成，与 defconfig 配套。

3. **文档**
   - 已在 **docs/Problems.md**（及 Problems.en.md）中记录了 Buildroot 与 COSIM 现象；可在该文档或 README 中补一句：**COSIM 下 Linux 需 RTL 实现 TINFO（0x7A4）只读返回 0**，并指向本次 CSR 修改。

---

## 五、关键文件索引

| 用途           | 路径 |
|----------------|------|
| 架构概览（中文） | docs/Overview.zh.md, docs/README.zh.md, docs/architect.zh.md |
| 问题记录       | docs/Problems.md, docs/Problems.en.md |
| COSIM 逻辑     | sim/Simif.cpp（cosim_instr、is_pass_thru_inst）, sim/Simif.hpp |
| 提交时调用 COSIM | sim/Top_tb.cpp（LogCommit） |
| CSR 定义与读   | src/CSR.sv（枚举、读分支、只读零 CSR 列表） |
| 顶层/构建      | Makefile, test_programs/linux/Makefile |

如果你接下来想先验证 COSIM、还是先稳定 Buildroot 构建，可以说明一下，我可以按其中一条线给出更具体的步骤（例如如何加 `-DCOSIM`、如何精简 Buildroot 配置等）。
