// ============================================================================
// File: tb_timer_pwm_wdt.sv
// Description: SystemVerilog Testbench Top Wrapper for Verilator Simulation
// Project: AXI_TIMER_PWM_WDT
// ============================================================================

module tb_timer_pwm_wdt (
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

  // External IO Pins
  input  logic        tim_capture_in,
  output logic        tim_match_out,

  input  logic        pwm_fault_in,
  output logic [3:0]  pwm_out,
  output logic [3:0]  pwm_out_n,

  output logic        wdt_reset_o,
  output logic        wdt_rst_n,

  output logic        irq_timer,
  output logic        irq_pwm,
  output logic        irq_wdt,
  output logic        irq_combined
);

  // Instantiate DUT
  axi_timer_pwm_wdt_top u_dut (
    .s_axi_aclk     (clk),
    .s_axi_aresetn  (rst_n),

    .s_axi_awaddr   (s_axi_awaddr),
    .s_axi_awprot   (s_axi_awprot),
    .s_axi_awvalid  (s_axi_awvalid),
    .s_axi_awready  (s_axi_awready),

    .s_axi_wdata    (s_axi_wdata),
    .s_axi_wstrb    (s_axi_wstrb),
    .s_axi_wvalid   (s_axi_wvalid),
    .s_axi_wready   (s_axi_wready),

    .s_axi_bresp    (s_axi_bresp),
    .s_axi_bvalid   (s_axi_bvalid),
    .s_axi_bready   (s_axi_bready),

    .s_axi_araddr   (s_axi_araddr),
    .s_axi_arprot   (s_axi_arprot),
    .s_axi_arvalid  (s_axi_arvalid),
    .s_axi_arready  (s_axi_arready),

    .s_axi_rdata    (s_axi_rdata),
    .s_axi_rresp    (s_axi_rresp),
    .s_axi_rvalid   (s_axi_rvalid),
    .s_axi_rready   (s_axi_rready),

    .tim_capture_in (tim_capture_in),
    .tim_match_out  (tim_match_out),

    .pwm_fault_in   (pwm_fault_in),
    .pwm_out        (pwm_out),
    .pwm_out_n      (pwm_out_n),

    .wdt_reset_o    (wdt_reset_o),
    .wdt_rst_n      (wdt_rst_n),

    .irq_timer      (irq_timer),
    .irq_pwm        (irq_pwm),
    .irq_wdt        (irq_wdt),
    .irq_combined   (irq_combined)
  );

endmodule
