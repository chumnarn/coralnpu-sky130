# คู่มือ Full-Chip Implementation ของ CoralNPU ด้วย LibreLane และ SKY130 PDK

**Version:** 1.1 (LibreLane 3.1)
**Last Updated:** 2 พฤศจิกายน 2026
**Duration:** ประมาณ 1–2 วันทำงาน (ส่วนใหญ่เป็นเวลารอเครื่องรัน flow)
**Level:** Intermediate – Advanced
**Author / Instructor:** โปรเจกต์ `coralnpu-sky130` (เตรียมให้ chumnarn@gmail.com)

| รายการ | เวอร์ชันที่ใช้ในคู่มือ |
|---|---|
| CoralNPU (google-coral/coralnpu) | commit `11619e2` (29 ต.ค. 2026) |
| LibreLane | 3.1.0.dev4 (ต้อง ≥ 3.1 เพราะ Chip flow ใช้ตัวแปรใหม่) |
| PDK | sky130A ผ่าน ciel (open_pdks `792ef67…` ตามที่ LibreLane 3.1.0 ล็อกไว้) |
| Bazel | 9.1.0 (ผ่าน Bazelisk ตาม `.bazelversion` ของ CoralNPU) |

---

## Workshop Overview

CoralNPU เป็น NPU แบบ open source ของ Google Research ที่ใช้ RISC-V (RV32IMF + Zve32x) มีหน่วยความจำ ITCM 8 KiB และ DTCM 32 KiB และเชื่อมต่อภายนอกด้วย AXI4 แต่ในรีโปต้นฉบับมีเฉพาะ physical flow สำหรับ ASAP7 (PDK เชิงทำนาย) โดยใช้ ORFS เท่านั้น คู่มือนี้พาทำ **full-chip implementation บน SkyWater SKY130** ด้วย **LibreLane** ครบทุกขั้น ตั้งแต่สร้าง RTL จาก Chisel แทนที่หน่วยความจำด้วย OpenRAM SRAM macro ของ sky130 ห่อด้วย SoC ขนาดเล็กที่มี SPI→AXI bridge และ GPIO ใส่ pad ring, seal ring และ fill ไปจนได้ GDS ที่ผ่าน DRC/LVS/STA

หลังทำครบทุก Lab ผู้เรียนจะสามารถ:

- **สร้าง** SystemVerilog ของ CoralNPU จาก Chisel ด้วย Bazel และปรับให้ใช้กับเทคโนโลยี sky130 ได้
- **ตรวจสอบ** SoC glue (SPI bridge, AXI GPIO, SRAM wrapper) ด้วย simulation ก่อนเข้า flow
- **รัน** LibreLane Classic flow เพื่อทำ block-level hardening ที่มี SRAM macro 20 ตัว
- **รัน** LibreLane Chip flow เพื่อทำ full chip ที่มี pad ring `sky130_ef_io`, seal ring และ metal fill
- **วิเคราะห์** รายงาน timing/DRC/LVS/antenna และปรับ floorplan/constraint ได้เอง
- **โหลดโปรแกรม** RISC-V เข้าชิปผ่าน SPI ทั้งใน simulation และกับชิปจริง

### สถาปัตยกรรมของชิป

```text
                         chip_top (pad ring sky130_ef_io, 30 pads)
 ┌─────────────────────────────────────────────────────────────────────────┐
 │  clk rst_n  spi_sck/csb/mosi/miso  gpio_in[3:0] irq   gpio_out[7:0] ... │
 │   │    │          │                    │       │            ▲           │
 │ ┌─▼────▼──────────▼────────────────────▼───────▼────────────┴─────────┐ │
 │ │ coralnpu_soc                                                        │ │
 │ │  ┌──────────────┐ AXI4 128b ┌───────────────────────────────┐       │ │
 │ │  │spi_axi_bridge├──────────►│ CoralNPUCore (CoreMiniAxi)    │       │ │
 │ │  └──────────────┘ (slave)   │  scalar RV32IMF core + CSR    │       │ │
 │ │                             │  ITCM 8K  = 4  x OpenRAM 2KB  │       │ │
 │ │                             │  DTCM 32K = 16 x OpenRAM 2KB  │       │ │
 │ │  ┌──────────────┐ AXI4 128b └──────────────┬────────────────┘       │ │
 │ │  │axi_gpio_slave│◄─────────────────────────┘ (master)               │ │
 │ │  └──────────────┘ GPIO_OUT/GPIO_IN/SCRATCH/ID @ 0x8000_0000         │ │
 │ └─────────────────────────────────────────────────────────────────────┘ │
 └─────────────────────────────────────────────────────────────────────────┘
```

> 📝 **หมายเหตุ:** คู่มือนี้ใช้ core แบบ scalar (`CoreMiniAxi`) ที่ทีม CoralNPU แนะนำสำหรับการ integrate แบบ AXI ส่วนรุ่น RVV (`RvvCoreMiniAxi`) มีขนาดราว 1.4 ล้าน cell บน ASAP7 ซึ่งใหญ่เกินกว่าจะทำบน sky130 ได้จริงในเวลาและพื้นที่ที่เหมาะสม

### สองรุ่น (VARIANT) ที่เลือกได้

| VARIANT | Core | หน่วยความจำ | SRAM macro | Die (chip) | เหมาะกับ |
|---|---|---|---|---|---|
| `full` (ค่าเริ่มต้น) | `CoreMiniAxi` RV32IMF + Zfbfmin | ITCM 8K + DTCM 32K | 20 | 5.0 × 5.0 mm | ตรงตาม spec ของ CoralNPU |
| `lite` | RV32IM (ไม่มี FPU) | ITCM 8K + DTCM 8K | 8 | 4.0 × 4.0 mm | workshop และการลองรอบแรก รันเร็วกว่า 2–3 เท่า |

> 💡 **เคล็ดลับ:** ถ้าเพิ่งเริ่ม ให้ทำทุก Lab ด้วย `VARIANT=lite` ก่อน แล้วค่อยกลับมารัน `full`

---

## Prerequisites

**ความรู้พื้นฐาน**

- Verilog/SystemVerilog และแนวคิด AXI4 เบื้องต้น
- RTL-to-GDS flow (synthesis, floorplan, placement, CTS, routing, STA, DRC/LVS)
- ใช้ Linux shell, `make` และ `git` ได้คล่อง

**ฮาร์ดแวร์ของเครื่องที่ใช้รัน**

