// ============================================================================
// File: timer_pwm_wdt_pkg.sv
// Description: SystemVerilog Package for AXI4-Lite Timer + 4 PWM + WDT IP
// Project: AXI_TIMER_PWM_WDT
// ============================================================================

package timer_pwm_wdt_pkg;

  // --------------------------------------------------------------------------
  // IP Identification & Version
  // --------------------------------------------------------------------------
  localparam logic [31:0] IP_ID_VAL          = 32'h54505701; // "TPW" v1.0

  // --------------------------------------------------------------------------
  // Register Offsets (Byte-Addressed, 32-bit Aligned)
  // --------------------------------------------------------------------------
  // Global & System Registers (0x00 - 0x1C)
  localparam logic [7:0] REG_IP_ID_VER       = 8'h00; // RO: IP ID and Version
  localparam logic [7:0] REG_GLOBAL_CTRL     = 8'h04; // RW: Global Control & Soft Reset
  localparam logic [7:0] REG_INTR_RAW        = 8'h08; // RO: Raw Interrupt Status
  localparam logic [7:0] REG_INTR_EN         = 8'h0C; // RW: Interrupt Enable Mask
  localparam logic [7:0] REG_INTR_MASKED     = 8'h10; // RO: Masked Interrupt Status
  localparam logic [7:0] REG_INTR_CLR        = 8'h14; // W1C: Interrupt Clear

  // Timer Registers (0x20 - 0x3C)
  localparam logic [7:0] REG_TIM_CTRL        = 8'h20; // RW: Timer Control
  localparam logic [7:0] REG_TIM_PRESCALER   = 8'h24; // RW: Timer Prescaler
  localparam logic [7:0] REG_TIM_COUNTER     = 8'h28; // RW: Timer Current Counter
  localparam logic [7:0] REG_TIM_AUTORELOAD  = 8'h2C; // RW: Timer Auto-Reload (ARR)
  localparam logic [7:0] REG_TIM_CAPTURE     = 8'h30; // RO: Timer Captured Value
  localparam logic [7:0] REG_TIM_STATUS      = 8'h34; // RO: Timer Status

  // PWM Registers (0x40 - 0x7C)
  localparam logic [7:0] REG_PWM_CTRL        = 8'h40; // RW: PWM Master Control
  localparam logic [7:0] REG_PWM_PRESCALER   = 8'h44; // RW: PWM Prescaler
  localparam logic [7:0] REG_PWM_PERIOD      = 8'h48; // RW: PWM Master Period (ARR)
  localparam logic [7:0] REG_PWM_COUNTER     = 8'h4C; // RO: PWM Current Counter
  localparam logic [7:0] REG_PWM_CH0_CMP     = 8'h50; // RW: Channel 0 Compare Value
  localparam logic [7:0] REG_PWM_CH1_CMP     = 8'h54; // RW: Channel 1 Compare Value
  localparam logic [7:0] REG_PWM_CH2_CMP     = 8'h58; // RW: Channel 2 Compare Value
  localparam logic [7:0] REG_PWM_CH3_CMP     = 8'h5C; // RW: Channel 3 Compare Value
  localparam logic [7:0] REG_PWM_CH_CFG      = 8'h60; // RW: Per-Channel Enable & Polarity
  localparam logic [7:0] REG_PWM_DEADTIME    = 8'h64; // RW: Complementary Dead-time Cycles
  localparam logic [7:0] REG_PWM_FAULT_CFG   = 8'h68; // RW: Fault & Brake Configuration
  localparam logic [7:0] REG_PWM_STATUS      = 8'h6C; // RO: PWM Status & Match Flags

  // Watchdog Registers (0x80 - 0x9C)
  localparam logic [7:0] REG_WDT_CTRL        = 8'h80; // RW: Watchdog Control
  localparam logic [7:0] REG_WDT_KEY         = 8'h84; // WO: Watchdog Key / Feed Register
  localparam logic [7:0] REG_WDT_TIMEOUT_VAL = 8'h88; // RW: WDT Reload Timeout Value
  localparam logic [7:0] REG_WDT_WINDOW_VAL  = 8'h8C; // RW: WDT Window Upper Limit Value
  localparam logic [7:0] REG_WDT_WARN_VAL    = 8'h90; // RW: WDT Pre-warning Threshold
  localparam logic [7:0] REG_WDT_COUNTER     = 8'h94; // RO: WDT Current Counter
  localparam logic [7:0] REG_WDT_STATUS      = 8'h98; // RO: WDT Status
  localparam logic [7:0] REG_WDT_RST_WIDTH   = 8'h9C; // RW: WDT Reset Pulse Width (cycles)

  // --------------------------------------------------------------------------
  // Safety Key Definitions for Watchdog
  // --------------------------------------------------------------------------
  localparam logic [31:0] WDT_KEY_FEED       = 32'h55AACAFE; // Pet/Reload Dog
  localparam logic [31:0] WDT_KEY_UNLOCK     = 32'h12345678; // Unlock Config
  localparam logic [31:0] WDT_KEY_LOCK       = 32'hDEADBEEF; // Lock WDT until Reset

  // --------------------------------------------------------------------------
  // Interrupt Bit Allocation in INTR_RAW / INTR_EN / INTR_CLR
  // --------------------------------------------------------------------------
  localparam int INTR_TIM_OVF_BIT            = 0; // Timer Overflow / Underflow
  localparam int INTR_TIM_CAP_BIT            = 1; // Timer Capture Event
  localparam int INTR_PWM_PERIOD_BIT         = 2; // PWM Period Match / Cycle Start
  localparam int INTR_PWM_CH0_BIT            = 3; // PWM CH0 Compare Match
  localparam int INTR_PWM_CH1_BIT            = 4; // PWM CH1 Compare Match
  localparam int INTR_PWM_CH2_BIT            = 5; // PWM CH2 Compare Match
  localparam int INTR_PWM_CH3_BIT            = 6; // PWM CH3 Compare Match
  localparam int INTR_PWM_FAULT_BIT          = 7; // PWM Fault / Emergency Brake
  localparam int INTR_WDT_WARN_BIT           = 8; // Watchdog Pre-warning Early Interrupt
  localparam int INTR_WDT_WIN_FAIL_BIT       = 9; // Watchdog Window Violation
  localparam int INTR_WDT_TIMEOUT_BIT        = 10;// Watchdog Timeout Occurred

  localparam int TOTAL_INTR_SOURCES          = 11;

  // Number of PWM Channels
  localparam int NUM_PWM_CHANNELS            = 4;

endpackage : timer_pwm_wdt_pkg
