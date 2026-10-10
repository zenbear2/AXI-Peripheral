// ============================================================================
// File: spi_tb.sv
// Description: SystemVerilog Testbench Top Wrapper for AXI_SPI IP Core
// Project: AXI_SPI
// ============================================================================

`timescale 1ns/1ps

module spi_tb import spi_pkg::*; (
  input  logic        clk,
  input  logic        rst_n,

  // AXI4-Lite Interface
  input  logic [31:0] s_axi_awaddr,
  input  logic [2:0]  s_axi_awprot,
  input  logic        s_axi_awvalid,
  output logic        s_axi_awready,

  input  logic [31:0] s_axi_wdata,
  input  logic [3:0]  s_axi_wstrb,
  input  logic        s_axi_wvalid,
  output logic        s_axi_wready,

  output logic [1:0]  s_axi_bresp,
  output logic        s_axi_bvalid,
  input  logic        s_axi_bready,

  input  logic [31:0] s_axi_araddr,
  input  logic [2:0]  s_axi_arprot,
  input  logic        s_axi_arvalid,
  output logic        s_axi_arready,

  output logic [31:0] s_axi_rdata,
  output logic [1:0]  s_axi_rresp,
  output logic        s_axi_rvalid,
  input  logic        s_axi_rready,

  // Direct Status Signals for Testbench Monitoring
  output logic        spi_sck,
  output logic        spi_mosi,
  output logic        spi_miso,
  output logic [3:0]  spi_ss_n,
  output logic        irq
);

  logic slave0_miso;
  logic slave1_miso;

  // MISO Bus Mux
  assign spi_miso = (!spi_ss_n[0]) ? slave0_miso :
                    (!spi_ss_n[1]) ? slave1_miso : 1'b1;

  // AXI SPI Top Instance
  axi_spi_top #(
    .FIFO_DEPTH (16)
  ) dut (
    .s_axi_aclk    (clk),
    .s_axi_aresetn (rst_n),
    .s_axi_awaddr  (s_axi_awaddr),
    .s_axi_awprot  (s_axi_awprot),
    .s_axi_awvalid (s_axi_awvalid),
    .s_axi_awready (s_axi_awready),
    .s_axi_wdata   (s_axi_wdata),
    .s_axi_wstrb   (s_axi_wstrb),
    .s_axi_wvalid  (s_axi_wvalid),
    .s_axi_wready  (s_axi_wready),
    .s_axi_bresp   (s_axi_bresp),
    .s_axi_bvalid  (s_axi_bvalid),
    .s_axi_bready  (s_axi_bready),
    .s_axi_araddr  (s_axi_araddr),
    .s_axi_arprot  (s_axi_arprot),
    .s_axi_arvalid (s_axi_arvalid),
    .s_axi_arready (s_axi_arready),
    .s_axi_rdata   (s_axi_rdata),
    .s_axi_rresp   (s_axi_rresp),
    .s_axi_rvalid  (s_axi_rvalid),
    .s_axi_rready  (s_axi_rready),
    .spi_sck       (spi_sck),
    .spi_mosi      (spi_mosi),
    .spi_miso      (spi_miso),
    .spi_ss_n      (spi_ss_n),
    .irq           (irq)
  );

  // Virtual SPI Slave 0 (NOR Flash / EEPROM)
  spi_slave_model u_slave0 (
    .sck   (spi_sck),
    .mosi  (spi_mosi),
    .miso  (slave0_miso),
    .ss_n  (spi_ss_n[0]),
    .cpol  (dut.u_regs.cpol),
    .cpha  (dut.u_regs.cpha)
  );

  // Virtual SPI Slave 1 (Peripheral Device)
  spi_slave_model u_slave1 (
    .sck   (spi_sck),
    .mosi  (spi_mosi),
    .miso  (slave1_miso),
    .ss_n  (spi_ss_n[1]),
    .cpol  (dut.u_regs.cpol),
    .cpha  (dut.u_regs.cpha)
  );

endmodule
