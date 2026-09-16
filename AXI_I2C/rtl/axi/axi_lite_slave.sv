// ============================================================================
// File: axi_lite_slave.sv
// Description: AXI4-Lite Slave Interface & Register Access Handshake Logic
// Project: AXI_I2C
// ============================================================================

module axi_lite_slave (
  input  logic        clk,
  input  logic        rst_n,

  /* verilator lint_off UNUSED */
  // AXI4-Lite Write Address Channel
  input  logic [31:0] s_axi_awaddr,
  input  logic [2:0]  s_axi_awprot,
  input  logic        s_axi_awvalid,
  output logic        s_axi_awready,

  // AXI4-Lite Write Data Channel
  input  logic [31:0] s_axi_wdata,
  input  logic [3:0]  s_axi_wstrb,
  input  logic        s_axi_wvalid,
  output logic        s_axi_wready,

  // AXI4-Lite Write Response Channel
  output logic [1:0]  s_axi_bresp,
  output logic        s_axi_bvalid,
  input  logic        s_axi_bready,

  // AXI4-Lite Read Address Channel
  input  logic [31:0] s_axi_araddr,
  input  logic [2:0]  s_axi_arprot,
  input  logic        s_axi_arvalid,
  output logic        s_axi_arready,
  /* verilator lint_on UNUSED */

  // AXI4-Lite Read Data Channel
  output logic [31:0] s_axi_rdata,
  output logic [1:0]  s_axi_rresp,
  output logic        s_axi_rvalid,
  input  logic        s_axi_rready,

  // Local Register Interface
  output logic        reg_wr_en,
  output logic [5:0]  reg_wr_addr,
  output logic [31:0] reg_wdata,
  output logic [3:0]  reg_wstrb,

  output logic        reg_rd_en,
  output logic [5:0]  reg_rd_addr,
  input  logic [31:0] reg_rdata
);

  // --------------------------------------------------------------------------
  // Write Channel State Machine & Handshake
  // --------------------------------------------------------------------------
  logic aw_captured;
  logic w_captured;
  logic [5:0] latched_awaddr;
  logic [31:0] latched_wdata;
  logic [3:0]  latched_wstrb;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axi_awready <= 1'b0;
      s_axi_wready  <= 1'b0;
      s_axi_bvalid  <= 1'b0;
      s_axi_bresp   <= 2'b00; // OKAY
      aw_captured   <= 1'b0;
      w_captured    <= 1'b0;
      latched_awaddr<= 6'd0;
      latched_wdata <= 32'd0;
      latched_wstrb <= 4'd0;
      reg_wr_en     <= 1'b0;
      reg_wr_addr   <= 6'd0;
      reg_wdata     <= 32'd0;
      reg_wstrb     <= 4'd0;
    end else begin
      reg_wr_en <= 1'b0;

      // Handle AW handshake
      if (!s_axi_awready && s_axi_awvalid && !aw_captured) begin
        s_axi_awready  <= 1'b1;
        latched_awaddr <= s_axi_awaddr[5:0];
        aw_captured    <= 1'b1;
      end else begin
        s_axi_awready  <= 1'b0;
      end

      // Handle W handshake
      if (!s_axi_wready && s_axi_wvalid && !w_captured) begin
        s_axi_wready  <= 1'b1;
        latched_wdata <= s_axi_wdata;
        latched_wstrb <= s_axi_wstrb;
        w_captured    <= 1'b1;
      end else begin
        s_axi_wready  <= 1'b0;
      end

      // Execute write when both AW and W are captured
      if (aw_captured && w_captured && !s_axi_bvalid) begin
        reg_wr_en      <= 1'b1;
        reg_wr_addr    <= latched_awaddr;
        reg_wdata      <= latched_wdata;
        reg_wstrb      <= latched_wstrb;
        s_axi_bvalid   <= 1'b1;
        s_axi_bresp    <= 2'b00; // OKAY
        aw_captured    <= 1'b0;
        w_captured     <= 1'b0;
      end

      // Clear BVALID on BREADY
      if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end
    end
  end

  // --------------------------------------------------------------------------
  // Read Channel State Machine & Handshake
  // --------------------------------------------------------------------------
  assign reg_rd_addr = s_axi_araddr[5:0];
  assign reg_rd_en   = s_axi_arvalid && !s_axi_rvalid;
  assign s_axi_rresp = 2'b00;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axi_arready <= 1'b0;
      s_axi_rvalid  <= 1'b0;
      s_axi_rdata   <= 32'd0;
    end else begin
      if (!s_axi_arready && s_axi_arvalid && !s_axi_rvalid) begin
        s_axi_arready <= 1'b1;
        s_axi_rvalid  <= 1'b1;
        s_axi_rdata   <= reg_rdata;
      end else begin
        s_axi_arready <= 1'b0;
        if (s_axi_rready) begin
          s_axi_rvalid <= 1'b0;
        end
      end
    end
  end

endmodule
