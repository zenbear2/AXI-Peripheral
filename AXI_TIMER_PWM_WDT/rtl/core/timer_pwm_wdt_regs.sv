// ============================================================================
// File: timer_pwm_wdt_regs.sv
// Description: Unified Register File, Address Decoder & Interrupt Controller
module timer_pwm_wdt_regs import timer_pwm_wdt_pkg::*; (
  input  logic        clk,
  input  logic        rst_n,

  // Local Register Access from AXI Slave
  input  logic        reg_wr_en,
  input  logic [7:0]  reg_wr_addr,
  input  logic [31:0] reg_wdata,
  /* verilator lint_off UNUSED */
  input  logic [3:0]  reg_wstrb,
  /* verilator lint_on UNUSED */

  /* verilator lint_off UNUSED */
  input  logic        reg_rd_en,
  /* verilator lint_on UNUSED */
  input  logic [7:0]  reg_rd_addr,
  output logic [31:0] reg_rdata,

  // Global Control
  output logic        global_en,
  output logic        soft_rst,

  // Timer Interface
  output logic        tim_en,
  output logic        tim_mode,
  output logic        tim_dir,
  output logic        tim_cap_en,
  output logic [1:0]  tim_cap_edge,
  output logic        tim_soft_trig,
  output logic [31:0] tim_prescaler,
  output logic [31:0] tim_autoreload,
  output logic        tim_cnt_wr_en,
  output logic [31:0] tim_cnt_wdata,
  input  logic [31:0] tim_counter_in,
  input  logic [31:0] tim_capture_val_in,
  input  logic        tim_ovf_pulse,
  input  logic        tim_cap_pulse,
  input  logic        tim_running,

  // PWM Interface
  output logic        pwm_master_en,
  output logic        pwm_center_align,
  output logic        pwm_fault_en,
  output logic        pwm_fault_pol,
  output logic        fault_safe_level,
  output logic [3:0]  comp_out_en,
  output logic [15:0] deadtime_cycles,
  output logic [31:0] pwm_prescaler,
  output logic [31:0] pwm_period,
  output logic [3:0]  pwm_ch_en,
  output logic [3:0]  pwm_ch_pol,
  output logic [31:0] pwm_ch0_cmp,
  output logic [31:0] pwm_ch1_cmp,
  output logic [31:0] pwm_ch2_cmp,
  output logic [31:0] pwm_ch3_cmp,
  output logic        pwm_fault_clr,
  input  logic [31:0] pwm_counter_in,
  input  logic        pwm_period_pulse,
  input  logic [3:0]  pwm_ch_match_pulse,
  input  logic        pwm_fault_pulse,
  input  logic        pwm_fault_active,

  // Watchdog Interface
  output logic        wdt_en,
  output logic        wdt_win_en,
  output logic        wdt_rst_en,
  output logic        wdt_warn_irq_en,
  output logic        wdt_key_wr,
  output logic [31:0] wdt_key_data,
  output logic [31:0] wdt_timeout_val,
  output logic [31:0] wdt_window_val,
  output logic [31:0] wdt_warn_val,
  output logic [7:0]  wdt_rst_width,
  input  logic [31:0] wdt_counter_in,
  input  logic        wdt_locked,
  input  logic        wdt_timeout_pulse,
  input  logic        wdt_win_fail_pulse,
  input  logic        wdt_warn_pulse,

  // Interrupt Outputs to Core / PLIC
  output logic        irq_timer,
  output logic        irq_pwm,
  output logic        irq_wdt,
  output logic        irq_combined
);

  // --------------------------------------------------------------------------
  // Register Storage Declarations
  // --------------------------------------------------------------------------
  logic        reg_global_en;
  logic        reg_soft_rst;

  // Interrupt registers
  logic [31:0] raw_intr;
  logic [31:0] intr_en;

  // Timer registers
  logic [31:0] reg_tim_ctrl;
  logic [31:0] reg_tim_prescaler;
  logic [31:0] reg_tim_autoreload;
  logic        tim_soft_trig_reg;
  logic        tim_cnt_wr_reg;
  logic [31:0] tim_cnt_wdata_reg;

  // PWM registers
  logic [31:0] reg_pwm_ctrl;
  logic [31:0] reg_pwm_prescaler;
  logic [31:0] reg_pwm_period;
  logic [31:0] reg_pwm_ch0_cmp;
  logic [31:0] reg_pwm_ch1_cmp;
  logic [31:0] reg_pwm_ch2_cmp;
  logic [31:0] reg_pwm_ch3_cmp;
  logic [31:0] reg_pwm_ch_cfg;
  logic [31:0] reg_pwm_deadtime;
  logic        pwm_fault_clr_reg;

  // Watchdog registers
  logic [31:0] reg_wdt_ctrl;
  logic [31:0] reg_wdt_timeout_val;
  logic [31:0] reg_wdt_window_val;
  logic [31:0] reg_wdt_warn_val;
  logic [31:0] reg_wdt_rst_width;
  logic        wdt_key_wr_reg;
  logic [31:0] wdt_key_data_reg;

  // --------------------------------------------------------------------------
  // Signal Mappings to Output Ports
  // --------------------------------------------------------------------------
  assign global_en        = reg_global_en;
  assign soft_rst         = reg_soft_rst;

  assign tim_en           = reg_global_en && reg_tim_ctrl[0];
  assign tim_mode         = reg_tim_ctrl[1];
  assign tim_dir          = reg_tim_ctrl[2];
  assign tim_cap_en       = reg_tim_ctrl[3];
  assign tim_cap_edge     = reg_tim_ctrl[5:4];
  assign tim_soft_trig    = tim_soft_trig_reg;
  assign tim_prescaler    = reg_tim_prescaler;
  assign tim_autoreload   = reg_tim_autoreload;
  assign tim_cnt_wr_en    = tim_cnt_wr_reg;
  assign tim_cnt_wdata    = tim_cnt_wdata_reg;

  assign pwm_master_en    = reg_global_en && reg_pwm_ctrl[0];
  assign pwm_center_align = reg_pwm_ctrl[1];
  assign pwm_fault_en     = reg_pwm_ctrl[2];
  assign pwm_fault_pol    = reg_pwm_ctrl[3];
  assign fault_safe_level = reg_pwm_ctrl[4];
  assign comp_out_en      = reg_pwm_ctrl[11:8];
  assign deadtime_cycles  = reg_pwm_deadtime[15:0];
  assign pwm_prescaler    = reg_pwm_prescaler;
  assign pwm_period       = reg_pwm_period;
  assign pwm_ch_en        = reg_pwm_ch_cfg[3:0];
  assign pwm_ch_pol       = reg_pwm_ch_cfg[7:4];
  assign pwm_ch0_cmp      = reg_pwm_ch0_cmp;
  assign pwm_ch1_cmp      = reg_pwm_ch1_cmp;
  assign pwm_ch2_cmp      = reg_pwm_ch2_cmp;
  assign pwm_ch3_cmp      = reg_pwm_ch3_cmp;
  assign pwm_fault_clr    = pwm_fault_clr_reg;

  assign wdt_en           = reg_global_en && reg_wdt_ctrl[0];
  assign wdt_win_en       = reg_wdt_ctrl[1];
  assign wdt_rst_en       = reg_wdt_ctrl[2];
  assign wdt_warn_irq_en  = reg_wdt_ctrl[3];
  assign wdt_key_wr       = wdt_key_wr_reg;
  assign wdt_key_data     = wdt_key_data_reg;
  assign wdt_timeout_val  = reg_wdt_timeout_val;
  assign wdt_window_val   = reg_wdt_window_val;
  assign wdt_warn_val     = reg_wdt_warn_val;
  assign wdt_rst_width    = reg_wdt_rst_width[7:0];

  // --------------------------------------------------------------------------
  // Interrupt Controller Logic
  // --------------------------------------------------------------------------
  logic [31:0] masked_intr;
  assign masked_intr = raw_intr & intr_en;

  assign irq_timer    = |masked_intr[1:0];
  assign irq_pwm      = |masked_intr[7:2];
  assign irq_wdt      = |masked_intr[10:8];
  assign irq_combined = |masked_intr[TOTAL_INTR_SOURCES-1:0];

  // --------------------------------------------------------------------------
  // Register Write Logic
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      reg_global_en      <= 1'b1;
      reg_soft_rst       <= 1'b0;
      raw_intr           <= 32'd0;
      intr_en            <= 32'd0;

      reg_tim_ctrl       <= 32'd0;
      reg_tim_prescaler  <= 32'd0;
      reg_tim_autoreload <= 32'h0000_FFFF;
      tim_soft_trig_reg  <= 1'b0;
      tim_cnt_wr_reg     <= 1'b0;
      tim_cnt_wdata_reg  <= 32'd0;

      reg_pwm_ctrl       <= 32'd0;
      reg_pwm_prescaler  <= 32'd0;
      reg_pwm_period     <= 32'd1000;
      reg_pwm_ch0_cmp    <= 32'd0;
      reg_pwm_ch1_cmp    <= 32'd0;
      reg_pwm_ch2_cmp    <= 32'd0;
      reg_pwm_ch3_cmp    <= 32'd0;
      reg_pwm_ch_cfg     <= 32'd0;
      reg_pwm_deadtime   <= 32'd0;
      pwm_fault_clr_reg  <= 1'b0;

      reg_wdt_ctrl       <= 32'h0000_0004; // Reset enabled by default
      wdt_key_wr_reg     <= 1'b0;
      wdt_key_data_reg   <= 32'd0;
      reg_wdt_timeout_val<= 32'h0000_FFFF;
      reg_wdt_window_val <= 32'h0000_7FFF;
      reg_wdt_warn_val   <= 32'h0000_1000;
      reg_wdt_rst_width  <= 32'd16;
    end else begin
      // Pulse clears
      reg_soft_rst      <= 1'b0;
      tim_soft_trig_reg <= 1'b0;
      tim_cnt_wr_reg    <= 1'b0;
      pwm_fault_clr_reg <= 1'b0;
      wdt_key_wr_reg    <= 1'b0;

      // Latch hardware interrupt events into raw_intr
      if (tim_ovf_pulse)          raw_intr[INTR_TIM_OVF_BIT]      <= 1'b1;
      if (tim_cap_pulse)          raw_intr[INTR_TIM_CAP_BIT]      <= 1'b1;
      if (pwm_period_pulse)       raw_intr[INTR_PWM_PERIOD_BIT]   <= 1'b1;
      if (pwm_ch_match_pulse[0])  raw_intr[INTR_PWM_CH0_BIT]      <= 1'b1;
      if (pwm_ch_match_pulse[1])  raw_intr[INTR_PWM_CH1_BIT]      <= 1'b1;
      if (pwm_ch_match_pulse[2])  raw_intr[INTR_PWM_CH2_BIT]      <= 1'b1;
      if (pwm_ch_match_pulse[3])  raw_intr[INTR_PWM_CH3_BIT]      <= 1'b1;
      if (pwm_fault_pulse)        raw_intr[INTR_PWM_FAULT_BIT]    <= 1'b1;
      if (wdt_warn_pulse)         raw_intr[INTR_WDT_WARN_BIT]     <= 1'b1;
      if (wdt_win_fail_pulse)     raw_intr[INTR_WDT_WIN_FAIL_BIT] <= 1'b1;
      if (wdt_timeout_pulse)      raw_intr[INTR_WDT_TIMEOUT_BIT]  <= 1'b1;

      // Handle Register Writes
      if (reg_wr_en) begin
        case (reg_wr_addr)
          REG_GLOBAL_CTRL: begin
            reg_global_en <= reg_wdata[0];
            reg_soft_rst  <= reg_wdata[1];
          end

          REG_INTR_EN: begin
            intr_en <= reg_wdata;
          end

          REG_INTR_CLR: begin
            // Write-1-to-Clear
            raw_intr <= raw_intr & ~reg_wdata;
          end

          // Timer Registers
          REG_TIM_CTRL: begin
            reg_tim_ctrl      <= reg_wdata;
            tim_soft_trig_reg <= reg_wdata[8];
          end

          REG_TIM_PRESCALER: begin
            reg_tim_prescaler <= reg_wdata;
          end

          REG_TIM_COUNTER: begin
            tim_cnt_wr_reg    <= 1'b1;
            tim_cnt_wdata_reg <= reg_wdata;
          end

          REG_TIM_AUTORELOAD: begin
            reg_tim_autoreload <= reg_wdata;
          end

          // PWM Registers
          REG_PWM_CTRL: begin
            reg_pwm_ctrl <= reg_wdata;
          end

          REG_PWM_PRESCALER: begin
            reg_pwm_prescaler <= reg_wdata;
          end

          REG_PWM_PERIOD: begin
            reg_pwm_period <= reg_wdata;
          end

          REG_PWM_CH0_CMP: begin
            reg_pwm_ch0_cmp <= reg_wdata;
          end

          REG_PWM_CH1_CMP: begin
            reg_pwm_ch1_cmp <= reg_wdata;
          end

          REG_PWM_CH2_CMP: begin
            reg_pwm_ch2_cmp <= reg_wdata;
          end

          REG_PWM_CH3_CMP: begin
            reg_pwm_ch3_cmp <= reg_wdata;
          end

          REG_PWM_CH_CFG: begin
            reg_pwm_ch_cfg <= reg_wdata;
          end

          REG_PWM_DEADTIME: begin
            reg_pwm_deadtime <= reg_wdata;
          end

          REG_PWM_FAULT_CFG: begin
            pwm_fault_clr_reg <= reg_wdata[0];
          end

          // Watchdog Registers (Protected when locked)
          REG_WDT_CTRL: begin
            if (!wdt_locked) begin
              reg_wdt_ctrl <= reg_wdata;
            end
          end

          REG_WDT_KEY: begin
            wdt_key_wr_reg   <= 1'b1;
            wdt_key_data_reg <= reg_wdata;
          end

          REG_WDT_TIMEOUT_VAL: begin
            if (!wdt_locked) begin
              reg_wdt_timeout_val <= reg_wdata;
            end
          end

          REG_WDT_WINDOW_VAL: begin
            if (!wdt_locked) begin
              reg_wdt_window_val <= reg_wdata;
            end
          end

          REG_WDT_WARN_VAL: begin
            if (!wdt_locked) begin
              reg_wdt_warn_val <= reg_wdata;
            end
          end

          REG_WDT_RST_WIDTH: begin
            if (!wdt_locked) begin
              reg_wdt_rst_width <= reg_wdata;
            end
          end

          default: ;
        endcase
      end
    end
  end

  // --------------------------------------------------------------------------
  // Register Read Logic (Combinational / Multiplexer)
  // --------------------------------------------------------------------------
  always_comb begin
    case (reg_rd_addr)
      REG_IP_ID_VER:       reg_rdata = IP_ID_VAL;
      REG_GLOBAL_CTRL:     reg_rdata = {30'd0, reg_soft_rst, reg_global_en};
      REG_INTR_RAW:        reg_rdata = raw_intr;
      REG_INTR_EN:         reg_rdata = intr_en;
      REG_INTR_MASKED:     reg_rdata = masked_intr;
      REG_INTR_CLR:        reg_rdata = 32'd0;

      // Timer
      REG_TIM_CTRL:        reg_rdata = reg_tim_ctrl;
      REG_TIM_PRESCALER:   reg_rdata = reg_tim_prescaler;
      REG_TIM_COUNTER:     reg_rdata = tim_counter_in;
      REG_TIM_AUTORELOAD:  reg_rdata = reg_tim_autoreload;
      REG_TIM_CAPTURE:     reg_rdata = tim_capture_val_in;
      REG_TIM_STATUS:      reg_rdata = {29'd0, raw_intr[INTR_TIM_CAP_BIT], raw_intr[INTR_TIM_OVF_BIT], tim_running};

      // PWM
      REG_PWM_CTRL:        reg_rdata = reg_pwm_ctrl;
      REG_PWM_PRESCALER:   reg_rdata = reg_pwm_prescaler;
      REG_PWM_PERIOD:      reg_rdata = reg_pwm_period;
      REG_PWM_COUNTER:     reg_rdata = pwm_counter_in;
      REG_PWM_CH0_CMP:     reg_rdata = reg_pwm_ch0_cmp;
      REG_PWM_CH1_CMP:     reg_rdata = reg_pwm_ch1_cmp;
      REG_PWM_CH2_CMP:     reg_rdata = reg_pwm_ch2_cmp;
      REG_PWM_CH3_CMP:     reg_rdata = reg_pwm_ch3_cmp;
      REG_PWM_CH_CFG:      reg_rdata = reg_pwm_ch_cfg;
      REG_PWM_DEADTIME:    reg_rdata = reg_pwm_deadtime;
      REG_PWM_FAULT_CFG:   reg_rdata = {31'd0, pwm_fault_active};
      REG_PWM_STATUS:      reg_rdata = {26'd0, raw_intr[INTR_PWM_FAULT_BIT], raw_intr[INTR_PWM_CH3_BIT:INTR_PWM_CH0_BIT], raw_intr[INTR_PWM_PERIOD_BIT]};

      // Watchdog
      REG_WDT_CTRL:        reg_rdata = reg_wdt_ctrl;
      REG_WDT_KEY:         reg_rdata = 32'd0;
      REG_WDT_TIMEOUT_VAL: reg_rdata = reg_wdt_timeout_val;
      REG_WDT_WINDOW_VAL:  reg_rdata = reg_wdt_window_val;
      REG_WDT_WARN_VAL:    reg_rdata = reg_wdt_warn_val;
      REG_WDT_COUNTER:     reg_rdata = wdt_counter_in;
      REG_WDT_STATUS:      reg_rdata = {28'd0, raw_intr[INTR_WDT_WARN_BIT], raw_intr[INTR_WDT_WIN_FAIL_BIT], raw_intr[INTR_WDT_TIMEOUT_BIT], wdt_locked};
      REG_WDT_RST_WIDTH:   reg_rdata = reg_wdt_rst_width;

      default:             reg_rdata = 32'd0;
    endcase
  end

endmodule
