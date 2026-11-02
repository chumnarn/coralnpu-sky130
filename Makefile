# SPDX-License-Identifier: Apache-2.0
# =============================================================================
# coralnpu-sky130 - CoralNPU full-chip implementation with LibreLane + sky130A
# =============================================================================
#   make help                     list targets
#   make fetch rtl                clone CoralNPU, generate + prepare RTL
#   make sim                      SoC glue test-bench (stub core, Icarus)
#   make soc   [VARIANT=lite]     harden coralnpu_soc block   (Classic flow)
#   make chip  [VARIANT=lite]     full chip with pad ring     (Chip flow)
# =============================================================================
SHELL        := /bin/bash
ROOT         := $(abspath .)
VARIANT      ?= full
TAG          ?= main
PDK_ROOT     ?= $(HOME)/.ciel
# This project is sky130-only. An inherited PDK/STD_CELL_LIBRARY from the
# shell (e.g. PDK=ihp-sg13g2 left over from another lab) is ignored on purpose,
# because LibreLane and ciel would otherwise silently use it.
ifneq ($(filter sky130A sky130B,$(PDK)),$(PDK))
  ifneq ($(origin PDK),command line)
    $(info NOTE: ignoring PDK=$(PDK) from the environment, using sky130A)
  endif
endif
ifeq ($(filter sky130A sky130B,$(PDK)),)
  override PDK := sky130A
endif
override STD_CELL_LIBRARY := sky130_fd_sc_hd
override PAD_CELL_LIBRARY := sky130_ef_io
# sky130 open_pdks build pinned by LibreLane 3.1.0 (librelane/pdk_hashes.yaml)
SKY130_HASH  ?= 792ef67037d74c8c51811eab3ce23cf793491296
LIBRELANE    ?= librelane
BAZEL        ?= bazel
CORALNPU_DIR ?= $(ROOT)/third_party/coralnpu
ELF          ?=
EXPECT       ?= 81
WAVES        ?= 0
ifeq ($(WAVES),1)
  VL_WAVES   := --trace-fst --trace-structs -DWAVES
endif

ifeq ($(VARIANT),lite)
  CONFIG     := config.lite.yaml
  SW_TARGET  := sky130_gpio_demo_lite
else
  CONFIG     := config.yaml
  SW_TARGET  := sky130_gpio_demo
endif

SRAM_MODEL_PDK ?= $(PDK_ROOT)/$(PDK)/libs.ref/sky130_sram_macros/verilog/sky130_sram_2kbyte_1rw1r_32x512_8.v
# simulator-friendly copy (see scripts/patch_sram_model.py)
SRAM_MODEL   := build/sky130_sram_2kbyte_1rw1r_32x512_8.sim.v
GLUE_RTL     := rtl/soc/spi_axi_bridge.v rtl/soc/axi_gpio_slave.v rtl/soc/coralnpu_soc.v \
                rtl/sky130/Sram_sky130.v rtl/sky130/ClockGate_sky130.v
BUILD        := build

export PDK_ROOT PDK STD_CELL_LIBRARY PAD_CELL_LIBRARY LIBRELANE TAG CORALNPU_DIR BAZEL

.PHONY: help tools pdk fetch check-coralnpu rtl chip-top sw sim sim-sram sim-real lint \
        soc chip report-soc report-chip view-soc view-chip clean distclean

help:
	@echo "coralnpu-sky130 (VARIANT=$(VARIANT), TAG=$(TAG))"
	@echo ""
	@echo "  setup     : tools pdk fetch"
	@echo "  RTL       : rtl  chip-top  lint"
	@echo "  verify    : sim  sim-sram  sw  sim-real ELF=<file.elf> EXPECT=<hex> [WAVES=1]"
	@echo "  implement : soc  chip        (FRESH=1 to restart, FROM=<step> to resume)"
	@echo "  results   : report-soc report-chip view-soc view-chip"
	@echo ""
	@echo "  VARIANT=full : CoreMiniAxi RV32IMF, ITCM 8K + DTCM 32K (20 SRAM macros)"
	@echo "  VARIANT=lite : RV32IM,  ITCM 8K + DTCM 8K (8 SRAM macros, ~2-3x faster flow)"

# ----------------------------------------------------------------- setup
tools:
	bash scripts/install_tools.sh

pdk:
	ciel enable --pdk-root $(PDK_ROOT) --pdk-family sky130 $(SKY130_HASH)
	@bash scripts/check_pdk.sh "$(PDK_ROOT)" "$(PDK)" "$(SKY130_HASH)"

fetch:
	bash scripts/fetch_coralnpu.sh

# ----------------------------------------------------------------- RTL
rtl: check-coralnpu
	bash scripts/emit_rtl.sh $(VARIANT)

chip-top:
	python3 scripts/gen_chip_top.py

lint: rtl/generated/CoralNPUCore.sv $(SRAM_MODEL)
	@mkdir -p $(BUILD)
	verilator --lint-only -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-PINCONNECTEMPTY \
	  -DCORALNPU_BEHAV_CLOCKGATE --top-module coralnpu_soc \
	  rtl/generated/CoralNPUCore.sv $(GLUE_RTL) $(SRAM_MODEL) 2>&1 | tee $(BUILD)/lint.log | tail -20

# ----------------------------------------------------------------- software
check-coralnpu:
	@test -f $(CORALNPU_DIR)/MODULE.bazel || { \
	  echo "ERROR: CoralNPU is not checked out in $(CORALNPU_DIR) (no MODULE.bazel)."; \
	  echo "       Run 'make fetch' first."; exit 1; }

