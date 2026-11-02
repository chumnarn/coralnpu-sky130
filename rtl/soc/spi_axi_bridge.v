// SPDX-License-Identifier: Apache-2.0
// -----------------------------------------------------------------------------
// spi_axi_bridge.v
//
// SPI (mode 0, MSB first) slave  ->  AXI4 manager (single-beat, 32-bit lane
// on a 128-bit bus).  Gives an external host (MCU, FTDI, Raspberry Pi, FPGA)
// access to CoralNPU's AXI subordinate port: ITCM, DTCM and the CSR block.
//
// All SPI signals are oversampled in the `clk` domain, so
//          f_sck  <=  f_clk / 16   (recommended)
//
// Frame format (CSB low for the whole frame):
//   WRITE32  : 0x02  A3 A2 A1 A0  D3 D2 D1 D0        (AXI write after D0)
//   READ32   : 0x03  A3 A2 A1 A0  xx  Q3 Q2 Q1 Q0    (xx = status byte)
//   STATUS   : 0x05  S                               (status on MISO)
//   READ_ID  : 0x9F  I3 I2 I1 I0                     (ID = 0x434E5055 "CNPU")
//
// Status byte S:
//   [7] busy  [6] last AXI response error  [5] overrun  [4] read late
//   [3] 1 (alive)  [2] core wfi  [1] core fault  [0] core halted
// -----------------------------------------------------------------------------
`default_nettype none

module spi_axi_bridge #(
    parameter ADDR_W = 32,
    parameter DATA_W = 128,
    parameter ID_W   = 6
) (
    input  wire                  clk,
    input  wire                  rst_n,
    // SPI
    input  wire                  spi_sck,
    input  wire                  spi_csb,
    input  wire                  spi_mosi,
    output wire                  spi_miso,
    // Core status (for the status byte)
    input  wire                  core_halted,
    input  wire                  core_fault,
    input  wire                  core_wfi,
    // AXI4 manager - write address
    output reg                   m_awvalid,
    input  wire                  m_awready,
    output reg  [  ADDR_W-1:0]   m_awaddr,
    output wire [    ID_W-1:0]   m_awid,
    output wire [         7:0]   m_awlen,
    output wire [         2:0]   m_awsize,
    output wire [         1:0]   m_awburst,
    // write data
    output reg                   m_wvalid,
    input  wire                  m_wready,
    output reg  [  DATA_W-1:0]   m_wdata,
    output reg  [DATA_W/8-1:0]   m_wstrb,
    output wire                  m_wlast,
    // write response
    input  wire                  m_bvalid,
    output wire                  m_bready,
    input  wire [         1:0]   m_bresp,
    // read address
    output reg                   m_arvalid,
    input  wire                  m_arready,
    output reg  [  ADDR_W-1:0]   m_araddr,
    output wire [    ID_W-1:0]   m_arid,
    output wire [         7:0]   m_arlen,
    output wire [         2:0]   m_arsize,
    output wire [         1:0]   m_arburst,
    // read data
    input  wire                  m_rvalid,
    output wire                  m_rready,
    input  wire [  DATA_W-1:0]   m_rdata,
    input  wire [         1:0]   m_rresp,
    input  wire                  m_rlast
);

  localparam [7:0] CMD_WRITE  = 8'h02;
  localparam [7:0] CMD_READ   = 8'h03;
  localparam [7:0] CMD_STATUS = 8'h05;
  localparam [7:0] CMD_ID     = 8'h9F;
  localparam [31:0] CHIP_ID   = 32'h434E_5055;  // "CNPU"

  // Constant AXI attributes: single beat, 4 bytes, INCR
  assign m_awid    = {ID_W{1'b0}};
  assign m_awlen   = 8'd0;
  assign m_awsize  = 3'd2;
  assign m_awburst = 2'b01;
  assign m_wlast   = 1'b1;
  assign m_bready  = 1'b1;
  assign m_arid    = {ID_W{1'b0}};
  assign m_arlen   = 8'd0;
  assign m_arsize  = 3'd2;
  assign m_arburst = 2'b01;
  assign m_rready  = 1'b1;

  // ---------------------------------------------------------------------------
  // Input synchronisers
  // ---------------------------------------------------------------------------
  reg [2:0] sck_q;
  reg [1:0] csb_q;
  reg [1:0] mosi_q;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sck_q  <= 3'b000;
      csb_q  <= 2'b11;
      mosi_q <= 2'b00;
    end else begin
      sck_q  <= {sck_q[1:0], spi_sck};
      csb_q  <= {csb_q[0], spi_csb};
      mosi_q <= {mosi_q[0], spi_mosi};
    end
  end
  wire sck_rise = (sck_q[2:1] == 2'b01);
  wire sck_fall = (sck_q[2:1] == 2'b10);
  wire csb      = csb_q[1];
  wire mosi     = mosi_q[1];

  // ---------------------------------------------------------------------------
  // SPI framing
  // ---------------------------------------------------------------------------
  reg  [ 2:0] bit_cnt;
  reg  [ 7:0] rx_sh;
  reg  [ 3:0] byte_idx;
  reg  [ 7:0] cmd;
  reg  [31:0] addr_sh;
  reg  [31:0] data_sh;
  reg  [ 7:0] tx_sh;

  // AXI engine status
  reg         busy;
  reg         resp_err;
  reg         overrun;
  reg         read_late;
  reg  [31:0] rd_word;
  reg         rd_valid;

  wire [ 7:0] status = {busy, resp_err, overrun, read_late, 1'b1,
                        core_wfi, core_fault, core_halted};

  wire [ 7:0] rx_byte = {rx_sh[6:0], mosi};

  reg         launch_wr;
  reg         launch_rd;

  // Next byte to shift out, selected by the index of the byte being started
  reg  [ 7:0] tx_next;
  always @(*) begin
    tx_next = 8'h00;
    case (cmd)
      CMD_STATUS: tx_next = status;
      CMD_ID: begin
        case (byte_idx)
          4'd1: tx_next = CHIP_ID[31:24];
          4'd2: tx_next = CHIP_ID[23:16];
          4'd3: tx_next = CHIP_ID[15:8];
          4'd4: tx_next = CHIP_ID[7:0];
          default: tx_next = 8'h00;
        endcase
      end
      CMD_READ: begin
        case (byte_idx)
          4'd5: tx_next = status;
          4'd6: tx_next = rd_word[31:24];
          4'd7: tx_next = rd_word[23:16];
          4'd8: tx_next = rd_word[15:8];
          4'd9: tx_next = rd_word[7:0];
          default: tx_next = 8'h00;
        endcase
      end
      default: tx_next = 8'h00;
    endcase
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bit_cnt   <= 3'd0;
      rx_sh     <= 8'd0;
      byte_idx  <= 4'd0;
      cmd       <= 8'd0;
      addr_sh   <= 32'd0;
      data_sh   <= 32'd0;
      tx_sh     <= 8'd0;
      launch_wr <= 1'b0;
      launch_rd <= 1'b0;
    end else begin
      launch_wr <= 1'b0;
      launch_rd <= 1'b0;
      if (csb) begin
        bit_cnt  <= 3'd0;
        byte_idx <= 4'd0;
        cmd      <= 8'd0;
        tx_sh    <= 8'd0;
      end else begin
        if (sck_rise) begin
          rx_sh   <= rx_byte;
          bit_cnt <= bit_cnt + 3'd1;
          if (bit_cnt == 3'd7) begin
            // A full byte has been received
            if (byte_idx != 4'hF) byte_idx <= byte_idx + 4'd1;
            case (byte_idx)
              4'd0: cmd <= rx_byte;
              4'd1, 4'd2, 4'd3, 4'd4: addr_sh <= {addr_sh[23:0], rx_byte};
              4'd5, 4'd6, 4'd7, 4'd8: data_sh <= {data_sh[23:0], rx_byte};
              default: ;
            endcase
            if (byte_idx == 4'd4 && cmd == CMD_READ) launch_rd <= 1'b1;
            if (byte_idx == 4'd8 && cmd == CMD_WRITE) launch_wr <= 1'b1;
          end
        end
        if (sck_fall) begin
          if (bit_cnt == 3'd0) tx_sh <= tx_next;  // start of a new byte
          else tx_sh <= {tx_sh[6:0], 1'b0};
        end
      end
    end
  end

  assign spi_miso = tx_sh[7];

  // ---------------------------------------------------------------------------
  // AXI engine
  // ---------------------------------------------------------------------------
  localparam [2:0] S_IDLE = 3'd0, S_WR = 3'd1, S_WB = 3'd2, S_AR = 3'd3, S_RD = 3'd4;
  reg [2:0] state;

  wire [1:0] lane_w = addr_sh[3:2];
  wire [1:0] lane_r = m_araddr[3:2];

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state     <= S_IDLE;
      busy      <= 1'b0;
      resp_err  <= 1'b0;
      overrun   <= 1'b0;
      read_late <= 1'b0;
      rd_word   <= 32'd0;
      rd_valid  <= 1'b0;
      m_awvalid <= 1'b0;
      m_awaddr  <= {ADDR_W{1'b0}};
      m_wvalid  <= 1'b0;
      m_wdata   <= {DATA_W{1'b0}};
      m_wstrb   <= {(DATA_W / 8) {1'b0}};
      m_arvalid <= 1'b0;
      m_araddr  <= {ADDR_W{1'b0}};
    end else begin
      // A read that has not finished when its first data byte starts
      if (sck_fall && !csb && cmd == CMD_READ && byte_idx == 4'd6 && bit_cnt == 3'd0 && !rd_valid)
        read_late <= 1'b1;

      case (state)
        S_IDLE: begin
          if (launch_wr) begin
            m_awaddr  <= {addr_sh[31:2], 2'b00};
            m_wdata   <= {(DATA_W / 32) {data_sh}};
            m_wstrb   <= {{(DATA_W / 8 - 4) {1'b0}}, 4'hF} << (4 * lane_w);
            m_awvalid <= 1'b1;
            m_wvalid  <= 1'b1;
            busy      <= 1'b1;
            state     <= S_WR;
          end else if (launch_rd) begin
            m_araddr  <= {addr_sh[31:2], 2'b00};
            m_arvalid <= 1'b1;
            rd_valid  <= 1'b0;
            read_late <= 1'b0;
            busy      <= 1'b1;
            state     <= S_AR;
          end
        end
        S_WR: begin
          if (m_awvalid && m_awready) m_awvalid <= 1'b0;
          if (m_wvalid && m_wready) m_wvalid <= 1'b0;
          if ((!m_awvalid || m_awready) && (!m_wvalid || m_wready)) state <= S_WB;
        end
        S_WB: begin
          if (m_bvalid) begin
            resp_err <= m_bresp[1];
            busy     <= 1'b0;
            state    <= S_IDLE;
          end
        end
        S_AR: begin
          if (m_arready) begin
            m_arvalid <= 1'b0;
            state     <= S_RD;
          end
        end
        S_RD: begin
          if (m_rvalid) begin
            rd_word <= m_rdata[32*lane_r+:32];
            if (m_rlast) begin
              resp_err <= m_rresp[1];
              rd_valid <= 1'b1;
              busy     <= 1'b0;
              state    <= S_IDLE;
            end
          end
        end
        default: state <= S_IDLE;
      endcase

      if ((launch_wr || launch_rd) && state != S_IDLE) overrun <= 1'b1;
      // Reading the status byte clears the sticky flags
      if (sck_fall && !csb && cmd == CMD_STATUS && byte_idx == 4'd1 && bit_cnt == 3'd0)
        overrun <= 1'b0;
    end
  end

endmodule

`default_nettype wire
