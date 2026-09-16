// ============================================================================
// File: i2c_bus_monitor.sv
// Description: Multi-Master Arbitration Loss & Bus Busy Monitor
// Project: AXI_I2C
// ============================================================================

module i2c_bus_monitor (
  input  logic        clk,
  input  logic        rst_n,

  // Control Signals
  input  logic        enable,
  input  logic        master_active,
  input  logic        check_arb_en,
  input  logic        expected_sda,   // Master's intended output SDA level (1=High-Z, 0=Drive low)
  input  logic        master_start_seq,
  input  logic        master_stop_seq,

  // Filtered Bus Signals & Events
  input  logic        scl_filtered,
  input  logic        sda_filtered,
  input  logic        start_detected,
  input  logic        stop_detected,

  // Bus Status Outputs
  output logic        bus_busy_o,
  output logic        arb_lost_pulse_o,
  output logic        bus_error_pulse_o
);

  logic bus_busy;

  // --------------------------------------------------------------------------
  // 1. Bus Busy State Tracking (START to STOP)
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bus_busy <= 1'b0;
    end else if (!enable) begin
      bus_busy <= 1'b0;
    end else begin
      if (start_detected) begin
        bus_busy <= 1'b1;
      end else if (stop_detected) begin
        bus_busy <= 1'b0;
      end
    end
  end

  assign bus_busy_o = bus_busy;

  // --------------------------------------------------------------------------
  // 2. Multi-Master Arbitration Lost Detector
  // --------------------------------------------------------------------------
  // Arbitration is checked in PH_HIGH when Master expects SDA to be High (1'b1),
  // but the filtered line is Low (1'b0) because another Master is driving '0'.
  logic arb_lost;

  always_comb begin
    arb_lost = 1'b0;
    if (enable && master_active && check_arb_en && scl_filtered) begin
      if (expected_sda == 1'b1 && sda_filtered == 1'b0) begin
        arb_lost = 1'b1;
      end
    end
  end

  assign arb_lost_pulse_o = arb_lost;

  // --------------------------------------------------------------------------
  // 3. Bus Error Detection (Illegal START/STOP during transmission)
  // --------------------------------------------------------------------------
  logic bus_error;

  always_comb begin
    bus_error = 1'b0;
    if (enable && master_active) begin
      // Unexpected START condition
      if (start_detected && !master_start_seq) begin
        bus_error = 1'b1;
      end
      // Unexpected STOP condition
      if (stop_detected && !master_stop_seq) begin
        bus_error = 1'b1;
      end
    end
  end

  assign bus_error_pulse_o = bus_error;

endmodule
