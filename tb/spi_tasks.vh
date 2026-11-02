// SPDX-License-Identifier: Apache-2.0
// SPI host tasks shared by tb_soc.v and tb_soc_real.v (include inside a module
// that declares: reg sck, csb, mosi; wire miso; localparam SCK_HALF_NS)
  // ------------------------------------------------------------ SPI host tasks
  task spi_byte(input [7:0] tx, output [7:0] rx);
    integer i;
    begin
      for (i = 7; i >= 0; i = i - 1) begin
        mosi = tx[i];
        #(SCK_HALF_NS);
        sck = 1'b1;
        rx[i] = miso;      // sample on rising edge (mode 0)
        #(SCK_HALF_NS);
        sck = 1'b0;
      end
    end
  endtask

  task spi_write32(input [31:0] addr, input [31:0] data);
    reg [7:0] d;
    begin
      csb = 1'b0; #(SCK_HALF_NS);
      spi_byte(8'h02, d);
      spi_byte(addr[31:24], d); spi_byte(addr[23:16], d);
      spi_byte(addr[15:8], d);  spi_byte(addr[7:0], d);
      spi_byte(data[31:24], d); spi_byte(data[23:16], d);
      spi_byte(data[15:8], d);  spi_byte(data[7:0], d);
      #(SCK_HALF_NS); csb = 1'b1; #(4 * SCK_HALF_NS);
    end
  endtask

  task spi_read32(input [31:0] addr, output [31:0] data, output [7:0] status);
    reg [7:0] d;
    begin
      csb = 1'b0; #(SCK_HALF_NS);
      spi_byte(8'h03, d);
      spi_byte(addr[31:24], d); spi_byte(addr[23:16], d);
      spi_byte(addr[15:8], d);  spi_byte(addr[7:0], d);
      spi_byte(8'h00, status);
      spi_byte(8'h00, d); data[31:24] = d;
      spi_byte(8'h00, d); data[23:16] = d;
      spi_byte(8'h00, d); data[15:8] = d;
      spi_byte(8'h00, d); data[7:0] = d;
      #(SCK_HALF_NS); csb = 1'b1; #(4 * SCK_HALF_NS);
    end
  endtask

  task spi_read_id(output [31:0] id);
    reg [7:0] d;
    begin
      csb = 1'b0; #(SCK_HALF_NS);
      spi_byte(8'h9F, d);
      spi_byte(8'h00, d); id[31:24] = d;
      spi_byte(8'h00, d); id[23:16] = d;
      spi_byte(8'h00, d); id[15:8] = d;
      spi_byte(8'h00, d); id[7:0] = d;
      #(SCK_HALF_NS); csb = 1'b1; #(4 * SCK_HALF_NS);
    end
  endtask

