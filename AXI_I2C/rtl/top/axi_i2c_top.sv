// ============================================================================
// File: axi_i2c_top.sv
// Description: Top-Level Module for AXI4-Lite I2C Master IP Core (AXI_I2C)
// Project: AXI_I2C
// ============================================================================

module axi_i2c_top #(
  parameter int FIFO_DEPTH = 16
)(
  input  logic        s_axi_aclk,
  input  logic        s_axi_aresetn,

  // External I2C Open-Drain Pin Interface
  input  logic        scl_i,
  output logic        scl_o,
  output logic        scl_oe,

  input  logic        sda_i,
  output logic        sda_o,
  output logic        sda_oe,

  // Interrupt Output
  output logic        irq,

  // AXI4-Lite Slave Interface
  // AW
  input  logic [31:0] s_axi_awaddr,
  input  logic [2:0]  s_axi_awprot,
  input  logic        s_axi_awvalid,
  output logic        s_axi_awready,
  // W
  input  logic [31:0] s_axi_wdata,
  input  logic [3:0]  s_axi_wstrb,
  input  logic        s_axi_wvalid,
  output logic        s_axi_wready,
  // B
  output logic [1:0]  s_axi_bresp,
  output logic        s_axi_bvalid,
  input  logic        s_axi_bready,
  // AR
  input  logic [31:0] s_axi_araddr,
  input  logic [2:0]  s_axi_arprot,
  input  logic        s_axi_arvalid,
  output logic        s_axi_arready,
  // R
  output logic [31:0] s_axi_rdata,
  output logic [1:0]  s_axi_rresp,
  output logic        s_axi_rvalid,
  input  logic        s_axi_rready
);

  import i2c_pkg::*;

  wire clk   = s_axi_aclk;
  wire rst_n = s_axi_aresetn;

  // --------------------------------------------------------------------------
  // Internal Wires & Busses
  // --------------------------------------------------------------------------
  // Local AXI register interface
  logic        reg_wr_en;
  logic [5:0]  reg_wr_addr;
  logic [31:0] reg_wdata;
  /* verilator lint_off UNUSED */
  logic [3:0]  reg_wstrb;
  /* verilator lint_on UNUSED */
  logic        reg_rd_en;
  logic [5:0]  reg_rd_addr;
  logic [31:0] reg_rdata;

  // Configurations
  logic        core_enable;
  /* verilator lint_off UNUSED */
  logic        global_irq_en;
  /* verilator lint_on UNUSED */
  logic        loopback_en;
  /* verilator lint_off UNUSED */
  logic        auto_recover;
  /* verilator lint_on UNUSED */
  logic        manual_recover_pulse;
  logic        stretch_en;
  logic [15:0] prescale;
  logic [7:0]  scl_low_extra;
  logic [7:0]  scl_high_extra;
  logic [7:0]  filter_cycles;
  logic [15:0] timeout_limit;

  // TX & RX FIFO Signals
  logic        tx_fifo_wr_en, tx_fifo_rd_en, tx_fifo_flush;
  logic [11:0] tx_fifo_din,   tx_fifo_dout;
  logic        tx_fifo_full,  tx_fifo_empty, tx_fifo_overflow;
  logic [$clog2(FIFO_DEPTH+1)-1:0] tx_fifo_count;

  // RX FIFO Signals
  logic        rx_fifo_wr_en, rx_fifo_rd_en, rx_fifo_flush;
  logic [7:0]  rx_fifo_din,   rx_fifo_dout;
  logic        rx_fifo_full,  rx_fifo_empty, rx_fifo_overflow;
  logic [$clog2(FIFO_DEPTH+1)-1:0] rx_fifo_count;

  // Filtered Input Signals & Edges
  logic        scl_raw_input, sda_raw_input;
  logic        scl_filtered,  sda_filtered;
  /* verilator lint_off UNUSED */
  logic        scl_posedge,   scl_negedge;
  logic        sda_posedge,   sda_negedge;
  /* verilator lint_on UNUSED */
  logic        start_detected, stop_detected;

  // 4-Phase Timing Generator Signals
  i2c_phase_t  timing_phase;
  logic        phase_end_pulse;
  logic        bit_end_pulse;
  logic        scl_held;
  logic        timeout_pulse;
  logic        timer_run;
  logic        timer_reset;

  // Bus Monitor Signals
  logic        bus_busy;
  logic        arb_lost_pulse;
  logic        bus_error_pulse;
  logic        master_active;
  logic        check_arb_en;
  logic        expected_sda_val;
  logic        master_start_seq;
  logic        master_stop_seq;

  // Core FSM Signals & Events
  logic        fsm_busy;
  logic        nack_received_pulse;
  logic        arb_lost_event_pulse;
  logic        transaction_done_pulse;
  logic        core_scl_oe;
  logic        core_sda_oe;

  // --------------------------------------------------------------------------
  // Pad Output Driving & Loopback Multiplexing
  // --------------------------------------------------------------------------
  assign scl_o  = 1'b0;
  assign sda_o  = 1'b0;
  assign scl_oe = core_scl_oe;
  assign sda_oe = core_sda_oe;

  assign scl_raw_input = loopback_en ? (core_scl_oe ? 1'b0 : 1'b1) : scl_i;
  assign sda_raw_input = loopback_en ? (core_sda_oe ? 1'b0 : 1'b1) : sda_i;

  // --------------------------------------------------------------------------
  // 1. AXI4-Lite Slave Interface
  // --------------------------------------------------------------------------
  axi_lite_slave u_axi_slave (
    .s_axi_aclk    (s_axi_aclk),
    .s_axi_aresetn (s_axi_aresetn),
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
  // 2. Register File & Control Block
  // --------------------------------------------------------------------------
  i2c_regs #(
    .FIFO_DEPTH (FIFO_DEPTH)
  ) u_regs (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .reg_wr_en              (reg_wr_en),
    .reg_wr_addr            (reg_wr_addr),
    .reg_wdata              (reg_wdata),
    .reg_rd_en              (reg_rd_en),
    .reg_rd_addr            (reg_rd_addr),
    .reg_rdata              (reg_rdata),
    .tx_fifo_wr_en          (tx_fifo_wr_en),
    .tx_fifo_din            (tx_fifo_din),
    .tx_fifo_flush          (tx_fifo_flush),
    .tx_fifo_full           (tx_fifo_full),
    .tx_fifo_empty          (tx_fifo_empty),
    .tx_fifo_count          (tx_fifo_count),
    .tx_fifo_overflow       (tx_fifo_overflow),
    .rx_fifo_rd_en          (rx_fifo_rd_en),
    .rx_fifo_dout           (rx_fifo_dout),
    .rx_fifo_flush          (rx_fifo_flush),
    .rx_fifo_full           (rx_fifo_full),
    .rx_fifo_empty          (rx_fifo_empty),
    .rx_fifo_count          (rx_fifo_count),
    .rx_fifo_overflow       (rx_fifo_overflow),
    .fsm_busy               (fsm_busy),
    .bus_busy               (bus_busy),
    .scl_held               (scl_held),
    .nack_received_pulse    (nack_received_pulse),
    .arb_lost_event_pulse   (arb_lost_event_pulse),
    .bus_error_pulse        (bus_error_pulse),
    .timeout_pulse          (timeout_pulse),
    .transaction_done_pulse (transaction_done_pulse),
    .core_enable_o          (core_enable),
    .global_irq_en_o        (global_irq_en),
    .loopback_en_o          (loopback_en),
    .auto_recover_o         (auto_recover),
    .manual_recover_pulse_o (manual_recover_pulse),
    .stretch_en_o           (stretch_en),
    .prescale_o             (prescale),
    .scl_low_extra_o        (scl_low_extra),
    .scl_high_extra_o       (scl_high_extra),
    .filter_cycles_o        (filter_cycles),
    .timeout_limit_o        (timeout_limit),
    .irq_o                  (irq)
  );

  // --------------------------------------------------------------------------
  // 3. Command & TX Synchronous FIFO (12-bit width)
  // --------------------------------------------------------------------------
  sync_fifo #(
    .DATA_WIDTH (12),
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
  // 4. RX Synchronous FIFO (8-bit width)
  // --------------------------------------------------------------------------
  sync_fifo #(
    .DATA_WIDTH (8),
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
  // 5. Input Deglitch & Synchronizer Filter
  // --------------------------------------------------------------------------
  i2c_input_filter u_filter (
    .clk              (clk),
    .rst_n            (rst_n),
    .scl_raw_i        (scl_raw_input),
    .sda_raw_i        (sda_raw_input),
    .filter_cycles    (filter_cycles),
    .scl_filtered_o   (scl_filtered),
    .sda_filtered_o   (sda_filtered),
    .scl_posedge_o    (scl_posedge),
    .scl_negedge_o    (scl_negedge),
    .sda_posedge_o    (sda_posedge),
    .sda_negedge_o    (sda_negedge),
    .start_detected_o (start_detected),
    .stop_detected_o  (stop_detected)
  );

  // --------------------------------------------------------------------------
  // 6. 4-Phase Micro-Timing & Clock Stretching Generator
  // --------------------------------------------------------------------------
  i2c_timing_gen u_timing_gen (
    .clk             (clk),
    .rst_n           (rst_n),
    .enable          (core_enable),
    .timer_reset     (timer_reset),
    .timer_run       (timer_run),
    .prescale        (prescale),
    .scl_low_extra   (scl_low_extra),
    .scl_high_extra  (scl_high_extra),
    .stretch_en      (stretch_en),
    .timeout_limit   (timeout_limit),
    .scl_filtered    (scl_filtered),
    .master_scl_oe   (core_scl_oe),
    .current_phase   (timing_phase),
    .phase_end_pulse (phase_end_pulse),
    .bit_end_pulse   (bit_end_pulse),
    .scl_held_o      (scl_held),
    .timeout_pulse_o (timeout_pulse)
  );

  // --------------------------------------------------------------------------
  // 7. Bus State & Multi-Master Arbitration Monitor
  // --------------------------------------------------------------------------
  i2c_bus_monitor u_bus_monitor (
    .clk              (clk),
    .rst_n            (rst_n),
    .enable           (core_enable),
    .master_active    (master_active),
    .check_arb_en     (check_arb_en),
    .expected_sda     (expected_sda_val),
    .master_start_seq (master_start_seq),
    .master_stop_seq  (master_stop_seq),
    .scl_filtered     (scl_filtered),
    .sda_filtered     (sda_filtered),
    .start_detected   (start_detected),
    .stop_detected    (stop_detected),
    .bus_busy_o       (bus_busy),
    .arb_lost_pulse_o (arb_lost_pulse),
    .bus_error_pulse_o(bus_error_pulse)
  );

  // --------------------------------------------------------------------------
  // 8. Protocol Core FSM
  // --------------------------------------------------------------------------
  i2c_fsm_core u_fsm_core (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .enable                 (core_enable),
    .manual_recover         (manual_recover_pulse),
    .tx_fifo_empty          (tx_fifo_empty),
    .tx_fifo_dout           (tx_fifo_dout),
    .tx_fifo_rd_en          (tx_fifo_rd_en),
    .rx_fifo_wr_en          (rx_fifo_wr_en),
    .rx_fifo_din            (rx_fifo_din),
    .timing_phase           (timing_phase),
    .phase_end_pulse        (phase_end_pulse),
    .bit_end_pulse          (bit_end_pulse),
    .timer_run              (timer_run),
    .timer_reset            (timer_reset),
    .scl_filtered           (scl_filtered),
    .sda_filtered           (sda_filtered),
    .arb_lost_pulse         (arb_lost_pulse),
    .timeout_pulse          (timeout_pulse),
    .master_active          (master_active),
    .check_arb_en           (check_arb_en),
    .expected_sda_val       (expected_sda_val),
    .master_start_seq       (master_start_seq),
    .master_stop_seq        (master_stop_seq),
    .scl_oe_o               (core_scl_oe),
    .sda_oe_o               (core_sda_oe),
    .fsm_busy_o             (fsm_busy),
    .nack_received_pulse    (nack_received_pulse),
    .arb_lost_event_pulse   (arb_lost_event_pulse),
    .transaction_done_pulse (transaction_done_pulse)
  );

endmodule
