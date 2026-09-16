// ============================================================================
// File: axi_spi_top.sv
// Description: Top-Level Module for AXI4-Lite SPI Master IP Core
// Project: AXI_SPI
// ============================================================================

module axi_spi_top import spi_pkg::*; #(
  parameter int FIFO_DEPTH = 16
)(
  input  logic                  clk,
  input  logic                  rst_n,

  // AXI4-Lite Write Address Channel
  input  logic [31:0]           s_axi_awaddr,
  input  logic [2:0]            s_axi_awprot,
  input  logic                  s_axi_awvalid,
  output logic                  s_axi_awready,

  // AXI4-Lite Write Data Channel
  input  logic [31:0]           s_axi_wdata,
  input  logic [3:0]            s_axi_wstrb,
  input  logic                  s_axi_wvalid,
  output logic                  s_axi_wready,

  // AXI4-Lite Write Response Channel
  output logic [1:0]            s_axi_bresp,
  output logic                  s_axi_bvalid,
  input  logic                  s_axi_bready,

  // AXI4-Lite Read Address Channel
  input  logic [31:0]           s_axi_araddr,
  input  logic [2:0]            s_axi_arprot,
  input  logic                  s_axi_arvalid,
  output logic                  s_axi_arready,

  // AXI4-Lite Read Data Channel
  output logic [31:0]           s_axi_rdata,
  output logic [1:0]            s_axi_rresp,
  output logic                  s_axi_rvalid,
  input  logic                  s_axi_rready,

  // SPI Master Physical Signals
  output logic                  spi_sck,
  output logic                  spi_mosi,
  input  logic                  spi_miso,
  output logic [NUM_SLAVES-1:0] spi_ss_n,

  // Hardware Interrupt Output
  output logic                  irq
);

  // --------------------------------------------------------------------------
  // Local Register Access Bus
  // --------------------------------------------------------------------------
  logic        reg_wr_en;
  logic [5:0]  reg_wr_addr;
  logic [31:0] reg_wdata;
  logic [3:0]  reg_wstrb;

  logic        reg_rd_en;
  logic [5:0]  reg_rd_addr;
  logic [31:0] reg_rdata;

  // --------------------------------------------------------------------------
  // Register Control & Configuration Signals
  // --------------------------------------------------------------------------
  logic                  core_en;
  /* verilator lint_off UNUSED */
  logic                  irq_en_sig;
  /* verilator lint_on UNUSED */
  logic                  loopback_en;
  logic                  cpol;
  logic                  cpha;
  logic                  lsb_first;
  logic                  rx_dis;
  logic                  tx_dis;

  logic [15:0]           prescale;
  logic [5:0]            data_bits;
  logic [NUM_SLAVES-1:0] cs_pol;

  logic                  cs_auto_en;
  logic [1:0]            cs_sel;
  logic [NUM_SLAVES-1:0] manual_ss;
  logic                  keep_cs_default;

  logic [7:0]            t_css;
  logic [7:0]            t_csh;
  logic [15:0]           t_idle;

  /* verilator lint_off UNUSED */
  logic [5:0]            tx_wm;
  logic [5:0]            rx_wm;
  /* verilator lint_on UNUSED */
  logic                  tx_fifo_flush;
  logic                  rx_fifo_flush;

  // --------------------------------------------------------------------------
  // FIFO Interconnect Signals
  // --------------------------------------------------------------------------
  // TX FIFO
  logic                  tx_fifo_wr_en;
  logic [35:0]           tx_fifo_din;
  logic                  tx_fifo_rd_en;
  logic [35:0]           tx_fifo_dout;
  logic                  tx_fifo_full;
  logic                  tx_fifo_empty;
  logic [$clog2(FIFO_DEPTH+1)-1:0] tx_fifo_count;
  /* verilator lint_off UNUSED */
  logic                  tx_fifo_overflow;
  /* verilator lint_on UNUSED */

  // RX FIFO
  logic                  rx_fifo_wr_en;
  logic [31:0]           rx_fifo_din;
  logic                  rx_fifo_rd_en;
  logic [31:0]           rx_fifo_dout;
  logic                  rx_fifo_full;
  logic                  rx_fifo_empty;
  logic [$clog2(FIFO_DEPTH+1)-1:0] rx_fifo_count;
  /* verilator lint_off UNUSED */
  logic                  rx_fifo_overflow;
  /* verilator lint_on UNUSED */

  // --------------------------------------------------------------------------
  // Timing Generator Signals
  // --------------------------------------------------------------------------
  logic                  timing_enable;
  logic                  tick_half;

  // --------------------------------------------------------------------------
  // Core Status Signals
  // --------------------------------------------------------------------------
  logic                  busy;
  logic                  ss_active;
  logic                  xfer_done_pulse;
  logic                  rx_overrun_pulse;
  logic                  tx_underrun_pulse;
  /* verilator lint_off UNUSED */
  logic [2:0]            fsm_state_out;
  /* verilator lint_on UNUSED */

  // --------------------------------------------------------------------------
  // AXI4-Lite Slave Interface Instance
  // --------------------------------------------------------------------------
  axi_lite_slave u_axi_slave (
    .clk           (clk),
    .rst_n         (rst_n),
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
    .reg_wr_en     (reg_wr_en),
    .reg_wr_addr   (reg_wr_addr),
    .reg_wdata     (reg_wdata),
    .reg_wstrb     (reg_wstrb),
    .reg_rd_en     (reg_rd_en),
    .reg_rd_addr   (reg_rd_addr),
    .reg_rdata     (reg_rdata)
  );

  // --------------------------------------------------------------------------
  // Synchronous TX FIFO (36-bit entry: keep_cs[35], cs_sel[34:33], rx_dis[32], data[31:0])
  // --------------------------------------------------------------------------
  sync_fifo #(
    .DATA_WIDTH (36),
    .DEPTH      (FIFO_DEPTH)
  ) u_tx_fifo (
    .clk      (clk),
    .rst_n    (rst_n),
    .clear    (tx_fifo_flush),
    .wr_en    (tx_fifo_wr_en),
    .din      (tx_fifo_din),
    .rd_en    (tx_fifo_rd_en),
    .dout     (tx_fifo_dout),
    .full     (tx_fifo_full),
    .empty    (tx_fifo_empty),
    .count    (tx_fifo_count),
    .overflow (tx_fifo_overflow)
  );

  // --------------------------------------------------------------------------
  // Synchronous RX FIFO (32-bit entry)
  // --------------------------------------------------------------------------
  sync_fifo #(
    .DATA_WIDTH (32),
    .DEPTH      (FIFO_DEPTH)
  ) u_rx_fifo (
    .clk      (clk),
    .rst_n    (rst_n),
    .clear    (rx_fifo_flush),
    .wr_en    (rx_fifo_wr_en),
    .din      (rx_fifo_din),
    .rd_en    (rx_fifo_rd_en),
    .dout     (rx_fifo_dout),
    .full     (rx_fifo_full),
    .empty    (rx_fifo_empty),
    .count    (rx_fifo_count),
    .overflow (rx_fifo_overflow)
  );

  // --------------------------------------------------------------------------
  // Timing Generator (Baud Prescaler)
  // --------------------------------------------------------------------------
  spi_timing_gen u_timing_gen (
    .clk       (clk),
    .rst_n     (rst_n),
    .enable    (timing_enable),
    .prescale  (prescale),
    .tick_half (tick_half)
  );

  // --------------------------------------------------------------------------
  // SPI Protocol & Serialization Core FSM
  // --------------------------------------------------------------------------
  spi_fsm_core u_fsm_core (
    .clk               (clk),
    .rst_n             (rst_n),
    .core_en           (core_en),
    .cpol              (cpol),
    .cpha              (cpha),
    .lsb_first         (lsb_first),
    .rx_dis            (rx_dis),
    .tx_dis            (tx_dis),
    .loopback_en       (loopback_en),
    .data_bits         (data_bits),
    .cs_pol            (cs_pol),
    .cs_auto_en        (cs_auto_en),
    .cs_sel            (cs_sel),
    .manual_ss         (manual_ss),
    .keep_cs_default   (keep_cs_default),
    .t_css             (t_css),
    .t_csh             (t_csh),
    .t_idle            (t_idle),
    .timing_enable     (timing_enable),
    .tick_half         (tick_half),
    .tx_fifo_empty     (tx_fifo_empty),
    .tx_fifo_dout      (tx_fifo_dout),
    .tx_fifo_rd_en     (tx_fifo_rd_en),
    .rx_fifo_full      (rx_fifo_full),
    .rx_fifo_din       (rx_fifo_din),
    .rx_fifo_wr_en     (rx_fifo_wr_en),
    .rx_overrun_pulse  (rx_overrun_pulse),
    .busy              (busy),
    .ss_active         (ss_active),
    .xfer_done_pulse   (xfer_done_pulse),
    .tx_underrun_pulse (tx_underrun_pulse),
    .fsm_state_out     (fsm_state_out),
    .sck               (spi_sck),
    .mosi              (spi_mosi),
    .miso              (spi_miso),
    .ss_n              (spi_ss_n)
  );

  // --------------------------------------------------------------------------
  // Memory-Mapped Register File & Interrupt Management
  // --------------------------------------------------------------------------
  spi_regs #(
    .FIFO_DEPTH (FIFO_DEPTH)
  ) u_regs (
    .clk                (clk),
    .rst_n              (rst_n),
    .reg_wr_en          (reg_wr_en),
    .reg_wr_addr        (reg_wr_addr),
    .reg_wdata          (reg_wdata),
    .reg_wstrb          (reg_wstrb),
    .reg_rd_en          (reg_rd_en),
    .reg_rd_addr        (reg_rd_addr),
    .reg_rdata          (reg_rdata),
    .core_en            (core_en),
    .irq_en             (irq_en_sig),
    .loopback_en        (loopback_en),
    .cpol               (cpol),
    .cpha               (cpha),
    .lsb_first          (lsb_first),
    .rx_dis             (rx_dis),
    .tx_dis             (tx_dis),
    .prescale           (prescale),
    .data_bits          (data_bits),
    .cs_pol             (cs_pol),
    .cs_auto_en         (cs_auto_en),
    .cs_sel             (cs_sel),
    .manual_ss          (manual_ss),
    .keep_cs_default    (keep_cs_default),
    .t_css              (t_css),
    .t_csh              (t_csh),
    .t_idle             (t_idle),
    .tx_wm              (tx_wm),
    .rx_wm              (rx_wm),
    .tx_fifo_flush      (tx_fifo_flush),
    .rx_fifo_flush      (rx_fifo_flush),
    .tx_fifo_wr_en      (tx_fifo_wr_en),
    .tx_fifo_din        (tx_fifo_din),
    .tx_fifo_full       (tx_fifo_full),
    .tx_fifo_empty      (tx_fifo_empty),
    .tx_fifo_count      (tx_fifo_count),
    .rx_fifo_rd_en      (rx_fifo_rd_en),
    .rx_fifo_dout       (rx_fifo_dout),
    .rx_fifo_full       (rx_fifo_full),
    .rx_fifo_empty      (rx_fifo_empty),
    .rx_fifo_count      (rx_fifo_count),
    .busy               (busy),
    .ss_active          (ss_active),
    .xfer_done_pulse    (xfer_done_pulse),
    .rx_overrun_pulse   (rx_overrun_pulse),
    .tx_underrun_pulse  (tx_underrun_pulse),
    .irq                (irq)
  );

endmodule
