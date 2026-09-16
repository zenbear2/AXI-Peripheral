// ============================================================================
// File: timer_core.sv
// Description: 32-bit High Precision General-Purpose Timer Core
// Features: 32-bit Prescaler, Up/Down, Auto-Reload, One-Shot, Input Capture, Match Out
// Project: AXI_TIMER_PWM_WDT
// ============================================================================

module timer_core (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        soft_rst,

  // Control & Configuration
  input  logic        tim_en,
  input  logic        tim_mode,     // 0: Periodic Auto-Reload, 1: One-Shot
  input  logic        tim_dir,      // 0: Up-count, 1: Down-count
  input  logic        tim_cap_en,   // Input Capture Enable
  input  logic [1:0]  tim_cap_edge, // 00: Rising, 01: Falling, 10/11: Both Edges
  input  logic        tim_soft_trig,// Software trigger/reload
  input  logic [31:0] tim_prescaler,
  input  logic [31:0] tim_autoreload,

  // Direct Counter Write Interface
  input  logic        tim_cnt_wr_en,
  input  logic [31:0] tim_cnt_wdata,

  // External IO
  input  logic        tim_capture_in,
  output logic        tim_match_out,

  // Status & Event Outputs
  output logic [31:0] tim_counter,
  output logic [31:0] tim_capture_val,
  output logic        tim_ovf_pulse,
  output logic        tim_cap_pulse,
  output logic        tim_running
);

  // --------------------------------------------------------------------------
  // Internal Registers
  // --------------------------------------------------------------------------
  logic [31:0] psc_cnt;
  logic [31:0] cnt_reg;
  logic [31:0] cap_reg;
  logic        active_reg;

  // Capture input synchronizer and edge detector
  logic [2:0]  cap_sync;
  logic        cap_event;

  assign tim_counter     = cnt_reg;
  assign tim_capture_val = cap_reg;
  assign tim_running     = active_reg;

  // --------------------------------------------------------------------------
  // Synchronizer and Edge Detection for Input Capture
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cap_sync <= 3'b000;
    end else if (soft_rst) begin
      cap_sync <= 3'b000;
    end else begin
      cap_sync <= {cap_sync[1:0], tim_capture_in};
    end
  end

  wire cap_rising  = (cap_sync[1] && !cap_sync[2]);
  wire cap_falling = (!cap_sync[1] && cap_sync[2]);
  wire cap_both    = (cap_sync[1] ^ cap_sync[2]);

  always_comb begin
    case (tim_cap_edge)
      2'b00:   cap_event = cap_rising;
      2'b01:   cap_event = cap_falling;
      default: cap_event = cap_both;
    endcase
  end

  // --------------------------------------------------------------------------
  // Input Capture Latch
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cap_reg       <= 32'd0;
      tim_cap_pulse <= 1'b0;
    end else if (soft_rst) begin
      cap_reg       <= 32'd0;
      tim_cap_pulse <= 1'b0;
    end else begin
      tim_cap_pulse <= 1'b0;
      if (tim_cap_en && cap_event) begin
        cap_reg       <= cnt_reg;
        tim_cap_pulse <= 1'b1;
      end
    end
  end

  // --------------------------------------------------------------------------
  // Prescaler & Counter Logic
  // --------------------------------------------------------------------------
  logic        tim_en_d;
  logic        halted_reg;
  logic        psc_tick;
  assign psc_tick = (psc_cnt == tim_prescaler);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      psc_cnt        <= 32'd0;
      cnt_reg        <= 32'd0;
      active_reg     <= 1'b0;
      halted_reg     <= 1'b0;
      tim_en_d       <= 1'b0;
      tim_ovf_pulse  <= 1'b0;
      tim_match_out  <= 1'b0;
    end else if (soft_rst) begin
      psc_cnt        <= 32'd0;
      cnt_reg        <= 32'd0;
      active_reg     <= 1'b0;
      halted_reg     <= 1'b0;
      tim_en_d       <= 1'b0;
      tim_ovf_pulse  <= 1'b0;
      tim_match_out  <= 1'b0;
    end else begin
      tim_en_d      <= tim_en;
      tim_ovf_pulse <= 1'b0;
      tim_match_out <= 1'b0;

      // Handle Direct Software Counter Write
      if (tim_cnt_wr_en) begin
        cnt_reg <= tim_cnt_wdata;
      end

      // Handle Software Trigger / Reload or Enable Rising Edge
      if (tim_soft_trig || (tim_en && !tim_en_d)) begin
        psc_cnt    <= 32'd0;
        halted_reg <= 1'b0;
        active_reg <= tim_en;
        if (tim_dir == 1'b0) begin
          cnt_reg <= 32'd0;
        end else begin
          cnt_reg <= tim_autoreload;
        end
      end else if (tim_en && !halted_reg) begin
        active_reg <= 1'b1;
        if (psc_tick) begin
          psc_cnt <= 32'd0;

          if (tim_dir == 1'b0) begin
            // Up-Counting Mode
            if (cnt_reg >= tim_autoreload) begin
              tim_ovf_pulse <= 1'b1;
              tim_match_out <= 1'b1;
              if (tim_mode == 1'b1) begin
                // One-shot mode: halt
                cnt_reg    <= 32'd0;
                active_reg <= 1'b0;
                halted_reg <= 1'b1;
              end else begin
                // Periodic auto-reload
                cnt_reg    <= 32'd0;
              end
            end else begin
              cnt_reg <= cnt_reg + 32'd1;
            end
          end else begin
            // Down-Counting Mode
            if (cnt_reg == 32'd0) begin
              tim_ovf_pulse <= 1'b1;
              tim_match_out <= 1'b1;
              if (tim_mode == 1'b1) begin
                // One-shot mode: halt
                cnt_reg    <= 32'd0;
                active_reg <= 1'b0;
                halted_reg <= 1'b1;
              end else begin
                // Periodic reload
                cnt_reg    <= tim_autoreload;
              end
            end else begin
              cnt_reg <= cnt_reg - 32'd1;
            end
          end
        end else begin
          psc_cnt <= psc_cnt + 32'd1;
        end
      end else begin
        // Disabled or halted
        active_reg <= 1'b0;
        psc_cnt    <= 32'd0;
        if (!tim_en) begin
          halted_reg <= 1'b0;
        end
      end
    end
  end

endmodule
