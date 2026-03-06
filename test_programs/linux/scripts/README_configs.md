# test_programs/linux 配置文件来源说明

## 三个 config 文件是怎么得到的

| 文件 | 来源说明 |
|------|----------|
| **buildroot.config** | 来自 Buildroot 的**完整 .config**：在 Buildroot 源码目录执行 `make menuconfig` 或 `make <defconfig>` 后，把生成的 `.config` 复制出来并重命名。本仓库中的版本基于 **Buildroot 2023.05-rc2**，并针对 SoomRV 做了配置（如 ilp32 ABI、无浮点扩展、自定义 kernel/busybox 路径、自定义 OpenSBI 等）。 |
| **kernel.config** | Linux 内核的**完整 .config**：由 Buildroot 在构建时根据 `BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG` + `BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE` 使用；若未提供则用 defconfig 生成。本仓库中的版本是**用当时 Buildroot 选定的内核版本 (如 6.3.4) 构建后导出的配置**，可通过 `make linux-menuconfig` 在 Buildroot 里改内核选项后，从 `buildroot/output/build/linux-*/`.config 复制出来。 |
| **busybox.config** | BusyBox 的**完整 .config**：由 Buildroot 根据 `BR2_PACKAGE_BUSYBOX_CONFIG` 使用。通常来自 Buildroot 默认 BusyBox 配置或 `make busybox-menuconfig` 后保存，从 `buildroot/output/build/busybox-*/.config` 复制得到。 |

“Automatically generated file; DO NOT EDIT.” 表示该文件由 Buildroot / kernel / busybox 的配置系统自动生成；人工可编辑，但再次运行 menuconfig 并保存时会覆盖。

---

## qemu_riscv32_virt_defconfig 是什么、有没有“具体配置文件”

- **有**。Buildroot 源码里有一份**最小 defconfig**，路径为：  
  **`configs/qemu_riscv32_virt_defconfig`**  
  在 [Buildroot 仓库](https://github.com/buildroot/buildroot/blob/master/configs/qemu_riscv32_virt_defconfig) 的 `configs/` 下。
- 执行 **`make qemu_riscv32_virt_defconfig`** 时，Buildroot 会：
  1. 把该 defconfig 合并进默认选项，生成**完整 .config**；
  2. 未在 defconfig 里写的选项按 Buildroot 默认值（如 rv32 的 ABI 可能是 ilp32d、带 F 扩展等）。
- defconfig 文件本身**只包含相对默认有改动的选项**，因此很短；完整配置是“defconfig + 默认值”展开后的结果。

---

## 是否需要把 buildroot.config 里的设置加进“配置文件”

- 若当前流程是：**只用 `make qemu_riscv32_virt_defconfig` 生成 .config**，则没有用到仓库里的 `buildroot.config`，生成的是“上游 QEMU rv32 默认”配置。
- 对 **SoomRV** 来说，通常需要与仓库中 `buildroot.config` 一致或至少不冲突的设定，例如：
  - **BR2_GCC_TARGET_ABI="ilp32"**（SoomRV 无 D 扩展时用 ilp32，避免 ilp32d）
  - **关闭 BR2_RISCV_ISA_CUSTOM_RVF**（若 SoomRV 不用 F 扩展）
  - **使用仓库提供的 kernel.config / busybox.config**（BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG + BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE，以及 BR2_PACKAGE_BUSYBOX_CONFIG）
  - 若使用 SoomRV 定制 OpenSBI，还需对应 BR2_TARGET_OPENSBI_* 等选项。
- **推荐做法**：在 `make qemu_riscv32_virt_defconfig` 之后，**把“需要与 SoomRV 一致”的选项以 overlay 形式追加**到 .config，再执行 `make olddefconfig` 修正依赖。本目录下 **`scripts/merge_br2_config.py`** 用于从仓库的 `buildroot.config` 中提取这些关键选项并生成 overlay 片段（默认输出为 **`soomrv_br2_overrides.config`**）。Makefile 已支持：若该文件存在，生成 .config 时会自动追加并执行 `make olddefconfig`。
- **重新生成 overlay**（例如修改过 buildroot.config 后）：
  ```bash
  cd test_programs/linux/scripts && python3 merge_br2_config.py extract -i ../buildroot.config -o ../soomrv_br2_overrides.config
  ```

---

## device_tree.dts 的生成（简要）

- **device_tree.dts** 一般**不是**由 Buildroot 的 defconfig 直接生成，而是：
  - 由**板级/SoC 的 dts 描述**（如 Buildroot 里 `board/` 下或内核 `arch/riscv/boot/dts/` 下）编译得到；
  - 或由 SoomRV 仿真/硬件描述里自带的 dts 源文件编译。
- 使用 `device_tree.dtb` 时，需保证其与当前内核、内存布局、SoomRV 外设一致；若只换 Buildroot 配置而不改板级，通常沿用现有 dts 即可。
