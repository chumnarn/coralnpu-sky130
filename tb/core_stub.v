// SPDX-License-Identifier: Apache-2.0
// -----------------------------------------------------------------------------
// core_stub.v  -  behavioural stand-in for CoralNPUCore used by tb_soc.v
//
// It is NOT the CoralNPU core.  It has exactly the same port names and
// implements just enough to test the SoC glue + SKY130 SRAM wrapper:
//   * AXI subordinate: ITCM 0x0000_0000 (8 KiB) implemented with the real
//     `Sram` sky130 wrapper (+ OpenRAM behavioural model), CSR 0x0003_0000
//   * after software releases reset (CSR+0 : 1 -> 0) the "core" reads ITCM
//     word 0 and writes its low byte to GPIO_OUT (0x8000_0000) through the
//     AXI manager port, then reads the GPIO ID register and raises io_halted.
// -----------------------------------------------------------------------------
`timescale 1ns / 1ps
`default_nettype none

module CoralNPUCore (
    input  wire         io_aclk,
    input  wire         io_aresetn,
    // AXI subordinate
    input  wire         io_axi_slave_write_addr_valid,
    output wire         io_axi_slave_write_addr_ready,
    input  wire [ 31:0] io_axi_slave_write_addr_bits_addr,
    input  wire [  2:0] io_axi_slave_write_addr_bits_prot,
    input  wire [  5:0] io_axi_slave_write_addr_bits_id,
    input  wire [  7:0] io_axi_slave_write_addr_bits_len,
    input  wire [  2:0] io_axi_slave_write_addr_bits_size,
    input  wire [  1:0] io_axi_slave_write_addr_bits_burst,
    input  wire [  0:0] io_axi_slave_write_addr_bits_lock,
    input  wire [  3:0] io_axi_slave_write_addr_bits_cache,
    input  wire [  3:0] io_axi_slave_write_addr_bits_qos,
    input  wire [  3:0] io_axi_slave_write_addr_bits_region,
    input  wire         io_axi_slave_write_data_valid,
    output wire         io_axi_slave_write_data_ready,
    input  wire [127:0] io_axi_slave_write_data_bits_data,
    input  wire         io_axi_slave_write_data_bits_last,
    input  wire [ 15:0] io_axi_slave_write_data_bits_strb,
    output reg          io_axi_slave_write_resp_valid,
    input  wire         io_axi_slave_write_resp_ready,
    output wire [  5:0] io_axi_slave_write_resp_bits_id,
    output wire [  1:0] io_axi_slave_write_resp_bits_resp,
    input  wire         io_axi_slave_read_addr_valid,
    output wire         io_axi_slave_read_addr_ready,
    input  wire [ 31:0] io_axi_slave_read_addr_bits_addr,
    input  wire [  2:0] io_axi_slave_read_addr_bits_prot,
    input  wire [  5:0] io_axi_slave_read_addr_bits_id,
    input  wire [  7:0] io_axi_slave_read_addr_bits_len,
    input  wire [  2:0] io_axi_slave_read_addr_bits_size,
    input  wire [  1:0] io_axi_slave_read_addr_bits_burst,
    input  wire [  0:0] io_axi_slave_read_addr_bits_lock,
    input  wire [  3:0] io_axi_slave_read_addr_bits_cache,
    input  wire [  3:0] io_axi_slave_read_addr_bits_qos,
    input  wire [  3:0] io_axi_slave_read_addr_bits_region,
    output reg          io_axi_slave_read_data_valid,
    input  wire         io_axi_slave_read_data_ready,
    output reg  [127:0] io_axi_slave_read_data_bits_data,
    output wire [  5:0] io_axi_slave_read_data_bits_id,
    output wire [  1:0] io_axi_slave_read_data_bits_resp,
    output wire         io_axi_slave_read_data_bits_last,
    // AXI manager
    output reg          io_axi_master_write_addr_valid,
    input  wire         io_axi_master_write_addr_ready,
    output wire [ 31:0] io_axi_master_write_addr_bits_addr,
    output wire [  2:0] io_axi_master_write_addr_bits_prot,
    output wire [  5:0] io_axi_master_write_addr_bits_id,
    output wire [  7:0] io_axi_master_write_addr_bits_len,
    output wire [  2:0] io_axi_master_write_addr_bits_size,
    output wire [  1:0] io_axi_master_write_addr_bits_burst,
    output wire [  0:0] io_axi_master_write_addr_bits_lock,
    output wire [  3:0] io_axi_master_write_addr_bits_cache,
    output wire [  3:0] io_axi_master_write_addr_bits_qos,
    output wire [  3:0] io_axi_master_write_addr_bits_region,
    output reg          io_axi_master_write_data_valid,
    input  wire         io_axi_master_write_data_ready,
    output reg  [127:0] io_axi_master_write_data_bits_data,
    output wire         io_axi_master_write_data_bits_last,
    output wire [ 15:0] io_axi_master_write_data_bits_strb,
    input  wire         io_axi_master_write_resp_valid,
    output wire         io_axi_master_write_resp_ready,
    input  wire [  5:0] io_axi_master_write_resp_bits_id,
    input  wire [  1:0] io_axi_master_write_resp_bits_resp,
    output reg          io_axi_master_read_addr_valid,
    input  wire         io_axi_master_read_addr_ready,
    output wire [ 31:0] io_axi_master_read_addr_bits_addr,
    output wire [  2:0] io_axi_master_read_addr_bits_prot,
    output wire [  5:0] io_axi_master_read_addr_bits_id,
    output wire [  7:0] io_axi_master_read_addr_bits_len,
    output wire [  2:0] io_axi_master_read_addr_bits_size,
    output wire [  1:0] io_axi_master_read_addr_bits_burst,
    output wire [  0:0] io_axi_master_read_addr_bits_lock,
    output wire [  3:0] io_axi_master_read_addr_bits_cache,
    output wire [  3:0] io_axi_master_read_addr_bits_qos,
    output wire [  3:0] io_axi_master_read_addr_bits_region,
    input  wire         io_axi_master_read_data_valid,
    output wire         io_axi_master_read_data_ready,
    input  wire [127:0] io_axi_master_read_data_bits_data,
    input  wire [  5:0] io_axi_master_read_data_bits_id,
    input  wire [  1:0] io_axi_master_read_data_bits_resp,
    input  wire         io_axi_master_read_data_bits_last,
    // status
    output reg          io_halted,
    output wire         io_fault,
    output wire         io_wfi,
    input  wire         io_irq,
    input  wire [ 31:0] io_boot_addr,
    input  wire         io_timer_irq,
    input  wire         io_software_irq,
    input  wire         io_dm_req_valid,
    output wire         io_dm_req_ready,
    input  wire [ 31:0] io_dm_req_bits_address,
    input  wire [ 31:0] io_dm_req_bits_data,
    input  wire [  1:0] io_dm_req_bits_op,
    output wire         io_dm_rsp_valid,
    input  wire         io_dm_rsp_ready,
    output wire [ 31:0] io_dm_rsp_bits_data,
    output wire [  1:0] io_dm_rsp_bits_op,
    input  wire         io_te
);
  wire clk = io_aclk;
  wire rstn = io_aresetn;

  assign io_fault = 1'b0;
  assign io_wfi = 1'b0;
  assign io_dm_req_ready = 1'b0;
  assign io_dm_rsp_valid = 1'b0;
  assign io_dm_rsp_bits_data = 32'd0;
  assign io_dm_rsp_bits_op = 2'd0;

  // ---------------------------------------------------------------- ITCM
  reg          sram_en, sram_we;
  reg  [  8:0] sram_addr;
  reg  [127:0] sram_wdata;
  reg  [ 15:0] sram_wmask;
  wire [127:0] sram_rdata;
  wire         sram_rvalid;

  Sram #(.NUM_ENTRIES(512)) u_itcm (
      .clock (clk),
      .enable(sram_en),
      .write (sram_we),
      .addr  (sram_addr),
      .wdata (sram_wdata),
      .wmask (sram_wmask),
      .rdata (sram_rdata),
      .rvalid(sram_rvalid)
  );

  reg [31:0] csr_reset, csr_pc;

  // ------------------------------------------------- AXI subordinate (single beat)
  localparam T_IDLE = 0, T_WDATA = 1, T_FETCH = 2, T_B = 3, T_RSRAM = 4, T_RWAIT = 5, T_R = 6;
  reg [2:0] t_state;
  reg [31:0] t_addr;
  reg [5:0] t_id;
  reg [127:0] word0;
  reg fetch_req, fetched;
  assign io_axi_slave_write_addr_ready = (t_state == T_IDLE) && !io_axi_slave_read_addr_valid;
  assign io_axi_slave_read_addr_ready = (t_state == T_IDLE);
  assign io_axi_slave_write_data_ready = (t_state == T_WDATA);
  assign io_axi_slave_write_resp_bits_id = t_id;
  assign io_axi_slave_write_resp_bits_resp = 2'b00;
  assign io_axi_slave_read_data_bits_id = t_id;
  assign io_axi_slave_read_data_bits_resp = 2'b00;
  assign io_axi_slave_read_data_bits_last = 1'b1;

  wire in_itcm = (t_addr < 32'h2000);
  wire in_csr = (t_addr[31:12] == 20'h00030);

  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      t_state <= T_IDLE;
      sram_en <= 1'b0;
      sram_we <= 1'b0;
      io_axi_slave_write_resp_valid <= 1'b0;
      io_axi_slave_read_data_valid <= 1'b0;
      csr_reset <= 32'd1;
      csr_pc <= 32'd0;
      fetched <= 1'b0;
    end else begin
      sram_en <= 1'b0;
      case (t_state)
        T_IDLE:
        if (fetch_req && !fetched) begin           // core instruction fetch
          sram_en   <= 1'b1;
          sram_we   <= 1'b0;
          sram_addr <= csr_pc[12:4];
          t_state   <= T_FETCH;
        end else if (io_axi_slave_read_addr_valid) begin
          t_addr  <= io_axi_slave_read_addr_bits_addr;
          t_id    <= io_axi_slave_read_addr_bits_id;
          t_state <= T_RSRAM;
        end else if (io_axi_slave_write_addr_valid) begin
          t_addr  <= io_axi_slave_write_addr_bits_addr;
          t_id    <= io_axi_slave_write_addr_bits_id;
          t_state <= T_WDATA;
        end
        T_WDATA:
        if (io_axi_slave_write_data_valid) begin
          if (in_itcm) begin
            sram_en    <= 1'b1;
            sram_we    <= 1'b1;
            sram_addr  <= t_addr[12:4];
            sram_wdata <= io_axi_slave_write_data_bits_data;
            sram_wmask <= io_axi_slave_write_data_bits_strb;
          end else if (in_csr) begin
            if (t_addr[11:0] == 12'h000) csr_reset <= io_axi_slave_write_data_bits_data[31:0];
            if (t_addr[11:0] == 12'h004) csr_pc <= io_axi_slave_write_data_bits_data[63:32];
          end
          t_state <= T_B;
          io_axi_slave_write_resp_valid <= 1'b1;
        end
        T_FETCH:
        if (sram_rvalid) begin
          word0   <= sram_rdata;
          fetched <= 1'b1;
          t_state <= T_IDLE;
        end
        T_B:
        if (io_axi_slave_write_resp_ready) begin
          io_axi_slave_write_resp_valid <= 1'b0;
          t_state <= T_IDLE;
        end
        T_RSRAM: begin
          if (in_itcm) begin
            sram_en   <= 1'b1;
            sram_we   <= 1'b0;
            sram_addr <= t_addr[12:4];
            t_state   <= T_RWAIT;
          end else begin
            io_axi_slave_read_data_bits_data <= {csr_pc, csr_pc, csr_reset, csr_reset};
            io_axi_slave_read_data_valid <= 1'b1;
            t_state <= T_R;
          end
        end
        T_RWAIT:
        if (sram_rvalid) begin
          io_axi_slave_read_data_bits_data <= sram_rdata;
          io_axi_slave_read_data_valid <= 1'b1;
          t_state <= T_R;
        end
        T_R:
        if (io_axi_slave_read_data_ready) begin
          io_axi_slave_read_data_valid <= 1'b0;
          t_state <= T_IDLE;
        end
        default: t_state <= T_IDLE;
      endcase
    end
  end

  // ---------------------------------------------------------- "program"
  reg [3:0] p_state;
  reg       was_reset;
  reg [31:0] m_addr;
  assign io_axi_master_write_addr_bits_addr = m_addr;
  assign io_axi_master_read_addr_bits_addr = m_addr;
  assign io_axi_master_write_addr_bits_prot = 3'd2;
  assign io_axi_master_write_addr_bits_id = 6'd0;
  assign io_axi_master_write_addr_bits_len = 8'd0;
  assign io_axi_master_write_addr_bits_size = 3'd2;
  assign io_axi_master_write_addr_bits_burst = 2'd1;
  assign io_axi_master_write_addr_bits_lock = 1'b0;
  assign io_axi_master_write_addr_bits_cache = 4'd0;
  assign io_axi_master_write_addr_bits_qos = 4'd0;
  assign io_axi_master_write_addr_bits_region = 4'd0;
  assign io_axi_master_write_data_bits_last = 1'b1;
  assign io_axi_master_write_data_bits_strb = 16'h000F;
  assign io_axi_master_write_resp_ready = 1'b1;
  assign io_axi_master_read_addr_bits_prot = 3'd2;
  assign io_axi_master_read_addr_bits_id = 6'd0;
  assign io_axi_master_read_addr_bits_len = 8'd0;
  assign io_axi_master_read_addr_bits_size = 3'd2;
  assign io_axi_master_read_addr_bits_burst = 2'd1;
  assign io_axi_master_read_addr_bits_lock = 1'b0;
  assign io_axi_master_read_addr_bits_cache = 4'd0;
  assign io_axi_master_read_addr_bits_qos = 4'd0;
  assign io_axi_master_read_addr_bits_region = 4'd0;
  assign io_axi_master_read_data_ready = 1'b1;

  always @(*) fetch_req = (p_state == 1);
  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      p_state <= 0;
      was_reset <= 1'b0;
      io_halted <= 1'b0;
      io_axi_master_write_addr_valid <= 1'b0;
      io_axi_master_write_data_valid <= 1'b0;
      io_axi_master_read_addr_valid <= 1'b0;
    end else begin
      case (p_state)
        0: if (csr_reset[0] == 1'b1) was_reset <= 1'b1;
           else if (was_reset) p_state <= 1;      // reset released by host
        1: if (fetched) p_state <= 4;             // ITCM[csr_pc] fetched
        4: begin
             m_addr <= 32'h8000_0000;
             io_axi_master_write_data_bits_data <= {96'd0, word0[31:0]};
             io_axi_master_write_addr_valid <= 1'b1;
             io_axi_master_write_data_valid <= 1'b1;
             p_state <= 5;
           end
        5: begin
             if (io_axi_master_write_addr_ready) io_axi_master_write_addr_valid <= 1'b0;
             if (io_axi_master_write_data_ready) io_axi_master_write_data_valid <= 1'b0;
             if (io_axi_master_write_resp_valid) p_state <= 6;
           end
        6: begin
             m_addr <= 32'h8000_000C;
             io_axi_master_read_addr_valid <= 1'b1;
             p_state <= 7;
           end
        7: if (io_axi_master_read_addr_ready) begin
             io_axi_master_read_addr_valid <= 1'b0;
             p_state <= 8;
           end
        8: if (io_axi_master_read_data_valid) begin
             if (io_axi_master_read_data_bits_data[127:96] == 32'hC0A1_5130) io_halted <= 1'b1;
             p_state <= 9;
           end
        default: ;
      endcase
    end
  end

endmodule

`default_nettype wire
