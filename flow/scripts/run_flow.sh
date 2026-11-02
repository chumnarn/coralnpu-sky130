#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------
# run_flow.sh <soc|chip> [config.yaml]
#
# Two-pass LibreLane run:
#   pass 1 : synthesis only (stops after the synthesis checkers)
#   place  : read SRAM instance names from the netlist -> macro_placement.cfg
#   pass 2 : resume the same run from floorplan to sign-off (GDS, DRC, LVS, STA)
#
# Environment:
#   LIBRELANE   command used to call LibreLane   (default: librelane)
#               e.g. LIBRELANE="librelane --dockerized"
#   TAG         run tag                           (default: main)
#   FRESH=1     delete an existing run with the same tag first
#   JOBS        parallel jobs for LibreLane       (default: nproc)
#   FROM        skip pass 1 and resume from this step id (e.g. OpenROAD.CTS)
# -----------------------------------------------------------------------------
set -euo pipefail

TARGET="${1:?usage: run_flow.sh <soc|chip> [config.yaml]}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DESIGN_DIR="${ROOT}/flow/${TARGET}"
CONFIG="${2:-config.yaml}"
LIBRELANE="${LIBRELANE:-librelane}"
TAG="${TAG:-main}"
JOBS="${JOBS:-$(nproc)}"

[[ -f "${DESIGN_DIR}/${CONFIG}" ]] || { echo "no ${DESIGN_DIR}/${CONFIG}"; exit 1; }
[[ -f "${ROOT}/rtl/generated/CoralNPUCore.sv" ]] || {
  echo "ERROR: rtl/generated/CoralNPUCore.sv missing - run 'make rtl' first"; exit 1; }

# Run from the project root so that a containerised LibreLane
# (LIBRELANE="librelane --dockerized") can see rtl/ as well as flow/.
cd "${ROOT}"
CFG="flow/${TARGET}/${CONFIG}"
RUNS="flow/${TARGET}/runs"
PLACEMENT="flow/${TARGET}/macro_placement.cfg"
[[ -f "${PLACEMENT}" ]] || echo "# placeholder - rewritten by place_srams.py" > "${PLACEMENT}"

if [[ "${FRESH:-0}" == "1" && -d "${RUNS}/${TAG}" ]]; then
  echo ">>> removing ${RUNS}/${TAG}"
  rm -rf "${RUNS}/${TAG}"
fi

ll() { echo "+ ${LIBRELANE} $*"; ${LIBRELANE} "$@"; }

if [[ -n "${FROM:-}" ]]; then
  ll "${CFG}" --run-tag "${TAG}" -j "${JOBS}" --from "${FROM}"
  exit 0
fi

echo "=================================================================="
echo " [1/3] ${TARGET}: synthesis"
echo "=================================================================="
ll "${CFG}" --run-tag "${TAG}" -j "${JOBS}" --to Checker.NetlistAssignStatements

echo "=================================================================="
echo " [2/3] ${TARGET}: SRAM macro placement"
echo "=================================================================="
python3 "${ROOT}/flow/scripts/place_srams.py" \
  --netlist "${RUNS}/${TAG}/*-yosys-synthesis/*.nl.v" \
  --config "${CFG}" --out "${PLACEMENT}"
python3 "${ROOT}/flow/scripts/report.py" "${RUNS}/${TAG}" --synth-only || true

echo "=================================================================="
echo " [3/3] ${TARGET}: floorplan -> sign-off"
echo "=================================================================="
ll "${CFG}" --run-tag "${TAG}" -j "${JOBS}" --from OpenROAD.CheckSDCFiles

python3 "${ROOT}/flow/scripts/report.py" "${RUNS}/${TAG}"
