// SPDX-License-Identifier: Apache-2.0
// -----------------------------------------------------------------------------
// axi_gpio_slave.v
//
// Minimal AXI4 subordinate (128-bit data) connected to CoralNPU's AXI
// *manager* port.  Every access that misses ITCM/DTCM/CSR leaves the core on
// that port; this block terminates it so the chip needs no external memory.
//
// Register map (decoded on addr[3:2] only, aliased over the whole space;
// software should use base 0x8000_0000):
//   +0x0  GPIO_OUT  [7:0]  RW   -> chip pads gpio_out[7:0]
//   +0x4  GPIO_IN   [3:0]  RO   <- chip pads gpio_in[3:0]
//   +0x8  SCRATCH   [31:0] RW
//   +0xC  ID        [31:0] RO   = 0xC0A1_5130
// Bursts are accepted; only the first beat of a write burst updates a register.
// -----------------------------------------------------------------------------
`default_nettype none

module axi_gpio_slave #(
    parameter ADDR_W = 32,
    parameter DATA_W = 128,
    parameter ID_W   = 6
) (
    input  wire                  clk,
    input  wire                  rst_n,
    // write address
    input  wire                  s_awvalid,
    output wire                  s_awready,
    input  wire [  ADDR_W-1:0]   s_awaddr,
    input  wire [    ID_W-1:0]   s_awid,
    // write data
    input  wire                  s_wvalid,
    output wire                  s_wready,
    input  wire [  DATA_W-1:0]   s_wdata,
    input  wire [DATA_W/8-1:0]   s_wstrb,
    input  wire                  s_wlast,
    // write response
    output reg                   s_bvalid,
    input  wire                  s_bready,
    output reg  [    ID_W-1:0]   s_bid,
    output wire [         1:0]   s_bresp,
    // read address
    input  wire                  s_arvalid,
    output wire                  s_arready,
    input  wire [  ADDR_W-1:0]   s_araddr,
    input  wire [    ID_W-1:0]   s_arid,
    input  wire [         7:0]   s_arlen,
    // read data
    output reg                   s_rvalid,
    input  wire                  s_rready,
    output wire [  DATA_W-1:0]   s_rdata,
    output reg  [    ID_W-1:0]   s_rid,
    output wire [         1:0]   s_rresp,
    output wire                  s_rlast,
    // GPIO
    output wire [         7:0]   gpio_out,
    input  wire [         3:0]   gpio_in
);

  localparam [31:0] ID_VALUE = 32'hC0A1_5130;

  reg  [ 7:0] gpio_out_q;
  reg  [31:0] scratch_q;
  reg  [ 3:0] gpio_in_q1, gpio_in_q2;  // 2-FF synchroniser

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      gpio_in_q1 <= 4'd0;
      gpio_in_q2 <= 4'd0;
    end else begin
      gpio_in_q1 <= gpio_in;
      gpio_in_q2 <= gpio_in_q1;
    end
  end

  // ---------------------------------------------------------------- write path
  reg              aw_busy;     // address accepted, collecting data beats
  reg [       1:0] aw_lane;
  reg              first_beat;

  assign s_awready = !aw_busy && !s_bvalid;
  assign s_wready  = aw_busy;
  assign s_bresp   = 2'b00;

  wire [31:0] w_word = s_wdata[32*aw_lane+:32];
  wire [ 3:0] w_strb = s_wstrb[4*aw_lane+:4];

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_busy    <= 1'b0;
      aw_lane    <= 2'd0;
      first_beat <= 1'b0;
      s_bvalid   <= 1'b0;
      s_bid      <= {ID_W{1'b0}};
      gpio_out_q <= 8'd0;
      scratch_q  <= 32'd0;
    end else begin
      if (s_awvalid && s_awready) begin
        aw_busy    <= 1'b1;
        aw_lane    <= s_awaddr[3:2];
        first_beat <= 1'b1;
        s_bid      <= s_awid;
      end
      if (s_wvalid && s_wready) begin
        first_beat <= 1'b0;
        if (first_beat) begin
          case (aw_lane)
            2'd0: if (w_strb[0]) gpio_out_q <= w_word[7:0];
            2'd2: begin
              if (w_strb[0]) scratch_q[7:0] <= w_word[7:0];
              if (w_strb[1]) scratch_q[15:8] <= w_word[15:8];
              if (w_strb[2]) scratch_q[23:16] <= w_word[23:16];
              if (w_strb[3]) scratch_q[31:24] <= w_word[31:24];
            end
            default: ;
          endcase
        end
        if (s_wlast) begin
          aw_busy  <= 1'b0;
          s_bvalid <= 1'b1;
        end
      end
      if (s_bvalid && s_bready) s_bvalid <= 1'b0;
    end
  end

  // ----------------------------------------------------------------- read path
  reg [7:0] r_beats;  // remaining beats - 1

  assign s_arready = !s_rvalid;
  assign s_rresp   = 2'b00;
  assign s_rlast   = (r_beats == 8'd0);
  assign s_rdata   = {ID_VALUE, scratch_q, {28'd0, gpio_in_q2}, {24'd0, gpio_out_q}};

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_rvalid <= 1'b0;
      s_rid    <= {ID_W{1'b0}};
      r_beats  <= 8'd0;
    end else begin
      if (s_arvalid && s_arready) begin
        s_rvalid <= 1'b1;
        s_rid    <= s_arid;
        r_beats  <= s_arlen;
      end else if (s_rvalid && s_rready) begin
        if (r_beats == 8'd0) s_rvalid <= 1'b0;
        else r_beats <= r_beats - 8'd1;
      end
    end
  end

  assign gpio_out = gpio_out_q;

  // Unused address bits are intentionally ignored
  wire unused_ok = &{1'b0, s_araddr, s_awaddr[ADDR_W-1:4], s_awaddr[1:0]};

endmodule

`default_nettype wire
