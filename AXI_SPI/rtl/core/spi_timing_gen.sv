// ============================================================================
// File: spi_timing_gen.sv
// Description: Baud Rate Prescaler & Half-Cycle Clock Tick Generator
// Project: AXI_SPI
// ============================================================================

module spi_timing_gen (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        enable,
  input  logic [15:0] prescale,

  output logic        tick_half
);

  logic [15:0] cnt;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt       <= 16'd0;
      tick_half <= 1'b0;
    end else if (!enable) begin
      cnt       <= 16'd0;
      tick_half <= 1'b0;
    end else begin
      if (cnt >= prescale) begin
        cnt       <= 16'd0;
        tick_half <= 1'b1;
      end else begin
        cnt       <= cnt + 16'd1;
        tick_half <= 1'b0;
      end
    end
  end

endmodule
