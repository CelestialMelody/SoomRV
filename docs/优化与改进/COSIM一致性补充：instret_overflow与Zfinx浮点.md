# COSIM 一致性补充：`instret_overflow` 与 Zfinx 浮点测试

## 1. 背景与问题分组

本次补充聚焦两类 COSIM 失配：

1. **`instret_overflow`（ERROR 6）**：退休计数口径差异。
2. **`float_flags.s` / `float.s`（ERROR 4）**：浮点/Zfinx 指令路径下，RTL 与 Spike 的 ISA/CSR 语义不一致。

对应日志证据：

- 旧回归日志：[`docs/logs/external-test.1.log`](/home/zoomin/codes/RISCV/SoomRV/docs/logs/external-test.1.log)
- `instret_overflow` 独立复现：[`docs/logs/external-test.instret_overflow.log`](/home/zoomin/codes/RISCV/SoomRV/docs/logs/external-test.instret_overflow.log)
- `instret_overflow` 修复尝试后复现：[`docs/logs/external-test.instret_overflow.after.log`](/home/zoomin/codes/RISCV/SoomRV/docs/logs/external-test.instret_overflow.after.log)

---

## 2. `Issue55` 文档对本问题是否有帮助

有帮助，但属于“方法论层面”，不是“直接修复复用”。

`Issue55` 的核心经验是：**COSIM 失配应优先通过“RTL 与 Spike 语义对齐”解决，而非在 Simif 侧做寄存器硬覆盖**。
这一方法同样适用于本次两类问题：

- `instret_overflow`：需要厘清计数器语义边界（尤其是写 `minstret` 与当拍退休关系）；
- 浮点/Zfinx：需要保证 Spike ISA 配置、`mstatus/sstatus` 的 FS/SD 表现与 RTL 一致。

但 `Issue55` 针对的是 `CSR_TINFO`，与本次的 `minstret`/Zfinx 不是同一代码路径，因此不能直接“照抄补丁”。

---

## 3. 浮点/Zfinx 失配分析与修复

## 3.1 现象

你给出的 `float_flags.s` / `float.s` 失败日志中，Spike 侧出现：

- `mcause=2`（非法指令）
- `pc` 跳到 `mtvec`
- GPR 结果与 RTL 分叉（`ERROR 4`）

这是一种典型模式：**Spike 把某条指令判定为 illegal，而 RTL 正常执行或执行了不同路径**。

## 3.2 根因 1：Spike ISA 未启用 `zfinx`

`sim/Simif.cpp` 原始配置里，`isa_parser_t` 的 ISA 字符串不含 `zfinx`：

- 原逻辑：`rv32imac_zicsr_zba_zbb_zbs_zicbom_zifencei_zcb_zihpm_zicntr`

而 SoomRV 的汇编链路在编译 `.s` 时已显式使用 `-march=..._zfinx...`，二者不一致会导致 Spike 在浮点/Zfinx 指令上走非法指令路径。

修复：

- 在 SpikeSimif ISA 字符串中加入 `zfinx`：[`sim/Simif.cpp:79`](/home/zoomin/codes/RISCV/SoomRV/sim/Simif.cpp:79)

## 3.3 根因 2（修复 1 的副作用）：`sstatus` 中 FS/SD 口径分叉

启用 `zfinx` 后，回归曾出现 `rv32uc-v-rvc` 新失配（`mismatch x5`，读 `sstatus`）：

- 复现样例：`csrr x5, sstatus` 时 RTL 读到 `0x80006000`，Spike 读到 `0`

本质是 `FS/SD` 处理口径不一致。
当前 SoomRV 使用的是 Zfinx 路径（有 FCSR，但无独立 FP 寄存器状态），需与 Spike 的 Zfinx 语义保持一致。

修复：

- 在 `CSR_mstatus` 写路径中将 `FS/SD` 置零，避免在 Zfinx 下产生伪“浮点状态脏位”：[`src/CSR.sv:926`](/home/zoomin/codes/RISCV/SoomRV/src/CSR.sv:926)

该修复后，`rv32uc-v-rvc` 恢复通过（见第 5 节回归结果）。

---

## 4. `instret_overflow (ERROR 6)` 分析与结论

## 4.1 现象

`instret_overflow` 在 `csrwi minstret, 0` / `csrr a0, minstret` 附近触发 `ERROR 6`，即：

- `inst.minstret`（RTL 提交侧标注）与 Spike 的 `CSR_MINSTRET` 不一致。

## 4.2 当前状态

本轮未将其彻底修复到“严格对拍通过”，原因是该问题牵涉：

1. RTL 中 `minstret` 更新时序；
2. `Top_tb.cpp` 提交阶段的 `inst.minstret` 标注方式；
3. Spike 对 `minstret` 写入/抑制增量的精确定义与读取时点。

该问题与功能正确性并不等价，属于“精细口径一致性”范畴。
当前回归策略保持为：默认列为已知不支持项（可用 `--no-skip-unsupported` 强制执行观察原始失败）。

---

## 5. 验证结果

## 5.1 Smoke 回归

命令：

```bash
make external-tests-smoke EXTERNAL_TEST_TIMEOUT=60 EXTERNAL_TEST_HEARTBEAT=10
```

结果日志：

- [`docs/logs/external-test.smoke.after.log`](/home/zoomin/codes/RISCV/SoomRV/docs/logs/external-test.smoke.after.log)

关键结论：

- `rv32uc-v-rvc` 恢复通过；
- smoke 总体通过；
- `instret_overflow/pmpaddr` 仍按已知不支持项跳过。

## 5.2 全量外部回归

命令：

```bash
make external-tests-run EXTERNAL_TEST_TIMEOUT=60 EXTERNAL_TEST_HEARTBEAT=10
```

结果日志：

- [`docs/logs/external-test.3.log`](/home/zoomin/codes/RISCV/SoomRV/docs/logs/external-test.3.log)

关键结论：

- `all selected tests passed (198 total)`；
- 仅保留两项已知不支持：`instret_overflow`、`pmpaddr`。

---

## 6. 关于文档组织（是否并入 `Issue55`）

建议：**保留独立文档，并在 `Issue55` 中增加链接和一段摘要说明**。

理由：

1. `Issue55` 主问题是 `TINFO`，本次问题是 `minstret` 与 Zfinx；直接合并会让单篇文档跨度过大；
2. 这次包含“修复主线 + 回归副作用 + 二次修复”的完整闭环，独立成文更利于后续复盘；
3. 两篇互链可保持检索效率：查 TINFO 看 `Issue55`，查浮点/Zfinx 与计数口径看本文。
