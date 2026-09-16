// ============================================================================
// File: i2c_timing_gen.sv
// Description: 4-Phase Micro-Timing Generator & Clock Stretching Monitor
// Project: AXI_I2C
// ============================================================================

module i2c_timing_gen (
  input  logic              clk,
  input  logic              rst_n,

  // Enable & Reset Control
  input  logic              enable,
  input  logic              timer_reset,
  input  logic              timer_run,

  // Timing Configurations
  input  logic [15:0]       prescale,
  input  logic [7:0]        scl_low_extra,
  input  logic [7:0]        scl_high_extra,
  input  logic              stretch_en,
  input  logic [15:0]       timeout_limit,

  // Filtered Input Pin & Master Output State
  input  logic              scl_filtered,
  input  logic              master_scl_oe,

  // Outputs
  output i2c_pkg::i2c_phase_t current_phase,
  output logic              phase_end_pulse,
  output logic              bit_end_pulse,
  output logic              scl_held_o,
  output logic              timeout_pulse_o
);

  import i2c_pkg::*;

  i2c_phase_t phase_q;
  logic [15:0] prescale_cnt;
  logic [15:0] phase_limit;
  logic [31:0] stretch_cnt;
  logic        is_stretching;

  assign current_phase = phase_q;

  // Determine current micro-phase clock limit
  always_comb begin
    case (phase_q)
      PH_LOW:  phase_limit = prescale + {8'd0, scl_low_extra};
      PH_HIGH: phase_limit = prescale + {8'd0, scl_high_extra};
      default: phase_limit = prescale;
    endcase
  end

  // Clock stretching detection: master releases SCL in PH_RISE/PH_HIGH but external SCL is held low
  assign is_stretching = enable && stretch_en && timer_run && (!master_scl_oe) &&
                         ((phase_q == PH_RISE) || (phase_q == PH_HIGH)) &&
                         (!scl_filtered);

  assign scl_held_o = is_stretching;

  // --------------------------------------------------------------------------
  // Prescaler & 4-Phase State Counter
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      phase_q         <= PH_LOW;
      prescale_cnt    <= 16'd0;
      phase_end_pulse <= 1'b0;
      bit_end_pulse   <= 1'b0;
      stretch_cnt     <= 32'd0;
      timeout_pulse_o <= 1'b0;
    end else if (!enable || timer_reset) begin
      phase_q         <= PH_LOW;
      prescale_cnt    <= 16'd0;
      phase_end_pulse <= 1'b0;
      bit_end_pulse   <= 1'b0;
      stretch_cnt     <= 32'd0;
      timeout_pulse_o <= 1'b0;
    end else if (timer_run) begin
      phase_end_pulse <= 1'b0;
      bit_end_pulse   <= 1'b0;
      timeout_pulse_o <= 1'b0;

      // Handle clock stretching
      if (is_stretching) begin
        stretch_cnt <= stretch_cnt + 1'b1;
        // Check timeout (scaled by prescale or raw limit)
        if ((timeout_limit > 16'd0) && (stretch_cnt >= {16'd0, timeout_limit} * ({16'd0, prescale} + 32'd1))) begin
          timeout_pulse_o <= 1'b1;
          stretch_cnt     <= 32'd0;
        end
      end else begin
        stretch_cnt <= 32'd0;

        // Normal phase timer increment
        if (prescale_cnt >= phase_limit) begin
          prescale_cnt    <= 16'd0;
          phase_end_pulse <= 1'b1;

          case (phase_q)
            PH_LOW:  phase_q <= PH_RISE;
            PH_RISE: phase_q <= PH_HIGH;
            PH_HIGH: phase_q <= PH_FALL;
            PH_FALL: begin
              phase_q       <= PH_LOW;
              bit_end_pulse <= 1'b1;
            end
          endcase
        end else begin
          prescale_cnt <= prescale_cnt + 1'b1;
        end
      end
    end else begin
      phase_end_pulse <= 1'b0;
      bit_end_pulse   <= 1'b0;
      timeout_pulse_o <= 1'b0;
      stretch_cnt     <= 32'd0;
    end
  end

endmodule
