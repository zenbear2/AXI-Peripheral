// ============================================================================
// File: i2c_tb.sv
// Description: SystemVerilog Top-Level Testbench for AXI_I2C IP Core
// Project: AXI_I2C
// ============================================================================

module i2c_tb (
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

  // Interrupt Output
  output logic        irq,

  // Testbench Injected Controls & Overrides
  input  logic        force_slave_nack,
  input  logic [15:0] force_slave_stretch,
  input  logic        force_bus_sda_stuck_low,
  input  logic        force_bus_scl_stuck_low,

  // Bus Observability Outputs
  output logic        i2c_scl_line,
  output logic        i2c_sda_line,
  output logic [3:0]  dbg_fsm_state,
  output logic [1:0]  dbg_phase,
  output logic        dbg_dut_scl_oe,
  output logic        dbg_dut_sda_oe,
  output logic        dbg_slv_scl_oe,
  output logic        dbg_slv_sda_oe,
  output logic        dbg_is_stretching
);

  assign dbg_fsm_state     = u_dut.u_fsm_core.state_q;
  assign dbg_phase         = u_dut.u_timing_gen.current_phase;
  assign dbg_dut_scl_oe    = dut_scl_oe;
  assign dbg_dut_sda_oe    = dut_sda_oe;
  assign dbg_slv_scl_oe    = slv_scl_oe;
  assign dbg_slv_sda_oe    = slv_sda_oe;
  assign dbg_is_stretching = u_dut.u_timing_gen.is_stretching;

  // --------------------------------------------------------------------------
  // Open-Drain Bus Resolution Wires
  // --------------------------------------------------------------------------
  /* verilator lint_off UNOPTFLAT */
  wire scl_line;
  wire sda_line;
  /* verilator lint_on UNOPTFLAT */

  /* verilator lint_off UNUSED */
  logic dut_scl_o;
  logic dut_sda_o;
  /* verilator lint_on UNUSED */
  logic dut_scl_oe;
  logic dut_sda_oe;

  /* verilator lint_off UNUSED */
  logic slv_scl_o;
  logic slv_sda_o;
  /* verilator lint_on UNUSED */
  logic slv_scl_oe;
  logic slv_sda_oe;

  // Open-Drain Wire-AND with Pull-Up Resistor
  assign scl_line = (dut_scl_oe || slv_scl_oe || force_bus_scl_stuck_low) ? 1'b0 : 1'b1;
  assign sda_line = (dut_sda_oe || slv_sda_oe || force_bus_sda_stuck_low) ? 1'b0 : 1'b1;

  assign i2c_scl_line = scl_line;
  assign i2c_sda_line = sda_line;

  // --------------------------------------------------------------------------
  // DUT Instantiation: axi_i2c_top
  // --------------------------------------------------------------------------
  axi_i2c_top #(
    .FIFO_DEPTH (16)
  ) u_dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .scl_i         (scl_line),
    .scl_o         (dut_scl_o),
    .scl_oe        (dut_scl_oe),
    .sda_i         (sda_line),
    .sda_o         (dut_sda_o),
    .sda_oe        (dut_sda_oe),
    .irq           (irq),
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
    .s_axi_rready  (s_axi_rready)
  );

  // --------------------------------------------------------------------------
  // Virtual I2C Slave Model Instantiation
  // --------------------------------------------------------------------------
  i2c_slave_model #(
    .SLAVE_ADDR (7'h50),
    .MEM_SIZE   (256)
  ) u_slave (
    .clk                (clk),
    .rst_n              (rst_n),
    .scl_i              (scl_line),
    .scl_o              (slv_scl_o),
    .scl_oe             (slv_scl_oe),
    .sda_i              (sda_line),
    .sda_o              (slv_sda_o),
    .sda_oe             (slv_sda_oe),
    .force_nack         (force_slave_nack),
    .force_stretch_clks (force_slave_stretch)
  );

endmodule
