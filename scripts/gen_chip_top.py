#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""
Generate rtl/chip/chip_top.v (pad ring + coralnpu_soc) and
flow/chip/pads.yaml (PAD_SOUTH/EAST/NORTH/WEST lists for LibreLane).

Edit the PADS table below to change pin-out, then re-run:
    python3 scripts/gen_chip_top.py
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (side, kind, name, core_signal)
#   kind: in | out | vccd | vssd | vddio | vssio
PADS = [
    # ---------------- south (left -> right)
    ("S", "vssio", "vssio_0", None),
    ("S", "in", "clk", "clk"),
    ("S", "in", "rst_n", "rst_n"),
    ("S", "vccd", "vccd_0", None),
    ("S", "vssd", "vssd_0", None),
    ("S", "in", "spi_sck", "spi_sck"),
    ("S", "in", "spi_csb", "spi_csb"),
    ("S", "vddio", "vddio_0", None),
    # ---------------- east (bottom -> top)
    ("E", "in", "spi_mosi", "spi_mosi"),
    ("E", "out", "spi_miso", "spi_miso"),
    ("E", "in", "irq", "irq"),
    ("E", "in", "gpio_in0", "gpio_in[0]"),
    ("E", "in", "gpio_in1", "gpio_in[1]"),
    ("E", "in", "gpio_in2", "gpio_in[2]"),
    ("E", "in", "gpio_in3", "gpio_in[3]"),
    # ---------------- north (left -> right)
    ("N", "vssio", "vssio_1", None),
    ("N", "out", "gpio_out0", "gpio_out[0]"),
    ("N", "out", "gpio_out1", "gpio_out[1]"),
    ("N", "out", "gpio_out2", "gpio_out[2]"),
    ("N", "out", "gpio_out3", "gpio_out[3]"),
    ("N", "vccd", "vccd_1", None),
    ("N", "vssd", "vssd_1", None),
    ("N", "vddio", "vddio_1", None),
    # ---------------- west (bottom -> top)
    ("W", "out", "gpio_out4", "gpio_out[4]"),
    ("W", "out", "gpio_out5", "gpio_out[5]"),
    ("W", "out", "gpio_out6", "gpio_out[6]"),
    ("W", "out", "gpio_out7", "gpio_out[7]"),
    ("W", "out", "halted", "halted"),
    ("W", "out", "fault", "fault"),
    ("W", "out", "wfi", "wfi"),
]

POWER_CELL = {
    "vccd": ("sky130_ef_io__vccd_lvc_clamped_pad", "VCCD_PAD"),
    "vssd": ("sky130_ef_io__vssd_lvc_clamped_pad", "VSSD_PAD"),
    "vddio": ("sky130_ef_io__vddio_hvc_clamped_pad", "VDDIO_PAD"),
    "vssio": ("sky130_ef_io__vssio_hvc_clamped_pad", "VSSIO_PAD"),
}


RING_PINS = ["VDDIO", "VDDIO_Q", "VDDA", "VCCD", "VSWITCH", "VCCHIB",
             "VSSA", "VSSD", "VSSIO_Q", "VSSIO"]


def ring(indent="      "):
    """Pad-ring rail connections (only visible to the powered netlist / LVS)."""
    lines = ["`ifdef USE_POWER_PINS"]
    lines += [f"{indent}.{p:<16s}({p})," for p in RING_PINS]
    lines += ["`endif",
              f"{indent}.AMUXBUS_A       (AMUXBUS_A),",
              f"{indent}.AMUXBUS_B       (AMUXBUS_B),"]
    return lines


def gpio_pad(name, kind, core):
    inst = f"pad_{name}"
    is_out = kind == "out"
    core_in = f"core_{name}"
    lines = [
        f"  // {kind.upper():3s} {name}",
        f"  wire {inst}_tie_hi, {inst}_tie_lo;",
    ]
    if not is_out:
        lines.append(f"  wire {core_in};")
    lines += [
        "  (* keep *)",
        f"  sky130_ef_io__gpiov2_pad {inst} (",
    ] + ring() + [
        f"      .PAD             ({name}_PAD),",
        f"      .OUT             ({core if is_out else "1'b0"}),",
        f"      .OE_N            ({"1'b0" if is_out else "1'b1"}),",
        f"      .DM              ({"3'b110" if is_out else "3'b001"}),",
        f"      .INP_DIS         (1'b{'1' if is_out else '0'}),",
        f"      .IN              ({'' if is_out else core_in}),",
        "      .IN_H            (),",
        "      .IB_MODE_SEL     (1'b0),",
        "      .VTRIP_SEL       (1'b0),",
        "      .SLOW            (1'b0),",
        "      .HLD_OVR         (1'b0),",
        "      .ANALOG_EN       (1'b0),",
        "      .ANALOG_SEL      (1'b0),",
        "      .ANALOG_POL      (1'b0),",
        "      .ENABLE_VDDIO    (1'b1),",
        f"      .HLD_H_N         ({inst}_tie_hi),",
        f"      .ENABLE_H        ({inst}_tie_hi),",
        f"      .ENABLE_INP_H    ({inst}_tie_hi),",
        f"      .ENABLE_VDDA_H   ({inst}_tie_lo),   // VDDA domain unused",
        f"      .ENABLE_VSWITCH_H({inst}_tie_lo),",
        f"      .TIE_HI_ESD      ({inst}_tie_hi),",
        f"      .TIE_LO_ESD      ({inst}_tie_lo),",
        "      .PAD_A_NOESD_H   (),",
        "      .PAD_A_ESD_0_H   (),",
        "      .PAD_A_ESD_1_H   ()",
        "  );",
        "",
    ]
    return "\n".join(lines)


