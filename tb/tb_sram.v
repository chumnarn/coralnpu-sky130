// SPDX-License-Identifier: Apache-2.0
// tb_sram.v - unit test for rtl/sky130/Sram_sky130.v (128 / 512 / 2048 entries)
`timescale 1ns / 1ps
`default_nettype none

module sram_check #(parameter N = 512) (input wire clk, output reg done, output integer errors);
  localparam AW = $clog2(N);
  reg en = 0, we = 0;
  reg [AW-1:0] addr = 0;
  reg [127:0] wdata = 0;
  reg [15:0] wmask = 0;
  wire [127:0] rdata;
  wire rvalid;
  Sram #(.NUM_ENTRIES(N)) dut (.clock(clk), .enable(en), .write(we), .addr(addr),
                               .wdata(wdata), .wmask(wmask), .rdata(rdata), .rvalid(rvalid));
  function [127:0] pat(input integer a);
    pat = {a[31:0] ^ 32'hA5A5A5A5, ~a[31:0], a[31:0] * 32'd2654435761, a[31:0]};
  endfunction
  integer i;
  reg [127:0] exp;
  initial begin
    done = 0; errors = 0;
    @(negedge clk);
    for (i = 0; i < N; i = i + (N / 8)) begin            // full writes
      en = 1; we = 1; addr = i; wdata = pat(i); wmask = 16'hFFFF; @(negedge clk);
    end
    // partial (byte-masked) write to entry 0: only byte 0 and byte 15
    en = 1; we = 1; addr = 0; wdata = {128{1'b1}}; wmask = 16'h8001; @(negedge clk);
    en = 0; we = 0; @(negedge clk);
    for (i = 0; i < N; i = i + (N / 8)) begin
      en = 1; we = 0; addr = i; @(negedge clk);
      en = 0;
      #15;  // sample late in the read-data cycle (as the next flop would)
      exp = pat(i);
      if (i == 0) begin exp[7:0] = 8'hFF; exp[127:120] = 8'hFF; end
      if (!rvalid || rdata !== exp) begin
        $display("  FAIL N=%0d addr %0d: %h (exp %h)", N, i, rdata, exp);
        errors = errors + 1;
      end
      @(negedge clk); #15;
      // data must stay stable after the read cycle
      if (rdata !== exp) begin
        $display("  FAIL N=%0d addr %0d: rdata not held", N, i);
        errors = errors + 1;
      end
    end
    $display("  Sram NUM_ENTRIES=%0d : %0d error(s)", N, errors);
    done = 1;
  end
endmodule

module tb_sram;
  reg clk = 0;
  always #20 clk = ~clk;
  wire d0, d1, d2;
  integer e0, e1, e2;
  sram_check #(128)  c0 (.clk(clk), .done(d0), .errors(e0));
  sram_check #(512)  c1 (.clk(clk), .done(d1), .errors(e1));
  sram_check #(2048) c2 (.clk(clk), .done(d2), .errors(e2));
  initial begin
    wait (d0 && d1 && d2);
    if (e0 + e1 + e2 == 0) $display("\n*** SRAM TEST PASSED ***\n");
    else $display("\n*** SRAM TEST FAILED ***\n");
    $finish;
  end
endmodule

`default_nettype wire
