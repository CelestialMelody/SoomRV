#!/usr/bin/env python3
"""Run ISA regression tests against SoomRV.

Default behavior remains compatible with historical usage:
    python scripts/test_suite.py
which scans `riscv-tests/isa` and runs discovered ELF tests with
`./obj_dir/VTop -t <test>`.
"""

from __future__ import annotations

import argparse
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from typing import Dict, Iterable, List, Tuple


DEFAULT_CATEGORIES = [
    "rv32mi",
    "rv32si",
    "rv32ui",
    "rv32um",
    "rv32uc",
    "rv32ua",
    "rv32uzba",
    "rv32uzbb",
    "rv32uzbs",
]

DEFAULT_EXCLUDES = {"rv32ui-p-ma_data", "rv32ui-v-ma_data"}

# Known unsupported/incompatible tests for the current SoomRV configuration.
# These can be overridden via --no-skip-unsupported when strict checking is needed.
UNSUPPORTED_TESTS: Dict[str, str] = {
    # SoomRV/Spike cosim is configured with PMP disabled (set_pmp_num(0)).
    "rv32mi-p-pmpaddr": "PMP not implemented/enabled in current SoomRV configuration",
    # Cosim currently enforces strict minstret equality; this test is sensitive to
    # counter write/inhibit micro-architectural semantics and is known to mismatch.
    "rv32mi-p-instret_overflow": "known minstret/cosim semantic mismatch",
}


class _Color:
    green = "\033[32m" if sys.stdout.isatty() else ""
    red = "\033[31m" if sys.stdout.isatty() else ""
    reset = "\033[0m" if sys.stdout.isatty() else ""


@dataclass
class TestResult:
    path: pathlib.Path
    passed: bool
    stdout: str
    stderr: str
    returncode: int
    duration_sec: float
    timed_out: bool = False


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run rv32 ISA tests on SoomRV.")
    parser.add_argument(
        "test_dir",
        nargs="?",
        default="riscv-tests/isa",
        help="Directory containing built ELF tests (default: %(default)s).",
    )
    parser.add_argument(
        "--binary",
        default="./obj_dir/VTop",
        help="Simulator binary to execute (default: %(default)s).",
    )
    parser.add_argument(
        "--categories",
        default=",".join(DEFAULT_CATEGORIES),
        help=(
            "Comma-separated category filters, matched on file name "
            "(default: %(default)s)."
        ),
    )
    parser.add_argument(
        "--max-tests-per-category",
        type=int,
        default=0,
        help="Limit tests per category (0 means no limit).",
    )
    parser.add_argument(
        "--exclude",
        action="append",
        default=[],
        help="Exclude specific test basename (can be repeated).",
    )
    parser.add_argument(
        "--debug-on-fail",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Rerun failed tests with '-x 0' and print the tail output.",
    )
    parser.add_argument(
        "--timeout-sec",
        type=int,
        default=0,
        help="Per-test timeout in seconds (0 means no timeout).",
    )
    parser.add_argument(
        "--heartbeat-sec",
        type=int,
        default=15,
        help="Print progress heartbeat for long-running tests (0 disables).",
    )
    parser.add_argument(
        "--skip-unsupported",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Skip known unsupported/incompatible tests (default: enabled).",
    )
    parser.add_argument(
        "--objcopy-fallback",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="If riscv32-unknown-elf-objcopy is missing, shim it with host objcopy.",
    )
    return parser.parse_args()


def is_elf(path: pathlib.Path) -> bool:
    if not path.is_file() or path.stat().st_size == 0:
        return False
    try:
        with path.open("rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False


def discover_elf_tests(test_dir: pathlib.Path) -> List[pathlib.Path]:
    tests: List[pathlib.Path] = []
    for root, _, files in os.walk(test_dir):
        root_path = pathlib.Path(root)
        for name in files:
            candidate = root_path / name
            if is_elf(candidate):
                tests.append(candidate)
    tests.sort()
    return tests


def run_once(
    binary: str,
    test: pathlib.Path,
    trace_start: int | None,
    timeout_sec: int,
    heartbeat_sec: int,
    run_env: Dict[str, str],
) -> TestResult:
    cmd = [binary]
    if trace_start is not None:
        cmd.extend(["-x", str(trace_start)])
    cmd.extend(["-t", str(test)])
    start = time.monotonic()
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=run_env,
    )
    next_heartbeat = start + heartbeat_sec if heartbeat_sec > 0 else float("inf")
    timed_out = False

    while True:
        ret = proc.poll()
        now = time.monotonic()
        if ret is not None:
            break

        elapsed = now - start
        if timeout_sec > 0 and elapsed > timeout_sec:
            timed_out = True
            proc.kill()
            break

        if heartbeat_sec > 0 and now >= next_heartbeat:
            print(f" ... {int(elapsed)}s", flush=True)
            next_heartbeat += heartbeat_sec

        time.sleep(0.2)

    out, err = proc.communicate()
    out = out or ""
    err = err or ""
    duration = time.monotonic() - start
    # Historical pass string is "PASSED test with return code ..."
    passed = (not timed_out) and ("PASSED" in out) and proc.returncode == 0
    return TestResult(
        path=test,
        passed=passed,
        stdout=out,
        stderr=err,
        returncode=proc.returncode if proc.returncode is not None else 124,
        duration_sec=duration,
        timed_out=timed_out,
    )


