# coralnpu-sky130

Full-chip implementation of Google's **CoralNPU** (scalar `CoreMiniAxi`) on the
**SkyWater SKY130** PDK with **LibreLane 3.1** (tested config-level with 3.1.0.dev4): Chisel RTL -> SKY130 SRAM /
clock-gate mapping -> SPI-bootable SoC -> pad ring, seal ring, fill -> GDS.

คู่มือภาษาไทยแบบ step-by-step: **[docs/GUIDE_TH.md](docs/GUIDE_TH.md)**

```bash
make tools                    # once: Nix + LibreLane, Bazelisk, iverilog
nix-shell ~/librelane/shell.nix
make pdk fetch                # sky130A via ciel, clone CoralNPU
make rtl  VARIANT=lite        # Chisel -> rtl/generated/CoralNPUCore.sv
make sim  && make sim-sram    # SoC glue + SRAM wrapper test-benches
make soc  VARIANT=lite        # block-level hardening  (Classic flow)
make chip VARIANT=lite        # full chip with pad ring (Chip flow)
make report-chip && make view-chip VARIANT=lite
```

| VARIANT | Core | Memory | SRAM macros | Die |
|---|---|---|---|---|
| `full` | RV32IMF + Zfbfmin | ITCM 8K + DTCM 32K | 20 | 5.0 x 5.0 mm |
| `lite` | RV32IM | ITCM 8K + DTCM 8K | 8 | 4.0 x 4.0 mm |

Licence: Apache-2.0 (same as CoralNPU). CoralNPU itself is fetched from
<https://github.com/google-coral/coralnpu> and is not redistributed here.
