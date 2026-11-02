#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""
report.py <run_dir> [--synth-only]

Print a short sign-off summary of a LibreLane run (area, timing, DRC, LVS,
antenna, power) from the latest state_out.json / final/metrics.json.
"""
import glob
import json
import os
import sys

KEYS = [
    ("Std-cell instances", "design__instance__count__stdcell"),
    ("All instances", "design__instance__count"),
    ("Macros", "design__instance__count__macros"),
    ("Std-cell area (um^2)", "design__instance__area__stdcell"),
    ("Die area (um^2)", "design__die__area"),
    ("Core utilization", "design__instance__utilization"),
    ("Setup WNS (ns)", "timing__setup__ws"),
    ("Setup TNS (ns)", "timing__setup__tns"),
    ("Setup violations", "timing__setup_vio__count"),
    ("Hold WNS (ns)", "timing__hold__ws"),
    ("Hold violations", "timing__hold_vio__count"),
    ("Max slew violations", "design__max_slew_violation__count"),
    ("Max cap violations", "design__max_cap_violation__count"),
    ("Routing DRC (TritonRoute)", "route__drc_errors"),
    ("Magic DRC", "magic__drc_error__count"),
    ("KLayout DRC", "klayout__drc_error__count"),
    ("LVS errors", "design__lvs_error__count"),
    ("Antenna violating nets", "antenna__violating__nets"),
    ("Total power (W)", "power__total"),
    ("IR drop worst (V)", "ir__drop__worst"),
]


def latest_metrics(run_dir):
    final = os.path.join(run_dir, "final", "metrics.json")
    if os.path.isfile(final):
        return final, json.load(open(final))
    states = sorted(glob.glob(os.path.join(run_dir, "*", "state_out.json")),
                    key=lambda p: int(os.path.basename(os.path.dirname(p)).split("-")[0]))
    if not states:
        return None, {}
    return states[-1], json.load(open(states[-1])).get("metrics", {})


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    run_dir = sys.argv[1]
    src, m = latest_metrics(run_dir)
    if not m:
        sys.exit(f"[report] no metrics found in {run_dir}")
    print("-" * 64)
    print(f" LibreLane summary : {run_dir}")
    print(f" source            : {src}")
    print("-" * 64)
    for label, key in KEYS:
        if key in m:
            v = m[key]
            if isinstance(v, float):
                v = f"{v:.4g}"
            print(f" {label:28s} {v}")
    if "--synth-only" in sys.argv:
        cells = {k: v for k, v in m.items() if k.startswith("design__instance__count__class:")}
        for k, v in sorted(cells.items()):
            print(f"   {k.split(':', 1)[1]:26s} {v}")
    print("-" * 64)


if __name__ == "__main__":
    main()
