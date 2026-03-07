#!/usr/bin/env bash
set -euo pipefail

# Build and validate SoomRV Linux image with upstream OpenSBI overlay.
# Usage:
#   scripts/validate_opensbi_upstream.sh
#   scripts/validate_opensbi_upstream.sh --buildroot-version 2026.02
#   scripts/validate_opensbi_upstream.sh --skip-clean

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINUX_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_DIR="$(cd "${LINUX_DIR}/../.." && pwd)"
OVERLAY_FILE="${LINUX_DIR}/soomrv_br2_overrides.opensbi_upstream.config"
BUILDROOT_VERSION="2026.02"
DO_CLEAN=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --buildroot-version)
            BUILDROOT_VERSION="${2:-}"
            shift 2
            ;;
        --skip-clean)
            DO_CLEAN=0
            shift
            ;;
        -h|--help)
            cat <<'EOF'
Usage: scripts/validate_opensbi_upstream.sh [options]

Options:
  --buildroot-version <ver>  Buildroot tag/version (default: 2026.02)
  --skip-clean               Skip "make clean" before build
  -h, --help                 Show this help
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [[ ! -f "${OVERLAY_FILE}" ]]; then
    echo "Missing overlay: ${OVERLAY_FILE}" >&2
    exit 1
fi

mkdir -p "${REPO_DIR}/tmp"
TS="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${REPO_DIR}/tmp/soomrv-linux-opensbi-upstream-${TS}.log"

pushd "${LINUX_DIR}" >/dev/null

echo "[1/5] Build with upstream OpenSBI overlay"
echo "      overlay : ${OVERLAY_FILE}"
echo "      version : ${BUILDROOT_VERSION}"
echo "      log     : ${LOG_FILE}"

if [[ ${DO_CLEAN} -eq 1 ]]; then
    make clean
fi

make SOOMRV_OVERLAY="$(basename "${OVERLAY_FILE}")" BUILDROOT_VERSION="${BUILDROOT_VERSION}" -j"$(nproc)" \
    2>&1 | tee "${LOG_FILE}"

echo "[2/5] Validate effective Buildroot config"
CONF="${LINUX_DIR}/buildroot/.config"
if [[ ! -f "${CONF}" ]]; then
    echo "Missing Buildroot config: ${CONF}" >&2
    exit 1
fi

grep -n '^BR2_TARGET_OPENSBI_CUSTOM_GIT=y$' "${CONF}" >/dev/null
grep -n '^BR2_TARGET_OPENSBI_CUSTOM_REPO_URL="https://github.com/riscv-software-src/opensbi"$' "${CONF}" >/dev/null
grep -n '^BR2_TARGET_OPENSBI_CUSTOM_REPO_VERSION="master"$' "${CONF}" >/dev/null
grep -n '^BR2_TARGET_OPENSBI_PLAT="template"$' "${CONF}" >/dev/null

echo "[3/5] Validate image artifacts"
IMAGES_DIR="${LINUX_DIR}/buildroot/output/images"
for f in fw_jump.bin fw_payload.bin fw_dynamic.bin Image rootfs.cpio; do
    if [[ ! -f "${IMAGES_DIR}/${f}" ]]; then
        echo "Missing artifact: ${IMAGES_DIR}/${f}" >&2
        exit 1
    fi
done

if [[ ! -f "${LINUX_DIR}/linux_image.elf" ]]; then
    echo "Missing packed image: ${LINUX_DIR}/linux_image.elf" >&2
    exit 1
fi

echo "[4/5] Scan build log for key OpenSBI milestones"
grep -n '>>> opensbi .* Downloading' "${LOG_FILE}" >/dev/null
grep -n '>>> opensbi .* Building' "${LOG_FILE}" >/dev/null
grep -n '>>> opensbi .* Installing to images directory' "${LOG_FILE}" >/dev/null

echo "[5/5] Summary"
echo "PASS: upstream OpenSBI trial build completed"
echo "      Log file: ${LOG_FILE}"
echo "      Image   : ${LINUX_DIR}/linux_image.elf"

popd >/dev/null
