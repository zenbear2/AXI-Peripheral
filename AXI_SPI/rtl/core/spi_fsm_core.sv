// ============================================================================
// File: spi_fsm_core.sv
// Description: SPI Master Protocol FSM, Serializer/Deserializer & Mode Controller
// Project: AXI_SPI
// ============================================================================

module spi_fsm_core import spi_pkg::*; (
  input  logic                  clk,
  input  logic                  rst_n,

  // Control & Configuration
  input  logic                  core_en,
  input  logic                  cpol,
  input  logic                  cpha,
  input  logic                  lsb_first,
  input  logic                  rx_dis,
  input  logic                  tx_dis,
  input  logic                  loopback_en,
  input  logic [5:0]            data_bits,
  input  logic [NUM_SLAVES-1:0] cs_pol,

  /* verilator lint_off UNUSED */
  // Chip Select Configuration
  input  logic                  cs_auto_en,
  input  logic [1:0]            cs_sel,
  input  logic [NUM_SLAVES-1:0] manual_ss,
  input  logic                  keep_cs_default,
  /* verilator lint_on UNUSED */

  // Programmable Delays
  input  logic [7:0]            t_css,
  input  logic [7:0]            t_csh,
  input  logic [15:0]           t_idle,

  // Timing Generator Interface
  output logic                  timing_enable,
  input  logic                  tick_half,

  // TX FIFO Interface
  input  logic                  tx_fifo_empty,
  input  logic [35:0]           tx_fifo_dout, // [35]=keep_cs, [34:33]=cs_sel, [32]=rx_dis, [31:0]=data
  output logic                  tx_fifo_rd_en,

  // RX FIFO Interface
  input  logic                  rx_fifo_full,
  output logic [31:0]           rx_fifo_din,
  output logic                  rx_fifo_wr_en,
  output logic                  rx_overrun_pulse,

  // Status & Event Pulses
  output logic                  busy,
  output logic                  ss_active,
  output logic                  xfer_done_pulse,
  output logic                  tx_underrun_pulse,
  output logic [2:0]            fsm_state_out,

  // Physical SPI Interface
  output logic                  sck,
  output logic                  mosi,
  input  logic                  miso,
  output logic [NUM_SLAVES-1:0] ss_n
);

  // Clamped Word Length (4 to 32 bits)
  logic [5:0] word_len;
  assign word_len = (data_bits < 6'd4)  ? 6'd4  :
                    (data_bits > 6'd32) ? 6'd32 : data_bits;

  // FSM State Register
  spi_fsm_state_t state;
  assign fsm_state_out = state;

  // Internal Registers
  logic [31:0] tx_data_reg;
  logic [31:0] rx_accum;
  logic        curr_keep_cs;
  logic [1:0]  curr_cs_sel;
  logic        curr_rx_dis;
  logic [5:0]  bit_count;
  logic        phase;
  logic [15:0] delay_cnt;
  logic        fsm_cs_active;
  logic        sck_reg;
  logic        mosi_reg;
  logic        push_rx_pending;

  // Effective MISO input (Loopback mux)
  logic eff_miso;
  assign eff_miso = loopback_en ? mosi_reg : miso;

  // Helper for bit position
  function automatic logic [4:0] get_bit_pos(input int k, input logic lsb_f, input int len);
    if (lsb_f) begin
      return 5'(k);
    end else begin
      return 5'(len - 1 - k);
    end
  endfunction

  // --------------------------------------------------------------------------
  // Output Port Assignments
  // --------------------------------------------------------------------------
  assign sck = sck_reg;
  assign mosi = tx_dis ? 1'b1 : mosi_reg;
  assign rx_fifo_din = rx_accum;

  // Chip Select Output Generation
  logic [NUM_SLAVES-1:0] ss_auto_val;
  always_comb begin
    for (int i = 0; i < NUM_SLAVES; i++) begin
      logic is_selected;
      is_selected = fsm_cs_active && (curr_cs_sel == 2'(i));
      // If cs_pol[i]=1 (active-high): output 1 when selected, 0 when idle
      // If cs_pol[i]=0 (active-low):  output 0 when selected, 1 when idle
      ss_auto_val[i] = cs_pol[i] ? is_selected : ~is_selected;
    end
  end

  assign ss_n = cs_auto_en ? ss_auto_val : manual_ss;
  assign ss_active = fsm_cs_active;
  assign busy = (state != ST_IDLE) || !tx_fifo_empty;

  // --------------------------------------------------------------------------
  // Sequential FSM & Datapath
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state             <= ST_IDLE;
      sck_reg           <= 1'b0;
      mosi_reg          <= 1'b1;
      tx_data_reg       <= 32'd0;
      rx_accum          <= 32'd0;
      curr_keep_cs      <= 1'b0;
      curr_cs_sel       <= 2'd0;
      curr_rx_dis       <= 1'b0;
      bit_count         <= 6'd0;
      phase             <= 1'b0;
      delay_cnt         <= 16'd0;
      fsm_cs_active     <= 1'b0;
      timing_enable     <= 1'b0;
      tx_fifo_rd_en     <= 1'b0;
      rx_fifo_wr_en     <= 1'b0;
      rx_overrun_pulse  <= 1'b0;
      xfer_done_pulse   <= 1'b0;
      tx_underrun_pulse <= 1'b0;
      push_rx_pending   <= 1'b0;
    end else if (!core_en) begin
      state             <= ST_IDLE;
      sck_reg           <= cpol;
      mosi_reg          <= 1'b1;
      tx_data_reg       <= 32'd0;
      rx_accum          <= 32'd0;
      curr_keep_cs      <= 1'b0;
      curr_cs_sel       <= 2'd0;
      curr_rx_dis       <= 1'b0;
      bit_count         <= 6'd0;
      phase             <= 1'b0;
      delay_cnt         <= 16'd0;
      fsm_cs_active     <= 1'b0;
      timing_enable     <= 1'b0;
      tx_fifo_rd_en     <= 1'b0;
      rx_fifo_wr_en     <= 1'b0;
      rx_overrun_pulse  <= 1'b0;
      xfer_done_pulse   <= 1'b0;
      tx_underrun_pulse <= 1'b0;
      push_rx_pending   <= 1'b0;
    end else begin
      // Defaults
      tx_fifo_rd_en     <= 1'b0;
      rx_fifo_wr_en     <= 1'b0;
      rx_overrun_pulse  <= 1'b0;
      xfer_done_pulse   <= 1'b0;
      tx_underrun_pulse <= 1'b0;

      case (state)
        // --------------------------------------------------------------------
        // ST_IDLE: Wait for data in TX FIFO
        // --------------------------------------------------------------------
        ST_IDLE: begin
          sck_reg         <= cpol;
          timing_enable   <= 1'b0;
          fsm_cs_active   <= 1'b0;
          phase           <= 1'b0;
          bit_count       <= 6'd0;
          push_rx_pending <= 1'b0;

          if (!tx_fifo_empty) begin
            // Fetch first word
            tx_fifo_rd_en <= 1'b1;
            tx_data_reg   <= tx_fifo_dout[31:0];
            curr_keep_cs  <= tx_fifo_dout[35];
            curr_cs_sel   <= tx_fifo_dout[34:33];
            curr_rx_dis   <= tx_fifo_dout[32];
            rx_accum      <= 32'd0;

            // Activate CS and timing generator
            fsm_cs_active <= 1'b1;
            timing_enable <= 1'b1;
            delay_cnt     <= (t_css == 8'd0) ? 16'd1 : 16'(t_css);

            // Pre-drive MOSI if CPHA == 0
            if (!cpha) begin
              logic [4:0] bpos;
              bpos = get_bit_pos(0, lsb_first, int'(word_len));
              mosi_reg <= tx_fifo_dout[bpos];
            end

            state <= ST_CS_SETUP;
          end
        end

        // --------------------------------------------------------------------
        // ST_CS_SETUP: Wait for T_CSS Setup Time
        // --------------------------------------------------------------------
        ST_CS_SETUP: begin
          sck_reg       <= cpol;
          timing_enable <= 1'b1;

          if (tick_half) begin
            if (delay_cnt <= 16'd1) begin
              bit_count <= 6'd0;
              phase     <= 1'b0;
              state     <= ST_TRANSFER;
            end else begin
              delay_cnt <= delay_cnt - 16'd1;
            end
          end
        end

        // --------------------------------------------------------------------
        // ST_TRANSFER: Bit Serialization & Deserialization
        // --------------------------------------------------------------------
        ST_TRANSFER: begin
          timing_enable <= 1'b1;

          if (tick_half) begin
            int cur_bit_idx;
            cur_bit_idx = int'(bit_count);

            if (phase == 1'b0) begin
              // Leading Edge (SCK = ~cpol)
              sck_reg <= ~cpol;
              phase   <= 1'b1;

              if (!cpha) begin
                // CPHA=0: Sample MISO on Leading Edge
                logic [4:0] bpos;
                bpos = get_bit_pos(cur_bit_idx, lsb_first, int'(word_len));
                rx_accum[bpos] <= eff_miso;
              end else begin
                // CPHA=1: Shift MOSI on Leading Edge
                logic [4:0] bpos;
                bpos = get_bit_pos(cur_bit_idx, lsb_first, int'(word_len));
                mosi_reg <= tx_data_reg[bpos];
              end

            end else begin
              // Trailing Edge (SCK = cpol)
              sck_reg <= cpol;
              phase   <= 1'b0;

              if (!cpha) begin
                // CPHA=0: Shift next bit onto MOSI on Trailing Edge
                if (cur_bit_idx < int'(word_len) - 1) begin
                  logic [4:0] next_bpos;
                  next_bpos = get_bit_pos(cur_bit_idx + 1, lsb_first, int'(word_len));
                  mosi_reg <= tx_data_reg[next_bpos];
                end
              end else begin
                // CPHA=1: Sample MISO on Trailing Edge
                logic [4:0] bpos;
                bpos = get_bit_pos(cur_bit_idx, lsb_first, int'(word_len));
                rx_accum[bpos] <= eff_miso;
              end

              // Advance bit counter or finish frame
              if (cur_bit_idx >= int'(word_len) - 1) begin
                // Word transfer complete! Flag pending RX FIFO push
                if (!curr_rx_dis && !rx_dis) begin
                  push_rx_pending <= 1'b1;
                end

                delay_cnt <= (t_csh == 8'd0) ? 16'd1 : 16'(t_csh);
                state     <= ST_CS_HOLD;
              end else begin
                bit_count <= bit_count + 6'd1;
              end
            end
          end
        end

        // --------------------------------------------------------------------
        // ST_CS_HOLD: Wait for T_CSH Hold Time & Write RX Data to FIFO
        // --------------------------------------------------------------------
        ST_CS_HOLD: begin
          sck_reg       <= cpol;
          timing_enable <= 1'b1;

          // Push completed RX word to RX FIFO on the first cycle of ST_CS_HOLD
          if (push_rx_pending) begin
            push_rx_pending <= 1'b0;
            if (rx_fifo_full) begin
              rx_overrun_pulse <= 1'b1;
            end else begin
              rx_fifo_wr_en <= 1'b1;
            end
          end

          if (tick_half) begin
            if (delay_cnt <= 16'd1) begin
              state <= ST_INTER_FRAME;
            end else begin
              delay_cnt <= delay_cnt - 16'd1;
            end
          end
        end

        // --------------------------------------------------------------------
        // ST_INTER_FRAME: Decide whether to continue burst or release CS
        // --------------------------------------------------------------------
        ST_INTER_FRAME: begin
          sck_reg <= cpol;

          if (!tx_fifo_empty && (tx_fifo_dout[34:33] == curr_cs_sel)) begin
            // Next word is for the same slave -> Continuous Burst!
            tx_fifo_rd_en <= 1'b1;
            tx_data_reg   <= tx_fifo_dout[31:0];
            curr_keep_cs  <= tx_fifo_dout[35];
            curr_cs_sel   <= tx_fifo_dout[34:33];
            curr_rx_dis   <= tx_fifo_dout[32];
            rx_accum      <= 32'd0;

            bit_count     <= 6'd0;
            phase         <= 1'b0;

            if (!cpha) begin
              logic [4:0] bpos;
              bpos = get_bit_pos(0, lsb_first, int'(word_len));
              mosi_reg <= tx_fifo_dout[bpos];
            end

            state <= ST_TRANSFER;
          end else if (curr_keep_cs && tx_fifo_empty) begin
            // KEEP_CS requested, wait for next word while holding CS
            timing_enable <= 1'b0;
          end else begin
            // End of transaction: Release CS and enter Idle Delay
            fsm_cs_active <= 1'b0;
            timing_enable <= 1'b1;
            delay_cnt     <= (t_idle == 16'd0) ? 16'd1 : t_idle;
            state         <= ST_CS_IDLE;
          end
        end

        // --------------------------------------------------------------------
        // ST_CS_IDLE: Wait for T_IDLE before accepting next independent transaction
        // --------------------------------------------------------------------
        ST_CS_IDLE: begin
          sck_reg       <= cpol;
          fsm_cs_active <= 1'b0;
          timing_enable <= 1'b1;

          if (tick_half) begin
            if (delay_cnt <= 16'd1) begin
              timing_enable   <= 1'b0;
              xfer_done_pulse <= 1'b1;
              state           <= ST_IDLE;
            end else begin
              delay_cnt <= delay_cnt - 16'd1;
            end
          end
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

endmodule
