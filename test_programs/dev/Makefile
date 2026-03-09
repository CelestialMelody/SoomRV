ROOT := ../..
VERILATOR ?= verilator

TB := tlb_dup_tb.sv
SUPER_TB := tlb_super_dup_tb.sv
BUILD_DIR := build
ORIG_DIR := $(BUILD_DIR)/orig
FIXED_DIR := $(BUILD_DIR)/fixed
SUPER_FIXED_DIR := $(BUILD_DIR)/super_fixed
SUPER_ENH_DIR := $(BUILD_DIR)/super_enh
BT_ARB_TB := bt_update_arb_tb.sv
BT_ARB_DIR := $(BUILD_DIR)/bt_arb
BT_ARB_BIN := Vbt_update_arb_tb
PW_ARB_TB := pagewalk_req_arb_tb.sv
PW_ARB_DIR := $(BUILD_DIR)/pw_arb
PW_ARB_BIN := Vpagewalk_req_arb_tb
TMQ_TB := tlb_miss_queue_param_tb.sv
TMQ_BIN := Vtlb_miss_queue_param_tb
TMQ4_ORIG_DIR := $(BUILD_DIR)/tmq4_orig
TMQ8_ORIG_DIR := $(BUILD_DIR)/tmq8_orig
TMQ4_ENH_DIR := $(BUILD_DIR)/tmq4_enh
TMQ8_ENH_DIR := $(BUILD_DIR)/tmq8_enh
SQB_ISSUE_TB := store_queue_backend_issue_tb.sv
SQB_ISSUE_BIN := Vstore_queue_backend_issue_tb
SQB_ISSUE_ORIG_DIR := $(BUILD_DIR)/sqb_issue_orig
SQB_ISSUE_OPT_DIR := $(BUILD_DIR)/sqb_issue_opt
BHT_FWD_TB := bht_write_read_forward_tb.sv
BHT_FWD_BIN := Vbht_write_read_forward_tb
BHT_FWD_ORIG_DIR := $(BUILD_DIR)/bht_fwd_orig
BHT_FWD_OPT_DIR := $(BUILD_DIR)/bht_fwd_opt
HARDFLOAT_DIR ?= $(ROOT)/hardfloat
HARDFLOAT_TB := hardfloat_ext_tb.sv
HARDFLOAT_BUILD_DIR := $(BUILD_DIR)/hardfloat
HARDFLOAT_BIN := Vhardfloat_ext_tb
HARDFLOAT_SRCS := $(sort $(wildcard $(HARDFLOAT_DIR)/*.v))

ORIG_TLB := $(ROOT)/src/TLB.sv
FIXED_TLB := $(ROOT)/src/TLB_fixed.sv
TB_BIN := Vtlb_dup_tb
FIXED_SP_TLB := $(ROOT)/src/TLB_fixed_sp_dedup.sv
SUPER_BIN := Vtlb_super_dup_tb
BT_ARB_SRC := $(ROOT)/src/BTUpdateArbiter.sv
PW_ARB_SRC := $(ROOT)/src/PageWalkReqArbiter.sv
TMQ_ORIG_SRC := $(ROOT)/src/TLBMissQueue.sv
TMQ_ENH_SRC := $(ROOT)/src/TLBMissQueue_param.sv
SQB_ORIG_SRC := $(ROOT)/src/StoreQueueBackend.sv
SQB_OPT_SRC := $(ROOT)/src/StoreQueueBackend_issue_opt.sv
BHT_ORIG_SRC := $(ROOT)/src/BranchPredictionTable.sv
BHT_FWD_SRC := $(ROOT)/src/BranchPredictionTable_bht_fwd.sv

VERILATOR_FLAGS := -sv --binary -Wno-fatal -Wno-IMPLICITSTATIC -I$(ROOT)

ifeq ($(strip $(HARDFLOAT_SRCS)),)
$(error No HardFloat sources found under '$(HARDFLOAT_DIR)')
endif

.PHONY: all build-orig build-fixed run-orig run-fixed compare build-super-fixed build-super-enh run-super-fixed run-super-enh compare-super build-tmq4-orig build-tmq8-orig build-tmq4-enh build-tmq8-enh run-tmq4-orig run-tmq8-orig run-tmq4-enh run-tmq8-enh compare-tmq-param build-sqb-issue-orig build-sqb-issue-opt run-sqb-issue-orig run-sqb-issue-opt compare-sqb-issue build-bht-fwd-orig build-bht-fwd-opt run-bht-fwd-orig run-bht-fwd-opt compare-bht-fwd build-bt-arb run-bt-arb build-pw-arb run-pw-arb build-hardfloat run-hardfloat clean

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

build-super-fixed: $(SUPER_FIXED_DIR)/$(SUPER_BIN)

build-super-enh: $(SUPER_ENH_DIR)/$(SUPER_BIN)

$(SUPER_FIXED_DIR)/$(SUPER_BIN): $(SUPER_TB) $(FIXED_TLB)
	@mkdir -p $(SUPER_FIXED_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) --Mdir $(SUPER_FIXED_DIR) $(SUPER_TB) $(FIXED_TLB)

$(SUPER_ENH_DIR)/$(SUPER_BIN): $(SUPER_TB) $(FIXED_SP_TLB)
	@mkdir -p $(SUPER_ENH_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) --Mdir $(SUPER_ENH_DIR) $(SUPER_TB) $(FIXED_SP_TLB)

run-super-fixed: build-super-fixed
	@$(SUPER_FIXED_DIR)/$(SUPER_BIN) | tee $(SUPER_FIXED_DIR)/run.log

run-super-enh: build-super-enh
	@$(SUPER_ENH_DIR)/$(SUPER_BIN) | tee $(SUPER_ENH_DIR)/run.log

compare-super: run-super-fixed run-super-enh
	@fixed_dup=$$(grep -o 'RESULT_SUPER_DUPLICATE=[01]' $(SUPER_FIXED_DIR)/run.log | tail -1 | cut -d= -f2); \
	enh_dup=$$(grep -o 'RESULT_SUPER_DUPLICATE=[01]' $(SUPER_ENH_DIR)/run.log | tail -1 | cut -d= -f2); \
	echo "fixed RESULT_SUPER_DUPLICATE=$$fixed_dup"; \
	echo "fixed_sp_dedup RESULT_SUPER_DUPLICATE=$$enh_dup"; \
	if [ -z "$$fixed_dup" ] || [ -z "$$enh_dup" ]; then \
		echo "ERROR: could not parse RESULT_SUPER_DUPLICATE from logs"; \
		exit 2; \
	fi; \
	if [ "$$fixed_dup" = "1" ] && [ "$$enh_dup" = "0" ]; then \
		echo "PASS: enhanced fixed TLB prevents superpage duplicate insertion"; \
	else \
		echo "FAIL: expected fixed=1 and fixed_sp_dedup=0"; \
		exit 1; \
	fi

build-tmq4-orig: $(TMQ4_ORIG_DIR)/$(TMQ_BIN)

build-tmq8-orig: $(TMQ8_ORIG_DIR)/$(TMQ_BIN)

build-tmq4-enh: $(TMQ4_ENH_DIR)/$(TMQ_BIN)

build-tmq8-enh: $(TMQ8_ENH_DIR)/$(TMQ_BIN)

$(TMQ4_ORIG_DIR)/$(TMQ_BIN): $(TMQ_TB) $(TMQ_ORIG_SRC)
	@mkdir -p $(TMQ4_ORIG_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) -DTMQ_SIZE=4 --Mdir $(TMQ4_ORIG_DIR) $(TMQ_TB) $(TMQ_ORIG_SRC)

$(TMQ8_ORIG_DIR)/$(TMQ_BIN): $(TMQ_TB) $(TMQ_ORIG_SRC)
	@mkdir -p $(TMQ8_ORIG_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) -DTMQ_SIZE=8 --Mdir $(TMQ8_ORIG_DIR) $(TMQ_TB) $(TMQ_ORIG_SRC)

$(TMQ4_ENH_DIR)/$(TMQ_BIN): $(TMQ_TB) $(TMQ_ENH_SRC)
	@mkdir -p $(TMQ4_ENH_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) -DTMQ_SIZE=4 --Mdir $(TMQ4_ENH_DIR) $(TMQ_TB) $(TMQ_ENH_SRC)

$(TMQ8_ENH_DIR)/$(TMQ_BIN): $(TMQ_TB) $(TMQ_ENH_SRC)
	@mkdir -p $(TMQ8_ENH_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) -DTMQ_SIZE=8 --Mdir $(TMQ8_ENH_DIR) $(TMQ_TB) $(TMQ_ENH_SRC)

run-tmq4-orig: build-tmq4-orig
	@$(TMQ4_ORIG_DIR)/$(TMQ_BIN) | tee $(TMQ4_ORIG_DIR)/run.log

run-tmq8-orig: build-tmq8-orig
	@$(TMQ8_ORIG_DIR)/$(TMQ_BIN) | tee $(TMQ8_ORIG_DIR)/run.log

run-tmq4-enh: build-tmq4-enh
	@$(TMQ4_ENH_DIR)/$(TMQ_BIN) | tee $(TMQ4_ENH_DIR)/run.log

run-tmq8-enh: build-tmq8-enh
	@$(TMQ8_ENH_DIR)/$(TMQ_BIN) | tee $(TMQ8_ENH_DIR)/run.log

compare-tmq-param: run-tmq4-orig run-tmq8-orig run-tmq4-enh run-tmq8-enh
	@orig4=$$(grep -o 'RESULT_TMQ_PARAM=[A-Z]*' $(TMQ4_ORIG_DIR)/run.log | tail -1 | cut -d= -f2); \
	orig8=$$(grep -o 'RESULT_TMQ_PARAM=[A-Z]*' $(TMQ8_ORIG_DIR)/run.log | tail -1 | cut -d= -f2); \
	enh4=$$(grep -o 'RESULT_TMQ_PARAM=[A-Z]*' $(TMQ4_ENH_DIR)/run.log | tail -1 | cut -d= -f2); \
	enh8=$$(grep -o 'RESULT_TMQ_PARAM=[A-Z]*' $(TMQ8_ENH_DIR)/run.log | tail -1 | cut -d= -f2); \
	echo "orig size4 RESULT_TMQ_PARAM=$$orig4"; \
	echo "orig size8 RESULT_TMQ_PARAM=$$orig8"; \
	echo "tmq_param size4 RESULT_TMQ_PARAM=$$enh4"; \
	echo "tmq_param size8 RESULT_TMQ_PARAM=$$enh8"; \
	if [ -z "$$orig4" ] || [ -z "$$orig8" ] || [ -z "$$enh4" ] || [ -z "$$enh8" ]; then \
		echo "ERROR: could not parse RESULT_TMQ_PARAM from logs"; \
		exit 2; \
	fi; \
	if [ "$$orig4" = "PASS" ] && [ "$$orig8" = "FAIL" ] && [ "$$enh4" = "PASS" ] && [ "$$enh8" = "PASS" ]; then \
		echo "PASS: tmq_param fixes SIZE!=4 free-count bug"; \
	else \
		echo "FAIL: expected orig4=PASS orig8=FAIL enh4=PASS enh8=PASS"; \
		exit 1; \
	fi

build-sqb-issue-orig: $(SQB_ISSUE_ORIG_DIR)/$(SQB_ISSUE_BIN)

build-sqb-issue-opt: $(SQB_ISSUE_OPT_DIR)/$(SQB_ISSUE_BIN)

$(SQB_ISSUE_ORIG_DIR)/$(SQB_ISSUE_BIN): $(SQB_ISSUE_TB) $(SQB_ORIG_SRC)
	@mkdir -p $(SQB_ISSUE_ORIG_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) --Mdir $(SQB_ISSUE_ORIG_DIR) $(SQB_ISSUE_TB) $(SQB_ORIG_SRC)

$(SQB_ISSUE_OPT_DIR)/$(SQB_ISSUE_BIN): $(SQB_ISSUE_TB) $(SQB_OPT_SRC)
	@mkdir -p $(SQB_ISSUE_OPT_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) --Mdir $(SQB_ISSUE_OPT_DIR) $(SQB_ISSUE_TB) $(SQB_OPT_SRC)

run-sqb-issue-orig: build-sqb-issue-orig
	@$(SQB_ISSUE_ORIG_DIR)/$(SQB_ISSUE_BIN) | tee $(SQB_ISSUE_ORIG_DIR)/run.log

run-sqb-issue-opt: build-sqb-issue-opt
	@$(SQB_ISSUE_OPT_DIR)/$(SQB_ISSUE_BIN) | tee $(SQB_ISSUE_OPT_DIR)/run.log

compare-sqb-issue: run-sqb-issue-orig run-sqb-issue-opt
	@orig_res=$$(grep -o 'RESULT_SQB_ISSUE=[A-Z_]*' $(SQB_ISSUE_ORIG_DIR)/run.log | tail -1 | cut -d= -f2); \
	opt_res=$$(grep -o 'RESULT_SQB_ISSUE=[A-Z_]*' $(SQB_ISSUE_OPT_DIR)/run.log | tail -1 | cut -d= -f2); \
	echo "orig RESULT_SQB_ISSUE=$$orig_res"; \
	echo "issue_opt RESULT_SQB_ISSUE=$$opt_res"; \
	if [ -z "$$orig_res" ] || [ -z "$$opt_res" ]; then \
		echo "ERROR: could not parse RESULT_SQB_ISSUE from logs"; \
		exit 2; \
	fi; \
	if [ "$$orig_res" = "FAIL_GAP" ] && [ "$$opt_res" = "PASS" ]; then \
		echo "PASS: issue_opt keeps store valid asserted under sustained stall"; \
	else \
		echo "FAIL: expected orig=FAIL_GAP and issue_opt=PASS"; \
		exit 1; \
	fi

build-bht-fwd-orig: $(BHT_FWD_ORIG_DIR)/$(BHT_FWD_BIN)

build-bht-fwd-opt: $(BHT_FWD_OPT_DIR)/$(BHT_FWD_BIN)

$(BHT_FWD_ORIG_DIR)/$(BHT_FWD_BIN): $(BHT_FWD_TB) $(BHT_ORIG_SRC)
	@mkdir -p $(BHT_FWD_ORIG_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) --Mdir $(BHT_FWD_ORIG_DIR) $(BHT_FWD_TB) $(BHT_ORIG_SRC)

$(BHT_FWD_OPT_DIR)/$(BHT_FWD_BIN): $(BHT_FWD_TB) $(BHT_FWD_SRC)
	@mkdir -p $(BHT_FWD_OPT_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) --Mdir $(BHT_FWD_OPT_DIR) $(BHT_FWD_TB) $(BHT_FWD_SRC)

run-bht-fwd-orig: build-bht-fwd-orig
	@$(BHT_FWD_ORIG_DIR)/$(BHT_FWD_BIN) | tee $(BHT_FWD_ORIG_DIR)/run.log

run-bht-fwd-opt: build-bht-fwd-opt
	@$(BHT_FWD_OPT_DIR)/$(BHT_FWD_BIN) | tee $(BHT_FWD_OPT_DIR)/run.log

compare-bht-fwd: run-bht-fwd-orig run-bht-fwd-opt
	@orig_res=$$(grep -o 'RESULT_BHT_FWD=[A-Z_]*' $(BHT_FWD_ORIG_DIR)/run.log | tail -1 | cut -d= -f2); \
	opt_res=$$(grep -o 'RESULT_BHT_FWD=[A-Z_]*' $(BHT_FWD_OPT_DIR)/run.log | tail -1 | cut -d= -f2); \
	echo "orig RESULT_BHT_FWD=$$orig_res"; \
	echo "bht_fwd RESULT_BHT_FWD=$$opt_res"; \
	if [ -z "$$orig_res" ] || [ -z "$$opt_res" ]; then \
		echo "ERROR: could not parse RESULT_BHT_FWD from logs"; \
		exit 2; \
	fi; \
	if [ "$$orig_res" = "FAIL_STALE" ] && [ "$$opt_res" = "PASS" ]; then \
		echo "PASS: bht_fwd removes same-index training lag"; \
	else \
		echo "FAIL: expected orig=FAIL_STALE and bht_fwd=PASS"; \
		exit 1; \
	fi

build-bt-arb: $(BT_ARB_DIR)/$(BT_ARB_BIN)

$(BT_ARB_DIR)/$(BT_ARB_BIN): $(BT_ARB_TB) $(BT_ARB_SRC)
	@mkdir -p $(BT_ARB_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) --Mdir $(BT_ARB_DIR) $(BT_ARB_TB) $(BT_ARB_SRC)

run-bt-arb: build-bt-arb
	@$(BT_ARB_DIR)/$(BT_ARB_BIN) | tee $(BT_ARB_DIR)/run.log

build-pw-arb: $(PW_ARB_DIR)/$(PW_ARB_BIN)

$(PW_ARB_DIR)/$(PW_ARB_BIN): $(PW_ARB_TB) $(PW_ARB_SRC)
	@mkdir -p $(PW_ARB_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) --Mdir $(PW_ARB_DIR) $(PW_ARB_TB) $(PW_ARB_SRC)

run-pw-arb: build-pw-arb
	@$(PW_ARB_DIR)/$(PW_ARB_BIN) | tee $(PW_ARB_DIR)/run.log

build-hardfloat: $(HARDFLOAT_BUILD_DIR)/$(HARDFLOAT_BIN)

$(HARDFLOAT_BUILD_DIR)/$(HARDFLOAT_BIN): $(HARDFLOAT_TB) $(HARDFLOAT_SRCS)
	@mkdir -p $(HARDFLOAT_BUILD_DIR)
	$(VERILATOR) $(VERILATOR_FLAGS) -I$(HARDFLOAT_DIR) --Mdir $(HARDFLOAT_BUILD_DIR) $(HARDFLOAT_TB) $(HARDFLOAT_SRCS)

run-hardfloat: build-hardfloat
	@$(HARDFLOAT_BUILD_DIR)/$(HARDFLOAT_BIN) | tee $(HARDFLOAT_BUILD_DIR)/run.log

clean:
	rm -rf $(BUILD_DIR)
