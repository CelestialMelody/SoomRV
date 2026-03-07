# Linux 启动失败对比分析（`test_programs/linux` vs `test_programs/linux.bak`）

## 1. 问题背景

两份运行日志：

- `tmp/output.4.txt`：运行 `test_programs/linux/linux_image.elf`，启动后在 VFS 阶段 panic。
- `tmp/output.5.txt`：运行 `test_programs/linux.bak/linux_image.elf`，可以进入 shell，且 `ls` 能看到 `extra/root` 的内容。

目标是判断：

1. 问题是否来自 Linux 构建。
2. 是否与 Issue #55（Buildroot 升级与配置迁移）相关。

---

## 2. 关键现象对比

### 2.1 失败镜像（`output.4`）

日志末尾出现：

- `/dev/root: Can't open blockdev`
- `VFS: Cannot open root device "" or unknown-block(0,0): error -6`
- `Kernel panic - not syncing: VFS: Unable to mount root fs on unknown-block(0,0)`

这说明内核没有拿到可用根文件系统：

- 既没有有效的 `root=` 块设备可挂载。
- 也没有成功使用内置 initramfs 启动。

### 2.2 成功镜像（`output.5`）

日志中出现：

- `Run /init as init process`
- `Welcome to SoomRV Buildroot`

说明成功镜像具备可用根文件系统（通常是内置 initramfs 路径）。

---

## 3. 分析过程（按排查顺序）

### 3.1 先排除启动参数差异

检查两个 DTS：

- `test_programs/linux/device_tree.dts:10`
- `test_programs/linux.bak/device_tree.dts:10`

两者 `bootargs` 都是：

- `earlycon=uart8250,mmio,0x10000000,1000000 console=ttyS0`

结论：不是 DTS 启动参数差异导致。

### 3.2 对比构建流程

发现 `test_programs/linux/Makefile` 与 `test_programs/linux.bak/Makefile` 的核心区别：

- `linux.bak`：直接使用仓库里的完整 `buildroot.config` 生成 Buildroot `.config`。
- `linux`：改成 `qemu_riscv32_virt_defconfig + soomrv_br2_overrides.config`。

这意味着新流程高度依赖 overlay 的正确性和 Buildroot 新版本对配置项语义的兼容性。

### 3.3 对比内核/Buildroot 配置文本

检查到：

- `test_programs/linux/kernel.config` 和 `test_programs/linux.bak/kernel.config` 中都包含：
  - `CONFIG_BLK_DEV_INITRD=y`
  - `CONFIG_INITRAMFS_SOURCE="${BR_BINARIES_DIR}/rootfs.cpio"`
- `soomrv_br2_overrides.config` 中也有：
  - `BR2_TARGET_ROOTFS_CPIO=y`
  - `BR2_TARGET_ROOTFS_INITRAMFS=y`

注意：配置文件“看起来一致”不代表“构建产物一定一致”，因为真实生效的是构建目录中的最终 `.config` 与最终产物。

### 3.4 结合 Issue #55 进行归因

Issue #55 中 maintainer 的结论要点是：

- 升级 Buildroot 后，不能直接依赖默认 QEMU defconfig；
- 需要自行迁移旧配置（`menuconfig` 或按 diff 手工迁移）；
- 否则可能触发 Linux/平台不匹配问题。

这与当前现象吻合：新流程虽然能产出 `linux_image.elf`，但运行时缺少可用 rootfs，最终落到 `unknown-block(0,0)`。

---

## 4. 结论

1. 问题更像是 Linux 镜像构建/打包链路问题，不是 CPU 执行主路径问题。
2. 根因方向是“Buildroot 升级后配置迁移不完整或生效链路异常”，导致内核未正确拿到可用 initramfs/rootfs。
3. 与 Issue #55 提到的风险高度相关。

---

## 5. 建议的验证与修复步骤

下面命令用于：

- 重新全量构建，避免旧缓存干扰；
- 验证最终生效配置是否仍包含 initramfs 关键项；
- 验证产物中是否真的生成了 `rootfs.cpio*`；
- 再次启动并抓日志判断是否修复。

