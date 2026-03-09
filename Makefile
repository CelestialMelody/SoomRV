# Optional -Wno-* flags: only added when this Verilator supports them. To add more, append to the list.
VERILATOR_WNO_OPTIONAL := -Wno-GENUNNAMED -Wno-PROCASSINIT -Wno-IMPLICITSTATIC -Wno-EOFNEWLINE -Wno-WIDTHEXPAND
SUPPORTS_OPTIONAL_WNO := $(shell for f in $(VERILATOR_WNO_OPTIONAL); do verilator $$f --version >/dev/null 2>&1 && echo $$f; done)

# Set COSIM=1 to enable co-simulation with Spike
COSIM ?= 0

# Select HardFloat source directory:
#   make soomrv HARDFLOAT_DIR=/abs/path/to/hardfloat
HARDFLOAT_DIR ?= hardfloat
HARDFLOAT_SRC := $(wildcard $(HARDFLOAT_DIR)/*.v)
ifeq ($(strip $(HARDFLOAT_SRC)),)
$(error No HardFloat Verilog sources found under '$(HARDFLOAT_DIR)')
endif

# Select TLB implementation:
#   make soomrv TLB_IMPL=orig
#   make soomrv TLB_IMPL=fixed
#   make soomrv TLB_IMPL=fixed_sp_dedup
TLB_IMPL ?= fixed_sp_dedup
ifeq ($(TLB_IMPL),orig)
TLB_SRC := src/TLB.sv
else ifeq ($(TLB_IMPL),fixed)
TLB_SRC := src/TLB_fixed.sv
else ifeq ($(TLB_IMPL),fixed_sp_dedup)
TLB_SRC := src/TLB_fixed_sp_dedup.sv
else
$(error Unsupported TLB_IMPL='$(TLB_IMPL)'. Expected 'orig', 'fixed' or 'fixed_sp_dedup')
endif

# Select BranchPredictor implementation:
#   make soomrv BRANCH_PRED_IMPL=orig
#   make soomrv BRANCH_PRED_IMPL=bt_arb
BRANCH_PRED_IMPL ?= bt_arb
ifeq ($(BRANCH_PRED_IMPL),orig)
BP_SRC := src/BranchPredictor.sv
else ifeq ($(BRANCH_PRED_IMPL),bt_arb)
BP_SRC := src/BranchPredictor_bt_arb.sv
else
$(error Unsupported BRANCH_PRED_IMPL='$(BRANCH_PRED_IMPL)'. Expected 'orig' or 'bt_arb')
endif

# Select base BHT implementation:
#   make soomrv BHT_IMPL=orig
#   make soomrv BHT_IMPL=bht_fwd
BHT_IMPL ?= bht_fwd
ifeq ($(BHT_IMPL),orig)
BHT_SRC := src/BranchPredictionTable.sv
else ifeq ($(BHT_IMPL),bht_fwd)
BHT_SRC := src/BranchPredictionTable_bht_fwd.sv
else
$(error Unsupported BHT_IMPL='$(BHT_IMPL)'. Expected 'orig' or 'bht_fwd')
endif

# Select PageWalker implementation:
#   make soomrv PAGEWALKER_IMPL=orig
#   make soomrv PAGEWALKER_IMPL=pw_arb
PAGEWALKER_IMPL ?= pw_arb
ifeq ($(PAGEWALKER_IMPL),orig)
PW_SRC := src/PageWalker.sv
else ifeq ($(PAGEWALKER_IMPL),pw_arb)
PW_SRC := src/PageWalker_pw_arb.sv
else
$(error Unsupported PAGEWALKER_IMPL='$(PAGEWALKER_IMPL)'. Expected 'orig' or 'pw_arb')
endif

# Select TLBMissQueue implementation:
#   make soomrv TLBMISSQ_IMPL=orig
#   make soomrv TLBMISSQ_IMPL=tmq_param
TLBMISSQ_IMPL ?= tmq_param
ifeq ($(TLBMISSQ_IMPL),orig)
TLBMISSQ_SRC := src/TLBMissQueue.sv
else ifeq ($(TLBMISSQ_IMPL),tmq_param)
TLBMISSQ_SRC := src/TLBMissQueue_param.sv
else
$(error Unsupported TLBMISSQ_IMPL='$(TLBMISSQ_IMPL)'. Expected 'orig' or 'tmq_param')
endif

# Select hardcoded-4 cleanup implementation set:
#   make soomrv HARDCODE4_IMPL=orig
#   make soomrv HARDCODE4_IMPL=param
HARDCODE4_IMPL ?= param
ifeq ($(HARDCODE4_IMPL),orig)
BRSEL_SRC := src/BranchSelector.sv
EXTAXI_SRC := src/ExternalAXISim.sv
STOREQUEUE_SRC := src/StoreQueue.sv
SCHED_SRC := src/Scheduler.sv
else ifeq ($(HARDCODE4_IMPL),param)
BRSEL_SRC := src/BranchSelector_param.sv
EXTAXI_SRC := src/ExternalAXISim_param.sv
STOREQUEUE_SRC := src/StoreQueue_param.sv
SCHED_SRC := src/Scheduler_param.sv
else
$(error Unsupported HARDCODE4_IMPL='$(HARDCODE4_IMPL)'. Expected 'orig' or 'param')
endif

# Select Load/Store issue-cadence backend implementation:
#   make soomrv LS_ISSUE_IMPL=orig
#   make soomrv LS_ISSUE_IMPL=issue_opt
LS_ISSUE_IMPL ?= issue_opt
ifeq ($(LS_ISSUE_IMPL),orig)
SQBACKEND_SRC := src/StoreQueueBackend.sv
else ifeq ($(LS_ISSUE_IMPL),issue_opt)
SQBACKEND_SRC := src/StoreQueueBackend_issue_opt.sv
else
$(error Unsupported LS_ISSUE_IMPL='$(LS_ISSUE_IMPL)'. Expected 'orig' or 'issue_opt')
endif

VERILATOR_FLAGS = \
    --cc --build --threads 4 --unroll-stmts 999999 -unroll-count 999999 --assert -Wall -Wno-fatal \
    -Wno-BLKSEQ -Wno-UNUSED -Wno-PINCONNECTEMPTY -Wno-DECLFILENAME -Wno-ENUMVALUE \
    $(SUPPORTS_OPTIONAL_WNO) \
    -O3 -sv \
    $(VFLAGS) \
    -CFLAGS "-std=c++17 -march=native" \
    -LDFLAGS "-ldl" \
	-MAKEFLAGS -j$(nproc) \
	-CFLAGS -DNOKONATA \
	-CFLAGS -DSAVEABLE \
	-CFLAGS -DNOCOVERAGE \
	$(if $(filter 1,$(COSIM)),-CFLAGS -DCOSIM,)

VERILATOR_CFG = --exe sim/Top_tb.cpp sim/Simif.cpp --savable ../riscv-isa-sim/libriscv.a ../riscv-isa-sim/libsoftfloat.a ../riscv-isa-sim/libdisasm.a -CFLAGS -I../riscv-isa-sim --top-module Top -I$(HARDFLOAT_DIR)

VERILATOR_TRACE_FLAGS = --trace --trace-fst --trace-structs --trace-max-width 128 --trace-max-array 256 -CFLAGS -DTRACE

SLANG_FLAGS = \
	--single-unit \
	--std latest \
	--allow-use-before-declare \
	--relax-enum-conversions \
	--ignore-unknown-modules \
	--allow-toplevel-iface-ports \
	-Wno-explicit-static \
	-Wno-missing-top

SLANG_HEADER_OUTPUT = sim/slang/slang.hpp

SRC_FILES = \
	src/lib/PriorityEncoder.sv \
	src/lib/OHEncoder.sv \
	src/lib/RangeMaskGen.sv \
	src/lib/PrefixSum.sv \
	src/lib/PrefixRed.sv \
	src/lib/OpDownsample.sv \
	src/lib/PopCnt.sv \
	src/lib/FIFO.sv \
	src/Config.sv \
	src/Include.sv  \
	src/InstrDecoder.sv  \
	src/Rename.sv  \
	src/Core.sv  \
	src/IssueQueue.sv  \
	src/IntALU.sv  \
	src/IFetch.sv \
	src/Load.sv \
	src/ROB.sv \
	src/AGU.sv \
	$(BP_SRC) \
	src/BTUpdateArbiter.sv \
	src/LoadBuffer.sv \
	$(STOREQUEUE_SRC) \
	src/Multiply.sv \
	src/Divide.sv \
	src/MMIO.sv \
	$(BRSEL_SRC) \
	src/MemRTL.sv \
	src/MemRTL2W.sv \
	src/Top.sv \
	src/MemoryController.sv \
	src/RenameTable.sv \
	src/TagBuffer.sv \
	src/FPU.sv \
	src/FMul.sv \
	src/FDiv.sv \
	src/BranchTargetBuffer.sv \
	$(BHT_SRC) \
	src/ReturnStack.sv \
	src/TageTable.sv \
	src/TagePredictor.sv \
	src/LoadStoreUnit.sv \
	src/IFetchPipeline.sv \
	src/CSR.sv \
	src/TrapHandler.sv \
	src/Peripherals.sv \
	$(PW_SRC) \
	src/PageWalkReqArbiter.sv \
	src/LoadSelector.sv \
	src/LoadResultBuffer.sv \
	$(TLB_SRC) \
	src/BypassLSU.sv \
	src/TValSelect.sv \
	src/SoC.sv \
	$(TLBMISSQ_SRC) \
	$(EXTAXI_SRC) \
	src/CacheWriteInterface.sv \
	src/CacheReadInterface.sv \
	src/RegFileRTL.sv \
	src/BranchHandler.sv \
	src/StoreDataIQ.sv \
	src/StoreDataLoad.sv \
	$(SQBACKEND_SRC) \
	$(SCHED_SRC) \
	src/ResultFlagsSplit.sv \
	src/InstrAligner.sv \
	src/RFReadMux.sv \
	src/CacheArbiter.sv \
	src/MemRTL1RW.sv \
	src/ExternalBus.sv \
	src/ExternalBusMem.sv \
	src/CacheLineManager.sv \
	src/DataPrefetch.sv \
	src/PrefetchPatternDetector.sv \
	src/PrefetchIssuer.sv \
	src/PrefetchExecutor.sv \
	$(HARDFLOAT_SRC)

.PHONY: soomrv
soomrv: $(SLANG_HEADER_OUTPUT)
	verilator $(VERILATOR_FLAGS) $(VERILATOR_CFG) $(SRC_FILES)

.PHONY: linux
linux: soomrv
	make -C test_programs/linux
	./obj_dir/VTop --device-tree=test_programs/linux/device_tree.dtb --backup-file=soomrv.backup test_programs/linux/linux_image.elf

.PHONY: trace
trace: VERILATOR_FLAGS += $(VERILATOR_TRACE_FLAGS)
trace: soomrv

.PHONY: setup
setup:
	git submodule update --init --recursive
	cd riscv-isa-sim && ./configure CFLAGS="-Os -g0" CXXFLAGS="-Os -g0" --with-boost=no --with-boost-asio=no --with-boost-regex=no
	make -j $(nproc) -C riscv-isa-sim

EXTERNAL_TESTS_DIR ?= external-tests
RISCV_TESTS_DIR ?= $(EXTERNAL_TESTS_DIR)/riscv-tests
RISCV_TESTS_REPO ?= https://github.com/riscv-software-src/riscv-tests.git
RISCV_TESTS_REF ?= master
RISCV_ARCH_TEST_DIR ?= $(EXTERNAL_TESTS_DIR)/riscv-arch-test
RISCV_ARCH_TEST_REPO ?= https://github.com/riscv-non-isa/riscv-arch-test.git
RISCV_ARCH_TEST_REF ?= main
PYTHON ?= python3
EXTERNAL_TEST_TIMEOUT ?= 180
EXTERNAL_TEST_HEARTBEAT ?= 15

.PHONY: external-tests-fetch
external-tests-fetch:
	@mkdir -p "$(EXTERNAL_TESTS_DIR)"
	@if [ -d "$(RISCV_TESTS_DIR)/.git" ]; then \
		echo "Updating existing riscv-tests checkout at $(RISCV_TESTS_DIR)"; \
		git -C "$(RISCV_TESTS_DIR)" fetch --depth 1 origin "$(RISCV_TESTS_REF)"; \
		git -C "$(RISCV_TESTS_DIR)" checkout FETCH_HEAD; \
	else \
		echo "Cloning riscv-tests into $(RISCV_TESTS_DIR)"; \
		git clone --depth 1 --branch "$(RISCV_TESTS_REF)" "$(RISCV_TESTS_REPO)" "$(RISCV_TESTS_DIR)"; \
	fi

.PHONY: external-arch-tests-fetch
external-arch-tests-fetch:
	@mkdir -p "$(EXTERNAL_TESTS_DIR)"
	@if [ -d "$(RISCV_ARCH_TEST_DIR)/.git" ]; then \
		echo "Updating existing riscv-arch-test checkout at $(RISCV_ARCH_TEST_DIR)"; \
		git -C "$(RISCV_ARCH_TEST_DIR)" fetch --depth 1 origin "$(RISCV_ARCH_TEST_REF)"; \
		git -C "$(RISCV_ARCH_TEST_DIR)" checkout FETCH_HEAD; \
	else \
		echo "Cloning riscv-arch-test into $(RISCV_ARCH_TEST_DIR)"; \
		git clone --depth 1 --branch "$(RISCV_ARCH_TEST_REF)" "$(RISCV_ARCH_TEST_REPO)" "$(RISCV_ARCH_TEST_DIR)"; \
	fi

.PHONY: external-tests-build
external-tests-build:
	@if [ ! -d "$(RISCV_TESTS_DIR)" ]; then \
		echo "Missing $(RISCV_TESTS_DIR). Run 'make external-tests-fetch' first."; \
		exit 1; \
	fi
	@cd "$(RISCV_TESTS_DIR)" && git submodule update --init --recursive
	@cd "$(RISCV_TESTS_DIR)" && autoconf
	@cd "$(RISCV_TESTS_DIR)" && ./configure --prefix="$$PWD/build-target"
	$(MAKE) -C "$(RISCV_TESTS_DIR)" isa XLEN=32

.PHONY: external-tests-run
external-tests-run:
	@if [ ! -d "$(RISCV_TESTS_DIR)" ]; then \
		echo "Missing $(RISCV_TESTS_DIR). Run 'make external-tests-fetch' first."; \
		exit 1; \
	fi
	$(PYTHON) scripts/test_suite.py "$(RISCV_TESTS_DIR)/isa" \
		--timeout-sec $(EXTERNAL_TEST_TIMEOUT) \
		--heartbeat-sec $(EXTERNAL_TEST_HEARTBEAT)

.PHONY: external-tests-smoke
external-tests-smoke:
	@if [ ! -d "$(RISCV_TESTS_DIR)" ]; then \
		echo "Missing $(RISCV_TESTS_DIR). Run 'make external-tests-fetch' first."; \
		exit 1; \
	fi
	$(PYTHON) scripts/test_suite.py "$(RISCV_TESTS_DIR)/isa" \
		--categories rv32ui,rv32um,rv32uc --max-tests-per-category 8 \
		--timeout-sec $(EXTERNAL_TEST_TIMEOUT) \
		--heartbeat-sec $(EXTERNAL_TEST_HEARTBEAT)

# if you encounter an error related to model_headers.h when executing `make`,
# please try running `make prepare_header`.
.PHONY: prepare_header
prepare_header:
	python scripts/prepare_header.py obj_dir/\*.h sim/model_headers.h

$(SLANG_HEADER_OUTPUT): src/Config.sv src/Include.sv
	@if [ -x "`command -v slang-reflect`" ]; then \
	mkdir -p sim/slang && \
	slang-reflect $^ $(SLANG_FLAGS) --output-dir sim/slang/ && \
	mv sim/slang/.h $@ && \
	sed -i '/#include <systemc.h>/d' $@;\
	else \
		echo "warning: Could not find slang-reflect, continuing without. Cosim will not be updated if parameters change.";\
	fi

.PHONY: clean
clean:
	$(RM) -r obj_dir
