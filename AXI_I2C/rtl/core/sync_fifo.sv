// ============================================================================
// File: sync_fifo.sv
// Description: Synchronous Parameterized FIFO Buffer for TX Command & RX Data
// Project: AXI_I2C
// ============================================================================

module sync_fifo #(
  parameter int DATA_WIDTH = 8,
  parameter int DEPTH      = 16
)(
  input  logic                        clk,
  input  logic                        rst_n,
  input  logic                        clear,

  input  logic                        wr_en,
  input  logic [DATA_WIDTH-1:0]       din,

  input  logic                        rd_en,
  output logic [DATA_WIDTH-1:0]       dout,

  output logic                        full,
  output logic                        empty,
  output logic [$clog2(DEPTH+1)-1:0]  count,
  output logic                        overflow
);

  localparam int ADDR_WIDTH = $clog2(DEPTH);
  localparam int CNT_WIDTH  = $clog2(DEPTH+1);

  logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
  logic [ADDR_WIDTH-1:0] wr_ptr;
  logic [ADDR_WIDTH-1:0] rd_ptr;
  logic [CNT_WIDTH-1:0]  fifo_cnt;

  assign full  = (fifo_cnt == CNT_WIDTH'(DEPTH));
  assign empty = (fifo_cnt == '0);
  assign count = fifo_cnt;
  assign dout  = mem[rd_ptr];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr   <= '0;
      rd_ptr   <= '0;
      fifo_cnt <= '0;
      overflow <= 1'b0;
    end else if (clear) begin
      wr_ptr   <= '0;
      rd_ptr   <= '0;
      fifo_cnt <= '0;
      overflow <= 1'b0;
    end else begin
      // Overflow detection
      if (wr_en && full && !rd_en) begin
        overflow <= 1'b1;
      end

      // Write & Read logic
      case ({wr_en && !full, rd_en && !empty})
        2'b10: begin // Write only
          mem[wr_ptr] <= din;
          wr_ptr      <= (wr_ptr == ADDR_WIDTH'(DEPTH - 1)) ? '0 : wr_ptr + 1'b1;
          fifo_cnt    <= fifo_cnt + 1'b1;
        end
        2'b01: begin // Read only
          rd_ptr      <= (rd_ptr == ADDR_WIDTH'(DEPTH - 1)) ? '0 : rd_ptr + 1'b1;
          fifo_cnt    <= fifo_cnt - 1'b1;
        end
        2'b11: begin // Concurrent Write & Read
          mem[wr_ptr] <= din;
          wr_ptr      <= (wr_ptr == ADDR_WIDTH'(DEPTH - 1)) ? '0 : wr_ptr + 1'b1;
          rd_ptr      <= (rd_ptr == ADDR_WIDTH'(DEPTH - 1)) ? '0 : rd_ptr + 1'b1;
        end
        default: ;
      endcase
    end
  end

endmodule