### 5.1 重新生成 overlay（可选但建议）

```bash
cd /home/zoomin/codes/RISCV/SoomRV/test_programs/linux/scripts
python3 merge_br2_config.py extract -i ../buildroot.config -o ../soomrv_br2_overrides.config
```

### 5.2 全量重建 linux 镜像

```bash
cd /home/zoomin/codes/RISCV/SoomRV/test_programs/linux
make clean
make -j"$(nproc)" 2>&1 | tee /tmp/soomrv-linux-build.log
```

### 5.3 检查 Buildroot 最终配置是否启用 initramfs

```bash
cd /home/zoomin/codes/RISCV/SoomRV/test_programs/linux
grep -n "BR2_TARGET_ROOTFS_INITRAMFS" buildroot/.config
grep -n "BR2_TARGET_ROOTFS_CPIO" buildroot/.config
```

### 5.4 检查内核最终配置是否仍指向 rootfs.cpio

```bash
cd /home/zoomin/codes/RISCV/SoomRV/test_programs/linux
grep -R -n "CONFIG_INITRAMFS_SOURCE" buildroot/output/build/linux-*/.config
```

### 5.5 检查实际产物是否有 rootfs 文件

```bash
cd /home/zoomin/codes/RISCV/SoomRV/test_programs/linux
ls -lh buildroot/output/images | grep -E "rootfs|Image|fw_jump|fw_payload"
```

### 5.6 运行仿真并记录启动日志

```bash
cd /home/zoomin/codes/RISCV/SoomRV
./obj_dir/VTop --device-tree=test_programs/linux/device_tree.dtb test_programs/linux/linux_image.elf | tee /tmp/soomrv-linux-boot.log
```

### 5.7 快速判断是否修复

```bash
rg -n "Run /init as init process|Welcome to SoomRV Buildroot|Cannot open root device|Kernel panic" /tmp/soomrv-linux-boot.log
```

如果看到 `Run /init as init process`，说明 rootfs 路径恢复；如果仍是 `Cannot open root device`，继续对比 `buildroot/.config` 与 `buildroot.config` 的 initramfs 相关项。

---

## 6. 补充排查记录（Buildroot 2026.02）

### 6.1 新问题现象

升级到 `BUILDROOT_VERSION=2026.02` 后，原先的 `host-m4` 失败不再出现，但构建在 OpenSBI 下载阶段失败：

- `ERROR: No hash found for opensbi-4f1c...-git4.tar.gz`

对应日志片段见：`tmp/soomrv-linux-build-2026.02.log`。

### 6.2 根因

Buildroot 最终配置中启用了强制 hash 校验，而 OpenSBI 使用的是自定义 Git 源：

- `BR2_DOWNLOAD_FORCE_CHECK_HASHES=y`
- `BR2_TARGET_OPENSBI_CUSTOM_GIT=y`
- `BR2_TARGET_OPENSBI_CUSTOM_REPO_VERSION="4f1c..."`

在这种组合下，Buildroot 会要求生成 tarball 具备对应 hash 条目；未提供时直接报错并停止。

### 6.3 已做修复

为兼容自定义 OpenSBI Git 源，在 overlay 中显式关闭强制 hash 检查，并保证后续自动提取不会丢失该选项：

- 修改 `test_programs/linux/soomrv_br2_overrides.config`：
  - `# BR2_DOWNLOAD_FORCE_CHECK_HASHES is not set`
- 修改 `test_programs/linux/scripts/merge_br2_config.py`：
  - 将 `BR2_DOWNLOAD_FORCE_CHECK_HASHES` 纳入 `SOOMRV_OVERRIDE_PREFIXES`

### 6.4 生效验证

重新生成 `buildroot/.config` 后确认：

