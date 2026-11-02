// SPDX-License-Identifier: Apache-2.0
// -----------------------------------------------------------------------------
// tb_soc.v - SoC glue testbench (SPI bridge, AXI GPIO, SKY130 SRAM wrapper)
//
// Run:  make sim            (stub core, no Bazel/Chisel needed)
//       make sim CORE=real  (real CoralNPU RTL from rtl/generated, Verilator)
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps
`default_nettype none

module tb_soc;
  localparam CLK_NS = 40;          // 25 MHz core clock
  localparam SCK_HALF_NS = 320;    // SPI 1.56 MHz (= clk/16)

  reg clk = 1'b0;
  reg rst_n = 1'b0;
  reg sck = 1'b0, csb = 1'b1, mosi = 1'b0;
  wire miso;
  wire [7:0] gpio_out;
  wire halted, fault, wfi;
  integer errors = 0;

  always #(CLK_NS / 2) clk = ~clk;

  coralnpu_soc dut (
      .clk(clk), .rst_n(rst_n),
      .spi_sck(sck), .spi_csb(csb), .spi_mosi(mosi), .spi_miso(miso),
      .gpio_out(gpio_out), .gpio_in(4'b1010), .irq(1'b0),
      .halted(halted), .fault(fault), .wfi(wfi)
  );

  `include "spi_tasks.vh"

  task check(input [255:0] what, input [31:0] got, input [31:0] exp);
    begin
      if (got !== exp) begin
        $display("  FAIL %0s: got 0x%08h expected 0x%08h", what, got, exp);
        errors = errors + 1;
      end else $display("  ok   %0s = 0x%08h", what, got);
    end
  endtask

  // ------------------------------------------------------------------- test
  reg [31:0] rd, id;
  reg [7:0] st;
  integer k;
  initial begin
    $dumpfile("tb_soc.vcd");
    $dumpvars(0, tb_soc);
    #(10 * CLK_NS) rst_n = 1'b1;
    #(10 * CLK_NS);

    $display("[tb] READ_ID");
    spi_read_id(id);
    check("chip id", id, 32'h434E5055);

    $display("[tb] write/read ITCM through SPI -> AXI -> SRAM wrapper");
    for (k = 0; k < 8; k = k + 1)
      spi_write32(32'h0000_0000 + 4 * k, 32'hA5000000 | (k << 8) | (8'h11 * k));
    for (k = 7; k >= 0; k = k - 1) begin
      spi_read32(32'h0000_0000 + 4 * k, rd, st);
      check("itcm word", rd, 32'hA5000000 | (k << 8) | (8'h11 * k));
    end
    // a different SRAM row (address 0x1FF0 = last row)
    spi_write32(32'h0000_1FF4, 32'hDEADBEEF);
    spi_read32(32'h0000_1FF4, rd, st);
    check("itcm last row", rd, 32'hDEADBEEF);
    spi_read32(32'h0000_0004, rd, st);
    check("itcm word1 still intact", rd, 32'hA5000111);

    spi_write32(32'h0000_0000, 32'h1234_563C);   // "program": low byte -> GPIO
    $display("[tb] boot: set PC, release clock gate, release reset");
    spi_write32(32'h0003_0004, 32'h0000_0000);
    spi_write32(32'h0003_0000, 32'h0000_0001);
    spi_write32(32'h0003_0000, 32'h0000_0000);

    // wait for the stub "program" to write GPIO and halt
    k = 0;
    while (!halted && k < 2000) begin
      @(posedge clk);
      k = k + 1;
    end
    check("halted", {31'd0, halted}, 32'd1);
    check("gpio_out", {24'd0, gpio_out}, 32'h0000_003C);
    spi_read32(32'h0003_0000, rd, st);
    check("status byte alive bit", {31'd0, st[3]}, 32'd1);
    check("status byte halted bit", {31'd0, st[0]}, 32'd1);

    if (errors == 0) $display("\n*** TEST PASSED ***\n");
    else $display("\n*** TEST FAILED: %0d error(s) ***\n", errors);
    $finish;
  end

  initial begin
    #(5_000_000);
    $display("*** TIMEOUT ***");
    $finish;
  end
endmodule

`default_nettype wire