| | `lite` | `full` |
|---|---|---|
| CPU | 8 cores ขึ้นไป | 16 cores ขึ้นไป |
| RAM | 32 GB | 64 GB (แนะนำ) |
| Disk ว่าง | 60 GB | 120 GB |
| เวลารัน flow (ประมาณ) | 2–5 ชม. | 8–20 ชม. |

> ⚠️ **คำเตือน:** ตัวเลขเวลาและ RAM เป็นเพียงการประมาณจากขนาดของ design (core scalar + FPU ประมาณ 1–3 แสน cell บน sky130) ค่าจริงขึ้นกับเครื่อง ให้ดูขนาดจริงจากรายงานหลัง synthesis ใน Lab 4

**ซอฟต์แวร์** (สคริปต์ `scripts/install_tools.sh` ติดตั้งให้)

- Ubuntu 22.04/24.04 x86_64 (หรือ WSL2)
- Nix + LibreLane 3.1.0.dev4 ซึ่งรวม Yosys 0.69 (มี slang ในตัว), OpenROAD, Magic 8.3.677, KLayout 0.30.12, Netgen และ Verilator 5.046
- Bazelisk สำหรับ build CoralNPU (Bazel 9.1.0) พร้อม gcc/clang และ Java
- Icarus Verilog และ GTKWave สำหรับ simulation
- Internet สำหรับดาวน์โหลด CoralNPU dependency (Maven, GitHub, BCR) และ PDK

---

## โครงสร้างโปรเจกต์

```text
coralnpu-sky130/
├── Makefile                      # ทุกคำสั่งของคู่มือ: make help
├── docs/GUIDE_TH.md              # คู่มือนี้
├── scripts/
│   ├── install_tools.sh          # ติดตั้ง Nix/LibreLane/Bazelisk/iverilog
│   ├── fetch_coralnpu.sh         # clone CoralNPU ที่ commit ที่ทดสอบแล้ว
│   ├── emit_rtl.sh               # Bazel/Chisel -> SystemVerilog (full|lite)
│   ├── prepare_rtl.py            # ถอด Sram/ClockGate, rename top, ตรวจพอร์ต
│   └── gen_chip_top.py           # สร้าง chip_top.v + รายชื่อ PAD_* จากตาราง pin-out
├── patches/coralnpu_lite_target.bzl.txt   # Bazel target ของรุ่น lite
├── rtl/
│   ├── sky130/Sram_sky130.v      # module Sram -> 4x sky130_sram_2kbyte_1rw1r_32x512_8
│   ├── sky130/ClockGate_sky130.v # module ClockGate -> sky130_fd_sc_hd__sdlclkp_4
│   ├── soc/spi_axi_bridge.v      # SPI slave -> AXI4 manager
│   ├── soc/axi_gpio_slave.v      # AXI4 subordinate: GPIO/SCRATCH/ID
│   ├── soc/coralnpu_soc.v        # SoC top (core + bridge + GPIO)
│   ├── chip/chip_top.v           # pad ring + SoC (generated)
│   └── generated/                # CoralNPUCore.sv (สร้างใน Lab 1)
├── tb/                           # test-bench: stub core, SRAM unit test, real core
├── sw/                           # gpio_demo.c, BUILD.bazel, spi_host.py (ตัวโหลดผ่าน SPI)
└── flow/
    ├── soc/   config.yaml config.lite.yaml coralnpu_soc.sdc
    ├── chip/  config.yaml config.lite.yaml chip_top.sdc
    └── scripts/ run_flow.sh place_srams.py report.py
```

---

## Environment Setup (Lab 0)

**Estimated Time:** 30–60 นาที
**Objective:** ติดตั้งเครื่องมือทั้งหมดและยืนยันว่า LibreLane กับ sky130 PDK ใช้งานได้

1. แตกไฟล์โปรเจกต์และเข้าไปในโฟลเดอร์:
   ```bash
   unzip coralnpu-sky130.zip && cd coralnpu-sky130
   ```
2. รันสคริปต์ติดตั้ง (ต้องใช้ sudo):
   ```bash
   make tools
   ```
3. ปิด terminal ทั้งหมดแล้วเปิดใหม่ เพื่อให้ Nix ทำงาน
4. เข้า LibreLane environment (ครั้งแรกจะดาวน์โหลดราว 3 GB):
   ```bash
   nix-shell ~/librelane/shell.nix
   ```
5. รัน smoke test ซึ่งจะดาวน์โหลด sky130 PDK มาไว้ที่ `~/.ciel` ให้ด้วย:
   ```bash
   librelane --log-level ERROR --condensed --show-progress-bar --smoke-test
   ```
6. ตรวจว่า PDK มี SRAM macro และ pad library ครบ:
   ```bash
   cd coralnpu-sky130
   make pdk
   ```

> ✅ **จุดตรวจสอบ:** `make pdk` ต้องขึ้น `ok` ทุกบรรทัดและจบด้วย `>>> PDK OK` (สคริปต์ `scripts/check_pdk.sh` ตรวจไฟล์ standard cell, pad และ SRAM ที่ flow ต้องใช้ทีละไฟล์)

> 📝 **หมายเหตุ:** ทุกคำสั่งตั้งแต่นี้ไปให้รัน **ภายใน nix-shell** ยกเว้นขั้นที่ใช้ Bazel ซึ่งรันได้ทั้งในและนอก nix-shell

> 💡 **เคล็ดลับ (Docker แทน Nix):** `pip3 install git+https://github.com/librelane/librelane@3.1.0.dev4` แล้วใส่ `LIBRELANE="librelane --dockerized"` นำหน้าคำสั่ง make ทุกครั้ง เช่น `LIBRELANE="librelane --dockerized" make soc` โดย `run_flow.sh` จะรันจาก root ของโปรเจกต์ container จึงมองเห็นทั้ง `rtl/` และ `flow/`

### อัปเกรดจาก LibreLane 3.0.x (ถ้าติดตั้งไว้ก่อนแล้ว)

1. ออกจาก nix-shell เดิม แล้วสลับ LibreLane ไปเวอร์ชัน 3.1:
   ```bash
   git -C ~/librelane fetch --tags
   git -C ~/librelane checkout 3.1.0.dev4
   ```
2. เข้า nix-shell ใหม่ (จะดาวน์โหลดเครื่องมือชุดใหม่ เช่น Yosys 0.69, Magic 8.3.677, KLayout 0.30.12):
   ```bash
   nix-shell ~/librelane/shell.nix
   librelane --version
   ```
3. Enable PDK ตัวใหม่ที่ LibreLane 3.1 ล็อกไว้ (open_pdks `792ef67…`):
   ```bash
   make pdk
   ```
