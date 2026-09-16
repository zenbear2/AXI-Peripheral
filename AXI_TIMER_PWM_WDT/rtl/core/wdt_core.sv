// ============================================================================
// File: wdt_core.sv
// Description: Advanced Industrial-Grade Windowed Watchdog Timer (WDT/WWDG) Core
// Features: Key Unlock/Pet, Window Violation Detection, Pre-Warning IRQ, Lockout Protection
module wdt_core import timer_pwm_wdt_pkg::*; (
  input  logic        clk,
  input  logic        rst_n,

  // Control & Settings
  input  logic        wdt_en_in,
  input  logic        wdt_win_en_in,
  input  logic        wdt_rst_en_in,
  input  logic        wdt_warn_irq_en_in,
  input  logic [31:0] wdt_timeout_val,
  input  logic [31:0] wdt_window_val,
  input  logic [31:0] wdt_warn_val,
  input  logic [7:0]  wdt_rst_width,

  // Key / Service Interface
  input  logic        wdt_key_wr,
  input  logic [31:0] wdt_key_data,

  // Status & Event Signals
  output logic [31:0] wdt_counter,
  output logic        wdt_locked,
  output logic        wdt_timeout_pulse,
  output logic        wdt_win_fail_pulse,
  output logic        wdt_warn_pulse,

  // Hardware Reset Pulse Outputs
  output logic        wdt_reset_o,     // Active-High Reset Output Pulse
  output logic        wdt_rst_n        // Active-Low Reset Output Pulse
);

  // --------------------------------------------------------------------------
  // Internal State Registers
  // --------------------------------------------------------------------------
  logic [31:0] cnt_reg;
  logic [7:0]  rst_timer;
  logic        rst_active;
  logic        warn_fired;
  logic        locked_reg;

  // Latch-protected configuration
  logic        cfg_en;
  logic        cfg_win_en;
  logic        cfg_rst_en;
  logic        cfg_warn_irq_en;

  assign wdt_counter = cnt_reg;
  assign wdt_locked  = locked_reg;
  assign wdt_reset_o = rst_active;
  assign wdt_rst_n   = ~rst_active;

  // --------------------------------------------------------------------------
  // Lock & Configuration Protection Logic
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      locked_reg      <= 1'b0;
      cfg_en          <= 1'b0;
      cfg_win_en      <= 1'b0;
      cfg_rst_en      <= 1'b1; // Default reset enabled on timeout
      cfg_warn_irq_en <= 1'b0;
    end else begin
      // Lock command
      if (wdt_key_wr && (wdt_key_data == WDT_KEY_LOCK)) begin
        locked_reg <= 1'b1;
      end

      // Update configuration only when unlocked
      if (!locked_reg) begin
        cfg_en          <= wdt_en_in;
        cfg_win_en      <= wdt_win_en_in;
        cfg_rst_en      <= wdt_rst_en_in;
        cfg_warn_irq_en <= wdt_warn_irq_en_in;
      end
    end
  end

  // --------------------------------------------------------------------------
  // Countdown Timer, Window Check & Reset Generator
  // --------------------------------------------------------------------------
  wire is_feed_key = (wdt_key_wr && (wdt_key_data == WDT_KEY_FEED));

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt_reg            <= 32'h0000_FFFF;
      rst_timer          <= 8'd0;
      rst_active         <= 1'b0;
      warn_fired         <= 1'b0;
      wdt_timeout_pulse  <= 1'b0;
      wdt_win_fail_pulse <= 1'b0;
      wdt_warn_pulse     <= 1'b0;
    end else begin
      wdt_timeout_pulse  <= 1'b0;
      wdt_win_fail_pulse <= 1'b0;
      wdt_warn_pulse     <= 1'b0;

      // Handle Reset Output Pulse Generator
      if (rst_active) begin
        if (rst_timer > 8'd1) begin
          rst_timer <= rst_timer - 8'd1;
        end else begin
          rst_active <= 1'b0;
          rst_timer  <= 8'd0;
        end
      end

      if (cfg_en) begin
        // Check for Service / Pet Key
        if (is_feed_key) begin
          // Windowed Watchdog Check
          if (cfg_win_en && (cnt_reg > wdt_window_val)) begin
            // Violation: Fed too early!
            wdt_win_fail_pulse <= 1'b1;
            if (cfg_rst_en && !rst_active) begin
              rst_active <= 1'b1;
              rst_timer  <= (wdt_rst_width == 8'd0) ? 8'd16 : wdt_rst_width;
            end
          end else begin
            // Valid feed: reload counter
            cnt_reg    <= wdt_timeout_val;
            warn_fired <= 1'b0;
          end
        end else begin
          // Pre-Warning Check
          if (cfg_warn_irq_en && !warn_fired && (cnt_reg <= wdt_warn_val) && (cnt_reg > 32'd0)) begin
            wdt_warn_pulse <= 1'b1;
            warn_fired     <= 1'b1;
          end

          // Countdown
          if (cnt_reg == 32'd0) begin
            // Timeout reached!
            wdt_timeout_pulse <= 1'b1;
            if (cfg_rst_en && !rst_active) begin
              rst_active <= 1'b1;
              rst_timer  <= (wdt_rst_width == 8'd0) ? 8'd16 : wdt_rst_width;
            end
            // Reload after timeout to continue monitoring
            cnt_reg    <= wdt_timeout_val;
            warn_fired <= 1'b0;
          end else begin
            cnt_reg <= cnt_reg - 32'd1;
          end
        end
      end else begin
        // Disabled: keep counter initialized
        cnt_reg    <= wdt_timeout_val;
        warn_fired <= 1'b0;
      end
    end
  end

endmodule
