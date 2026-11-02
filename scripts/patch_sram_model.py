#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""
patch_sram_model.py <in.v> <out.v>

Make the OpenRAM behavioural model of sky130_sram_2kbyte_1rw1r_32x512_8 work
with every simulator:
  * the PDK model uses `mem` in $display() before `reg ... mem[...]` is
    declared; Icarus Verilog >= 13 (the one in the LibreLane nix-shell) rejects
    that ("Scope index expression is not constant"). The declaration is moved
    up, right after the parameters.
  * VERBOSE is set to 0 so the simulation log is not flooded with every
    read/write.
The PDK file itself is never modified; the patched copy goes to build/.
"""
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
txt = open(src, encoding="utf8").read()

decl_rx = re.compile(r"^[ \t]*reg\s*\[\s*DATA_WIDTH\s*-\s*1\s*:\s*0\s*\]\s*mem\s*\[[^\]]*\]\s*;[ \t]*\n", re.M)
m = decl_rx.search(txt)
if not m:
    sys.exit(f"[patch_sram_model] memory declaration not found in {src}")
decl = m.group(0).strip()
txt = txt[: m.start()] + txt[m.end():]

anchor = re.search(r"^[ \t]*parameter\s+T_HOLD\b[^\n]*\n", txt, re.M) or \
         re.search(r"^[ \t]*parameter\s+RAM_DEPTH\b[^\n]*\n", txt, re.M)
if not anchor:
    sys.exit(f"[patch_sram_model] parameter block not found in {src}")
txt = txt[: anchor.end()] + f"  {decl}  // [patched] declared before first use\n" + txt[anchor.end():]

txt = re.sub(r"(parameter\s+VERBOSE\s*=\s*)1", r"\g<1>0", txt)
open(dst, "w", encoding="utf8").write("// patched copy of " + src + "\n" + txt)
print(f"[patch_sram_model] {dst}")
