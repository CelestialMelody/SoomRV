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

## TLB implementation switch in top-level build

The top-level `Makefile` now supports:

```bash
make soomrv TLB_IMPL=orig
make soomrv TLB_IMPL=fixed
```
