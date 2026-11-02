// SPDX-License-Identifier: Apache-2.0
// -----------------------------------------------------------------------------
// tb_soc_real.v - run a real program on the *real* CoralNPU RTL
//   (rtl/generated/CoralNPUCore.sv) + SKY130 SRAM wrapper + OpenRAM models.
//
//   make sim-real ELF=<path/to/sky130_gpio_demo.elf> EXPECT=81
//
// plusargs:  +PROG=<file from sw/spi_host.py --hex>  +EXPECT=<hex gpio_out>
// waves:     make sim-real ... WAVES=1  ->  gtkwave build/tb_soc_real.fst
// Simulator: Verilator >= 5.020 (--binary --timing)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps
`default_nettype none

module tb_soc_real;
  localparam CLK_NS = 40;
  localparam SCK_HALF_NS = 320;

  reg clk = 1'b0;
  reg rst_n = 1'b0;
  reg sck = 1'b0, csb = 1'b1, mosi = 1'b0;
  wire miso;
  wire [7:0] gpio_out;
  wire halted, fault, wfi;

  always #(CLK_NS / 2) clk = ~clk;

  coralnpu_soc dut (
      .clk(clk), .rst_n(rst_n),
      .spi_sck(sck), .spi_csb(csb), .spi_mosi(mosi), .spi_miso(miso),
      .gpio_out(gpio_out), .gpio_in(4'b0000), .irq(1'b0),
      .halted(halted), .fault(fault), .wfi(wfi)
  );

  `include "spi_tasks.vh"

  reg [63:0] prog[0:16383];
  reg [1023:0] prog_file;
  reg [31:0] expect_gpio;
  reg [31:0] rd;
  reg [7:0] st;
  integer i, cycles;

  always @(gpio_out) $display("[%0t ns] gpio_out = 0x%02h", $time, gpio_out);

`ifdef WAVES
  // make sim-real WAVES=1  ->  build/tb_soc_real.fst (tb + SoC + core ports)
  initial begin
    $dumpfile("tb_soc_real.fst");
    $dumpvars(3, tb_soc_real);
  end
`endif

  initial begin
    if (!$value$plusargs("PROG=%s", prog_file)) prog_file = "prog.hex";
    if (!$value$plusargs("EXPECT=%h", expect_gpio)) expect_gpio = 32'h81;
    for (i = 0; i < 16384; i = i + 1) prog[i] = 64'hFFFF_FFFF_FFFF_FFFF;
    $readmemh(prog_file, prog);

    #(10 * CLK_NS) rst_n = 1'b1;
    #(20 * CLK_NS);
    spi_read_id(rd);
    $display("[tb] chip id 0x%08h", rd);

    i = 0;
    while (prog[i] != 64'hFFFF_FFFF_FFFF_FFFF) begin
      spi_write32(prog[i][63:32], prog[i][31:0]);
      i = i + 1;
    end
    $display("[tb] %0d SPI writes done (program + boot), core running", i);

    cycles = 0;
    while (!halted && !fault && cycles < 2_000_000) begin
      @(posedge clk);
      cycles = cycles + 1;
    end
    $display("[tb] halted=%0d fault=%0d after %0d cycles, gpio_out=0x%02h",
             halted, fault, cycles, gpio_out);
    if (halted && !fault && gpio_out == expect_gpio[7:0]) $display("\n*** REAL CORE TEST PASSED ***\n");
    else $display("\n*** REAL CORE TEST FAILED ***\n");
    $finish;
  end
endmodule

`default_nettype wire
