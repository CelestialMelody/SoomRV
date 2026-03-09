# TLB_fixed 改进与对比测试说明

本文说明 4 件事：

1. `TLB_fixed.sv` 相比 `TLB.sv` 改了什么  
2. 改动解决了哪个具体问题  
3. `test_programs/dev` 的对比测试如何实现  
4. 如何判定修复是否生效

---

## 1. 改进点：TLB_fixed 做了什么

## 1.1 原始行为（TLB.sv）

原始版本在 page-walk 返回时，只要 `IN_pw.valid` 且满足 ifetch/dtlb 路径条件，就直接写入 `tlb[idx][assocIdx]`，没有“是否已存在”的检查：

- 入口条件：[`TLB.sv:83`](/home/zoomin/codes/RISCV/SoomRV/src/TLB.sv:83)
- 直接写入条目：[`TLB.sv:90`](/home/zoomin/codes/RISCV/SoomRV/src/TLB.sv:90) 到 [`TLB.sv:103`](/home/zoomin/codes/RISCV/SoomRV/src/TLB.sv:103)

源码里也有注释说明该问题：

- `FIXME: ... might double insert ...`：[`TLB.sv:82`](/home/zoomin/codes/RISCV/SoomRV/src/TLB.sv:82)

## 1.2 fixed 行为（TLB_fixed.sv）

`TLB_fixed.sv` 在同样入口条件下，新增了“查重再插入”逻辑：

- 新增 `already_exists`：[`TLB_fixed.sv:91`](/home/zoomin/codes/RISCV/SoomRV/src/TLB_fixed.sv:91)
- 扫描同一 set 的所有 way：[`TLB_fixed.sv:94`](/home/zoomin/codes/RISCV/SoomRV/src/TLB_fixed.sv:94) 到 [`TLB_fixed.sv:100`](/home/zoomin/codes/RISCV/SoomRV/src/TLB_fixed.sv:100)
- 判定条件：`valid && vpn相等 && isSuper相等`：[`TLB_fixed.sv:95`](/home/zoomin/codes/RISCV/SoomRV/src/TLB_fixed.sv:95) 到 [`TLB_fixed.sv:98`](/home/zoomin/codes/RISCV/SoomRV/src/TLB_fixed.sv:98)
- 仅在 `!already_exists` 时写入：[`TLB_fixed.sv:103`](/home/zoomin/codes/RISCV/SoomRV/src/TLB_fixed.sv:103) 到 [`TLB_fixed.sv:113`](/home/zoomin/codes/RISCV/SoomRV/src/TLB_fixed.sv:113)

## 1.3 这次改动的边界

这次改动是“去重插入”，不是 TLB 替换策略重构。以下行为保持不变：

- `counters[idx]` 的更新机制不变：[`TLB.sv:106`](/home/zoomin/codes/RISCV/SoomRV/src/TLB.sv:106) / [`TLB_fixed.sv:116`](/home/zoomin/codes/RISCV/SoomRV/src/TLB_fixed.sv:116)
- `clear/ignoreCur` 逻辑不变：[`TLB.sv:71`](/home/zoomin/codes/RISCV/SoomRV/src/TLB.sv:71) 到 [`TLB.sv:80`](/home/zoomin/codes/RISCV/SoomRV/src/TLB.sv:80)
- 命中匹配逻辑不变（尤其 superpage 命中比较）：
  [`TLB.sv:42`](/home/zoomin/codes/RISCV/SoomRV/src/TLB.sv:42) 到 [`TLB.sv:46`](/home/zoomin/codes/RISCV/SoomRV/src/TLB.sv:46)

说明：当前 `already_exists` 用的是“完整 `vpn` + `isSuper`”判断，因此它确保“相同 VPN 响应不重复插入”。它并不等价于重新定义 superpage 的唯一键。

---

## 2. 如何在工程里切换 TLB 实现

顶层 `Makefile` 现在支持开关：

- `TLB_IMPL=orig` 使用 `src/TLB.sv`
- `TLB_IMPL=fixed` 使用 `src/TLB_fixed.sv`

