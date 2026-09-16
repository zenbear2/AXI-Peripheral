// ============================================================================
// File: i2c_input_filter.sv
// Description: Double-Flop Synchronizer & Digital Deglitch Filter
// Project: AXI_I2C
// ============================================================================

module i2c_input_filter (
  input  logic        clk,
  input  logic        rst_n,

  // External Raw Pins
  input  logic        scl_raw_i,
  input  logic        sda_raw_i,

  // Configurable Filter Cycles
  input  logic [7:0]  filter_cycles,

  // Filtered & Synchronized Outputs
  output logic        scl_filtered_o,
  output logic        sda_filtered_o,

  // Edge Detectors
  output logic        scl_posedge_o,
  output logic        scl_negedge_o,
  output logic        sda_posedge_o,
  output logic        sda_negedge_o,

  // Bus Condition Events
  output logic        start_detected_o,
  output logic        stop_detected_o
);

  // --------------------------------------------------------------------------
  // 1. Double-Flop Synchronizers
  // --------------------------------------------------------------------------
  logic [1:0] scl_sync;
  logic [1:0] sda_sync;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      scl_sync <= 2'b11;
      sda_sync <= 2'b11;
    end else begin
      scl_sync <= {scl_sync[0], scl_raw_i};
      sda_sync <= {sda_sync[0], sda_raw_i};
    end
  end

  logic scl_synced;
  logic sda_synced;
  assign scl_synced = scl_sync[1];
  assign sda_synced = sda_sync[1];

  // --------------------------------------------------------------------------
  // 2. Digital Deglitch Majority / Stability Filter
  // --------------------------------------------------------------------------
  logic [7:0] scl_filter_cnt;
  logic [7:0] sda_filter_cnt;
  logic       scl_filtered;
  logic       sda_filtered;

  // SCL Deglitch
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      scl_filtered   <= 1'b1;
      scl_filter_cnt <= 8'd0;
    end else begin
      if (filter_cycles == 8'd0) begin
        scl_filtered   <= scl_synced;
        scl_filter_cnt <= 8'd0;
      end else if (scl_synced != scl_filtered) begin
        if (scl_filter_cnt >= filter_cycles - 1'b1) begin
          scl_filtered   <= scl_synced;
          scl_filter_cnt <= 8'd0;
        end else begin
          scl_filter_cnt <= scl_filter_cnt + 1'b1;
        end
      end else begin
        scl_filter_cnt <= 8'd0;
      end
    end
  end

  // SDA Deglitch
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sda_filtered   <= 1'b1;
      sda_filter_cnt <= 8'd0;
    end else begin
      if (filter_cycles == 8'd0) begin
        sda_filtered   <= sda_synced;
        sda_filter_cnt <= 8'd0;
      end else if (sda_synced != sda_filtered) begin
        if (sda_filter_cnt >= filter_cycles - 1'b1) begin
          sda_filtered   <= sda_synced;
          sda_filter_cnt <= 8'd0;
        end else begin
          sda_filter_cnt <= sda_filter_cnt + 1'b1;
        end
      end else begin
        sda_filter_cnt <= 8'd0;
      end
    end
  end

  assign scl_filtered_o = scl_filtered;
  assign sda_filtered_o = sda_filtered;

  // --------------------------------------------------------------------------
  // 3. Edge Detection & Bus Condition Triggers
  // --------------------------------------------------------------------------
  logic scl_filtered_prev;
  logic sda_filtered_prev;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      scl_filtered_prev <= 1'b1;
      sda_filtered_prev <= 1'b1;
    end else begin
      scl_filtered_prev <= scl_filtered;
      sda_filtered_prev <= sda_filtered;
    end
  end

  assign scl_posedge_o = (!scl_filtered_prev && scl_filtered);
  assign scl_negedge_o = (scl_filtered_prev && !scl_filtered);
  assign sda_posedge_o = (!sda_filtered_prev && sda_filtered);
  assign sda_negedge_o = (sda_filtered_prev && !sda_filtered);

  // START condition: SDA drops while SCL is high
  assign start_detected_o = sda_negedge_o && scl_filtered;

  // STOP condition: SDA rises while SCL is high
  assign stop_detected_o  = sda_posedge_o && scl_filtered;

endmodule
