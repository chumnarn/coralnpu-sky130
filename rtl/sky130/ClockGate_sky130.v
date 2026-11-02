// SPDX-License-Identifier: Apache-2.0
// -----------------------------------------------------------------------------
// ClockGate_sky130.v
//
// Replacement for CoralNPU's `ClockGate` black box (hdl/verilog/ClockGate.sv).
// Uses the SKY130 integrated clock-gating cell with scan enable:
//     sky130_fd_sc_hd__sdlclkp  (GATE, SCE, CLK -> GCLK)
// GCLK = CLK & latch(GATE | SCE)   (latch transparent while CLK is low)
//
// Define CORALNPU_BEHAV_CLOCKGATE for simulation without the PDK cell models.
// -----------------------------------------------------------------------------
`default_nettype none

module ClockGate (
    input  wire clk_i,
    input  wire enable,  // '1' pass clock, '0' gate clock
    input  wire te,      // test enable (forces clock on)
    output wire clk_o
);

`ifdef CORALNPU_BEHAV_CLOCKGATE
  reg en_latch;
  always @(*) if (!clk_i) en_latch = enable | te;
  assign clk_o = en_latch & clk_i;
`else
  (* keep *)
  sky130_fd_sc_hd__sdlclkp_4 u_icg (
      .CLK (clk_i),
      .GATE(enable),
      .SCE (te),
      .GCLK(clk_o)
  );
`endif

endmodule

`default_nettype wire
