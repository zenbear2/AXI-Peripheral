// ============================================================================
// File: axi_timer_pwm_wdt_top.sv
// Description: Top-Level Integration of AXI4-Lite 1 Timer + 4 PWM + WDT IP Core
module axi_timer_pwm_wdt_top import timer_pwm_wdt_pkg::*; (
  input  logic        clk,
  input  logic        rst_n,

  // AXI4-Lite Slave Interface
  input  logic [31:0] s_axi_awaddr,
  input  logic [2:0]  s_axi_awprot,
  input  logic        s_axi_awvalid,
  output logic        s_axi_awready,

  input  logic [31:0] s_axi_wdata,
  input  logic [3:0]  s_axi_wstrb,
  input  logic        s_axi_wvalid,
  output logic        s_axi_wready,

  output logic [1:0]  s_axi_bresp,
  output logic        s_axi_bvalid,
  input  logic        s_axi_bready,

  input  logic [31:0] s_axi_araddr,
  input  logic [2:0]  s_axi_arprot,
  input  logic        s_axi_arvalid,
  output logic        s_axi_arready,

  output logic [31:0] s_axi_rdata,
  output logic [1:0]  s_axi_rresp,
  output logic        s_axi_rvalid,
  input  logic        s_axi_rready,

  // External Peripheral IOs
  // 1. Timer IOs
  input  logic        tim_capture_in,
  output logic        tim_match_out,

  // 2. PWM IOs
  input  logic        pwm_fault_in,
  output logic [3:0]  pwm_out,
  output logic [3:0]  pwm_out_n,

  // 3. Watchdog System Reset Outputs
  output logic        wdt_reset_o,
  output logic        wdt_rst_n,

  // 4. Interrupt Request Lines
  output logic        irq_timer,
  output logic        irq_pwm,
  output logic        irq_wdt,
  output logic        irq_combined
);

  // --------------------------------------------------------------------------
  // Internal Interconnect Wires
  // --------------------------------------------------------------------------
  // AXI to Register File interface
  logic        reg_wr_en;
  logic [7:0]  reg_wr_addr;
  logic [31:0] reg_wdata;
  logic [3:0]  reg_wstrb;

  logic        reg_rd_en;
  logic [7:0]  reg_rd_addr;
  logic [31:0] reg_rdata;

  // Global control
  /* verilator lint_off UNUSED */
  logic        global_en;
  /* verilator lint_on UNUSED */
  logic        soft_rst;

  // Timer Core wires
  logic        tim_en;
  logic        tim_mode;
  logic        tim_dir;
  logic        tim_cap_en;
  logic [1:0]  tim_cap_edge;
  logic        tim_soft_trig;
  logic [31:0] tim_prescaler;
  logic [31:0] tim_autoreload;
  logic        tim_cnt_wr_en;
  logic [31:0] tim_cnt_wdata;
  logic [31:0] tim_counter;
  logic [31:0] tim_capture_val;
  logic        tim_ovf_pulse;
  logic        tim_cap_pulse;
  logic        tim_running;

  // PWM Core wires
  logic        pwm_master_en;
  logic        pwm_center_align;
  logic        pwm_fault_en;
  logic        pwm_fault_pol;
  logic        fault_safe_level;
  logic [3:0]  comp_out_en;
  logic [15:0] deadtime_cycles;
  logic [31:0] pwm_prescaler;
  logic [31:0] pwm_period;
  logic [3:0]  pwm_ch_en;
  logic [3:0]  pwm_ch_pol;
  logic [31:0] pwm_ch0_cmp;
  logic [31:0] pwm_ch1_cmp;
  logic [31:0] pwm_ch2_cmp;
  logic [31:0] pwm_ch3_cmp;
  logic        pwm_fault_clr;
  logic [31:0] pwm_counter;
  logic        pwm_period_pulse;
  logic [3:0]  pwm_ch_match_pulse;
  logic        pwm_fault_pulse;
  logic        pwm_fault_active;

  // Watchdog Core wires
  logic        wdt_en;
  logic        wdt_win_en;
  logic        wdt_rst_en;
  logic        wdt_warn_irq_en;
  logic        wdt_key_wr;
  logic [31:0] wdt_key_data;
  logic [31:0] wdt_timeout_val;
  logic [31:0] wdt_window_val;
  logic [31:0] wdt_warn_val;
  logic [7:0]  wdt_rst_width;
  logic [31:0] wdt_counter;
  logic        wdt_locked;
  logic        wdt_timeout_pulse;
  logic        wdt_win_fail_pulse;
  logic        wdt_warn_pulse;

  // --------------------------------------------------------------------------
  // Submodule 1: AXI4-Lite Slave Bridge
  // --------------------------------------------------------------------------
  axi_lite_slave u_axi_slave (
    .clk           (clk),
    .rst_n         (rst_n),

    .s_axi_awaddr  (s_axi_awaddr),
    .s_axi_awprot  (s_axi_awprot),
    .s_axi_awvalid (s_axi_awvalid),
    .s_axi_awready (s_axi_awready),

    .s_axi_wdata   (s_axi_wdata),
    .s_axi_wstrb   (s_axi_wstrb),
    .s_axi_wvalid  (s_axi_wvalid),
    .s_axi_wready  (s_axi_wready),

    .s_axi_bresp   (s_axi_bresp),
    .s_axi_bvalid  (s_axi_bvalid),
    .s_axi_bready  (s_axi_bready),

    .s_axi_araddr  (s_axi_araddr),
    .s_axi_arprot  (s_axi_arprot),
    .s_axi_arvalid (s_axi_arvalid),
    .s_axi_arready (s_axi_arready),

    .s_axi_rdata   (s_axi_rdata),
    .s_axi_rresp   (s_axi_rresp),
    .s_axi_rvalid  (s_axi_rvalid),
    .s_axi_rready  (s_axi_rready),

    .reg_wr_en     (reg_wr_en),
    .reg_wr_addr   (reg_wr_addr),
    .reg_wdata     (reg_wdata),
    .reg_wstrb     (reg_wstrb),

    .reg_rd_en     (reg_rd_en),
    .reg_rd_addr   (reg_rd_addr),
    .reg_rdata     (reg_rdata)
  );

  // --------------------------------------------------------------------------
  // Submodule 2: Unified Register File & Interrupt Controller
  // --------------------------------------------------------------------------
  timer_pwm_wdt_regs u_regs (
    .clk                (clk),
    .rst_n              (rst_n),

    .reg_wr_en          (reg_wr_en),
    .reg_wr_addr        (reg_wr_addr),
    .reg_wdata          (reg_wdata),
    .reg_wstrb          (reg_wstrb),

    .reg_rd_en          (reg_rd_en),
    .reg_rd_addr        (reg_rd_addr),
    .reg_rdata          (reg_rdata),

    .global_en          (global_en),
    .soft_rst           (soft_rst),

    .tim_en             (tim_en),
    .tim_mode           (tim_mode),
    .tim_dir            (tim_dir),
    .tim_cap_en         (tim_cap_en),
    .tim_cap_edge       (tim_cap_edge),
    .tim_soft_trig      (tim_soft_trig),
    .tim_prescaler      (tim_prescaler),
    .tim_autoreload     (tim_autoreload),
    .tim_cnt_wr_en      (tim_cnt_wr_en),
    .tim_cnt_wdata      (tim_cnt_wdata),
    .tim_counter_in     (tim_counter),
    .tim_capture_val_in (tim_capture_val),
    .tim_ovf_pulse      (tim_ovf_pulse),
    .tim_cap_pulse      (tim_cap_pulse),
    .tim_running        (tim_running),

    .pwm_master_en      (pwm_master_en),
    .pwm_center_align   (pwm_center_align),
    .pwm_fault_en       (pwm_fault_en),
    .pwm_fault_pol      (pwm_fault_pol),
    .fault_safe_level   (fault_safe_level),
    .comp_out_en        (comp_out_en),
    .deadtime_cycles    (deadtime_cycles),
    .pwm_prescaler      (pwm_prescaler),
    .pwm_period         (pwm_period),
    .pwm_ch_en          (pwm_ch_en),
    .pwm_ch_pol         (pwm_ch_pol),
    .pwm_ch0_cmp        (pwm_ch0_cmp),
    .pwm_ch1_cmp        (pwm_ch1_cmp),
    .pwm_ch2_cmp        (pwm_ch2_cmp),
    .pwm_ch3_cmp        (pwm_ch3_cmp),
    .pwm_fault_clr      (pwm_fault_clr),
    .pwm_counter_in     (pwm_counter),
    .pwm_period_pulse   (pwm_period_pulse),
    .pwm_ch_match_pulse (pwm_ch_match_pulse),
    .pwm_fault_pulse    (pwm_fault_pulse),
    .pwm_fault_active   (pwm_fault_active),

    .wdt_en             (wdt_en),
    .wdt_win_en         (wdt_win_en),
    .wdt_rst_en         (wdt_rst_en),
    .wdt_warn_irq_en    (wdt_warn_irq_en),
    .wdt_key_wr         (wdt_key_wr),
    .wdt_key_data       (wdt_key_data),
    .wdt_timeout_val    (wdt_timeout_val),
    .wdt_window_val     (wdt_window_val),
    .wdt_warn_val       (wdt_warn_val),
    .wdt_rst_width      (wdt_rst_width),
    .wdt_counter_in     (wdt_counter),
    .wdt_locked         (wdt_locked),
    .wdt_timeout_pulse  (wdt_timeout_pulse),
    .wdt_win_fail_pulse (wdt_win_fail_pulse),
    .wdt_warn_pulse     (wdt_warn_pulse),

    .irq_timer          (irq_timer),
    .irq_pwm            (irq_pwm),
    .irq_wdt            (irq_wdt),
    .irq_combined       (irq_combined)
  );

  // --------------------------------------------------------------------------
  // Submodule 3: Timer Core
  // --------------------------------------------------------------------------
  timer_core u_timer (
    .clk             (clk),
    .rst_n           (rst_n),
    .soft_rst        (soft_rst),

    .tim_en          (tim_en),
    .tim_mode        (tim_mode),
    .tim_dir         (tim_dir),
    .tim_cap_en      (tim_cap_en),
    .tim_cap_edge    (tim_cap_edge),
    .tim_soft_trig   (tim_soft_trig),
    .tim_prescaler   (tim_prescaler),
    .tim_autoreload  (tim_autoreload),
    .tim_cnt_wr_en   (tim_cnt_wr_en),
    .tim_cnt_wdata   (tim_cnt_wdata),

    .tim_capture_in  (tim_capture_in),
    .tim_match_out   (tim_match_out),

    .tim_counter     (tim_counter),
    .tim_capture_val (tim_capture_val),
    .tim_ovf_pulse   (tim_ovf_pulse),
    .tim_cap_pulse   (tim_cap_pulse),
    .tim_running     (tim_running)
  );

  // --------------------------------------------------------------------------
  // Submodule 4: 4-Channel PWM Core
  // --------------------------------------------------------------------------
  pwm_core u_pwm (
    .clk                (clk),
    .rst_n              (rst_n),
    .soft_rst           (soft_rst),

    .pwm_master_en      (pwm_master_en),
    .pwm_center_align   (pwm_center_align),
    .pwm_fault_en       (pwm_fault_en),
    .pwm_fault_pol      (pwm_fault_pol),
    .pwm_fault_clr      (pwm_fault_clr),
    .fault_safe_level   (fault_safe_level),
    .comp_out_en        (comp_out_en),
    .deadtime_cycles    (deadtime_cycles),

    .pwm_prescaler      (pwm_prescaler),
    .pwm_period         (pwm_period),

    .pwm_ch_en          (pwm_ch_en),
    .pwm_ch_pol         (pwm_ch_pol),
    .pwm_ch0_cmp        (pwm_ch0_cmp),
    .pwm_ch1_cmp        (pwm_ch1_cmp),
    .pwm_ch2_cmp        (pwm_ch2_cmp),
    .pwm_ch3_cmp        (pwm_ch3_cmp),

    .pwm_fault_in       (pwm_fault_in),
    .pwm_out            (pwm_out),
    .pwm_out_n          (pwm_out_n),

    .pwm_counter        (pwm_counter),
    .pwm_period_pulse   (pwm_period_pulse),
    .pwm_ch_match_pulse (pwm_ch_match_pulse),
    .pwm_fault_pulse    (pwm_fault_pulse),
    .pwm_fault_active   (pwm_fault_active)
  );

  // --------------------------------------------------------------------------
  // Submodule 5: Safety Watchdog Core
  // --------------------------------------------------------------------------
  wdt_core u_wdt (
    .clk                (clk),
    .rst_n              (rst_n),

    .wdt_en_in          (wdt_en),
    .wdt_win_en_in      (wdt_win_en),
    .wdt_rst_en_in      (wdt_rst_en),
    .wdt_warn_irq_en_in (wdt_warn_irq_en),
    .wdt_timeout_val    (wdt_timeout_val),
    .wdt_window_val     (wdt_window_val),
    .wdt_warn_val       (wdt_warn_val),
    .wdt_rst_width      (wdt_rst_width),

    .wdt_key_wr         (wdt_key_wr),
    .wdt_key_data       (wdt_key_data),

    .wdt_counter        (wdt_counter),
    .wdt_locked         (wdt_locked),
    .wdt_timeout_pulse  (wdt_timeout_pulse),
    .wdt_win_fail_pulse (wdt_win_fail_pulse),
    .wdt_warn_pulse     (wdt_warn_pulse),

    .wdt_reset_o        (wdt_reset_o),
    .wdt_rst_n          (wdt_rst_n)
  );

endmodule