4. ลบ run เก่าที่สร้างด้วย 3.0.x เพราะ state และ PDK ไม่ตรงกันแล้ว:
   ```bash
   rm -rf flow/soc/runs flow/chip/runs
   ```

> 📝 **หมายเหตุ:** สิ่งที่เปลี่ยนในโปรเจกต์สำหรับ 3.1: config ใช้ `meta.version: 3`, เลิกใช้ `pad_cfg.tcl` ที่ copy มาแก้ (ใช้ `PAD_SPACING_MULTIPLE` และ `PAD_ROTATION_*` ของ PDK แทน), core ring ย้ายไป met2/met3 พร้อม `PDN_CORE_RING_CONNECT_TO_PAD_LAYERS`, และ `chip_top.v` ต่อ rail ของ pad ring ใต้ `USE_POWER_PINS` ตาม reference design `full_chip_sky130` ของ LibreLane

> ⚠️ **คำเตือน:** 3.1.0.dev4 เป็นรุ่น pre-release (ยังไม่มี 3.1.0 บน PyPI ณ วันที่เขียน) เมื่อออก 3.1.0 ตัวจริง ให้ checkout tag นั้นแทนได้เลย โดย `run_flow.sh` รับทุกเวอร์ชันตั้งแต่ 3.1 ขึ้นไป

### Troubleshooting

| Problem | Solution |
|---|---|
| `nix: command not found` | ยังไม่ได้เปิด terminal ใหม่หลังติดตั้ง Nix |
| smoke test ดาวน์โหลด PDK ไม่ได้ | ตรวจ proxy/firewall ว่าออก `github.com` และ `fossi-foundation.github.io` ได้ |
| `make pdk` ไม่พบ `sky130_sram_macros` | ลบ `~/.ciel/ciel/sky130/versions/<hash>` แล้วรัน `make pdk` ใหม่ |
| `Failed to download PDK: Unknown library sky130_ef_io for PDK sky130` | ห้ามส่ง `--pad sky130_ef_io` หรือตั้ง `PAD_CELL_LIBRARY` เพราะ LibreLane ส่งค่านี้ให้ ciel เป็นชื่อ library ที่จะดาวน์โหลด (ciel รู้จักแค่ `sky130_fd_io`) zip รุ่นล่าสุด `unset` ให้แล้ว ถ้าเรียก `librelane` เองให้ `unset PAD_CELL_LIBRARY` |
| `make pdk` ขึ้น `MISSING` | รัน `ciel enable --pdk-root ~/.ciel --pdk-family sky130 -l all <hash>` ตามที่สคริปต์แนะนำ |
| `make pdk` ตรวจที่ `~/.ciel/ihp-sg13g2` (หรือ PDK อื่น) | shell มีตัวแปร `PDK` ค้างจาก lab อื่น ตั้งแต่ zip รุ่นนี้ Makefile และ `run_flow.sh` บังคับใช้ `sky130A` / `sky130_fd_sc_hd` ให้เอง (pad library `sky130_ef_io` ถูกเลือกโดย config ของ PDK) แต่ควร `unset PDK STD_CELL_LIBRARY PAD_CELL_LIBRARY` ด้วย เพราะ `librelane` ที่เรียกตรง ๆ จะอ่านตัวแปรพวกนี้ |
| `make pdk` ขึ้น `libs.ref not found` | ตัวแปร `PDK`/`PDK_ROOT` ใน environment ทับค่าของ Makefile ให้ `unset PDK PDK_ROOT` หรือส่งค่าเอง `make pdk PDK=sky130A PDK_ROOT=~/.ciel` |

---

## Lab 1: สร้าง RTL ของ CoralNPU และปรับให้เข้ากับ SKY130

**Estimated Time:** 30–90 นาที (Bazel build ครั้งแรกนาน)
**Objective:** ได้ไฟล์ `rtl/generated/CoralNPUCore.sv` ที่พร้อมใช้กับ sky130

### Background

CoralNPU เขียนด้วย Chisel และใช้ firtool แปลงเป็น SystemVerilog ไฟล์เดียว ส่วนที่ขึ้นกับเทคโนโลยีมีเพียง 2 black box คือ `Sram` (128 บิต byte-mask) และ `ClockGate` สคริปต์ `prepare_rtl.py` จะถอดสองโมดูลนี้ออกและใช้ไฟล์ใน `rtl/sky130/` แทน จากนั้นเปลี่ยนชื่อ top เป็น `CoralNPUCore` เพื่อให้ wrapper ใช้ได้กับทุก variant และตรวจว่าทุก input ของ core ถูกต่อใน `coralnpu_soc.v` แล้ว

### Instructions

1. Clone CoralNPU ไปไว้ที่ `third_party/coralnpu` ที่ commit ที่ทดสอบแล้ว:
   ```bash
   make fetch
   ```
2. สร้าง RTL รุ่น lite (สำหรับรอบแรก):
   ```bash
   make rtl VARIANT=lite
   ```
   หรือรุ่นเต็ม:
   ```bash
   make rtl VARIANT=full
   ```
3. เปิดดูผลลัพธ์ของ `prepare_rtl.py` ในหน้าจอ:
   ```text
   [prepare_rtl] top module      : CoreMini_ITCM8KB_DTCM8KBAxi
   [prepare_rtl] removed Sram      : 1 definition(s)
   [prepare_rtl] removed ClockGate : 1 definition(s)
   [prepare_rtl] core ports      : ...
   [prepare_rtl] port check      : OK
   ```
4. (ทางเลือก) Lint RTL ทั้งหมดด้วย Verilator:
   ```bash
   make lint
   ```

> 💡 **เคล็ดลับ:** สำหรับรุ่น `lite` สคริปต์จะเพิ่ม Bazel target `core_mini_lite_axi_cc_library` ต่อท้าย `hdl/chisel/src/coralnpu/BUILD` ให้อัตโนมัติ (ดู `patches/coralnpu_lite_target.bzl.txt`)

> ⚠️ **คำเตือน:** ถ้า `prepare_rtl.py` แจ้ง `core inputs not driven by coralnpu_soc.v` แปลว่า CoralNPU เวอร์ชันที่ใช้มีพอร์ตใหม่ ให้เพิ่มการต่อพอร์ตนั้น (ส่วนใหญ่ tie เป็น 0) ใน `rtl/soc/coralnpu_soc.v` แล้วรัน `make rtl` ซ้ำ

### Expected Result

- `rtl/generated/CoralNPUCore.sv` มีขนาดหลาย MB
- `rtl/generated/VARIANT` เก็บชื่อ variant ที่สร้าง