def power_pad(name, kind):
    cell, pin = POWER_CELL[kind]
    return "\n".join(
        [
            f"  // PWR {name}",
            "  (* keep *)",
            f"  {cell} pad_{name} (",
        ] + ring()[:-1] + [
            "      .AMUXBUS_B       (AMUXBUS_B)",
            "`ifdef USE_POWER_PINS",
            f"     ,.{pin:<16s}({name}_PAD)",
            "`endif",
            "  );",
            "",
        ]
    )


def main():
    ports = []
    pwr_ports = []
    body = []
    core_map = {}
    for side, kind, name, core in PADS:
        if kind in ("in", "out"):
            ports.append(f"    inout wire {name}_PAD")
            body.append(gpio_pad(name, kind, core))
            if kind == "in":
                core_map[core] = f"core_{name}"
        else:
            pwr_ports.append(f"    inout wire {name}_PAD")
            body.append(power_pad(name, kind))

    def cin(sig):
        return core_map[sig]

    soc = f"""
  // ---------------------------------------------------------------------------
  // Core logic
  // ---------------------------------------------------------------------------
  coralnpu_soc u_soc (
      .clk     ({cin('clk')}),
      .rst_n   ({cin('rst_n')}),
      .spi_sck ({cin('spi_sck')}),
      .spi_csb ({cin('spi_csb')}),
      .spi_mosi({cin('spi_mosi')}),
      .spi_miso(spi_miso),
      .gpio_out(gpio_out),
      .gpio_in ({{{cin('gpio_in[3]')}, {cin('gpio_in[2]')}, {cin('gpio_in[1]')}, {cin('gpio_in[0]')}}}),
      .irq     ({cin('irq')}),
      .halted  (halted),
      .fault   (fault),
      .wfi     (wfi)
  );
"""

    v = (
        "// SPDX-License-Identifier: Apache-2.0\n"
        "// AUTO-GENERATED by scripts/gen_chip_top.py - do not edit by hand.\n"
        "//\n"
        "// chip_top: SKY130 pad ring (sky130_ef_io) + coralnpu_soc.\n"
        "// Style follows LibreLane's sky130 full-chip reference (CI design\n"
        "// full_chip_sky130): pad-ring rails and power-pad terminals only exist\n"
        "// under USE_POWER_PINS, i.e. in the powered netlist used for LVS.\n"
        "// NOTE: VDDA/VSSA and VSWITCH/VCCHIB are not supplied by any pad - add\n"
        "// supplies (and a power-on-reset for ENABLE_H) before a real tape-out.\n"
        "`default_nettype none\n\n"
        "module chip_top (\n"
        "`ifdef USE_POWER_PINS\n" + ",\n".join(pwr_ports) + ",\n`endif\n"
        + ",\n".join(ports) + "\n);\n\n"
        "`ifdef USE_POWER_PINS\n"
        "  wire " + ", ".join(RING_PINS) + ";\n"
        "`endif\n"
        "  wire AMUXBUS_A, AMUXBUS_B;\n\n"
        "  // Core-side signals driven by coralnpu_soc\n"
        "  wire [7:0] gpio_out;\n"
        "  wire       spi_miso, halted, fault, wfi;\n\n"
        + "\n".join(body)
        + soc
        + "\nendmodule\n\n`default_nettype wire\n"
    )
    out_v = os.path.join(ROOT, "rtl", "chip", "chip_top.v")
    with open(out_v, "w") as f:
        f.write(v)

    sides = {"S": "PAD_SOUTH", "E": "PAD_EAST", "N": "PAD_NORTH", "W": "PAD_WEST"}
    y = []
    for s_, key in sides.items():
        y.append(f"{key}:")
        for side, kind, name, core in PADS:
            if side == s_:
                y.append(f"  - pad_{name}")
    block = "# >>> PADS (generated)\n" + "\n".join(y) + "\n# <<< PADS"
    import glob, re
    for cfg in sorted(glob.glob(os.path.join(ROOT, "flow", "chip", "config*.yaml"))):
        txt = open(cfg).read()
        txt = re.sub(r"# >>> PADS \(generated\).*?# <<< PADS", lambda m: block, txt, flags=re.S)
        open(cfg, "w").write(txt)
        print(f"updated {cfg}")
    print(f"wrote {out_v}")


if __name__ == "__main__":
    main()
