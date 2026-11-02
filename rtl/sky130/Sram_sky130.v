// SPDX-License-Identifier: Apache-2.0
// -----------------------------------------------------------------------------
// Sram_sky130.v
//
// Drop-in replacement for CoralNPU's `Sram` black box (hdl/verilog/Sram.v)
// targeting the SkyWater SKY130 PDK.  The generated CoralNPU RTL instantiates
// `Sram #(.NUM_ENTRIES(N))` with a 128-bit data bus and a 16-bit byte mask.
// Each 128-bit word is built from 4x OpenRAM macros
//     sky130_sram_2kbyte_1rw1r_32x512_8   (32 bit x 512 words, byte mask)
// placed side by side.  If NUM_ENTRIES > 512 the module banks additional rows
// of macros; if NUM_ENTRIES < 512 the upper address bits are tied to 0.
//
// Timing behaviour matches the generic CoralNPU model:
//   cycle N   : enable/addr/write presented
//   cycle N+1 : rdata valid, rvalid = 1
// The OpenRAM macro drives dout only during the cycle after the read, so a
// small hold register keeps `rdata` stable afterwards (same as the generic
// model, which holds the last read address).
//
// Macro power pins (vccd1/vssd1) are hooked up by LibreLane through
// PDN_MACRO_CONNECTIONS, so they are not modelled in RTL.
//
// All macro instances contain the token "u_sky130sram" in their name.  The
// flow scripts use that token for PDN hookup and automatic grid placement.
// -----------------------------------------------------------------------------
`default_nettype none

module Sram #(
    parameter NUM_ENTRIES      = 128,
    parameter GLOBAL_BASE_ADDR = 0
) (
    input  wire                           clock,
    input  wire                           enable,
    input  wire                           write,
    input  wire [$clog2(NUM_ENTRIES)-1:0] addr,
    input  wire [                  127:0] wdata,
    input  wire [                   15:0] wmask,
    output wire [                  127:0] rdata,
    output wire                           rvalid
);

  localparam MACRO_AW    = 9;                       // 512 words per macro
  localparam MACRO_DEPTH = 1 << MACRO_AW;
  localparam AW          = $clog2(NUM_ENTRIES);
  localparam NBANK       = (NUM_ENTRIES + MACRO_DEPTH - 1) / MACRO_DEPTH;
  localparam BSEL_W      = (NBANK > 1) ? $clog2(NBANK) : 1;

  // Address inside one macro (zero-extended when NUM_ENTRIES < 512)
  wire [MACRO_AW-1:0] maddr;
  generate
    if (AW >= MACRO_AW) begin : g_addr_full
      assign maddr = addr[MACRO_AW-1:0];
    end else begin : g_addr_ext
      assign maddr = {{(MACRO_AW - AW) {1'b0}}, addr};
    end
  endgenerate

  // Bank select
  wire [BSEL_W-1:0] bsel;
  generate
    if (NBANK > 1) begin : g_bsel
      assign bsel = addr[AW-1:MACRO_AW];
    end else begin : g_bsel0
      assign bsel = {BSEL_W{1'b0}};
    end
  endgenerate

  reg              rvalid_q;
  reg [BSEL_W-1:0] bsel_q;
  reg [     127:0] rdata_hold;
  always @(posedge clock) begin
    rvalid_q <= enable & ~write;
    if (enable) bsel_q <= bsel;
  end

  wire [127:0] bank_dout[0:NBANK-1];

  genvar b;
  generate
    for (b = 0; b < NBANK; b = b + 1) begin : g_bank
      wire csb = ~(enable & (bsel == b));
      wire web = ~write;

      sky130_sram_2kbyte_1rw1r_32x512_8 u_sky130sram_w0 (
          .clk0  (clock),
          .csb0  (csb),
          .web0  (web),
          .wmask0(wmask[3:0]),
          .addr0 (maddr),
          .din0  (wdata[31:0]),
          .dout0 (bank_dout[b][31:0]),
          .clk1  (clock),
          .csb1  (1'b1),
          .addr1 ({MACRO_AW{1'b0}}),
          .dout1 ()
      );
      sky130_sram_2kbyte_1rw1r_32x512_8 u_sky130sram_w1 (
          .clk0  (clock),
          .csb0  (csb),
          .web0  (web),
          .wmask0(wmask[7:4]),
          .addr0 (maddr),
          .din0  (wdata[63:32]),
          .dout0 (bank_dout[b][63:32]),
          .clk1  (clock),
          .csb1  (1'b1),
          .addr1 ({MACRO_AW{1'b0}}),
          .dout1 ()
      );
      sky130_sram_2kbyte_1rw1r_32x512_8 u_sky130sram_w2 (
          .clk0  (clock),
          .csb0  (csb),
          .web0  (web),
          .wmask0(wmask[11:8]),
          .addr0 (maddr),
          .din0  (wdata[95:64]),
          .dout0 (bank_dout[b][95:64]),
          .clk1  (clock),
          .csb1  (1'b1),
          .addr1 ({MACRO_AW{1'b0}}),
          .dout1 ()
      );
      sky130_sram_2kbyte_1rw1r_32x512_8 u_sky130sram_w3 (
          .clk0  (clock),
          .csb0  (csb),
          .web0  (web),
          .wmask0(wmask[15:12]),
          .addr0 (maddr),
          .din0  (wdata[127:96]),
          .dout0 (bank_dout[b][127:96]),
          .clk1  (clock),
          .csb1  (1'b1),
          .addr1 ({MACRO_AW{1'b0}}),
          .dout1 ()
      );
    end
  endgenerate

  wire [127:0] dout_sel = bank_dout[bsel_q];

  always @(posedge clock) begin
    if (rvalid_q) rdata_hold <= dout_sel;
  end

  assign rdata  = rvalid_q ? dout_sel : rdata_hold;
  // CoralNPU's generic model asserts rvalid for every enabled access
  // (read or write); keep identical semantics.
  reg rvalid_any_q;
  always @(posedge clock) rvalid_any_q <= enable;
  assign rvalid = rvalid_any_q;

endmodule

`default_nettype wire
