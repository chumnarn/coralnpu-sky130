#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# check_pdk.sh <PDK_ROOT> <PDK> <hash> - verify the sky130 files this project needs
PDK_ROOT="${1:-$HOME/.ciel}"; PDK="${2:-sky130A}"; HASH="${3:-}"
P="${PDK_ROOT}/${PDK}"
echo ">>> checking ${P}"
if [[ ! -d "${P}/libs.ref" ]]; then
  echo "ERROR: ${P}/libs.ref not found."
  echo "       PDK_ROOT=${PDK_ROOT}  PDK=${PDK}  (env PDK/PDK_ROOT override the Makefile)"
  ls -la "${PDK_ROOT}" 2>&1 | head -20
  exit 1
fi
fail=0
need=(
  "libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
  "libs.ref/sky130_fd_io/lef/sky130_ef_io.lef"
  "libs.ref/sky130_fd_io/verilog/sky130_ef_io.v"
  "libs.ref/sky130_sram_macros/lef/sky130_sram_2kbyte_1rw1r_32x512_8.lef"
  "libs.ref/sky130_sram_macros/gds/sky130_sram_2kbyte_1rw1r_32x512_8.gds"
  "libs.ref/sky130_sram_macros/lib/sky130_sram_2kbyte_1rw1r_32x512_8_TT_1p8V_25C.lib"
  "libs.ref/sky130_sram_macros/verilog/sky130_sram_2kbyte_1rw1r_32x512_8.v"
  "libs.ref/sky130_sram_macros/spice/sky130_sram_2kbyte_1rw1r_32x512_8.spice"
  "libs.tech/librelane/sky130_ef_io/config.tcl"
)
for f in "${need[@]}"; do
  if [[ -e "${P}/${f}" ]]; then echo "  ok      ${f}"
  else echo "  MISSING ${f}"; fail=1; fi
done
if [[ ${fail} -ne 0 ]]; then
  echo
  echo "Some files are missing. Installed libraries:"
  ls "${P}/libs.ref"
  echo "Fix: ciel enable --pdk-root ${PDK_ROOT} --pdk-family sky130 -l all ${HASH}"
  exit 1
fi
echo ">>> PDK OK"