### Troubleshooting

| Problem | Solution |
|---|---|
| Bazel โหลด `bcr.bazel.build` หรือ `repo1.maven.org` ไม่ได้ | ต้องออก internet ได้ หรือใช้ `--registry=<mirror>` ของ BCR |
| `CC` หา compiler ไม่เจอ | `sudo apt install build-essential clang` หรือกำหนด `CC=gcc make rtl` |
| Bazel ใช้ RAM มากจนเครื่องค้าง | เพิ่ม `--jobs=4` โดยแก้บรรทัด `bazel build` ใน `scripts/emit_rtl.sh` |

---

## Lab 2: ตรวจสอบ SoC ด้วย Simulation และสร้างโปรแกรมทดสอบ

**Estimated Time:** 30 นาที
**Objective:** ยืนยันว่า SPI→AXI bridge, AXI GPIO และ SRAM wrapper ทำงานถูกต้องก่อนเข้าสู่ physical flow

### Background

`tb/core_stub.v` เป็นโมเดลจำลองที่มีพอร์ตเหมือน `CoralNPUCore` ทุกประการ แต่ใช้ `Sram` wrapper ตัวจริงต่อกับ OpenRAM behavioral model ของ PDK จึงทดสอบ glue logic ได้โดยไม่ต้องรอ Chisel build ส่วน `tb_soc_real.v` จะรัน **core จริง** พร้อมโปรแกรม C ที่โหลดผ่าน SPI

### Instructions

1. รัน SoC test-bench (ใช้ Icarus Verilog):
   ```bash
   make sim
   ```
2. รัน unit test ของ SRAM wrapper (128/512/2048 entries, byte-mask, data hold):
   ```bash
   make sim-sram
   ```
3. Build โปรแกรมตัวอย่าง `sw/gpio_demo.c` ด้วย toolchain ของ CoralNPU:
   ```bash
   make sw VARIANT=lite
   ```
4. รันโปรแกรมบน core จริง (Verilator 5 ซึ่งมีใน nix-shell):
   ```bash
   make sim-real VARIANT=lite ELF=build/sky130_gpio_demo_lite.elf EXPECT=81
   ```
5. (ทางเลือก) เปิด waveform ของ test-bench แบบ stub (ไฟล์เกิดจาก `make sim` จึงต้องรัน `make sim` หลัง `make clean` ทุกครั้ง):
   ```bash
   make sim && gtkwave build/tb_soc.vcd
   ```
6. (ทางเลือก) เปิด waveform ของ core จริง (บันทึก tb, SoC และพอร์ตของ core ลึก 3 ชั้นเป็นไฟล์ FST):
   ```bash
   make sim-real VARIANT=lite ELF=build/sky130_gpio_demo_lite.elf EXPECT=81 WAVES=1
   gtkwave build/tb_soc_real.fst
   ```

> ✅ **จุดตรวจสอบ:** `make sim` ต้องแสดง `*** TEST PASSED ***` และ `make sim-sram` ต้องแสดง `*** SRAM TEST PASSED ***`

### Expected Result

```text
[tb] READ_ID
  ok   chip id = 0x434e5055
[tb] write/read ITCM through SPI -> AXI -> SRAM wrapper
  ok   itcm word = 0xa5000777
  ...
  ok   halted = 0x00000001
  ok   gpio_out = 0x0000003c
*** TEST PASSED ***
```

ใน `sim-real` จะเห็น `gpio_out` วิ่งแบบ knight-rider แล้วจบที่ `0x81` (385 & 0xFF) และ `*** REAL CORE TEST PASSED ***`

### Memory map ที่ต้องรู้

| ช่วง | full | lite |
|---|---|---|
| ITCM | `0x0000_0000` – `0x0000_1FFF` | `0x0000_0000` – `0x0000_1FFF` |
| DTCM | `0x0001_0000` – `0x0001_7FFF` | `0x0010_0000` – `0x0010_1FFF` |
| CSR (reset/PC/status) | `0x0003_0000` | `0x0020_0000` |
| GPIO (AXI master port) | `0x8000_0000` | `0x8000_0000` |

ลำดับการบูต: เขียนโปรแกรมลง ITCM/DTCM → `CSR+0x4 = entry PC` → `CSR+0x0 = 1` (เปิด clock) → `CSR+0x0 = 0` (ปล่อย reset)

### Troubleshooting

| Problem | Solution |
|---|---|
| `Scope index expression is not constant: addr0_reg` ใน `sky130_sram_2kbyte_1rw1r_32x512_8.v` | โมเดลของ PDK ใช้ `mem` ก่อนประกาศ Icarus 13 (ใน nix-shell) ไม่ยอม ตั้งแต่ zip รุ่นนี้ Makefile สร้างสำเนาที่แก้แล้วไว้ที่ `build/*.sim.v` ให้อัตโนมัติ (`scripts/patch_sram_model.py`) ถ้ายังเจอให้ `make clean` แล้วรันใหม่ |
| `SRAM model not found` | รัน `make pdk` หรือส่งพาธเอง: `make sim SRAM_MODEL_PDK=/path/to/sky130_sram_2kbyte_1rw1r_32x512_8.v` |
| `sim-real` ขึ้น `fault=1` | โปรแกรมถูกคอมไพล์ให้ใช้คำสั่ง vector/float ที่ core ไม่มี ให้ตรวจ `copts` ใน `sw/BUILD.bazel` และใช้ target `_lite` กับ VARIANT=lite |
| Verilator error `--timing` | ต้องใช้ Verilator ≥ 5.020 (ใช้ตัวที่มากับ nix-shell) |

---

## Lab 3: ทำความเข้าใจการปรับ CoralNPU ให้เป็นเทคโนโลยี SKY130

**Estimated Time:** 30 นาที (อ่านและทำความเข้าใจโค้ด)
**Objective:** เข้าใจการออกแบบ 4 จุดที่ทำให้ CoralNPU ใช้กับ sky130 ได้ เพื่อแก้ไขต่อเองได้

### Background

ไฟล์ทั้งหมดใน `rtl/` เขียนขึ้นสำหรับโปรเจกต์นี้ ไม่ได้แก้ RTL ของ CoralNPU โดยตรง

### Instructions

