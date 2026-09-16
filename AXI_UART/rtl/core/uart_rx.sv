// ============================================================================
// File: uart_rx.sv
// Description: UART Receiver Module with 16x Oversampling and Majority Voting
// Project: AXI_UART
// ============================================================================

module uart_rx (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       rx_enable,
  input  logic       tick,        // 16x oversampling tick
  input  logic       rx_in,       // Serial input line
  input  logic [1:0] data_bits,   // 00=5b, 01=6b, 10=7b, 11=8b
  input  logic       parity_en,
  input  logic       parity_odd,  // 0=Even, 1=Odd
  /* verilator lint_off UNUSED */
  input  logic       stop_bits,   // 0=1 bit, 1=2 bits (Unused in RX framing)
  /* verilator lint_on UNUSED */

  output logic [7:0] rx_data,
  output logic       rx_valid,
  output logic       rx_busy,
  output logic       frame_err,
  output logic       parity_err
);

  typedef enum logic [2:0] {
    ST_IDLE   = 3'b000,
    ST_START  = 3'b001,
    ST_DATA   = 3'b010,
    ST_PARITY = 3'b011,
    ST_STOP   = 3'b100
  } state_t;

  state_t state;

  // Double-flop synchronizer
  logic rx_sync_0, rx_sync_1;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_sync_0 <= 1'b1;
      rx_sync_1 <= 1'b1;
    end else begin
      rx_sync_0 <= rx_in;
      rx_sync_1 <= rx_sync_0;
    end
  end

  logic [3:0] tick_cnt;
  logic [2:0] bit_cnt;
  logic [7:0] rx_shift_reg;
  logic [2:0] sample_bits;
  logic       sampled_bit;
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

  // Majority Voting: 3 samples at tick 7, 8, 9
  always_comb begin
    sampled_bit = (sample_bits[0] & sample_bits[1]) |
                  (sample_bits[1] & sample_bits[2]) |
                  (sample_bits[0] & sample_bits[2]);
  end

  assign rx_busy = (state != ST_IDLE);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state        <= ST_IDLE;
      tick_cnt     <= 4'd0;
      bit_cnt      <= 3'd0;
      rx_shift_reg <= 8'd0;
      rx_data      <= 8'd0;
      rx_valid     <= 1'b0;
      frame_err    <= 1'b0;
      parity_err   <= 1'b0;
      sample_bits  <= 3'b111;
    end else begin
      rx_valid <= 1'b0;

      if (!rx_enable) begin
        state     <= ST_IDLE;
        frame_err <= 1'b0;
        parity_err<= 1'b0;
      end else begin
        case (state)
          ST_IDLE: begin
            if (!rx_sync_1) begin // Falling edge start bit detect
              tick_cnt    <= 4'd0;
              sample_bits <= 3'b111;
              state       <= ST_START;
            end
          end

          ST_START: begin
            if (tick) begin
              if (tick_cnt == 4'd7)  sample_bits[0] <= rx_sync_1;
              if (tick_cnt == 4'd8)  sample_bits[1] <= rx_sync_1;
              if (tick_cnt == 4'd9)  sample_bits[2] <= rx_sync_1;

              if (tick_cnt == 4'd15) begin
                tick_cnt <= 4'd0;
                if (sampled_bit == 1'b0) begin // Valid start bit
                  bit_cnt <= 3'd0;
                  state   <= ST_DATA;
                end else begin // False start bit noise
                  state   <= ST_IDLE;
                end
              end else begin
                tick_cnt <= tick_cnt + 4'd1;
              end
            end
          end

          ST_DATA: begin
            if (tick) begin
              if (tick_cnt == 4'd7)  sample_bits[0] <= rx_sync_1;
              if (tick_cnt == 4'd8)  sample_bits[1] <= rx_sync_1;
              if (tick_cnt == 4'd9)  sample_bits[2] <= rx_sync_1;

              if (tick_cnt == 4'd15) begin
                tick_cnt <= 4'd0;
                rx_shift_reg[bit_cnt] <= sampled_bit;

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
            if (tick) begin
              if (tick_cnt == 4'd7)  sample_bits[0] <= rx_sync_1;
              if (tick_cnt == 4'd8)  sample_bits[1] <= rx_sync_1;
              if (tick_cnt == 4'd9)  sample_bits[2] <= rx_sync_1;

              if (tick_cnt == 4'd15) begin
                tick_cnt <= 4'd0;
                // Calculate Parity
                begin
                  logic [7:0] masked_data;
                  logic calc_parity;
                  case (data_bits)
                    2'b00: masked_data = {3'b0, rx_shift_reg[4:0]};
                    2'b01: masked_data = {2'b0, rx_shift_reg[5:0]};
                    2'b10: masked_data = {1'b0, rx_shift_reg[6:0]};
                    2'b11: masked_data = rx_shift_reg;
                  endcase
                  calc_parity = parity_odd ? ~(^masked_data) : (^masked_data);
                  if (sampled_bit != calc_parity) begin
                    parity_err <= 1'b1;
                  end else begin
                    parity_err <= 1'b0;
                  end
                end
                state <= ST_STOP;
              end else begin
                tick_cnt <= tick_cnt + 4'd1;
              end
            end
          end

          ST_STOP: begin
            if (tick) begin
              if (tick_cnt == 4'd7)  sample_bits[0] <= rx_sync_1;
              if (tick_cnt == 4'd8)  sample_bits[1] <= rx_sync_1;
              if (tick_cnt == 4'd9)  sample_bits[2] <= rx_sync_1;

              if (tick_cnt == 4'd15) begin
                tick_cnt <= 4'd0;
                if (sampled_bit == 1'b0) begin
                  frame_err <= 1'b1; // Stop bit should be 1
                end else begin
                  frame_err <= 1'b0;
                end
                rx_data  <= rx_shift_reg;
                rx_valid <= 1'b1;
                state    <= ST_IDLE;
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
