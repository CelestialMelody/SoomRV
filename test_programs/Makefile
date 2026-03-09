ROOT_DIR ?= ..
ROOT_ABS := $(abspath $(ROOT_DIR))
SIM ?= $(ROOT_ABS)/obj_dir/VTop

# Runnable tests in this directory only.
# This excludes linux-related subdirectories by construction.
ALL_TEST_INPUTS := $(sort $(wildcard *.s) $(wildcard *.S) $(wildcard *.elf))
EXCLUDE_TESTS ?= entry.s
TEST_INPUTS := $(filter-out $(EXCLUDE_TESTS),$(ALL_TEST_INPUTS))

.PHONY: all test_all test list-tests check-sim run-one

all: test_all

# Backward-compatible alias.
test: test_all

check-sim:
	@test -x "$(SIM)" || { \
		echo "Simulator not found: $(SIM)"; \
		echo "Run 'make soomrv' at repository root first."; \
		exit 1; \
	}

list-tests:
	@for t in $(TEST_INPUTS); do \
		printf "%-24s -> %s\n" "$${t%.*}" "$$t"; \
	done

run-one: check-sim
	@test -n "$(TEST_FILE)" || { \
		echo "Missing TEST_FILE, internal make target misuse."; \
		exit 2; \
	}
	@set -eu; \
	t="$(TEST_FILE)"; \
	test_path="test_programs/$$t"; \
	printf "\n%s\n" "========================================================================"; \
	printf ">>> RUN TEST: %s\n" "$$t"; \
	printf "%s\n" "------------------------------------------------------------------------"; \
	if cd "$(ROOT_ABS)" && "$(SIM)" "$$test_path"; then \
		printf "%s\n" ">>> RESULT: PASS ($$t)"; \
	else \
		rc="$$?"; \
		printf "%s\n" ">>> RESULT: FAIL ($$t) exit=$$rc"; \
		printf "%s\n" "========================================================================"; \
		exit "$$rc"; \
	fi; \
	printf "%s\n" "========================================================================"

test_all: check-sim
	@set -eu; \
	total="$(words $(TEST_INPUTS))"; \
	if [ "$$total" -eq 0 ]; then \
		echo "No tests found."; \
		exit 0; \
	fi; \
	i=1; \
	failed=0; \
	for t in $(TEST_INPUTS); do \
		printf "\n\n#################### [%d/%d] %s ####################\n" "$$i" "$$total" "$$t"; \
		if ! $(MAKE) --no-print-directory run-one TEST_FILE="$$t"; then \
			failed=1; \
		fi; \
		i=$$((i + 1)); \
	done; \
	echo; \
	if [ "$$failed" -ne 0 ]; then \
		echo "test_all finished with failures."; \
		exit 1; \
	fi; \
	echo "test_all finished successfully."

define GEN_TEST_TARGET
.PHONY: $(1)
$(1):
	@$(MAKE) --no-print-directory run-one TEST_FILE=$(2)

.PHONY: $(2)
$(2): $(1)
endef

$(foreach t,$(TEST_INPUTS),$(eval $(call GEN_TEST_TARGET,$(basename $(t)),$(t))))