1. เปิด `rtl/sky130/Sram_sky130.v` แล้วสังเกตการแมป:
   - 1 entry ขนาด 128 บิต แบ่งเป็น 4 slice × 32 บิต แต่ละ slice เป็น `sky130_sram_2kbyte_1rw1r_32x512_8` (32 บิต × 512, write mask 8 บิต)
   - `wmask[15:0]` ของ CoralNPU แมปตรงกับ `wmask0[3:0]` ของแต่ละ macro
   - OpenRAM ขับ `dout0` เฉพาะช่วงหลัง falling edge ของรอบที่อ่าน จึงมี `rdata_hold` คงค่าไว้ให้เหมือนโมเดล generic ของ CoralNPU
   - ชื่อ instance ทุกตัวมีคำว่า `u_sky130sram` ซึ่ง flow ใช้ทั้งต่อไฟเลี้ยงและวาง macro
2. เปิด `rtl/sky130/ClockGate_sky130.v` แล้วดูว่า ICG แมปไปที่ `sky130_fd_sc_hd__sdlclkp_4` (GATE=enable, SCE=te)
3. เปิด `rtl/soc/spi_axi_bridge.v` และดูโปรโตคอล SPI:

   | คำสั่ง | ไบต์ที่ส่ง | ผลลัพธ์ |
   |---|---|---|
   | `0x02` WRITE32 | `02 A3 A2 A1 A0 D3 D2 D1 D0` | AXI write 32 บิต |
   | `0x03` READ32 | `03 A3 A2 A1 A0 xx Q3 Q2 Q1 Q0` | xx = status, Q = data |
   | `0x05` STATUS | `05 S` | busy/err/halted/fault/wfi |
   | `0x9F` READ_ID | `9F I3 I2 I1 I0` | `0x434E5055` ("CNPU") |

4. เปิด `scripts/gen_chip_top.py` แล้วดูตาราง `PADS` ซึ่งกำหนดทั้ง pin-out, ด้านของ pad และชนิด pad (in/out/power)

> ⚠️ **คำเตือน:** SPI bridge oversample สัญญาณด้วย core clock จึงต้องใช้ `f_sck ≤ f_clk/16` (เช่น clock 25 MHz ใช้ SPI ไม่เกิน ~1.5 MHz)

> 💡 **เคล็ดลับ:** ถ้าต้องการเปลี่ยน pin-out ให้แก้ตาราง `PADS` แล้วรัน `make chip-top` ทั้ง `rtl/chip/chip_top.v` และรายการ `PAD_SOUTH/EAST/NORTH/WEST` ใน `flow/chip/config*.yaml` จะถูกสร้างใหม่ให้ตรงกัน

### Expected Result

อธิบายได้ว่าทำไม ITCM ใช้ 4 macro และ DTCM ใช้ 16 macro (รุ่น full) และตอบได้ว่าทำไม flow ต้องรู้ชื่อ instance ของ macro หลัง synthesis

---

## Lab 4: Block-level Hardening ของ `coralnpu_soc` (Classic flow)

**Estimated Time:** 2–8 ชั่วโมง (รอเครื่อง)
**Objective:** Harden `coralnpu_soc` พร้อม SRAM macro ให้ผ่าน sign-off และเรียนรู้การปรับ floorplan จากผลจริง

### Background

LibreLane 3 ไม่มีขั้นตอนวาง macro อัตโนมัติใน Classic flow และชื่อ instance ของ SRAM ถูก Yosys สร้างขึ้นตอน flatten hierarchy ของ Chisel `run_flow.sh` จึงรันเป็น 2 pass:

1. **Pass 1:** รัน synthesis และ checker ถึง `Checker.NetlistAssignStatements`
2. **Place:** `place_srams.py` อ่านชื่อ macro จาก netlist แล้วเขียน `macro_placement.cfg` (เรียงเป็นแถว แถวละ 4 slice ของ bank เดียวกัน)
3. **Pass 2:** resume run เดิมด้วย `--from OpenROAD.CheckSDCFiles` ไปจนถึง sign-off

### Instructions

1. เริ่ม flow ของ block (ตัวอย่างนี้ใช้ lite):
   ```bash
   make soc VARIANT=lite
   ```
2. ดูรายงานหลัง synthesis ซึ่ง script พิมพ์ระหว่าง pass 1 และ 2:
   ```text
   [place_srams] 8 SRAM macros -> flow/soc/macro_placement.cfg
   [place_srams] grid 4 x 2, macro block occupies y = 50 .. 943 um
    Std-cell area (um^2)        ...
   ```
3. ตรวจขนาด die ที่เหมาะสมด้วยสูตร:
   ```text
   DIE_AREA_min ≈ stdcell_area / 0.45  +  N_macro × 683.1 × 416.54 × 1.3
   ```
   ถ้าค่าที่ได้มากกว่า die ใน `flow/soc/config.lite.yaml` (3.2 × 3.2 mm) ให้ขยาย `DIE_AREA`
4. ถ้าแก้ `DIE_AREA` หลัง pass 1 ให้สร้างไฟล์วาง macro ใหม่แล้ว resume:
   ```bash
   python3 flow/scripts/place_srams.py \
     --netlist 'flow/soc/runs/main/*-yosys-synthesis/*.nl.v' \
     --config flow/soc/config.lite.yaml --out flow/soc/macro_placement.cfg
   FROM=OpenROAD.CheckSDCFiles make soc VARIANT=lite
   ```
5. เมื่อ flow จบ ดูสรุปผล:
   ```bash
   make report-soc
   ```
6. เปิด layout ใน KLayout:
   ```bash
   make view-soc VARIANT=lite
   ```

> ✅ **จุดตรวจสอบ:** `report-soc` ต้องได้ `Setup WNS ≥ 0`, `Hold WNS ≥ 0`, `Routing DRC = 0`, `LVS errors = 0`

> 💡 **เคล็ดลับ:** รันใหม่ทั้งหมดด้วย `FRESH=1 make soc` หรือ resume จากขั้นใดก็ได้ด้วย `FROM=<step id>` เช่น `FROM=OpenROAD.GlobalRouting make soc`

### Expected Result

- GDS: `flow/soc/runs/main/final/gds/coralnpu_soc.gds`
- Netlist มีไฟเลี้ยง: `flow/soc/runs/main/final/pnl/coralnpu_soc.pnl.v`
- Metrics: `flow/soc/runs/main/final/metrics.json`

### Troubleshooting

