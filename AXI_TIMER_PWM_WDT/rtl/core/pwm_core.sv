// ============================================================================
// File: pwm_core.sv
// Description: 4-Channel Advanced PWM Generator Core
// Features: 32-bit Prescaler, Edge & Center-Aligned Modes, Dead-Time, Emergency Brake
module pwm_core import timer_pwm_wdt_pkg::*; (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        soft_rst,

  // Global & Master PWM Control
  input  logic        pwm_master_en,
  input  logic        pwm_center_align, // 0: Edge-Aligned, 1: Center-Aligned
  input  logic        pwm_fault_en,     // Fault/Brake protection enable
  input  logic        pwm_fault_pol,    // Fault pin active polarity (0: Low, 1: High)
  input  logic        pwm_fault_clr,    // Clear latched fault state
  input  logic        fault_safe_level, // Safe output state during fault (0: Low, 1: High)
  input  logic [3:0]  comp_out_en,      // Complementary output enable per channel
  input  logic [15:0] deadtime_cycles,  // Dead-time insertion length

  // Prescaler & Period
  input  logic [31:0] pwm_prescaler,
  input  logic [31:0] pwm_period,

  // Per-Channel Configuration
  input  logic [3:0]  pwm_ch_en,
  input  logic [3:0]  pwm_ch_pol,
  input  logic [31:0] pwm_ch0_cmp,
  input  logic [31:0] pwm_ch1_cmp,
  input  logic [31:0] pwm_ch2_cmp,
  input  logic [31:0] pwm_ch3_cmp,

  // External IO
  input  logic        pwm_fault_in,
  output logic [3:0]  pwm_out,
  output logic [3:0]  pwm_out_n,

  // Status & Event Signals
  output logic [31:0] pwm_counter,
  output logic        pwm_period_pulse,
  output logic [3:0]  pwm_ch_match_pulse,
  output logic        pwm_fault_pulse,
  output logic        pwm_fault_active
);

  // --------------------------------------------------------------------------
  // Fault / Brake Synchronizer & Latch
  // --------------------------------------------------------------------------
  logic [2:0] fault_sync;
  logic       raw_fault_detect;
  logic       fault_latched;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      fault_sync <= 3'b000;
    end else if (soft_rst) begin
      fault_sync <= 3'b000;
    end else begin
      fault_sync <= {fault_sync[1:0], pwm_fault_in};
    end
  end

  // Check polarity
  assign raw_fault_detect = (pwm_fault_pol) ? fault_sync[2] : ~fault_sync[2];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      fault_latched   <= 1'b0;
      pwm_fault_pulse <= 1'b0;
    end else if (soft_rst) begin
      fault_latched   <= 1'b0;
      pwm_fault_pulse <= 1'b0;
    end else begin
      pwm_fault_pulse <= 1'b0;

      if (pwm_fault_en && raw_fault_detect) begin
        if (!fault_latched) begin
          pwm_fault_pulse <= 1'b1;
        end
        fault_latched <= 1'b1;
      end else if (pwm_fault_clr && !raw_fault_detect) begin
        fault_latched <= 1'b0;
      end
    end
  end

  assign pwm_fault_active = fault_latched;

  // --------------------------------------------------------------------------
  // Prescaler & Master Period Counter
  // --------------------------------------------------------------------------
  logic [31:0] psc_cnt;
  logic [31:0] cnt_reg;
  logic        center_dir; // 0: Counting Up, 1: Counting Down

  assign pwm_counter = cnt_reg;

  wire psc_tick = (psc_cnt == pwm_prescaler);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      psc_cnt          <= 32'd0;
      cnt_reg          <= 32'd0;
      center_dir       <= 1'b0;
      pwm_period_pulse <= 1'b0;
    end else if (soft_rst) begin
      psc_cnt          <= 32'd0;
      cnt_reg          <= 32'd0;
      center_dir       <= 1'b0;
      pwm_period_pulse <= 1'b0;
    end else if (pwm_master_en && !fault_latched && (pwm_period > 32'd0)) begin
      pwm_period_pulse <= 1'b0;

      if (psc_tick) begin
        psc_cnt <= 32'd0;

        if (!pwm_center_align) begin
          // ------------------------------------------------------------------
          // Edge-Aligned Mode: 0 -> (pwm_period - 1)
          // ------------------------------------------------------------------
          center_dir <= 1'b0;
          if (cnt_reg >= (pwm_period - 32'd1)) begin
            cnt_reg          <= 32'd0;
            pwm_period_pulse <= 1'b1;
          end else begin
            cnt_reg <= cnt_reg + 32'd1;
          end
        end else begin
          // ------------------------------------------------------------------
          // Center-Aligned Mode: 0 -> (pwm_period - 1) -> 0
          // ------------------------------------------------------------------
          if (center_dir == 1'b0) begin
            // Counting UP
            if (cnt_reg >= (pwm_period - 32'd1)) begin
              center_dir <= 1'b1;
              if (pwm_period > 32'd1) begin
                cnt_reg <= cnt_reg - 32'd1;
              end
            end else begin
              cnt_reg <= cnt_reg + 32'd1;
            end
          end else begin
            // Counting DOWN
            if (cnt_reg == 32'd0) begin
              center_dir       <= 1'b0;
              pwm_period_pulse <= 1'b1; // Period event at valley
              if (pwm_period > 32'd1) begin
                cnt_reg <= cnt_reg + 32'd1;
              end
            end else begin
              cnt_reg <= cnt_reg - 32'd1;
            end
          end
        end
      end else begin
        psc_cnt <= psc_cnt + 32'd1;
      end
    end else begin
      // Inactive or in fault
      psc_cnt          <= 32'd0;
      cnt_reg          <= 32'd0;
      center_dir       <= 1'b0;
      pwm_period_pulse <= 1'b0;
    end
  end

  // --------------------------------------------------------------------------
  // 4 PWM Channels Generation
  // --------------------------------------------------------------------------
  logic [31:0] cmp_array [0:3];
  assign cmp_array[0] = pwm_ch0_cmp;
  assign cmp_array[1] = pwm_ch1_cmp;
  assign cmp_array[2] = pwm_ch2_cmp;
  assign cmp_array[3] = pwm_ch3_cmp;

  genvar i;
  generate
    for (i = 0; i < NUM_PWM_CHANNELS; i = i + 1) begin : gen_pwm_channels
      pwm_channel u_pwm_ch (
        .clk              (clk),
        .rst_n            (rst_n),
        .soft_rst         (soft_rst),
        .master_en        (pwm_master_en),
        .ch_en            (pwm_ch_en[i]),
        .ch_pol           (pwm_ch_pol[i]),
        .comp_en          (comp_out_en[i]),
        .deadtime_cycles  (deadtime_cycles),
        .cnt_val          (cnt_reg),
        .period_val       (pwm_period),
        .cmp_val          (cmp_array[i]),
        .fault_active     (fault_latched),
        .fault_safe_level (fault_safe_level),
        .cmp_match_pulse  (pwm_ch_match_pulse[i]),
        .pwm_out          (pwm_out[i]),
        .pwm_out_n        (pwm_out_n[i])
      );
    end
  endgenerate

endmodule
