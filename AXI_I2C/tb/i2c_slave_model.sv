// ============================================================================
// File: i2c_slave_model.sv
// Description: Behavioral Model of I2C Slave / EEPROM Device
// Project: AXI_I2C
// ============================================================================

module i2c_slave_model #(
  parameter logic [6:0] SLAVE_ADDR = 7'h50,
  parameter int         MEM_SIZE   = 256
)(
  input  logic        clk,
  input  logic        rst_n,

  // External Bus Lines
  input  logic        scl_i,
  output logic        scl_o,
  output logic        scl_oe,

  input  logic        sda_i,
  output logic        sda_o,
  output logic        sda_oe,

  // Fault Injection Controls
  input  logic        force_nack,
  input  logic [15:0] force_stretch_clks
);

  assign scl_o = 1'b0;
  assign sda_o = 1'b0;

  // --------------------------------------------------------------------------
  // Internal Memory Array
  // --------------------------------------------------------------------------
  logic [7:0] mem [0:MEM_SIZE-1];
  logic [7:0] current_reg_addr;

  // --------------------------------------------------------------------------
  // SCL & SDA Edge & Condition Detectors
  // --------------------------------------------------------------------------
  logic [1:0] scl_sync, sda_sync;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      scl_sync <= 2'b11;
      sda_sync <= 2'b11;
    end else begin
      scl_sync <= {scl_sync[0], scl_i};
      sda_sync <= {sda_sync[0], sda_i};
    end
  end

  logic scl_rising, scl_falling, sda_rising, sda_falling;
  assign scl_rising  = (!scl_sync[1] && scl_sync[0]);
  assign scl_falling = (scl_sync[1] && !scl_sync[0]);
  assign sda_rising  = (!sda_sync[1] && sda_sync[0]);
  assign sda_falling = (sda_sync[1] && !sda_sync[0]);

  logic start_cond, stop_cond;
  assign start_cond = sda_falling && (scl_sync == 2'b11);
  assign stop_cond  = sda_rising  && (scl_sync == 2'b11);

  // --------------------------------------------------------------------------
  // Slave State Machine
  // --------------------------------------------------------------------------
  typedef enum logic [3:0] {
    SLV_IDLE,
    SLV_RX_ADDR,
    SLV_ACK_ADDR,
    SLV_RX_REG_ADDR,
    SLV_ACK_REG_ADDR,
    SLV_RX_DATA,
    SLV_ACK_DATA,
    SLV_TX_DATA,
    SLV_RX_ACK_FROM_MTR
  } slv_state_t;

  slv_state_t state;
  logic [2:0]  bit_idx;
  logic [7:0]  shift_in;
  logic [7:0]  shift_out;
  logic        rw_bit;
  logic        addr_matched;
  logic [15:0] stretch_cnt;
  logic        is_stretching;
  logic        start_wait_scl_low;
  logic        bit_sampled;

  // Clock stretching control
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      scl_oe        <= 1'b0;
      stretch_cnt   <= 16'd0;
      is_stretching <= 1'b0;
    end else if (force_stretch_clks > 16'd0 && scl_falling && !is_stretching) begin
      scl_oe        <= 1'b1;
      stretch_cnt   <= 16'd0;
      is_stretching <= 1'b1;
    end else if (is_stretching) begin
      if (stretch_cnt >= force_stretch_clks) begin
        scl_oe        <= 1'b0;
        is_stretching <= 1'b0;
      end else begin
        stretch_cnt <= stretch_cnt + 1'b1;
      end
    end
  end

  // Pre-initialize memory array
  initial begin
    for (int i = 0; i < MEM_SIZE; i++) begin
      mem[i] = 8'(i ^ 32'hA5);
    end
  end

  // Slave Core Sequential Logic
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state              <= SLV_IDLE;
      bit_idx            <= 3'd7;
      shift_in           <= 8'd0;
      shift_out          <= 8'd0;
      rw_bit             <= 1'b0;
      addr_matched       <= 1'b0;
      current_reg_addr   <= 8'd0;
      sda_oe             <= 1'b0;
      bit_sampled        <= 1'b0;
      start_wait_scl_low <= 1'b0;
    end else begin
      // START Condition overrides any ongoing transaction
      if (start_cond) begin
        state              <= SLV_RX_ADDR;
        bit_idx            <= 3'd7;
        sda_oe             <= 1'b0;
        addr_matched       <= 1'b0;
        bit_sampled        <= 1'b0;
        start_wait_scl_low <= 1'b1; // Must wait for SCL to go low to finish START
      end else if (stop_cond) begin
        state              <= SLV_IDLE;
        sda_oe             <= 1'b0;
        bit_sampled        <= 1'b0;
        start_wait_scl_low <= 1'b0;
      end else begin
        case (state)
          SLV_IDLE: begin
            sda_oe             <= 1'b0;
            bit_idx            <= 3'd7;
            bit_sampled        <= 1'b0;
            start_wait_scl_low <= 1'b0;
          end

          // Receive 7-bit Device Address + 1-bit R/W
          SLV_RX_ADDR: begin
            if (start_wait_scl_low) begin
              if (scl_falling) begin
                start_wait_scl_low <= 1'b0;
              end
            end else begin
              if (scl_rising) begin
                shift_in[bit_idx] <= sda_sync[1];
                bit_sampled       <= 1'b1;
              end
              if (scl_falling && bit_sampled) begin
                bit_sampled <= 1'b0;
                if (bit_idx == 3'd0) begin
                  state        <= SLV_ACK_ADDR;
                  addr_matched <= (shift_in[7:1] == SLAVE_ADDR);
                  rw_bit       <= shift_in[0];
                  // Drive ACK if address matches and not forcing NACK
                  if ((shift_in[7:1] == SLAVE_ADDR) && !force_nack) begin
                    sda_oe <= 1'b1; // ACK (Drive 0)
                  end else begin
                    sda_oe <= 1'b0; // NACK (Release 1)
                  end
                end else begin
                  bit_idx <= bit_idx - 1'b1;
                end
              end
            end
          end

          // ACK phase for device address
          SLV_ACK_ADDR: begin
            if (scl_falling) begin
              sda_oe      <= 1'b0; // Release SDA
              bit_sampled <= 1'b0;
              if (addr_matched && !force_nack) begin
                if (rw_bit == 1'b0) begin
                  // Write mode -> receive register address or data
                  state   <= SLV_RX_REG_ADDR;
                  bit_idx <= 3'd7;
                end else begin
                  // Read mode -> transmit data from current register address
                  state     <= SLV_TX_DATA;
                  shift_out <= mem[current_reg_addr];
                  bit_idx   <= 3'd7;
                  // Pre-drive first bit
                  sda_oe    <= (mem[current_reg_addr][7] == 1'b0);
                end
              end else begin
                state <= SLV_IDLE;
              end
            end
          end

          // Receive Register Sub-Address
          SLV_RX_REG_ADDR: begin
            if (scl_rising) begin
              shift_in[bit_idx] <= sda_sync[1];
              bit_sampled       <= 1'b1;
            end
            if (scl_falling && bit_sampled) begin
              bit_sampled <= 1'b0;
              if (bit_idx == 3'd0) begin
                current_reg_addr <= shift_in;
                state            <= SLV_ACK_REG_ADDR;
                sda_oe           <= 1'b1; // Send ACK
              end else begin
                bit_idx <= bit_idx - 1'b1;
              end
            end
          end

          // ACK phase for Register Address
          SLV_ACK_REG_ADDR: begin
            if (scl_falling) begin
              sda_oe      <= 1'b0;
              state       <= SLV_RX_DATA;
              bit_idx     <= 3'd7;
              bit_sampled <= 1'b0;
            end
          end

          // Receive Data Byte from Master Write
          SLV_RX_DATA: begin
            if (scl_rising) begin
              shift_in[bit_idx] <= sda_sync[1];
              bit_sampled       <= 1'b1;
            end
            if (scl_falling && bit_sampled) begin
              bit_sampled <= 1'b0;
              if (bit_idx == 3'd0) begin
                mem[current_reg_addr] <= shift_in;
                current_reg_addr      <= current_reg_addr + 1'b1;
                state                 <= SLV_ACK_DATA;
                sda_oe                <= 1'b1; // Send ACK
              end else begin
                bit_idx <= bit_idx - 1'b1;
              end
            end
          end

          // ACK phase for Data Byte
          SLV_ACK_DATA: begin
            if (scl_falling) begin
              sda_oe      <= 1'b0;
              state       <= SLV_RX_DATA; // Ready for next byte or STOP
              bit_idx     <= 3'd7;
              bit_sampled <= 1'b0;
            end
          end

          // Transmit Data Byte to Master Read
          SLV_TX_DATA: begin
            if (scl_falling) begin
              if (bit_idx == 3'd0) begin
                state   <= SLV_RX_ACK_FROM_MTR;
                sda_oe  <= 1'b0; // Release SDA to let master ACK/NACK
                current_reg_addr <= current_reg_addr + 1'b1;
              end else begin
                bit_idx   <= bit_idx - 1'b1;
                sda_oe    <= (shift_out[bit_idx - 1'b1] == 1'b0);
              end
            end
          end

          // Sample ACK/NACK from Master
          SLV_RX_ACK_FROM_MTR: begin
            if (scl_rising) begin
              // Master drives SDA: 0 = ACK (continue reading), 1 = NACK (done)
              if (sda_sync[1] == 1'b0) begin
                // ACK received -> prepare next byte
                shift_out <= mem[current_reg_addr];
                bit_idx   <= 3'd7;
              end
            end
            if (scl_falling) begin
              if (sda_sync[1] == 1'b0) begin
                state  <= SLV_TX_DATA;
                sda_oe <= (shift_out[7] == 1'b0);
              end else begin
                // NACK received -> wait for STOP
                state  <= SLV_IDLE;
                sda_oe <= 1'b0;
              end
            end
          end

          default: state <= SLV_IDLE;
        endcase
      end
    end
  end

endmodule