- `buildroot/.config:358` 为 `# BR2_DOWNLOAD_FORCE_CHECK_HASHES is not set`
- OpenSBI 自定义源配置仍保留：
  - `BR2_TARGET_OPENSBI_CUSTOM_GIT=y`
  - `BR2_TARGET_OPENSBI_CUSTOM_REPO_VERSION="4f1c..."`

### 6.5 当前状态说明

最新日志显示构建已继续推进（`host-m4`、`host-libtool`、`host-autoconf` 阶段均在继续），
`install-info: No such file or directory for .../libtool.info` 在该段日志中未导致 make 终止，属于非致命提示。

建议继续完整跑完构建，并最终检查：

```bash
cd /home/zoomin/codes/RISCV/SoomRV/test_programs/linux
make BUILDROOT_VERSION=2026.02 -j"$(nproc)" 2>&1 | tee ../../tmp/soomrv-linux-build-2026.02.log
```

构建结束后再执行：

```bash
cd /home/zoomin/codes/RISCV/SoomRV/test_programs/linux
ls -lh buildroot/output/images | grep -E "Image|fw_jump|rootfs|cpio"
```

若 `Image` 与 `fw_jump.bin` 都存在，再进行 SoomRV 启动验证。

---

## 7. 最新进展记录（基于 `tmp/soomrv-linux-build-2026.02.log`）

### 7.1 OpenSBI hash 报错已解除

最新日志中，OpenSBI 流程已从 Download 继续走到：

- `Extracting`
- `Patching`
- `Configuring`
- `Building`
- `Installing to staging directory`
- `Installing to images directory`

并且成功生成并安装了：

- `fw_dynamic.bin/.elf`
- `fw_jump.bin/.elf`
- `fw_payload.bin/.elf`

说明此前的 `No hash found for opensbi-...` 问题在当前配置下已不再阻塞构建。

### 7.2 目前构建已推进到 Linux 内核阶段

日志显示已经进入：

- `linux 6.19.5 Extracting`
- `linux 6.19.5 Patching`
- `linux 6.19.5 Configuring`
- `linux 6.19.5 Building`

这代表 Buildroot 主链路已跨过 host 工具和 OpenSBI 阶段，正在进行内核编译。

### 7.3 当前可见 warning 说明

目前看到的典型信息包括：

- `refname ... is ambiguous`（git 提示）
- `grep: 警告：stray \ before -`
- `.config` 中个别符号值警告（如 `BASE_SMALL`、`BOOTPARAM_HUNG_TASK_PANIC`）

从当前日志上下文看，它们尚未导致 make 退出，属于非致命警告；需以最终是否出现 `make: *** ... 错误` 为准。

### 7.4 下一步检查点

待构建结束后，优先确认以下文件是否存在：

```bash
cd /home/zoomin/codes/RISCV/SoomRV/test_programs/linux
ls -lh buildroot/output/images | grep -E "Image|fw_jump|rootfs|cpio"
```

若 `Image`、`fw_jump.bin`、`rootfs.cpio*` 齐全，再重新打包并运行 `linux_image.elf` 做启动验证。

---

## 8. 当前生效配置说明（用于现状确认）

以下内容基于当前 `test_programs/linux/buildroot/.config` 的实际生效结果，而不是仅看源配置文件。

### 8.1 架构与工具链

- `BR2_ARCH="riscv32"`
- `BR2_GCC_TARGET_ABI="ilp32"`
- `BR2_GCC_VERSION="14.3.0"`

这表示当前是 RV32 用户态 ABI（`ilp32`）+ Buildroot 工具链 GCC 14.3.0。

### 8.2 内核与配置来源

- `BR2_LINUX_KERNEL_VERSION="6.19.5"`
- `BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG=y`
- `BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE="kernel.config"`

这表示当前 Linux 内核版本固定为 6.19.5，且使用仓库中的 `kernel.config`，不是完全跟随 defconfig 默认值。

### 8.3 RootFS / initramfs 路径

- `BR2_TARGET_ROOTFS_CPIO=y`
- `BR2_TARGET_ROOTFS_INITRAMFS=y`