| Problem | Solution |
|---|---|
| `place_srams: core area too small` | ขยาย `DIE_AREA` หรือลด `--hgap/--vgap` ของ `place_srams.py` |
| GPL/DPL ล้มเหลว utilization สูง | ลด `PL_TARGET_DENSITY_PCT` (เช่น 40) หรือขยาย die |
| พื้นที่ cell หลัง synthesis ใหญ่กว่าที่คาด | LibreLane 3.1 เปลี่ยนค่าเริ่มต้น `SYNTH_STRATEGY` เป็น `DELAY 4` ถ้า die ไม่พอให้ลองใส่ `SYNTH_STRATEGY: AREA 1` ใน config (ที่ 25 MHz ไม่จำเป็นต้องเน้น delay) |
| Setup violation | เพิ่ม `CLOCK_PERIOD` (เช่น 50 ns) เพราะ OpenRAM macro มี clock-to-q ช้า หรือดู critical path ใน `*-openroad-stapostpnr/` |
| Hold violation จำนวนมากที่ SRAM | ตรวจว่า clock ไปที่ `clk0` ของ macro ผ่าน CTS แล้ว และรัน `FROM=OpenROAD.ResizerTimingPostCTS` |
| `No match found for regular expression '.*u_sky130sram.*'` | ไม่พบ macro ใน netlist ให้ตรวจว่า `prepare_rtl.py` ถอด `Sram` ออกและ `Sram_sky130.v` อยู่ใน `VERILOG_FILES` |
| KLayout DRC มี error ภายใน SRAM | เป็นเรื่องปกติของ OpenRAM bitcell (ใช้กฎพิเศษของ SRAM) ให้ยึด Magic DRC เป็นหลัก config ตั้ง `ERROR_ON_KLAYOUT_DRC: false` ไว้แล้ว |
| LVS ช้าหรือ mismatch ภายใน SRAM | เพิ่ม `MAGIC_EXT_ABSTRACT_CELLS: [sky130_sram_2kbyte_1rw1r_32x512_8]` ใน config ให้ extract macro แบบ abstract |

---

## Lab 5: Full-Chip Implementation พร้อม Pad Ring (Chip flow)

**Estimated Time:** 3–12 ชั่วโมง (รอเครื่อง)
**Objective:** สร้าง GDS ระดับชิปที่มี pad ring `sky130_ef_io`, core ring ต่อกับ power pad, seal ring และ metal fill

### Background

LibreLane `Chip` flow คือ Classic flow ที่เพิ่ม `OpenROAD.PadRing` หลัง `Odb.SetPowerConnections` ตัดขั้น IO pin placement ออก (ใช้ pad เป็นขั้วแทน) และเพิ่ม `KLayout.Antenna`, `KLayout.SealRing`, `KLayout.Filler`, `KLayout.Density` ตอนท้าย

การตั้งค่าหลักใน `flow/chip/config.yaml`:

| ตัวแปร | ค่า | ความหมาย |
|---|---|---|
| `DIE_AREA` / `CORE_AREA` | 5000² / 300…4700 | pad สูง 200 µm, corner 200×204 µm |
| `PAD_SOUTH/EAST/NORTH/WEST` | 30 pad | สร้างจาก `gen_chip_top.py` |
| `PAD_SPACING_MULTIPLE` | `2.0` | (ใหม่ใน 3.1) ปัดระยะห่าง pad เป็นทวีคูณ 2 µm ให้เศษหารด้วย site 1 µm ลงตัวเสมอ |
| `PAD_ROTATION_*` | `R180` (จาก PDK) | (ใหม่ใน 3.1) หมุน pad ของ sky130 ให้ถูกทิศ |
| `VDD_NETS` / `GND_NETS` | `VCCD` / `VSSD` | ไฟ 1.8 V ของ core |
| `PDN_MACRO_CONNECTIONS` | `.*u_sky130sram.*` | ต่อ `vccd1/vssd1` ของ SRAM เข้ากับ `VCCD/VSSD` (ไฟของ pad มาจากการต่อใน `chip_top.v` ใต้ `USE_POWER_PINS`) |
| `PDN_CORE_VERTICAL/HORIZONTAL_LAYER` | `met2` / `met3` | core ring อยู่บน met2/met3 |
| `PDN_CORE_RING_CONNECT_TO_PAD_LAYERS` | `[met3]` | (ใหม่ใน 3.1) ต่อ core ring เข้าขาไฟของ pad ผ่าน met3 เท่านั้น |
| `IGNORE_DISCONNECTED_MODULES` | power/ground `wpad` ของ pad | ไม่ให้ checker นับเป็น error |
| `PDN_CORE_RING_CONNECT_TO_PADS` | `true` | core ring ต่อเข้ากับ power pad |

Pad แบบ `sky130_ef_io__gpiov2_pad` ต้องตั้งขา control ให้ถูก ซึ่ง `gen_chip_top.py` ทำให้แล้ว:

| ขา | Input pad | Output pad |
|---|---|---|
| `DM[2:0]` | `001` (input only) | `110` (strong push-pull) |
| `OE_N` | 1 | 0 |
| `INP_DIS` | 0 | 1 |
| `HLD_H_N`, `ENABLE_H`, `ENABLE_INP_H` | `TIE_HI_ESD` ของ pad เอง | `TIE_HI_ESD` |
| `ENABLE_VDDA_H`, `ENABLE_VSWITCH_H` | `TIE_LO_ESD` ของ pad เอง (ไม่ใช้โดเมน VDDA) | `TIE_LO_ESD` |
| `ENABLE_VDDIO` | 1 | 1 |

### Instructions

1. (ถ้าแก้ pin-out) สร้าง `chip_top.v` และรายการ pad ใหม่:
   ```bash
   make chip-top
   ```
2. รัน full-chip flow:
   ```bash
   make chip VARIANT=lite
   ```
   หรือรุ่นเต็ม:
   ```bash
   make chip VARIANT=full
   ```
3. ตรวจผลขั้น pad ring ใน log:
   ```bash
   grep -hE "space_side|Placing pads|Placing corner" flow/chip/runs/main/*-openroad-padring/*.log
   ```
4. เมื่อ flow จบ ดูสรุป sign-off:
   ```bash
   make report-chip
   ```
5. เปิด layout ของชิปทั้งตัว:
   ```bash
   make view-chip VARIANT=lite
   ```

> ✅ **จุดตรวจสอบ:** ใน KLayout ต้องเห็น pad 30 ตัวรอบชิป, corner 4 มุม, filler `com_bus_slice` เต็มช่องว่าง, seal ring รอบนอก และ SRAM เรียงแถวด้านล่างของ core