def tail_lines(text: str, n: int = 32) -> str:
    lines = text.splitlines()
    return "\n".join(lines[-n:])


def iter_group(
    tests: Iterable[pathlib.Path], category: str, max_per_category: int
) -> List[pathlib.Path]:
    matched = [t for t in tests if category in t.name]
    if max_per_category > 0:
        matched = matched[:max_per_category]
    return matched


def build_run_env(objcopy_fallback: bool) -> Tuple[Dict[str, str], str | None]:
    run_env = os.environ.copy()
    shim_dir = None

    if objcopy_fallback and shutil.which("riscv32-unknown-elf-objcopy") is None:
        host_objcopy = shutil.which("objcopy") or shutil.which("llvm-objcopy")
        if host_objcopy is not None:
            shim_dir = tempfile.mkdtemp(prefix="soomrv-objcopy-shim-")
            shim_path = pathlib.Path(shim_dir) / "riscv32-unknown-elf-objcopy"
            os.symlink(host_objcopy, shim_path)
            run_env["PATH"] = f"{shim_dir}:{run_env.get('PATH', '')}"

    return run_env, shim_dir


def main() -> int:
    args = parse_args()

    binary = pathlib.Path(args.binary)
    test_dir = pathlib.Path(args.test_dir)
    categories = [c.strip() for c in args.categories.split(",") if c.strip()]
    excludes = set(DEFAULT_EXCLUDES)
    excludes.update(args.exclude)
    skipped_unsupported: List[pathlib.Path] = []

    if not binary.exists():
        print(f"error: simulator not found: {binary}", file=sys.stderr)
        return 2
    if not test_dir.exists():
        print(f"error: test directory not found: {test_dir}", file=sys.stderr)
        return 2

    discovered = discover_elf_tests(test_dir)
    if not discovered:
        print(
            "error: no ELF tests discovered. "
            "If you just cloned riscv-tests, build them first (e.g. `make -C <repo> isa`).",
            file=sys.stderr,
        )
        return 2

    filtered = [t for t in discovered if t.name not in excludes]
    if args.skip_unsupported:
        temp_filtered = []
        for t in filtered:
            if t.name in UNSUPPORTED_TESTS:
                skipped_unsupported.append(t)
            else:
                temp_filtered.append(t)
        filtered = temp_filtered

    run_env, shim_dir = build_run_env(args.objcopy_fallback)
    if shim_dir is not None:
        print("info: using objcopy fallback shim for riscv32-unknown-elf-objcopy")

    any_failed = False
    executed = 0

    for category in categories:
        tests = iter_group(filtered, category, args.max_tests_per_category)
        if not tests:
            continue
        print(f"\n== category: {category} ({len(tests)} tests) ==")
        for test in tests:
            print(f"running {test}:", end="", flush=True)
            result = run_once(
                str(binary),
                test,
                trace_start=None,
                timeout_sec=args.timeout_sec,
                heartbeat_sec=args.heartbeat_sec,
                run_env=run_env,
            )
            executed += 1
            if result.passed:
                print(f" {_Color.green}passed{_Color.reset} ({result.duration_sec:.1f}s)")
                continue

            any_failed = True
            if result.timed_out:
                print(f" {_Color.red}failed{_Color.reset} (timeout after {result.duration_sec:.1f}s)")
            else:
                print(f" {_Color.red}failed{_Color.reset} (rc={result.returncode}, {result.duration_sec:.1f}s)")

            if args.debug_on_fail and not result.timed_out:
                debug_result = run_once(
                    str(binary),
                    test,
                    trace_start=0,
                    timeout_sec=args.timeout_sec,
                    heartbeat_sec=0,
                    run_env=run_env,
                )
                merged = (debug_result.stdout or "") + (debug_result.stderr or "")
                print(tail_lines(merged, n=32))
                print()

    if executed == 0:
        print("error: no tests matched selected categories.", file=sys.stderr)
        if shim_dir is not None:
            shutil.rmtree(shim_dir, ignore_errors=True)
        return 2

    if skipped_unsupported:
        print("\nskipped unsupported tests:")
        for t in sorted(skipped_unsupported):
            reason = UNSUPPORTED_TESTS.get(t.name, "unspecified")
            print(f"  - {t} ({reason})")

    if shim_dir is not None:
        shutil.rmtree(shim_dir, ignore_errors=True)

    if any_failed:
        return 1
    print(f"\nall selected tests passed ({executed} total).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
