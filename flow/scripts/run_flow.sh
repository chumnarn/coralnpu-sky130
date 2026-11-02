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

# LibreLane 3.1 is preferred (PAD_SPACING_MULTIPLE, pad rotation, ...).
# On 3.0.x the chip flow automatically switches to the *.v30.yaml fallback.
LL_VER="$(${LIBRELANE} --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9.]*' | head -1 || true)"
echo ">>> LibreLane ${LL_VER:-unknown}"
LL_MM="$(echo "${LL_VER}" | cut -d. -f1-2)"
if [[ -n "${LL_MM}" ]] && ! printf '3.0\n%s\n' "${LL_MM}" | sort -V -C; then
  echo "ERROR: LibreLane ${LL_VER} is too old - this project needs 3.0.17 or >= 3.1"; exit 1
fi
if [[ "${LL_MM}" == "3.0" && "${TARGET}" == "chip" && "${CFG}" != *.v30.yaml ]]; then
  CFG="${CFG%.yaml}.v30.yaml"
  echo ">>> LibreLane 3.0.x detected: using ${CFG}"
fi
[[ -f "${CFG}" ]] || { echo "ERROR: ${CFG} not found"; exit 1; }

# Always pin the PDK/SCL/pad library explicitly: LibreLane otherwise reads
# PDK / STD_CELL_LIBRARY / PAD_CELL_LIBRARY from the environment.
PDK="${PDK:-sky130A}"
case "${PDK}" in sky130A|sky130B) ;; *)
  echo ">>> NOTE: ignoring PDK=${PDK} from the environment, using sky130A"; PDK=sky130A ;;
esac
PDK_ARGS=(--pdk "${PDK}" --scl sky130_fd_sc_hd)
if [[ "${LL_MM}" == "3.0" && "${TARGET}" == "chip" ]]; then
  # The sky130 build pinned by LibreLane 3.0.x has no sky130_ef_io pad-ring
  # config, so use the newer build (fetched by 'make pdk') as a manual PDK.
  CHIP_PDK_HASH="${CHIP_PDK_HASH:-792ef67037d74c8c51811eab3ce23cf793491296}"
  CHIP_PDK_ROOT="$(ciel path --pdk-root "${PDK_ROOT:-$HOME/.ciel}" --pdk-family sky130 "${CHIP_PDK_HASH}" 2>/dev/null || true)"
  if [[ -z "${CHIP_PDK_ROOT}" || ! -f "${CHIP_PDK_ROOT}/${PDK}/libs.tech/librelane/sky130_ef_io/config.tcl" ]]; then
    echo "ERROR: sky130 ${CHIP_PDK_HASH} (pad-ring config) not found - run 'make pdk' first"; exit 1
  fi
  PDK_ARGS=(--manual-pdk --pdk-root "${CHIP_PDK_ROOT}" --pdk "${PDK}" --scl sky130_fd_sc_hd)
elif [[ -n "${PDK_ROOT:-}" ]]; then
  PDK_ARGS+=(--pdk-root "${PDK_ROOT}")
fi
# Do NOT pass --pad / PAD_CELL_LIBRARY: LibreLane hands it to ciel as a library
# name to download ("Unknown library sky130_ef_io"); the sky130 PDK config
# already selects sky130_ef_io as the pad library.
unset PAD_CELL_LIBRARY STD_CELL_LIBRARY
echo ">>> PDK args: ${PDK_ARGS[*]}"

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