> ⚠️ **คำเตือน:** Pad ring ในโปรเจกต์นี้ (เช่นเดียวกับ reference design `full_chip_sky130` ของ LibreLane) ต่อเฉพาะ `VCCD/VSSD` (1.8 V) และ `VDDIO/VSSIO` (3.3 V) ส่วน rail `VDDA/VSSA/VCCHIB/VSWITCH` ของ ring ไม่มี pad จ่ายไฟ ถ้าจะ tape-out จริงต้องเพิ่ม pad หรือ connect slice ของ `sky130_ef_io` (เช่น `sky130_ef_io__connect_vcchib_vccd_and_vswitch_vddio_slice_20um`) และวงจร power-on-reset สำหรับ `ENABLE_H` แล้วรัน LVS ยืนยัน หรือใช้ harness ของ shuttle (Caravel/OpenFrame) แทน pad ring ของตนเอง

### Expected Result

- GDS ระดับชิป: `flow/chip/runs/main/final/gds/chip_top.gds`
- รายงาน density และ antenna จาก KLayout อยู่ในโฟลเดอร์ `*-klayout-density/` และ `*-klayout-antenna/`

### Troubleshooting

| Problem | Solution |
|---|---|
| `Sum of cell widths for PAD_xxx is larger than the width of this side` | ย้าย pad ไปด้านอื่นในตาราง `PADS` หรือขยาย `DIE_AREA` |
| `No instance pad_xxx found` | `chip_top.v` กับ config ไม่ตรงกัน ให้รัน `make chip-top` |
| `Unknown key 'PAD_SPACING_MULTIPLE'` | ใช้ LibreLane เก่ากว่า 3.1 ให้ `git -C ~/librelane checkout 3.1.0.dev4` แล้วเข้า nix-shell ใหม่ (`run_flow.sh` ตรวจเวอร์ชันให้ก่อนรัน) |
| `The remaining area for the pads ... is not divisible` | ปรับ `PAD_SPACING_MULTIPLE` (เช่น 4.0) หรือเปลี่ยน `DIE_AREA` ทีละ 2 µm |
| core ring ไม่ต่อกับ pad | ตรวจว่า power pad อยู่ห่าง core ring ไม่เกินช่วงที่ `-connect_to_pads` เอื้อมถึง (ลด `CORE_AREA` offset ให้ใกล้ pad) และดูว่า `PDN_CORE_RING_CONNECT_TO_PAD_LAYERS` ตรงกับชั้นโลหะของขาไฟ pad |
| KLayout density fail | ปรับ `KLAYOUT_FILLER_OPTIONS` หรือ config ตั้ง `ERROR_ON_KLAYOUT_DENSITY: false` ไว้เพื่อให้ flow จบก่อนแล้วค่อยแก้ |

---

## Lab 6: Sign-off และการอ่านผล

**Estimated Time:** 30–60 นาที
**Objective:** ตรวจว่า GDS ผ่านเกณฑ์ sign-off และรู้ว่าแต่ละรายงานอยู่ที่ไหน

### Instructions

1. ดูสรุปผลรวม:
   ```bash
   python3 flow/scripts/report.py flow/chip/runs/main
   ```
2. ตรวจ timing ทุก corner (nom/min/max × tt/ss/ff):
   ```bash
   ls flow/chip/runs/main/*-openroad-stapostpnr/
   cat flow/chip/runs/main/*-openroad-stapostpnr/*summary*
   ```
3. ตรวจ DRC จาก Magic และ KLayout:
   ```bash
   ls flow/chip/runs/main/*-magic-drc/ flow/chip/runs/main/*-klayout-drc/
   ```
4. ตรวจ LVS:
   ```bash
   ls flow/chip/runs/main/*-netgen-lvs/
   grep -h "Final result" flow/chip/runs/main/*-netgen-lvs/*.rpt
   ```
5. ตรวจ IR drop:
   ```bash
   ls flow/chip/runs/main/*-openroad-irdropreport/
   ```

### เกณฑ์ Sign-off

| รายการ | เกณฑ์ | Metric |
|---|---|---|
| Setup timing ทุก corner | WNS ≥ 0 | `timing__setup__ws` |
| Hold timing ทุก corner | WNS ≥ 0 | `timing__hold__ws` |
| Max slew/cap | 0 violation | `design__max_slew_violation__count` |
| Routing DRC | 0 | `route__drc_errors` |
| Magic DRC | 0 (นอก SRAM) | `magic__drc_error__count` |
| LVS | 0 | `design__lvs_error__count` |
| Antenna | 0 หรือยอมรับได้ | `antenna__violating__nets` |

> ✅ **จุดตรวจสอบ:** ทุกแถวในตารางผ่าน แล้ว GDS ใน `final/gds/` จึงพร้อมส่งตรวจ precheck ของ shuttle

---

## Lab 7: Bring-up บนชิปจริงหรือ FPGA ผ่าน SPI

**Estimated Time:** 30 นาที
**Objective:** โหลดและรันโปรแกรมผ่าน SPI ด้วย FT232H

### Instructions

1. ต่อสาย FT232H → ชิป: `AD0=spi_sck`, `AD1=spi_mosi`, `AD2=spi_miso`, `AD3=spi_csb` และ GND ร่วมกัน (ชิปใช้ VDDIO 3.3 V)
2. ป้อน clock 25 MHz ที่ `clk` แล้วปล่อย `rst_n` เป็น 1
3. ติดตั้ง pyftdi:
   ```bash
   pip install pyftdi
   ```
4. โหลดและรันโปรแกรม:
   ```bash
   python3 sw/spi_host.py build/sky130_gpio_demo_lite.elf --variant lite \
     --ftdi ftdi://ftdi:232h/1 --freq 1e6 --verify
   ```
5. ทดสอบโดยไม่ต่อฮาร์ดแวร์ (แสดงเฉพาะ transaction):
   ```bash
   python3 sw/spi_host.py build/sky130_gpio_demo_lite.elf --variant lite --dry-run
   ```

### Expected Result

```text
[spi_host] chip id 0x434e5055 OK
[spi_host] verify: 0 mismatches
[spi_host] status: halted, alive
```

LED ที่ `gpio_out[7:0]` วิ่งไปกลับ 2 รอบแล้วค้างที่ `1000_0001`

---

## Summary & Key Takeaways