关键位置：

- 开关定义：[`Makefile:8`](/home/zoomin/codes/RISCV/SoomRV/Makefile:8) 到 [`Makefile:18`](/home/zoomin/codes/RISCV/SoomRV/Makefile:18)
- 源文件接入点：[`Makefile:99`](/home/zoomin/codes/RISCV/SoomRV/Makefile:99)

命令示例：

```bash
make soomrv TLB_IMPL=orig
make soomrv TLB_IMPL=fixed
```

---

## 3. 对比测试是如何实现的

## 3.1 测试文件

- testbench：[`test_programs/dev/tlb_dup_tb.sv`](/home/zoomin/codes/RISCV/SoomRV/test_programs/dev/tlb_dup_tb.sv)
- 测试 Makefile：[`test_programs/dev/Makefile`](/home/zoomin/codes/RISCV/SoomRV/test_programs/dev/Makefile)

## 3.2 测试思路（核心流程）

`tlb_dup_tb.sv` 构造了“同一 VPN 两次 page-walk 回填”的场景：

1. 复位后第一次 `IN_pw.valid=1`，插入一个条目  
   代码：[`tlb_dup_tb.sv:49`](/home/zoomin/codes/RISCV/SoomRV/test_programs/dev/tlb_dup_tb.sv:49) 到 [`tlb_dup_tb.sv:61`](/home/zoomin/codes/RISCV/SoomRV/test_programs/dev/tlb_dup_tb.sv:61)
2. 发起一次命中请求，推动 set 的替换指针变化  
   代码：[`tlb_dup_tb.sv:63`](/home/zoomin/codes/RISCV/SoomRV/test_programs/dev/tlb_dup_tb.sv:63) 到 [`tlb_dup_tb.sv:67`](/home/zoomin/codes/RISCV/SoomRV/test_programs/dev/tlb_dup_tb.sv:67)
3. 第二次发送同样的 page-walk 结果  
   代码：[`tlb_dup_tb.sv:69`](/home/zoomin/codes/RISCV/SoomRV/test_programs/dev/tlb_dup_tb.sv:69) 到 [`tlb_dup_tb.sv:81`](/home/zoomin/codes/RISCV/SoomRV/test_programs/dev/tlb_dup_tb.sv:81)
4. 统计同一 set/同一 VPN 的有效条目个数 `count`  
   代码：[`tlb_dup_tb.sv:85`](/home/zoomin/codes/RISCV/SoomRV/test_programs/dev/tlb_dup_tb.sv:85) 到 [`tlb_dup_tb.sv:92`](/home/zoomin/codes/RISCV/SoomRV/test_programs/dev/tlb_dup_tb.sv:92)

## 3.3 白盒检查点

测试使用了层次访问 `dut.tlb` 和 `dut.counters` 来直接观察内部状态：

- 条目扫描：[`tlb_dup_tb.sv:87`](/home/zoomin/codes/RISCV/SoomRV/test_programs/dev/tlb_dup_tb.sv:87)
- 计数输出：[`tlb_dup_tb.sv:94`](/home/zoomin/codes/RISCV/SoomRV/test_programs/dev/tlb_dup_tb.sv:94)

这是验证“重复插入”最直接的方式，属于开发测试（不用于综合）。

---

## 4. 如何判断修复前后效果

## 4.1 单次运行判定

testbench 打印两类信息：

- `RESULT count=<N>`：同一 VPN 在该 set 中的匹配条目数
- `RESULT_DUPLICATE=<0|1>`：是否重复（`count > 1`）

判定代码：

- [`tlb_dup_tb.sv:95`](/home/zoomin/codes/RISCV/SoomRV/test_programs/dev/tlb_dup_tb.sv:95) 到 [`tlb_dup_tb.sv:96`](/home/zoomin/codes/RISCV/SoomRV/test_programs/dev/tlb_dup_tb.sv:96)

期望：

- 原始版 `TLB.sv`：`RESULT_DUPLICATE=1`
- 修复版 `TLB_fixed.sv`：`RESULT_DUPLICATE=0`

