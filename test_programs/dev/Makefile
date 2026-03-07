ROOT := ../..
VERILATOR ?= verilator

TB := tlb_dup_tb.sv
BUILD_DIR := build
ORIG_DIR := $(BUILD_DIR)/orig
FIXED_DIR := $(BUILD_DIR)/fixed
HARDFLOAT_DIR ?= $(ROOT)/hardfloat
HARDFLOAT_TB := hardfloat_ext_tb.sv
HARDFLOAT_BUILD_DIR := $(BUILD_DIR)/hardfloat
HARDFLOAT_BIN := Vhardfloat_ext_tb
HARDFLOAT_SRCS := $(sort $(wildcard $(HARDFLOAT_DIR)/*.v))

ORIG_TLB := $(ROOT)/src/TLB.sv
FIXED_TLB := $(ROOT)/src/TLB_fixed.sv
TB_BIN := Vtlb_dup_tb

VERILATOR_FLAGS := -sv --binary -Wno-fatal -Wno-IMPLICITSTATIC -I$(ROOT)

ifeq ($(strip $(HARDFLOAT_SRCS)),)
$(error No HardFloat sources found under '$(HARDFLOAT_DIR)')
endif

.PHONY: all build-orig build-fixed run-orig run-fixed compare build-hardfloat run-hardfloat clean

all: compare

build-orig: $(ORIG_DIR)/$(TB_BIN)

build-fixed: $(FIXED_DIR)/$(TB_BIN)

$(ORIG_DIR)/$(TB_BIN): $(TB) $(ORIG_TLB)
	@mkdir -p $(ORIG_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) --Mdir $(ORIG_DIR) $(TB) $(ORIG_TLB)

$(FIXED_DIR)/$(TB_BIN): $(TB) $(FIXED_TLB)
	@mkdir -p $(FIXED_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) --Mdir $(FIXED_DIR) $(TB) $(FIXED_TLB)

run-orig: build-orig
	@$(ORIG_DIR)/$(TB_BIN) | tee $(ORIG_DIR)/run.log

run-fixed: build-fixed
	@$(FIXED_DIR)/$(TB_BIN) | tee $(FIXED_DIR)/run.log

compare: run-orig run-fixed
	@orig_dup=$$(grep -o 'RESULT_DUPLICATE=[01]' $(ORIG_DIR)/run.log | tail -1 | cut -d= -f2); \
	fixed_dup=$$(grep -o 'RESULT_DUPLICATE=[01]' $(FIXED_DIR)/run.log | tail -1 | cut -d= -f2); \
	echo "orig RESULT_DUPLICATE=$$orig_dup"; \
	echo "fixed RESULT_DUPLICATE=$$fixed_dup"; \
	if [ -z "$$orig_dup" ] || [ -z "$$fixed_dup" ]; then \
		echo "ERROR: could not parse RESULT_DUPLICATE from logs"; \
		exit 2; \
	fi; \
	if [ "$$orig_dup" = "1" ] && [ "$$fixed_dup" = "0" ]; then \
		echo "PASS: fixed TLB prevents duplicate insertion"; \
	else \
		echo "FAIL: expected orig=1 and fixed=0"; \
		exit 1; \
	fi

build-hardfloat: $(HARDFLOAT_BUILD_DIR)/$(HARDFLOAT_BIN)

$(HARDFLOAT_BUILD_DIR)/$(HARDFLOAT_BIN): $(HARDFLOAT_TB) $(HARDFLOAT_SRCS)
	@mkdir -p $(HARDFLOAT_BUILD_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) -I$(HARDFLOAT_DIR) --Mdir $(HARDFLOAT_BUILD_DIR) $(HARDFLOAT_TB) $(HARDFLOAT_SRCS)

run-hardfloat: build-hardfloat
	@$(HARDFLOAT_BUILD_DIR)/$(HARDFLOAT_BIN) | tee $(HARDFLOAT_BUILD_DIR)/run.log

clean:
	rm -rf $(BUILD_DIR)
