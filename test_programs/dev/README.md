# Dev Tests

This folder contains developer-oriented micro tests that are separate from normal program tests.

## TLB duplicate insertion test

`tlb_dup_tb.sv` reproduces a duplicated TLB-entry scenario and compares:
- `src/TLB.sv` (original)
- `src/TLB_fixed.sv` (fixed)

Run from repository root:

```bash
make -C test_programs/dev compare
```

Expected output:
- original: `RESULT_DUPLICATE=1`
- fixed: `RESULT_DUPLICATE=0`

## TLB superpage duplicate insertion test

`tlb_super_dup_tb.sv` reproduces duplicated insertion for superpage refill in the same set and compares:
- `src/TLB_fixed.sv` (current fixed baseline)
- `src/TLB_fixed_sp_dedup.sv` (enhanced fixed variant)

Run from repository root:

```bash
make -C test_programs/dev compare-super
```

Expected output:
- fixed: `RESULT_SUPER_DUPLICATE=1`
- fixed_sp_dedup: `RESULT_SUPER_DUPLICATE=0`

## HardFloat external integration smoke test

`hardfloat_ext_tb.sv` is a direct HardFloat module smoke test that validates:
- `addRecFN`
- `mulRecFN`
- `iNToRecFN`
- `recFNToIN`
- `compareRecFN`
- `divSqrtRecFN_small`

Run from repository root:

```bash
make -C test_programs/dev run-hardfloat
```

Use an external HardFloat directory:

```bash
make -C test_programs/dev run-hardfloat HARDFLOAT_DIR=/abs/path/to/hardfloat
```

## BranchPredictor BT-update arbitration micro test

`bt_update_arb_tb.sv` validates the BT update arbitration behavior used by the frontend:
- explicit source priority
- same-cycle multi-source updates are buffered instead of being dropped

Run from repository root:

```bash
make -C test_programs/dev run-bt-arb
```

Expected output includes:
- `RESULT_BT_ARB=PASS`

Build top-level with different BranchPredictor implementations:

```bash
make soomrv BRANCH_PRED_IMPL=orig
make soomrv BRANCH_PRED_IMPL=bt_arb
```

## PageWalker request arbitration micro test

`pagewalk_req_arb_tb.sv` validates the explicit PageWalker request-selection policy:
- selection starts from a configurable pointer (round-robin scan)
- no reliance on implicit "last-valid-wins" behavior

Run from repository root:

```bash
make -C test_programs/dev run-pw-arb
```

Expected output includes:
- `RESULT_PAGEWALK_REQ_ARB=PASS`

Build top-level with different PageWalker implementations:

```bash
make soomrv PAGEWALKER_IMPL=orig
make soomrv PAGEWALKER_IMPL=pw_arb
```

## TLBMissQueue parameterization test

`tlb_miss_queue_param_tb.sv` validates `TLBMissQueue` free-count behavior under queue-size variants:
- `SIZE=4`
- `SIZE=8`

Run from repository root:

```bash
make -C test_programs/dev compare-tmq-param
```

Expected output:
- original `TLBMissQueue.sv`: `SIZE=4` passes, `SIZE=8` fails
- enhanced `TLBMissQueue_param.sv`: both `SIZE=4/8` pass

## StoreQueueBackend issue-cadence test

`store_queue_backend_issue_tb.sv` validates store-issue behavior under sustained downstream stall:
- original `StoreQueueBackend.sv` drops `OUT_uopSt.valid` every other cycle (gap)
- enhanced `StoreQueueBackend_issue_opt.sv` keeps `OUT_uopSt.valid` asserted continuously

Run from repository root:

```bash
make -C test_programs/dev compare-sqb-issue
```

Expected output:
- original: `RESULT_SQB_ISSUE=FAIL_GAP`
- issue_opt: `RESULT_SQB_ISSUE=PASS`

## BHT write-after-read forwarding test

`bht_write_read_forward_tb.sv` validates consecutive same-index training behavior in the base predictor:
- original `BranchPredictionTable.sv` samples stale counter state and shows delayed convergence
- enhanced `BranchPredictionTable_bht_fwd.sv` forwards same-cycle writeback and converges immediately

Run from repository root:

```bash
make -C test_programs/dev compare-bht-fwd
```

Expected output:
- original: `RESULT_BHT_FWD=FAIL_STALE`
- bht_fwd: `RESULT_BHT_FWD=PASS`

## TLB implementation switch in top-level build

The top-level `Makefile` now supports:

```bash
make soomrv TLB_IMPL=orig
make soomrv TLB_IMPL=fixed
make soomrv TLB_IMPL=fixed_sp_dedup
```

Additional implementation switches used by recent optimizations:

```bash
make soomrv TLBMISSQ_IMPL=orig
make soomrv TLBMISSQ_IMPL=tmq_param
make soomrv HARDCODE4_IMPL=orig
make soomrv HARDCODE4_IMPL=param
make soomrv LS_ISSUE_IMPL=orig
make soomrv LS_ISSUE_IMPL=issue_opt
make soomrv BHT_IMPL=orig
make soomrv BHT_IMPL=bht_fwd
```