## 4.2 Makefile 自动对比判定

`test_programs/dev/Makefile` 同时编译并运行 orig/fixed 两个版本，然后解析日志并给出 PASS/FAIL：

- 运行两版：[`dev/Makefile:37`](/home/zoomin/codes/RISCV/SoomRV/test_programs/dev/Makefile:37)
- 提取 `RESULT_DUPLICATE`：[`dev/Makefile:38`](/home/zoomin/codes/RISCV/SoomRV/test_programs/dev/Makefile:38) 到 [`dev/Makefile:39`](/home/zoomin/codes/RISCV/SoomRV/test_programs/dev/Makefile:39)
- 判定条件（orig=1 且 fixed=0）：[`dev/Makefile:46`](/home/zoomin/codes/RISCV/SoomRV/test_programs/dev/Makefile:46) 到 [`dev/Makefile:50`](/home/zoomin/codes/RISCV/SoomRV/test_programs/dev/Makefile:50)

运行命令：

```bash
make -C test_programs/dev compare
```

---

## 5. 建议的验证顺序（实践）

1. 先跑微测试确认修复点有效：  
   `make -C test_programs/dev compare`
2. 再切顶层 TLB 实现做系统回归：  
   `make soomrv TLB_IMPL=orig` / `make soomrv TLB_IMPL=fixed`
3. 对比关键场景（VM/高 miss/并发 load-store）行为与性能计数器。

这样可以把“修复点有效性”与“系统级副作用”分层验证。

---

## 6. 本次编译兼容问题补充（output.3）

## 6.1 失败点变化与原因

`tmp/output.3.txt` 的失败点已从“`riscv-isa-sim` 缺失”转为 `sim/slang/slang.hpp` 中大量 `sc_dt::sc_bv<...>` 解析失败。

关键现象：

- 错误位置集中在：[`sim/slang/slang.hpp:355`](/home/zoomin/codes/RISCV/SoomRV/sim/slang/slang.hpp:355) 等处（`sc_dt` 未识别）
- 头文件包含链路是：[`sim/Registers.hpp:3`](/home/zoomin/codes/RISCV/SoomRV/sim/Registers.hpp:3) 先包含 [`sim/sc_stub.hpp`](/home/zoomin/codes/RISCV/SoomRV/sim/sc_stub.hpp)，再包含 [`sim/slang/slang.hpp:4`](/home/zoomin/codes/RISCV/SoomRV/sim/slang/slang.hpp:4)

根因是命名空间接口不一致：`sc_stub.hpp` 的轻量位向量实现最初只提供了全局 `sc_bv`，而生成头 `slang.hpp` 依赖 `sc_dt::sc_bv` 命名。

补充判断（关于“是否因为重新更新 slang”）：

- 是，高概率相关。`slang.hpp` 由 `slang-reflect` 重新生成后，当前文件中广泛使用 `sc_dt::sc_bv<...>`（如 [`sim/slang/slang.hpp:355`](/home/zoomin/codes/RISCV/SoomRV/sim/slang/slang.hpp:355)）。
- 构建规则会把生成头里的 `#include <systemc.h>` 删除（[`Makefile:165`](/home/zoomin/codes/RISCV/SoomRV/Makefile:165)），因此不会从 SystemC 获得 `sc_dt` 定义。
- 在这种“无 SystemC 头”的构建路径下，必须由本地 stub 补齐 `sc_dt::sc_bv` 兼容接口，否则会出现 `sc_dt` 未声明错误。

## 6.2 最小修复（已采用）

在 [`sim/sc_stub.hpp:156`](/home/zoomin/codes/RISCV/SoomRV/sim/sc_stub.hpp:156) 到 [`sim/sc_stub.hpp:160`](/home/zoomin/codes/RISCV/SoomRV/sim/sc_stub.hpp:160) 增加兼容别名：

- `namespace sc_dt { template <size_t LEN> using sc_bv = ::sc_bv<LEN>; }`

这属于“命名空间兼容层”，不改变既有 `sc_bv` 的位行为与编码逻辑，只补齐 `slang.hpp` 期望的类型名。