这表示 Buildroot 会生成 `rootfs.cpio*`，并走内核内置 initramfs 路线。若该链路被破坏，通常会在启动时出现 `unknown-block(0,0)` 一类错误。

### 8.4 OpenSBI 配置（当前）

- `BR2_TARGET_OPENSBI_CUSTOM_GIT=y`
- `BR2_TARGET_OPENSBI_CUSTOM_REPO_URL="https://github.com/mathis-s/opensbi"`
- `BR2_TARGET_OPENSBI_CUSTOM_REPO_VERSION="4f1c9865b83d874dd657630b08c6ef747ef41265"`
- `BR2_TARGET_OPENSBI_VERSION="4f1c9865b83d874dd657630b08c6ef747ef41265"`
- `BR2_TARGET_OPENSBI_PLAT="template"`

这表示 OpenSBI 当前固定在 `mathis-s/opensbi` 的指定 commit，而不是追踪上游分支头。

### 8.5 下载校验策略

- `# BR2_DOWNLOAD_FORCE_CHECK_HASHES is not set`

这是为了兼容自定义 Git 源（尤其是 OpenSBI 的自定义 commit tarball），避免再次触发 `No hash found for ...` 的阻塞错误。

---

## 9. OpenSBI 是否必须使用 `mathis-s/opensbi`

结论：不是“必须”，但当前工程配置与 SoomRV 平台参数是按该 fork 对齐过的，直接切官方仓库存在兼容风险，需要做一次可回滚验证。

### 9.1 为什么当前会用 fork

从提供的 compare 页面（`riscv-software-src/opensbi` vs `mathis-s/opensbi`）可以看到该 fork 相比上游有 SoomRV 相关改动，至少包含：

- `platform/template/platform.c`：PLIC/CLINT/UART 地址、hart 数量、时钟频率等平台参数改动。
- `platform/template/objects.mk`：`FW_DYNAMIC/FW_JUMP/FW_PAYLOAD` 相关构建与地址参数调整。
- `Makefile`：默认 `FW_OPTIONS`、`PLATFORM_RISCV_ISA` 等构建参数调整。

这些改动与 SoomRV 的内存映射和启动链路直接相关，因此当前使用 fork 是合理的“已知可工作路径”。

### 9.2 能否切回官方仓库

可以尝试，但建议按“最小变更、可回滚”的方式验证：

1. 只改 OpenSBI 仓库地址与版本，不同时改其他配置。
2. 先通过构建，再验证 `fw_jump` 与 Linux 启动日志。
3. 若出现早期卡死、SBI 初始化异常、串口无输出或 rootfs 路径异常，再回滚到 fork。

### 9.3 最小切换实验步骤（建议）

先备份当前 overlay：

```bash
cd /home/zoomin/codes/RISCV/SoomRV/test_programs/linux
cp soomrv_br2_overrides.config soomrv_br2_overrides.config.bak.opensbi
```

将 OpenSBI URL 改为官方（版本先保留可比对 commit，或改为官方可用 tag/commit）：

```bash
cd /home/zoomin/codes/RISCV/SoomRV/test_programs/linux
sed -i 's#BR2_TARGET_OPENSBI_CUSTOM_REPO_URL="https://github.com/mathis-s/opensbi"#BR2_TARGET_OPENSBI_CUSTOM_REPO_URL="https://github.com/riscv-software-src/opensbi"#' soomrv_br2_overrides.config
```

重建并检查产物：

```bash
cd /home/zoomin/codes/RISCV/SoomRV/test_programs/linux
make clean
make BUILDROOT_VERSION=2026.02 -j"$(nproc)" 2>&1 | tee ../../tmp/soomrv-linux-build-opensbi-upstream.log
ls -lh buildroot/output/images | grep -E "fw_jump|fw_payload|Image|rootfs|cpio"
```

若需要回滚：

```bash
cd /home/zoomin/codes/RISCV/SoomRV/test_programs/linux
mv -f soomrv_br2_overrides.config.bak.opensbi soomrv_br2_overrides.config
```

