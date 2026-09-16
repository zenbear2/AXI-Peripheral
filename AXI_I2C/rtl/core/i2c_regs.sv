// ============================================================================
// File: i2c_regs.sv
// Description: Register File, Interrupt Logic, and FIFO Watermark Status
// Project: AXI_I2C
// ============================================================================

module i2c_regs #(
  parameter int FIFO_DEPTH = 16
)(
  input  logic                            clk,
  input  logic                            rst_n,

  // AXI Register Bus Interface
  input  logic                            reg_wr_en,
  input  logic [5:0]                      reg_wr_addr,
  input  logic [31:0]                     reg_wdata,
  input  logic                            reg_rd_en,
  input  logic [5:0]                      reg_rd_addr,
  output logic [31:0]                     reg_rdata,

  // FIFO Controls & Status
  output logic                            tx_fifo_wr_en,
  output logic [11:0]                     tx_fifo_din,
  output logic                            tx_fifo_flush,
  input  logic                            tx_fifo_full,
  input  logic                            tx_fifo_empty,
  input  logic [$clog2(FIFO_DEPTH+1)-1:0] tx_fifo_count,
  input  logic                            tx_fifo_overflow,

  output logic                            rx_fifo_rd_en,
  input  logic [7:0]                      rx_fifo_dout,
  output logic                            rx_fifo_flush,
  input  logic                            rx_fifo_full,
  input  logic                            rx_fifo_empty,
  input  logic [$clog2(FIFO_DEPTH+1)-1:0] rx_fifo_count,
  input  logic                            rx_fifo_overflow,

  // Hardware Status Inputs from FSM / Bus Monitor / Timing Gen
  input  logic                            fsm_busy,
  input  logic                            bus_busy,
  input  logic                            scl_held,
  input  logic                            nack_received_pulse,
  input  logic                            arb_lost_event_pulse,
  input  logic                            bus_error_pulse,
  input  logic                            timeout_pulse,
  input  logic                            transaction_done_pulse,

  // Register Configuration Outputs
  output logic                            core_enable_o,
  output logic                            global_irq_en_o,
  output logic                            loopback_en_o,
  output logic                            auto_recover_o,
  output logic                            manual_recover_pulse_o,
  output logic                            stretch_en_o,
  output logic [15:0]                     prescale_o,
  output logic [7:0]                      scl_low_extra_o,
  output logic [7:0]                      scl_high_extra_o,
  output logic [7:0]                      filter_cycles_o,
  output logic [15:0]                     timeout_limit_o,

  // IRQ Output
  output logic                            irq_o
);

  import i2c_pkg::*;

  // --------------------------------------------------------------------------
  // Registers
  // --------------------------------------------------------------------------
  logic [31:0] cr_reg;
  logic [15:0] prescale_reg;
  logic [15:0] timing_reg;
  logic [7:0]  filter_reg;
  logic [7:0]  tx_watermark_reg;
  logic [7:0]  rx_watermark_reg;
  logic [8:0]  ier_reg;
  logic [8:0]  isr_reg;
  logic [15:0] timeout_reg;
  logic        nack_sticky_sr;
  logic        manual_recover_pulse;

  // --------------------------------------------------------------------------
  // Configuration Output Mappings
  // --------------------------------------------------------------------------
  assign core_enable_o          = cr_reg[CR_CORE_EN_BIT];
  assign global_irq_en_o        = cr_reg[CR_IRQ_EN_BIT];
  assign loopback_en_o          = cr_reg[CR_LOOPBACK_EN_BIT];
  assign auto_recover_o         = cr_reg[CR_AUTO_RECOVER_BIT];
  assign manual_recover_pulse_o = manual_recover_pulse;
  assign stretch_en_o           = cr_reg[CR_STRETCH_EN_BIT];
  assign prescale_o             = prescale_reg;
  assign scl_low_extra_o        = timing_reg[7:0];
  assign scl_high_extra_o       = timing_reg[15:8];
  assign filter_cycles_o        = filter_reg;
  assign timeout_limit_o        = timeout_reg;

  // --------------------------------------------------------------------------
  // FIFO Write & Read Direct Ports
  // --------------------------------------------------------------------------
  assign tx_fifo_wr_en = reg_wr_en && (reg_wr_addr == OFFSET_TX_CMD);
  assign tx_fifo_din   = reg_wdata[11:0];

  assign rx_fifo_rd_en = reg_rd_en && (reg_rd_addr == OFFSET_RX_DATA) && !rx_fifo_empty;

  // --------------------------------------------------------------------------
  // Register Read Decoding
  // --------------------------------------------------------------------------
  always_comb begin
    case (reg_rd_addr)
      OFFSET_CR: begin
        reg_rdata = cr_reg;
      end
      OFFSET_SR: begin
        reg_rdata = 32'd0;
        reg_rdata[SR_BUSY_BIT]      = fsm_busy;
        reg_rdata[SR_BUS_BUSY_BIT]  = bus_busy;
        reg_rdata[SR_TX_EMPTY_BIT]  = tx_fifo_empty;
        reg_rdata[SR_TX_FULL_BIT]   = tx_fifo_full;
        reg_rdata[SR_RX_EMPTY_BIT]  = rx_fifo_empty;
        reg_rdata[SR_RX_FULL_BIT]   = rx_fifo_full;
        reg_rdata[SR_NACK_RECV_BIT] = nack_sticky_sr;
        reg_rdata[SR_ARB_LOST_BIT]  = isr_reg[INTR_ARB_LOST_BIT];
        reg_rdata[SR_SCL_HELD_BIT]  = scl_held;
        reg_rdata[SR_BUS_ERROR_BIT] = isr_reg[INTR_BUS_ERROR_BIT];
      end
      OFFSET_TX_CMD: begin
        reg_rdata = 32'd0;
      end
      OFFSET_RX_DATA: begin
        reg_rdata = {24'd0, rx_fifo_dout};
      end
      OFFSET_PRESCALE: begin
        reg_rdata = {16'd0, prescale_reg};
      end
      OFFSET_TIMING: begin
        reg_rdata = {16'd0, timing_reg};
      end
      OFFSET_FILTER: begin
        reg_rdata = {24'd0, filter_reg};
      end
      OFFSET_FIFO_CTRL: begin
        reg_rdata = {8'd0, rx_watermark_reg, tx_watermark_reg, 8'd0};
      end
      OFFSET_FIFO_STAT: begin
        reg_rdata = {rx_watermark_reg, tx_watermark_reg, 8'(rx_fifo_count), 8'(tx_fifo_count)};
      end
      OFFSET_IER: begin
        reg_rdata = {23'd0, ier_reg};
      end
      OFFSET_ISR: begin
        reg_rdata = {23'd0, isr_reg};
      end
      OFFSET_TIMEOUT: begin
        reg_rdata = {16'd0, timeout_reg};
      end
      default: reg_rdata = 32'd0;
    endcase
  end

  // --------------------------------------------------------------------------
  // Register Write Logic & Hardware Interrupt Management
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cr_reg               <= 32'h0000_0021; // Default CORE_EN=1, STRETCH_EN=1
      prescale_reg         <= DEFAULT_PRESCALE;
      timing_reg           <= DEFAULT_TIMING;
      filter_reg           <= DEFAULT_FILTER;
      tx_watermark_reg     <= 8'd4;
      rx_watermark_reg     <= 8'd4;
      ier_reg              <= 9'd0;
      isr_reg              <= 9'd0;
      timeout_reg          <= DEFAULT_TIMEOUT;
      nack_sticky_sr       <= 1'b0;
      manual_recover_pulse <= 1'b0;
      tx_fifo_flush        <= 1'b0;
      rx_fifo_flush        <= 1'b0;
    end else begin
      manual_recover_pulse <= 1'b0;
      tx_fifo_flush        <= 1'b0;
      rx_fifo_flush        <= 1'b0;

      // ----------------------------------------------------------------------
      // Hardware-Asserted Interrupts & Status
      // ----------------------------------------------------------------------
      // TX Watermark: TX Count <= Watermark
      if (8'(tx_fifo_count) <= tx_watermark_reg) begin
        isr_reg[INTR_TX_WATERMARK_BIT] <= 1'b1;
      end else begin
        isr_reg[INTR_TX_WATERMARK_BIT] <= 1'b0;
      end

      // RX Watermark: RX Count >= Watermark
      if ((8'(rx_fifo_count) >= rx_watermark_reg) && (rx_watermark_reg > 8'd0)) begin
        isr_reg[INTR_RX_WATERMARK_BIT] <= 1'b1;
      end else begin
        isr_reg[INTR_RX_WATERMARK_BIT] <= 1'b0;
      end

      // TX Empty: FIFO empty and FSM idle
      if (tx_fifo_empty && !fsm_busy) begin
        isr_reg[INTR_TX_EMPTY_BIT] <= 1'b1;
      end else begin
        isr_reg[INTR_TX_EMPTY_BIT] <= 1'b0;
      end

      // Event-based Interrupts
      if (rx_fifo_overflow || tx_fifo_overflow || rx_fifo_full) begin
        isr_reg[INTR_RX_FULL_BIT] <= 1'b1;
      end

      if (transaction_done_pulse) begin
        isr_reg[INTR_DONE_BIT] <= 1'b1;
      end

      if (nack_received_pulse) begin
        isr_reg[INTR_NACK_BIT] <= 1'b1;
        nack_sticky_sr         <= 1'b1;
      end

      if (arb_lost_event_pulse) begin
        isr_reg[INTR_ARB_LOST_BIT] <= 1'b1;
      end

      if (bus_error_pulse) begin
        isr_reg[INTR_BUS_ERROR_BIT] <= 1'b1;
      end

      if (timeout_pulse) begin
        isr_reg[INTR_TIMEOUT_BIT] <= 1'b1;
      end

      // ----------------------------------------------------------------------
      // AXI Register Write Handlers
      // ----------------------------------------------------------------------
      if (reg_wr_en) begin
        case (reg_wr_addr)
          OFFSET_CR: begin
            cr_reg <= reg_wdata;
            if (reg_wdata[CR_MANUAL_RECOVER_BIT]) begin
              manual_recover_pulse <= 1'b1;
            end
          end

          OFFSET_PRESCALE: begin
            prescale_reg <= reg_wdata[15:0];
          end

          OFFSET_TIMING: begin
            timing_reg <= reg_wdata[15:0];
          end

          OFFSET_FILTER: begin
            filter_reg <= reg_wdata[7:0];
          end

          OFFSET_FIFO_CTRL: begin
            if (reg_wdata[0]) tx_fifo_flush <= 1'b1;
            if (reg_wdata[1]) rx_fifo_flush <= 1'b1;
            tx_watermark_reg <= reg_wdata[15:8];
            rx_watermark_reg <= reg_wdata[23:16];
          end

          OFFSET_IER: begin
            ier_reg <= reg_wdata[8:0];
          end

          OFFSET_ISR: begin
            // Write-1-to-Clear for event bits
            if (reg_wdata[INTR_RX_FULL_BIT])   isr_reg[INTR_RX_FULL_BIT]   <= 1'b0;
            if (reg_wdata[INTR_DONE_BIT])      isr_reg[INTR_DONE_BIT]      <= 1'b0;
            if (reg_wdata[INTR_NACK_BIT]) begin
              isr_reg[INTR_NACK_BIT] <= 1'b0;
              nack_sticky_sr         <= 1'b0;
            end
            if (reg_wdata[INTR_ARB_LOST_BIT])  isr_reg[INTR_ARB_LOST_BIT]  <= 1'b0;
            if (reg_wdata[INTR_BUS_ERROR_BIT]) isr_reg[INTR_BUS_ERROR_BIT] <= 1'b0;
            if (reg_wdata[INTR_TIMEOUT_BIT])   isr_reg[INTR_TIMEOUT_BIT]   <= 1'b0;
          end

          OFFSET_TIMEOUT: begin
            timeout_reg <= reg_wdata[15:0];
          end

          default: ;
        endcase
      end
    end
  end

  // --------------------------------------------------------------------------
  // Global IRQ Line Generation
  // --------------------------------------------------------------------------
  assign irq_o = cr_reg[CR_IRQ_EN_BIT] && (|(isr_reg & ier_reg));

endmodule
