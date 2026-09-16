// ============================================================================
// File: pwm_deadtime.sv
// Description: Dead-Time Generator (DTG) for Complementary Half-Bridge Outputs
// Features: Non-overlapping deadband insertion on rising and falling transitions
// Project: AXI_TIMER_PWM_WDT
// ============================================================================

module pwm_deadtime (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        soft_rst,

  input  logic        pwm_raw,          // Raw PWM logic signal from channel
  input  logic        comp_en,          // Complementary Output Enable
  input  logic [15:0] deadtime_cycles,  // Dead-time length in clock cycles

  output logic        pwm_out,          // Non-inverted delayed output
  output logic        pwm_out_n         // Complementary delayed output
);

  logic [15:0] dt_cnt_rise;
  logic [15:0] dt_cnt_fall;
  logic        out_p_reg;
  logic        out_n_reg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dt_cnt_rise <= 16'd0;
      dt_cnt_fall <= 16'd0;
      out_p_reg   <= 1'b0;
      out_n_reg   <= 1'b0;
    end else if (soft_rst) begin
      dt_cnt_rise <= 16'd0;
      dt_cnt_fall <= 16'd0;
      out_p_reg   <= 1'b0;
      out_n_reg   <= 1'b0;
    end else begin
      if (deadtime_cycles == 16'd0) begin
        // Bypass dead-time logic
        out_p_reg <= pwm_raw;
        out_n_reg <= comp_en ? ~pwm_raw : 1'b0;
      end else begin
        // Rising edge of pwm_raw: raw went 0 -> 1
        if (pwm_raw) begin
          // Immediately kill complementary output
          out_n_reg   <= 1'b0;
          dt_cnt_fall <= 16'd0;

          // Count dead-time before asserting primary output
          if (dt_cnt_rise < deadtime_cycles) begin
            dt_cnt_rise <= dt_cnt_rise + 16'd1;
            out_p_reg   <= 1'b0;
          end else begin
            out_p_reg   <= 1'b1;
          end
        end else begin
          // Falling edge of pwm_raw: raw went 1 -> 0
          // Immediately kill primary output
          out_p_reg   <= 1'b0;
          dt_cnt_rise <= 16'd0;

          // Count dead-time before asserting complementary output
          if (dt_cnt_fall < deadtime_cycles) begin
            dt_cnt_fall <= dt_cnt_fall + 16'd1;
            out_n_reg   <= 1'b0;
          end else begin
            out_n_reg   <= comp_en ? 1'b1 : 1'b0;
          end
        end
      end
    end
  end

  assign pwm_out   = out_p_reg;
  assign pwm_out_n = out_n_reg;

endmodule