sw: check-coralnpu
	mkdir -p $(CORALNPU_DIR)/examples/sky130
	cp sw/gpio_demo.c sw/BUILD.bazel $(CORALNPU_DIR)/examples/sky130/
	cd $(CORALNPU_DIR) && $(BAZEL) build //examples/sky130:$(SW_TARGET).elf
	@mkdir -p $(BUILD)
	@# The ELF is built in a transitioned configuration (bazel-out/k8-fastbuild-ST-<hash>/),
	@# not in bazel-bin/, so ask Bazel where it is (fallback: search bazel-out).
	@elf=$$(cd $(CORALNPU_DIR) && $(BAZEL) cquery --output=files //examples/sky130:$(SW_TARGET).elf 2>/dev/null | grep '\.elf$$' | head -1); \
	if [ -z "$$elf" ] || [ ! -f "$(CORALNPU_DIR)/$$elf" ]; then \
	  elf=$$(cd $(CORALNPU_DIR) && find -L bazel-out -path '*/bin/examples/sky130/$(SW_TARGET).elf' -newer examples/sky130/gpio_demo.c 2>/dev/null | head -1); \
	fi; \
	test -n "$$elf" || { echo "ERROR: $(SW_TARGET).elf not found under $(CORALNPU_DIR)/bazel-out"; exit 1; }; \
	cp -fL "$(CORALNPU_DIR)/$$elf" $(BUILD)/$(SW_TARGET).elf; \
	echo ">>> $(BUILD)/$(SW_TARGET).elf  (from $$elf)"

# ----------------------------------------------------------------- simulation
sim: $(BUILD)/tb_soc.vvp
	cd $(BUILD) && vvp -n tb_soc.vvp | grep -v -E "Reading|Writing"
	@echo ">>> waveform: gtkwave $(BUILD)/tb_soc.vcd"

$(SRAM_MODEL): $(SRAM_MODEL_PDK) scripts/patch_sram_model.py
	@mkdir -p $(BUILD)
	python3 scripts/patch_sram_model.py $< $@

$(SRAM_MODEL_PDK):
	@echo "SRAM model not found: $@ (run 'make pdk')"; exit 1

$(BUILD)/tb_soc.vvp: tb/tb_soc.v tb/core_stub.v tb/spi_tasks.vh $(GLUE_RTL) $(SRAM_MODEL)
	@mkdir -p $(BUILD)
	iverilog -g2012 -Itb -DCORALNPU_BEHAV_CLOCKGATE -o $@ \
	  tb/tb_soc.v tb/core_stub.v $(GLUE_RTL) $(SRAM_MODEL)

sim-sram: $(SRAM_MODEL)
	@mkdir -p $(BUILD)
	iverilog -g2012 -o $(BUILD)/tb_sram.vvp tb/tb_sram.v rtl/sky130/Sram_sky130.v $(SRAM_MODEL)
	cd $(BUILD) && vvp -n tb_sram.vvp | grep -v -E "Reading|Writing"

# Real CoralNPU RTL + program loaded over SPI (Verilator >= 5.020, e.g. inside nix-shell)
sim-real: rtl/generated/CoralNPUCore.sv $(SRAM_MODEL)
	@test -n "$(ELF)" || { echo "usage: make sim-real ELF=build/$(SW_TARGET).elf [EXPECT=81]"; exit 1; }
	@mkdir -p $(BUILD)
	python3 sw/spi_host.py $(ELF) --variant $(VARIANT) --hex $(BUILD)/prog.hex
	verilator --binary --timing -j 0 $(VL_WAVES) -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN \
	  -DCORALNPU_BEHAV_CLOCKGATE -Itb --top-module tb_soc_real -Mdir $(BUILD)/obj_real \
	  tb/tb_soc_real.v rtl/generated/CoralNPUCore.sv $(GLUE_RTL) $(SRAM_MODEL)
	cd $(BUILD) && ./obj_real/Vtb_soc_real +PROG=prog.hex +EXPECT=$(EXPECT) | grep -v -E "Reading|Writing"
	@if [ "$(WAVES)" = "1" ]; then echo ">>> waveform: gtkwave $(BUILD)/tb_soc_real.fst"; fi

# ----------------------------------------------------------------- implementation
soc: rtl/generated/CoralNPUCore.sv
	bash flow/scripts/run_flow.sh soc $(CONFIG)

chip: rtl/generated/CoralNPUCore.sv rtl/chip/chip_top.v
	bash flow/scripts/run_flow.sh chip $(CONFIG)

report-soc:
	python3 flow/scripts/report.py flow/soc/runs/$(TAG)
report-chip:
	python3 flow/scripts/report.py flow/chip/runs/$(TAG)

view-soc:
	$(LIBRELANE) --last-run --flow openinklayout flow/soc/$(CONFIG)
view-chip:
	$(LIBRELANE) --last-run --flow openinklayout flow/chip/$(CONFIG)

rtl/generated/CoralNPUCore.sv:
	@echo "rtl/generated/CoralNPUCore.sv missing - run: make fetch rtl VARIANT=$(VARIANT)"; exit 1

# ----------------------------------------------------------------- clean
clean:
	rm -rf $(BUILD)
distclean: clean
	rm -rf flow/soc/runs flow/chip/runs flow/*/macro_placement.cfg rtl/generated