### 9.4 工程建议

如果后续验证显示官方 OpenSBI 可稳定启动，建议把 fork 中必要改动整理为可维护方案（例如 SoomRV 独立平台 patch 或独立补丁集），减少长期依赖个人 fork 的维护风险。

---

## 10. 官方 OpenSBI 试验分支配置与验证脚本

本节记录本次实际新增文件、创建过程、脚本逻辑和预期结果，便于后续复现与交接。

### 10.1 新增文件

- `test_programs/linux/soomrv_br2_overrides.opensbi_upstream.config`
- `test_programs/linux/scripts/validate_opensbi_upstream.sh`

### 10.2 创建思路

采用“最小侵入 + 可回滚”策略：

1. 不修改默认 `soomrv_br2_overrides.config`，避免影响当前稳定路径。
2. 利用 `test_programs/linux/Makefile` 已支持的 `SOOMRV_OVERLAY` 变量，切换到试验 overlay。
3. 将“切换配置、构建、验证”固化成脚本，减少手工操作偏差。

### 10.3 试验 overlay 的关键内容

`soomrv_br2_overrides.opensbi_upstream.config` 与现有 SoomRV 配置保持一致，只对 OpenSBI 源做试验性替换：

- `BR2_TARGET_OPENSBI_CUSTOM_REPO_URL="https://github.com/riscv-software-src/opensbi"`
- `BR2_TARGET_OPENSBI_CUSTOM_REPO_VERSION="master"`
- `BR2_TARGET_OPENSBI_VERSION="master"`

同时保留：

- `BR2_TARGET_OPENSBI_PLAT="template"`（避免同时改平台参数）
- `# BR2_DOWNLOAD_FORCE_CHECK_HASHES is not set`（避免自定义 Git 源触发 hash 阻塞）

### 10.4 验证脚本流程说明

`scripts/validate_opensbi_upstream.sh` 分 5 步执行：

1. 构建：可选 `make clean`，再执行

- `make SOOMRV_OVERLAY=soomrv_br2_overrides.opensbi_upstream.config BUILDROOT_VERSION=<ver> -j$(nproc)`
- 全量日志输出到 `tmp/soomrv-linux-opensbi-upstream-<timestamp>.log`

2. 生效配置校验：检查 `buildroot/.config` 中 OpenSBI URL/版本/平台是否按试验 overlay 生效。
3. 产物校验：检查 `fw_jump.bin`、`fw_payload.bin`、`fw_dynamic.bin`、`Image`、`rootfs.cpio`、`linux_image.elf`。
4. 日志里程碑校验：确认 OpenSBI 至少经历 `Downloading`、`Building`、`Installing to images directory`。
5. 汇总：全部通过时打印 PASS 与日志路径。

### 10.5 执行方式

默认执行（Buildroot 2026.02，含 clean）：

```bash
cd /home/zoomin/codes/RISCV/SoomRV/test_programs/linux
./scripts/validate_opensbi_upstream.sh
```

指定 Buildroot 版本：

```bash
cd /home/zoomin/codes/RISCV/SoomRV/test_programs/linux
./scripts/validate_opensbi_upstream.sh --buildroot-version 2026.02
```

跳过 clean（加速二次试验）：

```bash
cd /home/zoomin/codes/RISCV/SoomRV/test_programs/linux
./scripts/validate_opensbi_upstream.sh --skip-clean
```

### 10.6 预期结果与判定标准

通过判定：

- 脚本末尾出现 `PASS: upstream OpenSBI trial build completed`
- 日志中有 OpenSBI 关键里程碑
- 产物目录与 `linux_image.elf` 均存在

失败判定：

- 任一配置项未生效、产物缺失、或 OpenSBI 里程碑缺失，脚本会直接 `exit 1` 并打印失败点。

注意：脚本当前验证的是“构建链路可行性”。是否“运行可启动并进入 `/init`”仍需追加仿真启动验证（可在后续扩展脚本接入 `VTop` 自动检查）。