- IP ที่เขียนด้วย Chisel อย่าง CoralNPU แยกส่วนที่ขึ้นกับเทคโนโลยีไว้ใน black box เพียงไม่กี่ตัว (`Sram`, `ClockGate`) การย้ายไป PDK ใหม่จึงทำได้ด้วย wrapper โดยไม่ต้องแก้ RTL ต้นฉบับ
- SRAM เป็นตัวกำหนดหลักทั้งพื้นที่ (20 macro ≈ 5.7 mm²) และความเร็ว (~25 MHz) ของชิป sky130
- เมื่อ flow ไม่มีขั้นวาง macro อัตโนมัติ การอ่านชื่อ instance จาก netlist แล้ว resume run เป็นวิธีที่แข็งแรงกว่าการ hard-code ชื่อ
- Full chip ต่างจาก block ตรงที่มี pad ring, การจ่ายไฟผ่าน power pad, seal ring และ density fill ซึ่ง LibreLane `Chip` flow จัดการให้
- ตรวจด้วย simulation ก่อนเข้า flow เสมอ: bug ใน glue logic ที่หลุดเข้าไปถึง GDS แก้ได้ยากมาก

## Next Steps / Further Reading

- CoralNPU: <https://github.com/google-coral/coralnpu> (`doc/integration_guide.md`, `synthesis/BUILDING_CORALNPU_WITH_OPENROAD.md`)
- LibreLane documentation: <https://librelane.readthedocs.io>
- SKY130 PDK / sky130_fd_io user guide: <https://skywater-pdk.readthedocs.io>
- OpenRAM SKY130 macros: <https://github.com/fossi-foundation/sky130_sram_macros>

**Challenge exercises**

1. ลด `CLOCK_PERIOD` ลงทีละ 5 ns จนกว่า setup timing ไม่ผ่าน แล้วหา critical path
2. เพิ่ม UART TX ใน `axi_gpio_slave.v` แล้วแก้ `gpio_demo.c` ให้พิมพ์ข้อความ
3. Harden `coralnpu_soc` เป็น macro แล้วนำไปวางใน Caravel `user_project_wrapper`
4. เพิ่ม connect slice ของ ring (`VDDA/VCCHIB/VSWITCH`) และทำ LVS ให้ผ่านเพื่อให้ pad ring พร้อม tape-out

---

## Appendix A: คำสั่ง make ทั้งหมด

| คำสั่ง | หน้าที่ |
|---|---|
| `make tools` | ติดตั้ง apt packages, Bazelisk, Nix, LibreLane 3.1.0.dev4 |
| `make pdk` | enable sky130 PDK ด้วย ciel และตรวจ library |
| `make fetch` | clone CoralNPU ที่ commit ที่ทดสอบ |
| `make rtl VARIANT=…` | สร้าง `rtl/generated/CoralNPUCore.sv` |
| `make chip-top` | สร้าง `chip_top.v` และรายการ `PAD_*` ใหม่ |
| `make lint` | Verilator lint ของ SoC |
| `make sim` / `make sim-sram` | test-bench SoC glue / SRAM wrapper |
| `make sw` | build `gpio_demo` ด้วย toolchain ของ CoralNPU |
| `make sim-real ELF=… EXPECT=…` | รันโปรแกรมบน core จริง (Verilator) |
| `make soc` / `make chip` | LibreLane block / full chip |
| `FRESH=1`, `FROM=<step>`, `TAG=<name>`, `JOBS=<n>` | ตัวเลือกของ `run_flow.sh` |
| `make report-soc` / `make report-chip` | สรุป metrics |
| `make view-soc` / `make view-chip` | เปิด KLayout |

## Appendix B: ลำดับขั้นของ LibreLane ที่ควรรู้ (ใช้กับ `FROM=`)

| Step id | ขั้นตอน |
|---|---|
| `Yosys.Synthesis` | synthesis (yosys-slang) |
| `OpenROAD.CheckSDCFiles` | จุดเริ่ม pass 2 |
| `OpenROAD.Floorplan` | floorplan |
| `Odb.ManualMacroPlacement` | วาง SRAM ตาม `macro_placement.cfg` |
| `OpenROAD.PadRing` | สร้าง pad ring (Chip flow) |
| `OpenROAD.GeneratePDN` | power grid |
| `OpenROAD.GlobalPlacement` | global placement |
| `OpenROAD.CTS` | clock tree synthesis |
| `OpenROAD.GlobalRouting` / `OpenROAD.DetailedRouting` | routing |
| `OpenROAD.STAPostPNR` | STA หลัง route ทุก corner |
| `Magic.StreamOut` / `KLayout.StreamOut` | GDS |
| `Magic.DRC` / `KLayout.DRC` / `Netgen.LVS` | sign-off |
| `KLayout.SealRing` / `KLayout.Filler` / `KLayout.Density` | ขั้นท้ายของ Chip flow |

## Appendix C: Pin-out ของชิป

| ด้าน | Pad (ตามลำดับ) |
|---|---|
| South | vssio_0, clk, rst_n, vccd_0, vssd_0, spi_sck, spi_csb, vddio_0 |
| East | spi_mosi, spi_miso, irq, gpio_in0..3 |
| North | vssio_1, gpio_out0..3, vccd_1, vssd_1, vddio_1 |
| West | gpio_out4..7, halted, fault, wfi |

## Appendix D: สถานะการทดสอบของโปรเจกต์

| รายการ | สถานะ |
|---|---|
| `make sim` (SPI bridge + AXI GPIO + SRAM wrapper + OpenRAM model) | ✅ ผ่าน (Icarus Verilog 12) |
| `make sim-sram` (128/512/2048 entries, byte-mask, data hold) | ✅ ผ่าน |
| Yosys + slang synthesis ของ `chip_top` (pads + SoC + SRAM, ใช้ stub core) | ✅ ผ่าน ได้ 30 pad + SRAM macro ครบ |
| ตรวจ config ทั้ง 4 ไฟล์กับ LibreLane 3.1.0.dev4 `Config.load` และ step id ที่ flow ใช้ | ✅ ผ่าน ไม่มี variable ที่ไม่รู้จัก |
| Yosys + slang synthesis ของ `chip_top` ทั้งแบบมีและไม่มี `USE_POWER_PINS` | ✅ ผ่าน (22 / 30 พอร์ต ตามลำดับ) |
| `place_srams.py`, `spi_host.py`, `prepare_rtl.py` (ทดสอบกับข้อมูลจำลอง) | ✅ ผ่าน |
| Chisel/Bazel emit RTL ของ CoralNPU จริง | ⏳ ยังไม่ได้ทดสอบในสภาพแวดล้อมที่เตรียมงาน (เครือข่ายเข้า Maven/BCR ไม่ได้) |
| LibreLane PnR เต็มรูปแบบ (soc/chip) | ⏳ ยังไม่ได้รันจริง ต้องใช้ PDK และเวลาหลายชั่วโมง ให้เริ่มจาก `VARIANT=lite` และดู Troubleshooting ในแต่ละ Lab |
