Hi [@mathis-s](https://github.com/mathis-s) 我正在学习 SoomRV. 目前我遇到了一些关于 Linux 启动与 COSIM 的问题。

**Boost Linux**

make linux 在 Arch Linux 系统上编译 buildroot-2023.05-rc2 时遇到了 host-m4-1.4.19 的编译错误，新版本 GCC（15.2.1）对`_GL_ATTRIBUTE_NODISCARD`属性的处理方式与旧版 m4 代码不兼容

```bash
make[5]: Entering directory '/home/zoomin/codes/RISCV/SoomRV/test_programs/linux.bak/buildroot/output/build/host-m4-1.4.19/lib'

/* ... */
	
  CC       hash-pjw.o
In file included from gl_avltree_oset.h:21,
                 from gl_avltree_oset.c:21:
gl_oset.h:275:1: warning: 'nodiscard' attribute ignored [-Wattributes]
  275 | GL_OSET_INLINE _GL_ATTRIBUTE_NODISCARD int
      | ^~~~~~~~~~~~~~
gl_oset.h:275:40: error: expected identifier or '(' before 'int'
  275 | GL_OSET_INLINE _GL_ATTRIBUTE_NODISCARD int
      |                                        ^~~
In file included from clean-temp-private.h:22,
                 from clean-temp-simple.c:22:
gl_list.h:633:1: warning: 'nodiscard' attribute ignored [-Wattributes]
  633 | GL_LIST_INLINE _GL_ATTRIBUTE_NODISCARD int
      | ^~~~~~~~~~~~~~
gl_list.h:633:40: error: expected identifier or '(' before 'int'
  633 | GL_LIST_INLINE _GL_ATTRIBUTE_NODISCARD int
      |                                        ^~~
gl_list.h:688:1: warning: 'nodiscard' attribute ignored [-Wattributes]
  688 | GL_LIST_INLINE _GL_ATTRIBUTE_NODISCARD gl_list_node_t
      | ^~~~~~~~~~~~~~
gl_list.h:688:40: error: expected identifier or '(' before 'gl_list_node_t'

/* same "error: expected identifier or '(' before 'gl_list_node_t'"*/

make[5]: *** [Makefile:2871: gl_avltree_oset.o] Error 1
make[5]: *** Waiting for unfinished jobs....
In file included from hash.c:27:
hash.h:180:8: warning: 'nodiscard' attribute ignored [-Wattributes]
  180 |        _GL_ATTRIBUTE_NODISCARD;
      |        ^~~~~~~~~~~~~~~~~~~~~~~

/* same "warning: 'nodiscard' attribute ignored [-Wattributes]" */

  633 | GL_LIST_INLINE _GL_ATTRIBUTE_NODISCARD int
      | ^~~~~~~~~~~~~~
gl_list.h:633:40: error: expected identifier or '(' before 'int'
  633 | GL_LIST_INLINE _GL_ATTRIBUTE_NODISCARD int
      |                                        ^~~
gl_list.h:688:1: warning: 'nodiscard' attribute ignored [-Wattributes]
  688 | GL_LIST_INLINE _GL_ATTRIBUTE_NODISCARD gl_list_node_t
      | ^~~~~~~~~~~~~~
 
/* same "GL_LIST_INLINE _GL_ATTRIBUTE_NODISCARD gl_list_node_t" */

In file included from clean-temp.c:49:
gl_xlist.h: In function 'gl_list_node_set_value':
gl_xlist.h:104:16: error: implicit declaration of function 'gl_list_node_nx_set_value'; did you mean 'gl_list_node_set_value'? [-Wimplicit-function-declaration]
  104 |   int result = gl_list_node_nx_set_value (list, node, elt);
      |                ^~~~~~~~~~~~~~~~~~~~~~~~~
      |                gl_list_node_set_value

/* glist related errors */

  185 |   gl_list_node_t result = gl_sortedlist_nx_add (list, compar, elt);
      |                           ^~~~~~~~~~~~~~~~~~~~
      |                           gl_sortedlist_add
gl_xlist.h:185:27: error: initialization of 'gl_list_node_t' {aka 'struct gl_list_node_impl *'} from 'int' makes pointer from integer without a cast [-Wint-conversion]
make[5]: *** [Makefile:2871: clean-temp-simple.o] Error 1
make[5]: *** [Makefile:2871: clean-temp.o] Error 1
make[5]: Leaving directory '/home/zoomin/codes/RISCV/SoomRV/test_programs/linux.bak/buildroot/output/build/host-m4-1.4.19/lib'
make[4]: *** [Makefile:2481: all] Error 2
make[4]: Leaving directory '/home/zoomin/codes/RISCV/SoomRV/test_programs/linux.bak/buildroot/output/build/host-m4-1.4.19/lib'
make[3]: *** [Makefile:2018: all-recursive] Error 1
make[3]: Leaving directory '/home/zoomin/codes/RISCV/SoomRV/test_programs/linux.bak/buildroot/output/build/host-m4-1.4.19'
make[2]: *** [Makefile:1974：all] 错误 2
make[2]: 离开目录“/home/zoomin/codes/RISCV/SoomRV/test_programs/linux.bak/buildroot/output/build/host-m4-1.4.19”
make[1]: *** [package/pkg-generic.mk:293：/home/zoomin/codes/RISCV/SoomRV/test_programs/linux.bak/buildroot/output/build/host-m4-1.4.19/.stamp_built] 错误 2
make[1]: 离开目录“/home/zoomin/codes/RISCV/SoomRV/test_programs/linux.bak/buildroot”
make: *** [Makefile:29：buildroot/output/images/Image] 错误 2                                   
```

因此，我想要使用较新的 buildroot 构建 linux 镜像。

Makefile 内容如下：

```makefile
BUILDROOT_DIR ?= buildroot
BUILDROOT_VERSION ?= 2025.11
BUILDROOT_CFG ?= buildroot.config
KERNEL_CFG ?= kernel.config
BUSYBOX_CFG ?= busybox.config
RV32_OBJCOPY ?= riscv32-unknown-linux-gnu-objcopy

.PHONY: all
all: linux_image.elf

$(BUILDROOT_DIR): $(KERNEL_CFG) $(BUSYBOX_CFG)
	curl -Lo buildroot.tar.gz https://github.com/buildroot/buildroot/archive/refs/tags/$(BUILDROOT_VERSION).tar.gz
	tar -xzf buildroot.tar.gz
	$(RM) buildroot.tar.gz
	mv buildroot-$(BUILDROOT_VERSION) $@

$(BUILDROOT_DIR)/.config: $(BUILDROOT_DIR)
	cp $(BUILDROOT_CFG) $@

# Kernel 和 Busybox 配置（保持不变，除非你也想用默认的）
$(BUILDROOT_DIR)/kernel.config: $(BUILDROOT_DIR) $(KERNEL_CFG)
	cp $(KERNEL_CFG) $@

$(BUILDROOT_DIR)/busybox.config: $(BUILDROOT_DIR) $(BUSYBOX_CFG)
	cp $(BUSYBOX_CFG) $@

# 编译规则
.PHONY: $(BUILDROOT_DIR)/output/images/Image
$(BUILDROOT_DIR)/output/images/Image: $(BUILDROOT_DIR) $(BUILDROOT_DIR)/.config $(BUILDROOT_DIR)/kernel.config $(BUILDROOT_DIR)/busybox.config
	mkdir -p buildroot/output/target/
	cp -r $(wildcard extra/*) buildroot/output/target/
	make -C buildroot

# The buildroot-generated fw_payload.bin seems to chop off the end of the kernel image sometimes,
# so we assemble the image ourselves.
linux_image.bin: $(BUILDROOT_DIR)/output/images/Image
	cp $(BUILDROOT_DIR)/output/images/fw_jump.bin linux_image.bin
# Enlarge the OpenSBI image to exactly 4MiB. This alignment is required by OpenSBI.
	dd if=/dev/zero bs=1 seek=4194304 count=0 of=linux_image.bin
# Append the actual kernel image
	cat $(BUILDROOT_DIR)/output/images/Image >> linux_image.bin

# Pack the raw image into a dummy ELF for VTop to read
linux_image.elf: linux_image.bin
	$(RV32_OBJCOPY) -B riscv --input-target=binary --output-target=elf32-little linux_image.bin linux_image.elf
# Rename .data to .text for the testbench to execute it
	$(RV32_OBJCOPY) -B riscv --input-target=elf32-little --rename-section .data=.text --output-target=elf32-little linux_image.elf

.PHONY: clean
clean:
	$(RM) -r $(BUILDROOT_DIR) linux_image.elf linux_image.bin
```

仍然无法编译成功。

大量警告如：

```bash
/usr/bin/gcc -O2 -I/home/zoomin/codes/RISCV/SoomRV/test_programs/linux/buildroot/output/host/include -D_LARGEFILE64_SOURCE=1 -DHAVE_HIDDEN -I. -D_FILE_OFFSET_BITS=64 -c -o minigzip64.o test/minigzip.c
test/minigzip.c: 在函数‘error’中:
test/minigzip.c:351:6: 警告：旧式的函数定义 [-Wold-style-definition]
  351 | void error(msg)
      |      ^~~~~
test/minigzip.c: 在函数‘gz_compress’中:
test/minigzip.c:362:6: 警告：旧式的函数定义 [-Wold-style-definition]
  362 | void gz_compress(in, out)
      |      ^~~~~~~~~~~
test/minigzip.c: 在函数‘gz_uncompress’中:
test/minigzip.c:430:6: 警告：旧式的函数定义 [-Wold-style-definition]
  430 | void gz_uncompress(in, out)
      |      ^~~~~~~~~~~~~
test/minigzip.c: 在函数‘file_compress’中:
test/minigzip.c:457:6: 警告：旧式的函数定义 [-Wold-style-definition]
  457 | void file_compress(file, mode)
      |      ^~~~~~~~~~~~~
test/minigzip.c: 在函数‘file_uncompress’中:
test/minigzip.c:496:6: 警告：旧式的函数定义 [-Wold-style-definition]
  496 | void file_uncompress(file)
      |      ^~~~~~~~~~~~~~~
test/minigzip.c: 在函数‘main’中:
test/minigzip.c:556:5: 警告：旧式的函数定义 [-Wold-style-definition]
  556 | int main(argc, argv)
      |     ^~~~
```

最后报错：

```bash
  CCLD     fsfreeze
misc-utils/kill.c: 在函数‘kill_with_timeout’中:
misc-utils/kill.c:397:20: 错误：implicit declaration of function ‘pidfd_open’; did you mean ‘fdopen’? [-Wimplicit-function-declaration]
  397 |         if ((pfd = pidfd_open(ctl->pid, 0)) < 0)
      |                    ^~~~~~~~~~
      |                    fdopen
misc-utils/kill.c:397:20: 警告：对‘pidfd_open’的嵌套的外部声明 [-Wnested-externs]
misc-utils/kill.c:402:13: 错误：implicit declaration of function ‘pidfd_send_signal’; did you mean ‘SYS_pidfd_send_signal’? [-Wimplicit-function-declaration]
  402 |         if (pidfd_send_signal(pfd, ctl->numsig, &info, 0) < 0)
      |             ^~~~~~~~~~~~~~~~~
      |             SYS_pidfd_send_signal
misc-utils/kill.c:402:13: 警告：对‘pidfd_send_signal’的嵌套的外部声明 [-Wnested-externs]
  CCLD     pivot_root
make[4]: *** [Makefile:9691：misc-utils/kill.o] 错误 1
make[4]: *** 正在等待未完成的任务....
make[4]: 离开目录“/home/zoomin/codes/RISCV/SoomRV/test_programs/linux/buildroot/output/build/host-util-linux-2.38”
make[3]: *** [Makefile:15052：all-recursive] 错误 1
make[3]: 离开目录“/home/zoomin/codes/RISCV/SoomRV/test_programs/linux/buildroot/output/build/host-util-linux-2.38”
make[2]: *** [Makefile:6454：all] 错误 2
make[2]: 离开目录“/home/zoomin/codes/RISCV/SoomRV/test_programs/linux/buildroot/output/build/host-util-linux-2.38”
make[1]: *** [package/pkg-generic.mk:293：/home/zoomin/codes/RISCV/SoomRV/test_programs/linux/buildroot/output/build/host-util-linux-2.38/.stamp_built] 错误 2
make[1]: 离开目录“/home/zoomin/codes/RISCV/SoomRV/test_programs/linux/buildroot”
make: *** [Makefile:37：buildroot/output/images/Image] 错误 2
```

因此我将 Makefile 修改为：

```bash
BUILDROOT_DIR ?= buildroot
BUILDROOT_VERSION ?= 2025.11
# BUILDROOT_CFG ?= buildroot.config
KERNEL_CFG ?= kernel.config
BUSYBOX_CFG ?= busybox.config
RV32_OBJCOPY ?= riscv32-unknown-linux-gnu-objcopy

.PHONY: all
all: linux_image.elf

$(BUILDROOT_DIR): $(KERNEL_CFG) $(BUSYBOX_CFG)
	curl -Lo buildroot.tar.gz https://github.com/buildroot/buildroot/archive/refs/tags/$(BUILDROOT_VERSION).tar.gz
	tar -xzf buildroot.tar.gz
	$(RM) buildroot.tar.gz
	mv buildroot-$(BUILDROOT_VERSION) $@

# 生成 .config 的规则
# 不再复制旧文件，而是让 Buildroot 生成一个标准的 RISC-V 32位 默认配置
# 使用 qemu_riscv32_virt_defconfig 作为基础
$(BUILDROOT_DIR)/.config: $(BUILDROOT_DIR)
	make -C $(BUILDROOT_DIR) qemu_riscv32_virt_defconfig

# 后面内容不变
```

**Help [1]**
buildroot.config、kernel.config、busybox.config 文件开头写着 Automatically generated file，我很想知道这些配置文件是如何生成的？（当然，如果有机会的话，也告诉我 device_tree.dts 如何生成的？不过这与 issue 无关）。

1. `make qemu_riscv32_virt_defconfig`  生成的 .config 很可能还需要配置。比如，Target ABI 为 `ilp32d` ，而仓库提供的 buildroot.config 中 Target ABI 为 `ilp32`。（不过，我暂时没有在意，因为在非 COSIM 下能运行。）
2. kenel.config，busybox.config 是一定需要的吗？可以采用默认吗？与默认的区别是什么？kenel.config 的默认似乎与 buildroot/arch/Config.in.riscv 相关；busybox.config 存在默认文件 package/busybox/busybox.config。

**COSIM**

在使用上述的 Makfile 构建镜像后，运行 Linux

```cpp
# make clean && make soomrv
❯ ./obj_dir/VTop --perfc --device-tree=test_programs/linux/device_tree.dtb test_programs/linux/linux_image.elf
mismatch x30
ERROR 4 (fetchID=18, sqN=42)
time=1596305
ir=001ef6bb ppc=8000351c inst=7a402f73 sqn=43
x00=00000000 x01=80003590 x02=80045f20 x03=00000000 x04=80046000 x05=00002000 x06=80046000 x07=00001000 
x08=80045f50 x09=800420b0 x10=00000001 x11=80045f2c x12=800003b0 x13=80045f2c x14=80045f2c x15=00000000 
x16=80040a84 x17=80049f80 x18=80046000 x19=00000000 x20=80042004 x21=80042008 x22=00000000 x23=00000001 
x24=00002000 x25=80042310 x26=00000000 x27=00000000 x28=00000020 x29=00000000 x30=00000004 x31=00000000 


SHOULD BE
mstatus=00000000 mepc=80010130 mcause=00000002 mtvec=80000b80 mideleg=00000222 medeleg=0000b109 mie=00000000 mip=00000000
ir=001ef6bb ppc=8000351c pc=80003520 priv=3
x00=00000000 x01=80003590 x02=80045f20 x03=00000000 x04=80046000 x05=00002000 x06=80046000 x07=00001000 
x08=80045f50 x09=800420b0 x10=00000001 x11=80045f2c x12=800003b0 x13=80045f2c x14=80045f2c x15=00000000 
x16=80040a84 x17=80049f80 x18=80046000 x19=00000000 x20=80042004 x21=80042008 x22=00000000 x23=00000001 
x24=00002000 x25=80042310 x26=00000000 x27=00000000 x28=00000020 x29=00000000 x30=00000000 x31=00000000 
```

在 Simif.cpp 文件中：

在 `is_pass_thru_inst` 之前过滤 `CSR_TINFO`。因为我发现 `is_pass_thru_inst` 的  `switch (csrID)` 添加了 `case CSR_TINFO` 并未解决问题。然后，修改原本的 ERROR 6 逻辑，忽略对 `CSR_TINFO` 的检查。

```cpp
// Simif.cpp: func cosim_instr

// 1. 强制同步：针对 CSR TINFO (0x7a4) （仅测试）
// 直接检查指令位，不依赖 is_pass_thru_inst，也不检查 flags
// 0x7a4 是 CSR 地址，位于指令的高 12 位 (bits 31-20)
if (((inst.inst >> 20) & 0xFFF) == CSR_TINFO)
{
    fprintf(stderr, "[DEBUG] Force Sync TINFO: RTL x%d = %u\n",
            inst.rd, registers.ReadRegister(inst.rd));

    if (inst.rd != 0) {
        // 强制将 RTL 的寄存器值写入 Spike
        write_reg(inst.rd, registers.ReadRegister(inst.rd));
    }
}

if ((mem_pass_thru || is_pass_thru_inst(inst)) && inst.rd != 0 && inst.flags < 6)
{
    write_reg(inst.rd, inst.result);
}
/* same code */

// 2. 修改原本的 ERROR 6 逻辑，忽略对 CSR_TINFO 的检查（仅测试）
// if  (inst.minstret != processor->get_state()->csrmap[CSR_MINSTRET]->read())
//     return -6;
reg_t spike_minstret = processor->get_state()->csrmap[CSR_MINSTRET]->read();
if (inst.minstret != spike_minstret)
{
    // 如果是 TINFO (0x7a4) 指令，我们允许 instret 不一致
    if (((inst.inst >> 20) & 0xFFF) == CSR_TINFO)
    {
        // 可以选择打印一条警告，或者完全忽略
        // fprintf(stderr, "Warn: Ignoring TINFO instret mismatch. RTL=%lu, Spike=%lu\n", inst.minstret, spike_minstret);
    }
    else
    {
        // 对其他指令，仍然报错
        printf("mismatch instret: RTL=%lu, Spike=%lu\n", inst.minstret, spike_minstret);
        return -6;
    }
}
```

然而出现了新的错误。

```cpp
❯ ./obj_dir/VTop --perfc --device-tree=test_programs/linux/device_tree.dtb test_programs/linux/linux_image.elf
[DEBUG] Force Sync TINFO: RTL x30 = 4
ERROR 1 (fetchID=19, sqN=43)
time=1596333
ir=001ef6bb ppc=80000b80 inst=34202773 sqn=44
x00=00000000 x01=80003590 x02=80045f20 x03=00000000 x04=80046000 x05=00002000 x06=80046000 x07=00001000 
x08=80045f50 x09=800420b0 x10=00000001 x11=80045f2c x12=800003b0 x13=80045f2c x14=00000002 x15=00000000 
x16=80040a84 x17=80049f80 x18=80046000 x19=00000000 x20=80042004 x21=80042008 x22=00000000 x23=00000001 
x24=00002000 x25=80042310 x26=00000000 x27=00000000 x28=00000020 x29=00000000 x30=00000004 x31=00000000 


SHOULD BE
mstatus=00000000 mepc=80010130 mcause=00000002 mtvec=800003b0 mideleg=00000222 medeleg=0000b109 mie=00000000 mip=00000000
ir=001ef6bc ppc=80003520 pc=80003524 priv=3
x00=00000000 x01=80003590 x02=80045f20 x03=00000000 x04=80046000 x05=00002000 x06=80046000 x07=00001000 
x08=80045f50 x09=800420b0 x10=00000001 x11=80045f2c x12=800003b0 x13=80045f2c x14=80045f2c x15=00000000 
x16=80040a84 x17=80049f80 x18=80046000 x19=00000000 x20=80042004 x21=80042008 x22=00000000 x23=00000001 
x24=00002000 x25=80042310 x26=00000000 x27=00000000 x28=00000020 x29=00000000 x30=00000004 x31=00000000 
```

由于 0x342 为 CSR_MCAUSE，我想采用类似方式来强制同步 PC 会导致更多的错误。

但是，如果我关闭 COSIM 就能成功启动 Linux。

```makefile
VERILATOR_FLAGS = \
	--cc --build --threads 4 --unroll-stmts 999999 -unroll-count 999999 --assert -Wall -Wno-BLKSEQ -Wno-UNUSED \
	-Wno-PINCONNECTEMPTY -Wno-DECLFILENAME -Wno-ENUMVALUE -O3 -sv \
	$(VFLAGS) \
	-CFLAGS "-std=c++17 -march=native" \
	-LDFLAGS "-ldl" \
	-MAKEFLAGS -j$(nproc) \
	-CFLAGS -DNOKONATA \
	-CFLAGS -DSAVEABLE \
	-CFLAGS -DNOCOVERAG
```

```bash
# make clean && make soomrv
./obj_dir/VTop --perfc --device-tree=test_programs/linux/device_tree.dtb test_programs/linux/linux_image.elf

OpenSBI v1.6
   ____                    _____ ____ _____
  / __ \                  / ____|  _ \_   _|
 | |  | |_ __   ___ _ __ | (___ | |_) || |
 | |  | | '_ \ / _ \ '_ \ \___ \|  _ < | |
 | |__| | |_) |  __/ | | |____) | |_) || |_
  \____/| .__/ \___|_| |_|_____/|____/_____|
        | |
        |_|

Platform Name               : riscv-minimal
Platform Features           : medeleg
Platform HART Count         : 1
Platform IPI Device         : aclint-mswi
Platform Timer Device       : aclint-mtimer @ 41666666Hz
Platform Console Device     : uart8250
Platform HSM Device         : ---
Platform PMU Device         : ---
Platform Reboot Device      : syscon-reboot
Platform Shutdown Device    : syscon-poweroff
Platform Suspend Device     : ---
Platform CPPC Device        : ---
Firmware Base               : 0x80000000
Firmware Size               : 321 KB
Firmware RW Offset          : 0x40000
Firmware RW Size            : 65 KB
Firmware Heap Offset        : 0x47000
Firmware Heap Size          : 37 KB (total), 2 KB (reserved), 10 KB (used), 24 KB (free)
Firmware Scratch Size       : 4096 B (total), 256 B (used), 3840 B (free)
Runtime SBI Version         : 2.0
Standard SBI Extensions     : time,rfnc,ipi,base,hsm,srst,pmu,dbcn,legacy
Experimental SBI Extensions : fwft,sse

Domain0 Name                : root
Domain0 Boot HART           : 0
Domain0 HARTs               : 0*
Domain0 Region00            : 0x10000000-0x10000fff M: (I,R,W) S/U: (R,W)
Domain0 Region01            : 0x11100000-0x11100fff M: (I,R,W) S/U: (R,W)
Domain0 Region02            : 0x11000000-0x1100ffff M: (I,R,W) S/U: ()
Domain0 Region03            : 0x80040000-0x8005ffff M: (R,W) S/U: ()
Domain0 Region04            : 0x80000000-0x8003ffff M: (R,X) S/U: ()
Domain0 Region05            : 0x00000000-0xffffffff M: () S/U: (R,W,X)
Domain0 Next Address        : 0x80400000
Domain0 Next Arg1           : 0x82200000
Domain0 Next Mode           : S-mode
Domain0 SysReset            : yes
Domain0 SysSuspend          : yes

Boot HART ID                : 0
Boot HART Domain            : root
Boot HART Priv Version      : v1.12
Boot HART Base ISA          : rv32imacx
Boot HART ISA Extensions    : zicntr,zihpm,sdtrig
Boot HART PMP Count         : 0
Boot HART PMP Granularity   : 0 bits
Boot HART PMP Address Bits  : 0
Boot HART MHPM Info         : 6 (0x00000f50)
Boot HART Debug Triggers    : 0 triggers
Boot HART MIDELEG           : 0x00000222
Boot HART MEDELEG           : 0x0000b109
[    0.000000] Linux version 6.12.47 (zoomin@clstilmldy) (riscv32-buildroot-linux-gnu-gcc.br_real (Buildroot -g1f90001-dirty) 14.3.0, GNU ld (GNU Binutils) 2.43.1) #1 SMP Sun Jan  4 23:35:35 CST 2026
[    0.000000] OF: fdt: Ignoring memory range 0x80000000 - 0x80400000
[    0.000000] Machine model: riscv-minimal
......
```



**Help [2]**

我不知道该如何支持 COMSIM。如果可以的话，可以告知我您的思路吗？（当然，我正在研究您的代码）
