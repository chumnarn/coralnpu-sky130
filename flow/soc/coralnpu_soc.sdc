# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------
# coralnpu_soc.sdc - block-level constraints (LibreLane Classic flow)
#
# All SoC inputs except the clock are asynchronous (SPI, GPIO, reset, irq):
# they are synchronised inside the design, so their paths are false paths.
# -----------------------------------------------------------------------------
set clk_period $::env(CLOCK_PERIOD)

create_clock -name clk -period $clk_period [get_ports clk]
set_clock_uncertainty -setup [expr {$clk_period * 0.03}] [get_clocks clk]
set_clock_uncertainty -hold 0.10 [get_clocks clk]
set_clock_transition 0.15 [get_clocks clk]

# Generic I/O environment
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin Y [all_inputs]
set_load 0.033 [all_outputs]

# Nominal I/O budgets (kept so that STA reports something meaningful)
set non_clk_inputs [lsearch -inline -all -not -exact [all_inputs] [get_ports clk]]
set_input_delay  [expr {$clk_period * 0.20}] -clock clk $non_clk_inputs
set_output_delay [expr {$clk_period * 0.20}] -clock clk [all_outputs]

# Asynchronous / synchronised interfaces
set_false_path -from [get_ports {rst_n spi_sck spi_csb spi_mosi irq gpio_in*}]
set_false_path -to   [get_ports {spi_miso gpio_out* halted fault wfi}]

# Quasi-static soft-reset flops inside the core (CSR reset bit, debug module)
set soft_rst [get_cells -hierarchical -quiet {*resetReg_0* *dmcontrol_1*}]
if {[llength $soft_rst] > 0} {
    set_false_path -from $soft_rst
}

set_max_fanout 16 [current_design]
set_max_transition 1.5 [current_design]
