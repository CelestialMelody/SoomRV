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
# 这是一个通用的 RV32 配置，包含 Linux Kernel 和 OpenSBI
$(BUILDROOT_DIR)/.config: $(BUILDROOT_DIR)
	make -C $(BUILDROOT_DIR) qemu_riscv32_virt_defconfig

# Kernel 和 Busybox 配置（保持不变）
$(BUILDROOT_DIR)/kernel.config: $(BUILDROOT_DIR) $(KERNEL_CFG)
	cp $(KERNEL_CFG) $@

$(BUILDROOT_DIR)/busybox.config: $(BUILDROOT_DIR) $(BUSYBOX_CFG)
	cp $(BUSYBOX_CFG) $@

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