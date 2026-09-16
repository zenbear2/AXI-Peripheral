// ============================================================================
// File: baud_rate_gen.sv
// Description: Baud Rate Generator & 16x Over-Sampling Tick Generator
// Project: AXI_UART
// ============================================================================

module baud_rate_gen (
  input  logic        clk,
  input  logic        rst_n,
  input  logic [15:0] baud_div, // Baud rate divisor (clk_freq / (baud_rate * 16))
  output logic        tick      // 16x oversampling pulse
);

  logic [15:0] count;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count <= 16'd0;
      tick  <= 1'b0;
    end else begin
      if (baud_div <= 16'd1) begin
        count <= 16'd0;
        tick  <= 1'b1;
      end else if (count >= (baud_div - 16'd1)) begin
        count <= 16'd0;
        tick  <= 1'b1;
      end else begin
        count <= count + 16'd1;
        tick  <= 1'b0;
      end
    end
  end

endmodule
