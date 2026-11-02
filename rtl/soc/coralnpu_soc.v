// SPDX-License-Identifier: Apache-2.0
// -----------------------------------------------------------------------------
// coralnpu_soc.v
//
// Small SoC around Google's CoralNPU scalar core (CoreMiniAxi, renamed to
// `CoralNPUCore` by scripts/prepare_rtl.py):
//
//            +-----------+   AXI4 (128b)   +----------------+
//  SPI  ---> | spi_axi   |---------------->| CoralNPUCore   |
//            | bridge    |  axi_slave port | ITCM 8K/DTCM32K|
//            +-----------+                 |  (sky130 SRAM) |
//                                          +-------+--------+
//                                                  | axi_master port
//                                          +-------v--------+
//                                          | axi_gpio_slave | --> gpio_out[7:0]
//                                          +----------------+ <-- gpio_in[3:0]
//
// Boot sequence (driven by the host over SPI, see sw/spi_host.py):
//   1. WRITE32 program words into ITCM (0x0000_0000 ...)
//   2. WRITE32 CSR+0x4  = start PC        (CSR base 0x0003_0000 default map)
//   3. WRITE32 CSR+0x0  = 1  (release clock gate, keep reset)
//   4. WRITE32 CSR+0x0  = 0  (release core reset)  -> core runs
// -----------------------------------------------------------------------------
`default_nettype none

module coralnpu_soc (
    input  wire       clk,
    input  wire       rst_n,      // asynchronous, active low
    // SPI host interface
    input  wire       spi_sck,
    input  wire       spi_csb,
    input  wire       spi_mosi,
    output wire       spi_miso,
    // GPIO
    output wire [7:0] gpio_out,
    input  wire [3:0] gpio_in,
    // Interrupt and status
    input  wire       irq,
    output wire       halted,
    output wire       fault,
    output wire       wfi
);

  localparam AW = 32;
  localparam DW = 128;
  localparam IW = 6;

  // ---------------------------------------------------------------------------
  // Reset synchroniser for the SoC glue logic (the core has its own RstSync)
  // ---------------------------------------------------------------------------
  reg [1:0] rst_sync;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) rst_sync <= 2'b00;
    else rst_sync <= {rst_sync[0], 1'b1};
  end
  wire glue_rst_n = rst_sync[1];

  // ---------------------------------------------------------------------------
  // Bridge -> core subordinate port
  // ---------------------------------------------------------------------------
  wire          s_awvalid, s_awready, s_wvalid, s_wready, s_wlast;
  wire          s_bvalid, s_bready, s_arvalid, s_arready, s_rvalid, s_rready, s_rlast;
  wire [AW-1:0] s_awaddr, s_araddr;
  wire [IW-1:0] s_awid, s_arid, s_bid, s_rid;
  wire [   7:0] s_awlen, s_arlen;
  wire [   2:0] s_awsize, s_arsize;
  wire [   1:0] s_awburst, s_arburst, s_bresp, s_rresp;
  wire [DW-1:0] s_wdata, s_rdata;
  wire [DW/8-1:0] s_wstrb;

  spi_axi_bridge #(
      .ADDR_W(AW),
      .DATA_W(DW),
      .ID_W  (IW)
  ) u_bridge (
      .clk        (clk),
      .rst_n      (glue_rst_n),
      .spi_sck    (spi_sck),
      .spi_csb    (spi_csb),
      .spi_mosi   (spi_mosi),
      .spi_miso   (spi_miso),
      .core_halted(halted),
      .core_fault (fault),
      .core_wfi   (wfi),
      .m_awvalid  (s_awvalid),
      .m_awready  (s_awready),
      .m_awaddr   (s_awaddr),
      .m_awid     (s_awid),
      .m_awlen    (s_awlen),
      .m_awsize   (s_awsize),
      .m_awburst  (s_awburst),
      .m_wvalid   (s_wvalid),
      .m_wready   (s_wready),
      .m_wdata    (s_wdata),
      .m_wstrb    (s_wstrb),
      .m_wlast    (s_wlast),
      .m_bvalid   (s_bvalid),
      .m_bready   (s_bready),
      .m_bresp    (s_bresp),
      .m_arvalid  (s_arvalid),
      .m_arready  (s_arready),
      .m_araddr   (s_araddr),
      .m_arid     (s_arid),
      .m_arlen    (s_arlen),
      .m_arsize   (s_arsize),
      .m_arburst  (s_arburst),
      .m_rvalid   (s_rvalid),
      .m_rready   (s_rready),
      .m_rdata    (s_rdata),
      .m_rresp    (s_rresp),
      .m_rlast    (s_rlast)
  );

  // ---------------------------------------------------------------------------
  // Core manager port -> GPIO subordinate
  // ---------------------------------------------------------------------------
  wire          m_awvalid, m_awready, m_wvalid, m_wready, m_wlast;
  wire          m_bvalid, m_bready, m_arvalid, m_arready, m_rvalid, m_rready, m_rlast;
  wire [AW-1:0] m_awaddr, m_araddr;
  wire [IW-1:0] m_awid, m_arid, m_bid, m_rid;
  wire [   7:0] m_awlen, m_arlen;
  wire [DW-1:0] m_wdata, m_rdata;
  wire [DW/8-1:0] m_wstrb;
  wire [   1:0] m_bresp, m_rresp;

  axi_gpio_slave #(
      .ADDR_W(AW),
      .DATA_W(DW),
      .ID_W  (IW)
  ) u_gpio (
      .clk      (clk),
      .rst_n    (glue_rst_n),
      .s_awvalid(m_awvalid),
      .s_awready(m_awready),
      .s_awaddr (m_awaddr),
      .s_awid   (m_awid),
      .s_wvalid (m_wvalid),
      .s_wready (m_wready),
      .s_wdata  (m_wdata),
      .s_wstrb  (m_wstrb),
      .s_wlast  (m_wlast),
      .s_bvalid (m_bvalid),
      .s_bready (m_bready),
      .s_bid    (m_bid),
      .s_bresp  (m_bresp),
      .s_arvalid(m_arvalid),
      .s_arready(m_arready),
      .s_araddr (m_araddr),
      .s_arid   (m_arid),
      .s_arlen  (m_arlen),
      .s_rvalid (m_rvalid),
      .s_rready (m_rready),
      .s_rdata  (m_rdata),
      .s_rid    (m_rid),
      .s_rresp  (m_rresp),
      .s_rlast  (m_rlast),
      .gpio_out (gpio_out),
      .gpio_in  (gpio_in)
  );

  // ---------------------------------------------------------------------------
  // CoralNPU core (generated by Chisel; top renamed to CoralNPUCore)
  // Port names follow Chisel's io_<bundle>_<field> flattening.
  // Debug trace outputs (io_debug_*) are left unconnected.
  // ---------------------------------------------------------------------------
  CoralNPUCore u_core (
      .io_aclk                          (clk),
      .io_aresetn                       (rst_n),
      // ---- AXI subordinate (from SPI bridge)
      .io_axi_slave_write_addr_valid    (s_awvalid),
      .io_axi_slave_write_addr_ready    (s_awready),
      .io_axi_slave_write_addr_bits_addr(s_awaddr),
      .io_axi_slave_write_addr_bits_prot(3'd0),
      .io_axi_slave_write_addr_bits_id  (s_awid),
      .io_axi_slave_write_addr_bits_len (s_awlen),
      .io_axi_slave_write_addr_bits_size(s_awsize),
      .io_axi_slave_write_addr_bits_burst(s_awburst),
      .io_axi_slave_write_addr_bits_lock(1'b0),
      .io_axi_slave_write_addr_bits_cache(4'd0),
      .io_axi_slave_write_addr_bits_qos (4'd0),
      .io_axi_slave_write_addr_bits_region(4'd0),
      .io_axi_slave_write_data_valid    (s_wvalid),
      .io_axi_slave_write_data_ready    (s_wready),
      .io_axi_slave_write_data_bits_data(s_wdata),
      .io_axi_slave_write_data_bits_last(s_wlast),
      .io_axi_slave_write_data_bits_strb(s_wstrb),
      .io_axi_slave_write_resp_valid    (s_bvalid),
      .io_axi_slave_write_resp_ready    (s_bready),
      .io_axi_slave_write_resp_bits_id  (s_bid),
      .io_axi_slave_write_resp_bits_resp(s_bresp),
      .io_axi_slave_read_addr_valid     (s_arvalid),
      .io_axi_slave_read_addr_ready     (s_arready),
      .io_axi_slave_read_addr_bits_addr (s_araddr),
      .io_axi_slave_read_addr_bits_prot (3'd0),
      .io_axi_slave_read_addr_bits_id   (s_arid),
      .io_axi_slave_read_addr_bits_len  (s_arlen),
      .io_axi_slave_read_addr_bits_size (s_arsize),
      .io_axi_slave_read_addr_bits_burst(s_arburst),
      .io_axi_slave_read_addr_bits_lock (1'b0),
      .io_axi_slave_read_addr_bits_cache(4'd0),
      .io_axi_slave_read_addr_bits_qos  (4'd0),
      .io_axi_slave_read_addr_bits_region(4'd0),
      .io_axi_slave_read_data_valid     (s_rvalid),
      .io_axi_slave_read_data_ready     (s_rready),
      .io_axi_slave_read_data_bits_data (s_rdata),
      .io_axi_slave_read_data_bits_id   (s_rid),
      .io_axi_slave_read_data_bits_resp (s_rresp),
      .io_axi_slave_read_data_bits_last (s_rlast),
      // ---- AXI manager (to GPIO block)
      .io_axi_master_write_addr_valid   (m_awvalid),
      .io_axi_master_write_addr_ready   (m_awready),
      .io_axi_master_write_addr_bits_addr(m_awaddr),
      .io_axi_master_write_addr_bits_prot(),
      .io_axi_master_write_addr_bits_id (m_awid),
      .io_axi_master_write_addr_bits_len(m_awlen),
      .io_axi_master_write_addr_bits_size(),
      .io_axi_master_write_addr_bits_burst(),
      .io_axi_master_write_addr_bits_lock(),
      .io_axi_master_write_addr_bits_cache(),
      .io_axi_master_write_addr_bits_qos(),
      .io_axi_master_write_addr_bits_region(),
      .io_axi_master_write_data_valid   (m_wvalid),
      .io_axi_master_write_data_ready   (m_wready),
      .io_axi_master_write_data_bits_data(m_wdata),
      .io_axi_master_write_data_bits_last(m_wlast),
      .io_axi_master_write_data_bits_strb(m_wstrb),
      .io_axi_master_write_resp_valid   (m_bvalid),
      .io_axi_master_write_resp_ready   (m_bready),
      .io_axi_master_write_resp_bits_id (m_bid),
      .io_axi_master_write_resp_bits_resp(m_bresp),
      .io_axi_master_read_addr_valid    (m_arvalid),
      .io_axi_master_read_addr_ready    (m_arready),
      .io_axi_master_read_addr_bits_addr(m_araddr),
      .io_axi_master_read_addr_bits_prot(),
      .io_axi_master_read_addr_bits_id  (m_arid),
      .io_axi_master_read_addr_bits_len (m_arlen),
      .io_axi_master_read_addr_bits_size(),
      .io_axi_master_read_addr_bits_burst(),
      .io_axi_master_read_addr_bits_lock(),
      .io_axi_master_read_addr_bits_cache(),
      .io_axi_master_read_addr_bits_qos (),
      .io_axi_master_read_addr_bits_region(),
      .io_axi_master_read_data_valid    (m_rvalid),
      .io_axi_master_read_data_ready    (m_rready),
      .io_axi_master_read_data_bits_data(m_rdata),
      .io_axi_master_read_data_bits_id  (m_rid),
      .io_axi_master_read_data_bits_resp(m_rresp),
      .io_axi_master_read_data_bits_last(m_rlast),
      // ---- Status / interrupts
      .io_halted                        (halted),
      .io_fault                         (fault),
      .io_wfi                           (wfi),
      .io_irq                           (irq),
      .io_boot_addr                     ('0),
      .io_timer_irq                     (1'b0),
      .io_software_irq                  (1'b0),
      // ---- Debug module interface: unused, tied off
      .io_dm_req_valid                  (1'b0),
      .io_dm_req_ready                  (),
      .io_dm_req_bits_address           ('0),
      .io_dm_req_bits_data              ('0),
      .io_dm_req_bits_op                ('0),
      .io_dm_rsp_valid                  (),
      .io_dm_rsp_ready                  (1'b1),
      .io_dm_rsp_bits_data              (),
      .io_dm_rsp_bits_op                (),
      // ---- Test enable (DFT) off
      .io_te                            (1'b0)
  );

endmodule

`default_nettype wire
