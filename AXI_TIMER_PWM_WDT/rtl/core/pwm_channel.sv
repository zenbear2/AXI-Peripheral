// ============================================================================
// File: pwm_channel.sv
// Description: Individual PWM Channel Comparator & Output Stage
// Features: Independent Duty Compare, Polarity Inversion, Dead-time & Brake Integration
// Project: AXI_TIMER_PWM_WDT
// ============================================================================

module pwm_channel (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        soft_rst,

  // Channel Configuration
  input  logic        master_en,
  input  logic        ch_en,
  input  logic        ch_pol,           // 0: Active-High, 1: Active-Low
  input  logic        comp_en,          // Complementary Output Enable
  input  logic [15:0] deadtime_cycles,

  // Master Counter Inputs
  input  logic [31:0] cnt_val,
  input  logic [31:0] period_val,
  input  logic [31:0] cmp_val,

  // Fault Protection
  input  logic        fault_active,
  input  logic        fault_safe_level, // 0: Low, 1: High

  // Events & Outputs
  output logic        cmp_match_pulse,
  output logic        pwm_out,
  output logic        pwm_out_n
);

  logic raw_pwm;
  logic pol_pwm;
  logic dt_out_p;
  logic dt_out_n;

  // --------------------------------------------------------------------------
  // Compare Logic & Event Pulse
  // --------------------------------------------------------------------------
  always_comb begin
    if (!master_en || !ch_en) begin
      raw_pwm = 1'b0;
    end else if (cmp_val == 32'd0) begin
      raw_pwm = 1'b0; // 0% Duty Cycle
    end else if (cmp_val >= period_val) begin
      raw_pwm = 1'b1; // 100% Duty Cycle
    end else begin
      raw_pwm = (cnt_val < cmp_val);
    end
  end

  // Polarity selection
  assign pol_pwm = ch_pol ? ~raw_pwm : raw_pwm;

  // Match pulse on exact compare match
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cmp_match_pulse <= 1'b0;
    end else if (soft_rst) begin
      cmp_match_pulse <= 1'b0;
    end else begin
      cmp_match_pulse <= (master_en && ch_en && (cnt_val == cmp_val));
    end
  end

  // --------------------------------------------------------------------------
  // Dead-Time Generator Instance
  // --------------------------------------------------------------------------
  pwm_deadtime u_deadtime (
    .clk             (clk),
    .rst_n           (rst_n),
    .soft_rst        (soft_rst),
    .pwm_raw         (pol_pwm),
    .comp_en         (comp_en),
    .deadtime_cycles (deadtime_cycles),
    .pwm_out         (dt_out_p),
    .pwm_out_n       (dt_out_n)
  );

  // --------------------------------------------------------------------------
  // Fault Overdrive / Output Gate
  // --------------------------------------------------------------------------
  always_comb begin
    if (fault_active) begin
      pwm_out   = fault_safe_level;
      pwm_out_n = fault_safe_level;
    end else if (!master_en || !ch_en) begin
      pwm_out   = ch_pol ? 1'b1 : 1'b0;
      pwm_out_n = 1'b0;
    end else begin
      pwm_out   = dt_out_p;
      pwm_out_n = dt_out_n;
    end
  end

endmodule
