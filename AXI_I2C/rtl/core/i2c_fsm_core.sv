// ============================================================================
// File: i2c_fsm_core.sv
// Description: I2C Master Protocol Finite State Machine (FSM) Core
// Project: AXI_I2C
// ============================================================================

module i2c_fsm_core (
  input  logic                        clk,
  input  logic                        rst_n,

  // Control from Register File
  input  logic                        enable,
  input  logic                        manual_recover,

  // Command & TX FIFO Interface
  input  logic                        tx_fifo_empty,
  input  logic [11:0]                 tx_fifo_dout, // [11]=NACK, [10]=READ, [9]=STOP, [8]=START, [7:0]=DATA
  output logic                        tx_fifo_rd_en,

  // RX FIFO Interface
  output logic                        rx_fifo_wr_en,
  output logic [7:0]                  rx_fifo_din,

  // 4-Phase Timing Interface
  input  i2c_pkg::i2c_phase_t         timing_phase,
  input  logic                        phase_end_pulse,
  input  logic                        bit_end_pulse,
  output logic                        timer_run,
  output logic                        timer_reset,

  // Input Filtered Signals
  /* verilator lint_off UNUSED */
  input  logic                        scl_filtered,
  /* verilator lint_on UNUSED */
  input  logic                        sda_filtered,

  // Bus Monitor Signals & Events
  input  logic                        arb_lost_pulse,
  input  logic                        timeout_pulse,
  output logic                        master_active,
  output logic                        check_arb_en,
  output logic                        expected_sda_val,
  output logic                        master_start_seq,
  output logic                        master_stop_seq,

  // Tristate IO Pin Drive Control
  output logic                        scl_oe_o, // 1 = Drive Low, 0 = High-Z
  output logic                        sda_oe_o, // 1 = Drive Low, 0 = High-Z

  // Core Status & Interrupt Trigger Events
  output logic                        fsm_busy_o,
  output logic                        nack_received_pulse,
  output logic                        arb_lost_event_pulse,
  output logic                        transaction_done_pulse
);

  import i2c_pkg::*;

  // State register
  i2c_fsm_state_t state_q;

  // Latched Command and Data fields
  logic [7:0] latched_data;
  /* verilator lint_off UNUSED */
  logic       latched_cmd_start;
  /* verilator lint_on UNUSED */
  logic       latched_cmd_stop;
  logic       latched_cmd_read;
  logic       latched_cmd_nack;

  // Internal Registers
  logic [2:0] bit_cnt;
  logic [7:0] tx_shift_reg;
  logic [7:0] rx_shift_reg;
  logic [3:0] recovery_cnt;
  logic       nack_sample;

  // --------------------------------------------------------------------------
  // Output Assignments
  // --------------------------------------------------------------------------
  assign fsm_busy_o    = (state_q != ST_IDLE);
  assign master_active = (state_q != ST_IDLE) && (state_q != ST_ARB_LOST);

  assign master_start_seq = (state_q == ST_START_1) || (state_q == ST_START_2) ||
                            (state_q == ST_RESTART_1) || (state_q == ST_RESTART_2);
  assign master_stop_seq  = (state_q == ST_STOP_1)  || (state_q == ST_STOP_2);

  // Expected SDA output level (1 = High-Z, 0 = Drive Low)
  assign expected_sda_val = (state_q == ST_TX_BYTE) ? tx_shift_reg[7] :
                            (state_q == ST_TX_ACK)  ? latched_cmd_nack : 1'b1;

  assign check_arb_en = (state_q == ST_TX_BYTE) && (timing_phase == PH_HIGH);

  // --------------------------------------------------------------------------
  // Combinational Pin Drive Controls
  // --------------------------------------------------------------------------
  always_comb begin
    scl_oe_o = 1'b0;
    sda_oe_o = 1'b0;

    case (state_q)
      ST_IDLE: begin
        scl_oe_o = 1'b0;
        sda_oe_o = 1'b0;
      end

      ST_START_1: begin
        // SCL released High, SDA driven Low (START condition)
        scl_oe_o = 1'b0;
        sda_oe_o = 1'b1;
      end

      ST_START_2: begin
        // SCL driven Low, SDA driven Low
        scl_oe_o = 1'b1;
        sda_oe_o = 1'b1;
      end

      ST_RESTART_1: begin
        // SCL driven Low, SDA released High
        scl_oe_o = 1'b1;
        sda_oe_o = 1'b0;
      end

      ST_RESTART_2: begin
        // SCL released High, SDA released High
        scl_oe_o = 1'b0;
        sda_oe_o = 1'b0;
      end

      ST_TX_BYTE: begin
        // SCL follows 4-phase: Low in PH_LOW/PH_FALL (and during timer_reset), High in PH_RISE/PH_HIGH
        scl_oe_o = timer_reset || (timing_phase == PH_LOW) || (timing_phase == PH_FALL);
        // SDA driven low if bit is 0, released if bit is 1
        sda_oe_o = (tx_shift_reg[7] == 1'b0);
      end

      ST_RX_ACK: begin
        // SCL follows 4-phase
        scl_oe_o = (timing_phase == PH_LOW) || (timing_phase == PH_FALL);
        // Master releases SDA to sample Slave ACK/NACK
        sda_oe_o = 1'b0;
      end

      ST_RX_BYTE: begin
        // SCL follows 4-phase
        scl_oe_o = timer_reset || (timing_phase == PH_LOW) || (timing_phase == PH_FALL);
        // Master releases SDA to receive data
        sda_oe_o = 1'b0;
      end

      ST_TX_ACK: begin
        // SCL follows 4-phase
        scl_oe_o = (timing_phase == PH_LOW) || (timing_phase == PH_FALL);
        // ACK: drive SDA low (latched_cmd_nack == 0); NACK: release SDA (latched_cmd_nack == 1)
        sda_oe_o = (latched_cmd_nack == 1'b0);
      end

      ST_STOP_1: begin
        // SCL driven Low, SDA driven Low
        scl_oe_o = 1'b1;
        sda_oe_o = 1'b1;
      end

      ST_STOP_2: begin
        // SCL released High, SDA initially Low then released High (STOP condition)
        scl_oe_o = 1'b0;
        sda_oe_o = (timing_phase == PH_LOW) || (timing_phase == PH_RISE);
      end

      ST_RECOVERY: begin
        // SCL toggles with 4-phase, SDA released
        scl_oe_o = (timing_phase == PH_LOW) || (timing_phase == PH_FALL);
        sda_oe_o = 1'b0;
      end

      ST_ARB_LOST: begin
        scl_oe_o = 1'b0;
        sda_oe_o = 1'b0;
      end

      ST_HOLD: begin
        // Master holds SCL Low between bytes until TX FIFO has next command
        scl_oe_o = 1'b1;
        sda_oe_o = 1'b0;
      end

      default: begin
        scl_oe_o = 1'b0;
        sda_oe_o = 1'b0;
      end
    endcase
  end

  // --------------------------------------------------------------------------
  // Main FSM Sequential Logic
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q                <= ST_IDLE;
      latched_data           <= 8'd0;
      latched_cmd_start      <= 1'b0;
      latched_cmd_stop       <= 1'b0;
      latched_cmd_read       <= 1'b0;
      latched_cmd_nack       <= 1'b0;
      bit_cnt                <= 3'd7;
      tx_shift_reg           <= 8'd0;
      rx_shift_reg           <= 8'd0;
      recovery_cnt           <= 4'd0;
      nack_sample            <= 1'b0;
      tx_fifo_rd_en          <= 1'b0;
      rx_fifo_wr_en          <= 1'b0;
      rx_fifo_din            <= 8'd0;
      timer_run              <= 1'b0;
      timer_reset            <= 1'b0;
      nack_received_pulse    <= 1'b0;
      arb_lost_event_pulse   <= 1'b0;
      transaction_done_pulse <= 1'b0;
    end else if (!enable) begin
      state_q                <= ST_IDLE;
      latched_data           <= 8'd0;
      latched_cmd_start      <= 1'b0;
      latched_cmd_stop       <= 1'b0;
      latched_cmd_read       <= 1'b0;
      latched_cmd_nack       <= 1'b0;
      bit_cnt                <= 3'd7;
      tx_shift_reg           <= 8'd0;
      rx_shift_reg           <= 8'd0;
      recovery_cnt           <= 4'd0;
      nack_sample            <= 1'b0;
      tx_fifo_rd_en          <= 1'b0;
      rx_fifo_wr_en          <= 1'b0;
      rx_fifo_din            <= 8'd0;
      timer_run              <= 1'b0;
      timer_reset            <= 1'b0;
      nack_received_pulse    <= 1'b0;
      arb_lost_event_pulse   <= 1'b0;
      transaction_done_pulse <= 1'b0;
    end else begin
      // Default single-cycle strobe resets
      tx_fifo_rd_en          <= 1'b0;
      rx_fifo_wr_en          <= 1'b0;
      timer_reset            <= 1'b0;
      nack_received_pulse    <= 1'b0;
      arb_lost_event_pulse   <= 1'b0;
      transaction_done_pulse <= 1'b0;

      // Handle asynchronous Timeout or Arbitration Lost abort
      if (timeout_pulse) begin
        state_q     <= ST_IDLE;
        timer_run   <= 1'b0;
        timer_reset <= 1'b1;
      end else if (arb_lost_pulse && (state_q != ST_IDLE) && (state_q != ST_ARB_LOST)) begin
        state_q              <= ST_ARB_LOST;
        arb_lost_event_pulse <= 1'b1;
        timer_run            <= 1'b0;
      end else begin
        case (state_q)
          // ------------------------------------------------------------------
          // IDLE: Wait for TX FIFO command or manual recovery
          // ------------------------------------------------------------------
          ST_IDLE: begin
            timer_run <= 1'b0;
            if (manual_recover) begin
              state_q      <= ST_RECOVERY;
              recovery_cnt <= 4'd0;
              timer_run    <= 1'b1;
              timer_reset  <= 1'b1;
            end else if (!tx_fifo_empty) begin
              // Fetch command entry
              latched_data      <= tx_fifo_dout[7:0];
              latched_cmd_start <= tx_fifo_dout[CMD_START_BIT];
              latched_cmd_stop  <= tx_fifo_dout[CMD_STOP_BIT];
              latched_cmd_read  <= tx_fifo_dout[CMD_READ_BIT];
              latched_cmd_nack  <= tx_fifo_dout[CMD_NACK_BIT];
              tx_fifo_rd_en     <= 1'b1;

              timer_run   <= 1'b1;
              timer_reset <= 1'b1;

              if (tx_fifo_dout[CMD_START_BIT]) begin
                state_q <= ST_START_1;
              end else if (tx_fifo_dout[CMD_READ_BIT]) begin
                state_q <= ST_RX_BYTE;
                bit_cnt <= 3'd7;
              end else begin
                state_q      <= ST_TX_BYTE;
                bit_cnt      <= 3'd7;
                tx_shift_reg <= tx_fifo_dout[7:0];
              end
            end
          end

          // ------------------------------------------------------------------
          // START_1: SCL High, SDA pulled Low
          // ------------------------------------------------------------------
          ST_START_1: begin
            timer_run <= 1'b1;
            if (phase_end_pulse) begin
              state_q <= ST_START_2;
            end
          end

          // ------------------------------------------------------------------
          // START_2: SCL pulled Low, SDA Low
          // ------------------------------------------------------------------
          ST_START_2: begin
            timer_run <= 1'b1;
            if (phase_end_pulse) begin
              timer_reset <= 1'b1;
              if (latched_cmd_read) begin
                state_q <= ST_RX_BYTE;
                bit_cnt <= 3'd7;
              end else begin
                state_q      <= ST_TX_BYTE;
                bit_cnt      <= 3'd7;
                tx_shift_reg <= latched_data;
              end
            end
          end

          // ------------------------------------------------------------------
          // RESTART_1: SCL Low, SDA released High
          // ------------------------------------------------------------------
          ST_RESTART_1: begin
            timer_run <= 1'b1;
            if (phase_end_pulse) begin
              state_q <= ST_RESTART_2;
            end
          end

          // ------------------------------------------------------------------
          // RESTART_2: SCL released High, SDA High
          // ------------------------------------------------------------------
          ST_RESTART_2: begin
            timer_run <= 1'b1;
            if (phase_end_pulse) begin
              state_q <= ST_START_1;
            end
          end

          // ------------------------------------------------------------------
          // TX_BYTE: Shift out 8 bits MSB first
          // ------------------------------------------------------------------
          ST_TX_BYTE: begin
            timer_run <= 1'b1;
            if (bit_end_pulse) begin
              if (bit_cnt == 3'd0) begin
                state_q <= ST_RX_ACK;
              end else begin
                bit_cnt      <= bit_cnt - 1'b1;
                tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
              end
            end
          end

          // ------------------------------------------------------------------
          // RX_ACK: Receive ACK/NACK bit from Slave
          // ------------------------------------------------------------------
          ST_RX_ACK: begin
            timer_run <= 1'b1;
            // Sample ACK/NACK at PH_HIGH end
            if ((timing_phase == PH_HIGH) && phase_end_pulse) begin
              nack_sample <= sda_filtered;
            end

            if (bit_end_pulse) begin
              if (nack_sample) begin
                // NACK received from Slave
                nack_received_pulse <= 1'b1;
                if (latched_cmd_stop) begin
                  state_q <= ST_STOP_1;
                end else begin
                  // Auto-abort on NACK with STOP
                  state_q <= ST_STOP_1;
                end
              end else if (latched_cmd_stop) begin
                state_q <= ST_STOP_1;
              end else if (!tx_fifo_empty) begin
                // Chain next transaction
                latched_data      <= tx_fifo_dout[7:0];
                latched_cmd_start <= tx_fifo_dout[CMD_START_BIT];
                latched_cmd_stop  <= tx_fifo_dout[CMD_STOP_BIT];
                latched_cmd_read  <= tx_fifo_dout[CMD_READ_BIT];
                latched_cmd_nack  <= tx_fifo_dout[CMD_NACK_BIT];
                tx_fifo_rd_en     <= 1'b1;

                if (tx_fifo_dout[CMD_START_BIT]) begin
                  state_q <= ST_RESTART_1;
                end else if (tx_fifo_dout[CMD_READ_BIT]) begin
                  state_q <= ST_RX_BYTE;
                  bit_cnt <= 3'd7;
                end else begin
                  state_q      <= ST_TX_BYTE;
                  bit_cnt      <= 3'd7;
                  tx_shift_reg <= tx_fifo_dout[7:0];
                end
              end else begin
                // No STOP requested, but TX FIFO is empty: hold SCL Low until next byte is ready
                state_q   <= ST_HOLD;
                timer_run <= 1'b0;
              end
            end
          end

          // ------------------------------------------------------------------
          // RX_BYTE: Receive 8 bits MSB first
          // ------------------------------------------------------------------
          ST_RX_BYTE: begin
            timer_run <= 1'b1;
            // Sample bit in PH_HIGH
            if ((timing_phase == PH_HIGH) && phase_end_pulse) begin
              rx_shift_reg <= {rx_shift_reg[6:0], sda_filtered};
            end

            if (bit_end_pulse) begin
              if (bit_cnt == 3'd0) begin
                // Push received byte into RX FIFO
                rx_fifo_wr_en <= 1'b1;
                rx_fifo_din   <= rx_shift_reg;
                state_q       <= ST_TX_ACK;
              end else begin
                bit_cnt <= bit_cnt - 1'b1;
              end
            end
          end

          // ------------------------------------------------------------------
          // TX_ACK: Master drives ACK (0) or NACK (1) to Slave
          // ------------------------------------------------------------------
          ST_TX_ACK: begin
            timer_run <= 1'b1;
            if (bit_end_pulse) begin
              if (latched_cmd_stop) begin
                state_q <= ST_STOP_1;
              end else if (!tx_fifo_empty) begin
                latched_data      <= tx_fifo_dout[7:0];
                latched_cmd_start <= tx_fifo_dout[CMD_START_BIT];
                latched_cmd_stop  <= tx_fifo_dout[CMD_STOP_BIT];
                latched_cmd_read  <= tx_fifo_dout[CMD_READ_BIT];
                latched_cmd_nack  <= tx_fifo_dout[CMD_NACK_BIT];
                tx_fifo_rd_en     <= 1'b1;

                if (tx_fifo_dout[CMD_START_BIT]) begin
                  state_q <= ST_RESTART_1;
                end else if (tx_fifo_dout[CMD_READ_BIT]) begin
                  state_q <= ST_RX_BYTE;
                  bit_cnt <= 3'd7;
                end else begin
                  state_q      <= ST_TX_BYTE;
                  bit_cnt      <= 3'd7;
                  tx_shift_reg <= tx_fifo_dout[7:0];
                end
              end else begin
                // No STOP requested, but TX FIFO is empty: hold SCL Low until next byte is ready
                state_q   <= ST_HOLD;
                timer_run <= 1'b0;
              end
            end
          end

          // ------------------------------------------------------------------
          // HOLD: Master holds SCL Low between bytes until TX FIFO has data
          // ------------------------------------------------------------------
          ST_HOLD: begin
            timer_run <= 1'b0;
            if (!tx_fifo_empty) begin
              latched_data      <= tx_fifo_dout[7:0];
              latched_cmd_start <= tx_fifo_dout[CMD_START_BIT];
              latched_cmd_stop  <= tx_fifo_dout[CMD_STOP_BIT];
              latched_cmd_read  <= tx_fifo_dout[CMD_READ_BIT];
              latched_cmd_nack  <= tx_fifo_dout[CMD_NACK_BIT];
              tx_fifo_rd_en     <= 1'b1;

              timer_run   <= 1'b1;
              timer_reset <= 1'b1;

              if (tx_fifo_dout[CMD_START_BIT]) begin
                state_q <= ST_RESTART_1;
              end else if (tx_fifo_dout[CMD_READ_BIT]) begin
                state_q <= ST_RX_BYTE;
                bit_cnt <= 3'd7;
              end else begin
                state_q      <= ST_TX_BYTE;
                bit_cnt      <= 3'd7;
                tx_shift_reg <= tx_fifo_dout[7:0];
              end
            end
          end

          // ------------------------------------------------------------------
          // STOP_1: SCL Low, SDA Low
          // ------------------------------------------------------------------
          ST_STOP_1: begin
            timer_run <= 1'b1;
            if (phase_end_pulse) begin
              state_q <= ST_STOP_2;
            end
          end

          // ------------------------------------------------------------------
          // STOP_2: SCL High, SDA rises Low -> High (STOP condition)
          // ------------------------------------------------------------------
          ST_STOP_2: begin
            timer_run <= 1'b1;
            if (bit_end_pulse) begin
              transaction_done_pulse <= 1'b1;
              state_q                <= ST_IDLE;
              timer_run              <= 1'b0;
            end
          end

          // ------------------------------------------------------------------
          // RECOVERY: 9 SCL Clock Pulses to unfreeze stuck slave
          // ------------------------------------------------------------------
          ST_RECOVERY: begin
            timer_run <= 1'b1;
            if (bit_end_pulse) begin
              if (recovery_cnt >= 4'd8) begin
                state_q <= ST_STOP_1;
              end else begin
                recovery_cnt <= recovery_cnt + 1'b1;
              end
            end
          end

          // ------------------------------------------------------------------
          // ARB_LOST: Release bus and return to IDLE
          // ------------------------------------------------------------------
          ST_ARB_LOST: begin
            timer_run <= 1'b0;
            state_q   <= ST_IDLE;
          end

          default: state_q <= ST_IDLE;
        endcase
      end
    end
  end

endmodule
