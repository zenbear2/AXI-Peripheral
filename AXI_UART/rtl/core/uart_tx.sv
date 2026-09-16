// ============================================================================
// File: uart_tx.sv
// Description: UART Transmitter Unit with Parity & Stop Bit Generation
// Project: AXI_UART
// ============================================================================

module uart_tx (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       tx_enable,
  input  logic       tick,        // 16x oversampling tick
  input  logic       tx_start,
  input  logic [7:0] tx_data,
  input  logic [1:0] data_bits,   // 00=5b, 01=6b, 10=7b, 11=8b
  input  logic       parity_en,
  input  logic       parity_odd,  // 0=Even, 1=Odd
  input  logic       stop_bits,   // 0=1 bit, 1=2 bits

  output logic       tx_out,
  output logic       tx_busy,
  output logic       tx_done
);

  typedef enum logic [2:0] {
    ST_IDLE   = 3'b000,
    ST_START  = 3'b001,
    ST_DATA   = 3'b010,
    ST_PARITY = 3'b011,
    ST_STOP   = 3'b100
  } state_t;

  state_t state;

  logic [3:0] tick_cnt;
  logic [2:0] bit_cnt;
  logic [7:0] tx_shift_reg;
  logic       parity_bit;
  logic [3:0] total_data_bits;

  // Compute number of data bits
  always_comb begin
    case (data_bits)
      2'b00: total_data_bits = 4'd5;
      2'b01: total_data_bits = 4'd6;
      2'b10: total_data_bits = 4'd7;
      2'b11: total_data_bits = 4'd8;
    endcase
  end

  // Calculate Parity
  always_comb begin
    logic [7:0] masked_data;
    case (data_bits)
      2'b00: masked_data = {3'b0, tx_shift_reg[4:0]};
      2'b01: masked_data = {2'b0, tx_shift_reg[5:0]};
      2'b10: masked_data = {1'b0, tx_shift_reg[6:0]};
      2'b11: masked_data = tx_shift_reg;
    endcase
    if (parity_odd) begin
      parity_bit = ~(^masked_data);
    end else begin
      parity_bit = ^masked_data;
    end
  end

  assign tx_busy = (state != ST_IDLE);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state        <= ST_IDLE;
      tick_cnt     <= 4'd0;
      bit_cnt      <= 3'd0;
      tx_shift_reg <= 8'd0;
      tx_out       <= 1'b1;
      tx_done      <= 1'b0;
    end else begin
      tx_done <= 1'b0;

      if (!tx_enable) begin
        state  <= ST_IDLE;
        tx_out <= 1'b1;
      end else begin
        case (state)
          ST_IDLE: begin
            tx_out <= 1'b1;
            if (tx_start) begin
              tx_shift_reg <= tx_data;
              tick_cnt     <= 4'd0;
              bit_cnt      <= 3'd0;
              state        <= ST_START;
            end
          end

          ST_START: begin
            tx_out <= 1'b0;
            if (tick) begin
              if (tick_cnt == 4'd15) begin
                tick_cnt <= 4'd0;
                state    <= ST_DATA;
              end else begin
                tick_cnt <= tick_cnt + 4'd1;
              end
            end
          end

          ST_DATA: begin
            tx_out <= tx_shift_reg[bit_cnt];
            if (tick) begin
              if (tick_cnt == 4'd15) begin
                tick_cnt <= 4'd0;
                if ({1'b0, bit_cnt} == (total_data_bits - 4'd1)) begin
                  bit_cnt <= 3'd0;
                  if (parity_en) begin
                    state <= ST_PARITY;
                  end else begin
                    state <= ST_STOP;
                  end
                end else begin
                  bit_cnt <= bit_cnt + 3'd1;
                end
              end else begin
                tick_cnt <= tick_cnt + 4'd1;
              end
            end
          end

          ST_PARITY: begin
            tx_out <= parity_bit;
            if (tick) begin
              if (tick_cnt == 4'd15) begin
                tick_cnt <= 4'd0;
                state    <= ST_STOP;
              end else begin
                tick_cnt <= tick_cnt + 4'd1;
              end
            end
          end

          ST_STOP: begin
            tx_out <= 1'b1;
            if (tick) begin
              if (tick_cnt == 4'd15) begin
                tick_cnt <= 4'd0;
                if (stop_bits && (bit_cnt == 3'd0)) begin
                  bit_cnt <= 3'd1;
                end else begin
                  bit_cnt <= 3'd0;
                  state   <= ST_IDLE;
                  tx_done <= 1'b1;
                end
              end else begin
                tick_cnt <= tick_cnt + 4'd1;
              end
            end
          end

          default: state <= ST_IDLE;
        endcase
      end
    end
  end

endmodule