为什么不直接改 `slang.hpp`：

- `slang.hpp` 是生成产物（[`Makefile:160`](/home/zoomin/codes/RISCV/SoomRV/Makefile:160) 到 [`Makefile:164`](/home/zoomin/codes/RISCV/SoomRV/Makefile:164)），后续重生成会覆盖手工修改。
- 在 `sc_stub.hpp` 提供兼容别名属于一次性修复，对后续生成版本更稳健。

## 6.3 语法兼容性补充（局部变量声明顺序）

为避免更严格工具链对块内声明顺序的兼容问题，`TLB_fixed` 的局部变量声明统一提前到 `begin` 顶部：

- [`src/TLB_fixed.sv:88`](/home/zoomin/codes/RISCV/SoomRV/src/TLB_fixed.sv:88) 到 [`src/TLB_fixed.sv:90`](/home/zoomin/codes/RISCV/SoomRV/src/TLB_fixed.sv:90)

该调整不改变原有状态机和插入条件语义，只是语法层面的兼容性整理。

## 6.4 可执行修复路径（离线/联网分离）

不依赖网络的本地步骤：

1. 确认 `sc_dt::sc_bv` 兼容别名存在：[`sim/sc_stub.hpp:156`](/home/zoomin/codes/RISCV/SoomRV/sim/sc_stub.hpp:156)
2. 先做本地构建验证：`make soomrv TLB_IMPL=fixed`
3. 再做 TLB 行为对比：`make -C test_programs/dev compare`

仅在依赖缺失时需要网络的步骤：

1. 如果报 `../riscv-isa-sim/libriscv.a` / `libsoftfloat.a` / `libdisasm.a` 缺失，执行：`make setup`
2. `make setup` 会执行 `git submodule update --init --recursive` 并编译 `riscv-isa-sim`：[`Makefile:149`](/home/zoomin/codes/RISCV/SoomRV/Makefile:149) 到 [`Makefile:153`](/home/zoomin/codes/RISCV/SoomRV/Makefile:153)
3. 完成后重试本地步骤 2/3

---

## 7. P0-3：superpage 去重条件增强（`fixed_sp_dedup`）

## 7.1 问题定义

`TLB_fixed.sv` 的重复插入判定是“`vpn全等 + isSuper相等`”，对普通页有效；但 superpage 命中本身使用的是高位键比较。  
这会留下一个窗口：同一 superpage 区域、低位 VPN 不同的两次回填，可能被视为不同条目而重复插入。

## 7.2 实现方式

保持原有 `TLB_fixed.sv` 不动，新增副本 `TLB_fixed_sp_dedup.sv`：

1. 普通页：保持完整 VPN 相等判定。
2. superpage：改为按 superpage 高位键判重（与命中逻辑同构）。

配套开关：

```bash
make soomrv TLB_IMPL=orig
make soomrv TLB_IMPL=fixed
make soomrv TLB_IMPL=fixed_sp_dedup
```

## 7.3 微测试结果

原始去重回归：

```bash
make -C test_programs/dev compare
```

结果：

1. `orig RESULT_DUPLICATE=1`
2. `fixed RESULT_DUPLICATE=0`

superpage 专项回归：

```bash
make -C test_programs/dev compare-super
```

结果：

1. `fixed RESULT_SUPER_DUPLICATE=1`
2. `fixed_sp_dedup RESULT_SUPER_DUPLICATE=0`

说明新增实现确实消除了 superpage 场景的重复插入。

## 7.4 顶层构建验证

按串行流程（`clean -> build`）验证两种 fixed 方案均可构建：

```bash
make clean && make soomrv TLB_IMPL=fixed BRANCH_PRED_IMPL=bt_arb PAGEWALKER_IMPL=pw_arb
make clean && make soomrv TLB_IMPL=fixed_sp_dedup BRANCH_PRED_IMPL=bt_arb PAGEWALKER_IMPL=pw_arb
```

两条命令均通过，表明 `fixed_sp_dedup` 已满足顶层接入条件。
