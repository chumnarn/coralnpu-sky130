# SPDX-License-Identifier: Apache-2.0
# -----------------------------------------------------------------------------
# chip_top.sdc - full-chip constraints (LibreLane Chip flow)
#
# The clock enters through the clk pad; it is defined on the pad's core-side
# output pin so the clock tree is rooted inside the core area.
# Every other pad is asynchronous to the core clock (SPI is oversampled,
# GPIO/irq/reset are synchronised) -> false paths.
# -----------------------------------------------------------------------------
set clk_period $::env(CLOCK_PERIOD)

create_clock -name clk -period $clk_period [get_pins pad_clk/IN]
set_clock_uncertainty -setup [expr {$clk_period * 0.03}] [get_clocks clk]
set_clock_uncertainty -hold 0.10 [get_clocks clk]
set_clock_transition 0.30 [get_clocks clk]

# Pad <-> core paths
set_false_path -from [get_ports *_PAD]
set_false_path -to   [get_ports *_PAD]
foreach p {rst_n spi_sck spi_csb spi_mosi irq gpio_in0 gpio_in1 gpio_in2 gpio_in3} {
    set_false_path -from [get_pins -quiet pad_${p}/IN]
}
foreach p {spi_miso gpio_out0 gpio_out1 gpio_out2 gpio_out3 gpio_out4 gpio_out5 gpio_out6 gpio_out7 halted fault wfi} {
    set_false_path -to [get_pins -quiet pad_${p}/OUT]
}

# Quasi-static soft-reset flops inside the core (CSR reset bit, debug module)
set soft_rst [get_cells -hierarchical -quiet {*resetReg_0* *dmcontrol_1*}]
if {[llength $soft_rst] > 0} {
    set_false_path -from $soft_rst
}

set_max_fanout 16 [current_design]
set_max_transition 1.5 [current_design]
