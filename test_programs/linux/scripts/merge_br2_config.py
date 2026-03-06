#!/usr/bin/env python3
"""
Analyze and merge Buildroot config for SoomRV.

Usage:
  # Generate overlay fragment from repo's buildroot.config (SoomRV-relevant options only)
  python merge_br2_config.py extract -i ../buildroot.config -o ../soomrv_br2_overrides.config

  # Compare two Buildroot .config files and report differences
  python merge_br2_config.py diff -a ../buildroot.config -b /path/to/buildroot/.config

  # Full: extract overlay, then you can in Makefile:
  #   make qemu_riscv32_virt_defconfig && cat soomrv_br2_overrides.config >> .config && make olddefconfig
"""

import argparse
import re
import sys
from pathlib import Path

# Options we want to force from the repo's buildroot.config when using defconfig.
# Add prefixes or exact BR2_ names. Options not listed are left to defconfig/defaults.
SOOMRV_OVERRIDE_PREFIXES = (
    "BR2_ARCH",
    "BR2_GCC_TARGET_ABI",
    "BR2_RISCV_",
    "BR2_LINUX_KERNEL_USE_CUSTOM_CONFIG",
    "BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE",
    "BR2_LINUX_KERNEL_VERSION",
    "BR2_LINUX_KERNEL_LATEST_VERSION",
    "BR2_LINUX_KERNEL_CUSTOM_VERSION",
    "BR2_LINUX_KERNEL_CUSTOM_VERSION_VALUE",
    "BR2_LINUX_KERNEL_DEFCONFIG",
    "BR2_LINUX_KERNEL_IMAGE",
    "BR2_LINUX_KERNEL_GZIP",
    "BR2_PACKAGE_BUSYBOX_CONFIG",
    "BR2_TARGET_OPENSBI",
    "BR2_TARGET_ROOTFS_CPIO",
    "BR2_TARGET_ROOTFS_INITRAMFS",
    "BR2_TARGET_ROOTFS_EXT2",
)


def parse_config(path: Path) -> dict[str, str]:
    """Parse Buildroot .config: key=value or '# CONFIG_FOO is not set' -> key=None."""
    cfg = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") and " is not set" not in line:
                continue
            if line.startswith("# ") and " is not set" in line:
                # "# BR2_FOO is not set"
                m = re.match(r"# (BR2_\S+) is not set", line)
                if m:
                    cfg[m.group(1)] = "# is not set"
                continue
            if "=" in line:
                k, v = line.split("=", 1)
                k = k.strip()
                cfg[k] = v.strip()
    return cfg


def matches_override(key: str) -> bool:
    return any(key == p or key.startswith(p + "_") or (p.endswith("_") and key.startswith(p)) for p in SOOMRV_OVERRIDE_PREFIXES)


def extract_overlay(repo_config: Path, out_path: Path) -> None:
    """Write a fragment containing only SoomRV-relevant options from repo_config."""
    cfg = parse_config(repo_config)
    lines = [
        "# SoomRV Buildroot overlay: options extracted from repo buildroot.config",
        "# Append to buildroot/.config after: make qemu_riscv32_virt_defconfig",
        "# Then run: make olddefconfig",
        "",
    ]
    for k in sorted(cfg.keys()):
        if not k.startswith("BR2_"):
            continue
        if not matches_override(k):
            continue
        v = cfg[k]
        if v == "# is not set":
            lines.append(f"# {k} is not set")
        else:
            lines.append(f'{k}={v}')
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {len(lines) - 4} options to {out_path}", file=sys.stderr)


def diff_config(path_a: Path, path_b: Path) -> None:
    """Print differences between two Buildroot .config files."""
    a = parse_config(path_a)
    b = parse_config(path_b)
    all_keys = sorted(set(a) | set(b))
    only_a = []
    only_b = []
    diff_val = []
    for k in all_keys:
        va, vb = a.get(k), b.get(k)
        if k not in b:
            only_a.append((k, va))
        elif k not in a:
            only_b.append((k, vb))
        elif va != vb:
            diff_val.append((k, va, vb))

    def show(title: str, items: list, max_show: int = 30) -> None:
        print(f"\n--- {title} ({len(items)} total) ---")
        for i, item in enumerate(items[:max_show]):
            print("  ", item)
        if len(items) > max_show:
            print(f"  ... and {len(items) - max_show} more")

    show("Only in A (first file)", only_a)
    show("Only in B (second file)", only_b)
    show("Different value", diff_val)

    # SoomRV-relevant differences
    soomrv_diff = [(k, va, vb) for k, va, vb in diff_val if matches_override(k)]
    if soomrv_diff:
        print("\n--- SoomRV-relevant options (different value) ---")
        for k, va, vb in soomrv_diff:
            print(f"  {k}")
            print(f"    A: {va}")
            print(f"    B: {vb}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Buildroot config analysis/merge for SoomRV")
    sub = parser.add_subparsers(dest="cmd", required=True)
    # extract
    ex = sub.add_parser("extract", help="Extract SoomRV-relevant options into an overlay fragment")
    ex.add_argument("-i", "--input", type=Path, default=Path("../buildroot.config"), help="Repo buildroot.config")
    ex.add_argument("-o", "--output", type=Path, default=Path("../soomrv_br2_overrides.config"), help="Output fragment")
    # diff
    di = sub.add_parser("diff", help="Compare two Buildroot .config files")
    di.add_argument("-a", "--config-a", type=Path, required=True, help="First .config (e.g. repo buildroot.config)")
    di.add_argument("-b", "--config-b", type=Path, required=True, help="Second .config (e.g. buildroot/.config)")

    args = parser.parse_args()
    if args.cmd == "extract":
        extract_overlay(args.input, args.output)
    elif args.cmd == "diff":
        diff_config(args.config_a, args.config_b)


if __name__ == "__main__":
    main()
