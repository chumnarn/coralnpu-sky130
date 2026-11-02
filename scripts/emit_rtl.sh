#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------
# emit_rtl.sh [full|lite]
#
# Generate CoralNPU SystemVerilog with Bazel/Chisel and post-process it for
# SKY130 (rtl/generated/CoralNPUCore.sv).
#
#   full : CoreMiniAxi                  RV32IMF + Zfbfmin, ITCM 8K, DTCM 32K
#   lite : CoreMini_ITCM8KB_DTCM8KBAxi  RV32IM,            ITCM 8K, DTCM  8K
#
# Environment:
#   CORALNPU_DIR  CoralNPU checkout (default: third_party/coralnpu)
#   BAZEL         bazel / bazelisk command (default: bazel)
# -----------------------------------------------------------------------------
set -euo pipefail

VARIANT="${1:-full}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORALNPU_DIR="${CORALNPU_DIR:-${ROOT}/third_party/coralnpu}"
BAZEL="${BAZEL:-bazel}"
PKG="hdl/chisel/src/coralnpu"

case "${VARIANT}" in
  full)
    TARGET="//${PKG}:core_mini_axi_cc_library_emit_verilog"
    EMITTED="CoreMiniAxi.sv"
    ;;
  lite)
    TARGET="//${PKG}:core_mini_lite_axi_cc_library_emit_verilog"
    EMITTED="CoreMini_ITCM8KB_DTCM8KBAxi.sv"
    if ! grep -q "core_mini_lite_axi_cc_library" "${CORALNPU_DIR}/${PKG}/BUILD"; then
      echo ">>> adding lite target to ${PKG}/BUILD"
      cat "${ROOT}/patches/coralnpu_lite_target.bzl.txt" >> "${CORALNPU_DIR}/${PKG}/BUILD"
    fi
    ;;
  *) echo "usage: $0 [full|lite]"; exit 1 ;;
esac

[[ -d "${CORALNPU_DIR}" ]] || { echo "CoralNPU not found at ${CORALNPU_DIR} - run 'make fetch'"; exit 1; }

CC_BIN="${CC:-gcc}"
command -v "${CC_BIN}" >/dev/null 2>&1 || CC_BIN=clang

echo "=================================================================="
echo " CoralNPU RTL generation (${VARIANT})"
echo "   repo   : ${CORALNPU_DIR}"
echo "   target : ${TARGET}"
echo "=================================================================="
( cd "${CORALNPU_DIR}" && \
  "${BAZEL}" build --action_env=CC="${CC_BIN}" --repo_env=CC="${CC_BIN}" "${TARGET}" )

SRC="${CORALNPU_DIR}/bazel-bin/${PKG}/${EMITTED}"
[[ -f "${SRC}" ]] || { echo "ERROR: ${SRC} not produced"; exit 1; }

mkdir -p "${ROOT}/rtl/generated"
cp -L "${SRC}" "${ROOT}/rtl/generated/${EMITTED}"
chmod u+w "${ROOT}/rtl/generated/${EMITTED}"

python3 "${ROOT}/scripts/prepare_rtl.py" \
  "${ROOT}/rtl/generated/${EMITTED}" "${ROOT}/rtl/generated/CoralNPUCore.sv"
echo "${VARIANT}" > "${ROOT}/rtl/generated/VARIANT"
echo ">>> done: rtl/generated/CoralNPUCore.sv ($(du -h "${ROOT}/rtl/generated/CoralNPUCore.sv" | cut -f1))"
