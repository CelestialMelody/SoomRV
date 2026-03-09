# SoomRV Issue #55

## 一、要点与根因

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

## 二、已做的修改（COSIM TINFO 修复）

在 **src/CSR.sv** 中：

1. **枚举**：增加 `CSR_tinfo=12'h7A4`（与 Spike 的 CSR_TINFO 一致）。
2. **读**：在“只读且恒为 0”的 CSR 列表中加入 `CSR_tinfo`，与 tselect/tdata1/tdata2/tdata3 一样 `rdata = 0`。
3. **写**：未单独处理，仍走 default → `invalidCSR = 1`，写 TINFO 会非法指令，符合只读 CSR 语义。

这样，Linux 读 TINFO 时 RTL 与 Spike 都返回 0 且都不 trap，COSIM 不再因 TINFO 产生 x30 或 PC 不一致。若你之前为 TINFO 在 Simif 里做过临时 workaround（如强制写 x30、忽略 minstret），可以撤掉，直接开 COSIM 重测。

---

## 三、后续可做的工作建议

1. **COSIM**

   - 用当前仓库重新 `make soomrv`（若启用 COSIM 需在 Makefile 中加 `-DCOSIM`，并去掉或保留 `-DNOCOVERAGE` 按需），然后跑 Linux：`./obj_dir/VTop --perfc --device-tree=test_programs/linux/device_tree.dtb test_programs/linux/linux_image.elf`
   - 若仍有其它 CSR 或指令导致 COSIM 报错，可同样采用“在 RTL 中实现与 Spike 一致”的方式，必要时在 `Simif.cpp` 的 `is_pass_thru_inst()` 里对已知差异做只读/非关键 CSR 的 pass-thru（慎用，避免掩盖 RTL 错误）。
2. **Buildroot / 配置**

   - 若 2025.11 的 host 包仍失败：可尝试固定到 2024.02 或 2024.08 等已知在 GCC 15 下能过的版本；或查 Buildroot 邮件列表/issue 里对 `pidfd_*`、host-util-linux 的讨论。
   - `buildroot.config` / `kernel.config` / `busybox.config`：通常由 `make savedefconfig` 或 Buildroot 的 `make menuconfig` 后保存得到；`device_tree.dts` 多为 SoC/板级描述，可由 Buildroot 的 board 配置或内核 dts 生成，与 defconfig 配套。

---

## 四、与 `instret_overflow` / 浮点 Zfinx 失配的关系

`Issue55` 的 TINFO 修复经验对后续 COSIM 问题是**方法论上可复用**的：优先让 RTL 与 Spike 语义对齐，而不是在 Simif 里做寄存器硬改值。

但就“可直接复用补丁”而言，`instret_overflow` 与 `float*.s` 属于不同路径：

- `instret_overflow` 主要涉及 `minstret` 计数与提交标注口径；
- `float*.s` 主要涉及 Spike ISA（`zfinx`）与 `mstatus/sstatus` 的 FS/SD 语义。

对应分析与修复记录已单独整理为：

- [COSIM一致性补充：instret_overflow与Zfinx浮点](COSIM一致性补充：instret_overflow与Zfinx浮点.md)
