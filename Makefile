# Optional -Wno-* flags: only added when this Verilator supports them. To add more, append to the list.
VERILATOR_WNO_OPTIONAL := -Wno-GENUNNAMED -Wno-PROCASSINIT -Wno-IMPLICITSTATIC -Wno-EOFNEWLINE
SUPPORTS_OPTIONAL_WNO := $(shell for f in $(VERILATOR_WNO_OPTIONAL); do verilator $$f --version >/dev/null 2>&1 && echo $$f; done)

# Set COSIM=1 to enable co-simulation with Spike
COSIM ?= 1

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
TLB_IMPL ?= fixed
ifeq ($(TLB_IMPL),orig)
TLB_SRC := src/TLB.sv
else ifeq ($(TLB_IMPL),fixed)
TLB_SRC := src/TLB_fixed.sv
else
$(error Unsupported TLB_IMPL='$(TLB_IMPL)'. Expected 'orig' or 'fixed')
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
	src/BranchPredictor.sv \
	src/LoadBuffer.sv \
	src/StoreQueue.sv \
	src/Multiply.sv \
	src/Divide.sv \
	src/MMIO.sv \
	src/BranchSelector.sv \
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
	src/BranchPredictionTable.sv \
	src/ReturnStack.sv \
	src/TageTable.sv \
	src/TagePredictor.sv \
	src/LoadStoreUnit.sv \
	src/IFetchPipeline.sv \
	src/CSR.sv \
	src/TrapHandler.sv \
	src/Peripherals.sv \
	src/PageWalker.sv \
	src/LoadSelector.sv \
	src/LoadResultBuffer.sv \
	$(TLB_SRC) \
	src/BypassLSU.sv \
	src/TValSelect.sv \
	src/SoC.sv \
	src/TLBMissQueue.sv \
	src/ExternalAXISim.sv \
	src/CacheWriteInterface.sv \
	src/CacheReadInterface.sv \
	src/RegFileRTL.sv \
	src/BranchHandler.sv \
	src/StoreDataIQ.sv \
	src/StoreDataLoad.sv \
	src/StoreQueueBackend.sv \
	src/Scheduler.sv \
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
