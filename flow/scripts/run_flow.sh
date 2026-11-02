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

# The chip configs use LibreLane >= 3.1 features (PAD_SPACING_MULTIPLE,
# PDN_CORE_RING_CONNECT_TO_PAD_LAYERS, meta.version 3).
LL_VER="$(${LIBRELANE} --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9.]*' | head -1 || true)"
echo ">>> LibreLane ${LL_VER:-unknown}"
LL_MM="$(echo "${LL_VER}" | cut -d. -f1-2)"
if [[ -n "${LL_MM}" ]] && ! printf '3.1\n%s\n' "${LL_MM}" | sort -V -C; then
  echo "ERROR: LibreLane ${LL_VER} is too old - this project needs >= 3.1.0.dev4"
  echo "       (git -C ~/librelane checkout 3.1.0.dev4 && nix-shell ~/librelane/shell.nix)"
  exit 1
fi

# Always pin the PDK/SCL/pad library explicitly: LibreLane otherwise reads
# PDK / STD_CELL_LIBRARY / PAD_CELL_LIBRARY from the environment.
PDK="${PDK:-sky130A}"
case "${PDK}" in sky130A|sky130B) ;; *)
  echo ">>> NOTE: ignoring PDK=${PDK} from the environment, using sky130A"; PDK=sky130A ;;
esac
PDK_ARGS=(--pdk "${PDK}" --scl sky130_fd_sc_hd)
[[ -n "${PDK_ROOT:-}" ]] && PDK_ARGS+=(--pdk-root "${PDK_ROOT}")
# Do NOT pass --pad / PAD_CELL_LIBRARY: LibreLane hands it to ciel as a library
# name to download ("Unknown library sky130_ef_io"); the sky130 PDK config
# already selects sky130_ef_io as the pad library.
unset PAD_CELL_LIBRARY STD_CELL_LIBRARY
echo ">>> PDK ${PDK} (${PDK_ROOT:-default ciel root}), SCL sky130_fd_sc_hd"

ll() { echo "+ ${LIBRELANE} ${PDK_ARGS[*]} $*"; ${LIBRELANE} "${PDK_ARGS[@]}" "$@"; }

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
