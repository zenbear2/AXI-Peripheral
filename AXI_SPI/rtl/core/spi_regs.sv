// ============================================================================
// File: spi_regs.sv
// Description: SPI Memory-Mapped Register File, FIFO Management & Interrupts
// Project: AXI_SPI
// ============================================================================

module spi_regs import spi_pkg::*; #(
  parameter int FIFO_DEPTH = 16
)(
  input  logic                  clk,
  input  logic                  rst_n,

  // Local Register Access Interface
  input  logic                  reg_wr_en,
  input  logic [5:0]            reg_wr_addr,
  input  logic [31:0]           reg_wdata,
  /* verilator lint_off UNUSED */
  input  logic [3:0]            reg_wstrb,
  /* verilator lint_on UNUSED */

  input  logic                  reg_rd_en,
  input  logic [5:0]            reg_rd_addr,
  output logic [31:0]           reg_rdata,

  // Hardware Configuration & Control Outputs
  output logic                  core_en,
  output logic                  irq_en,
  output logic                  loopback_en,
  output logic                  cpol,
  output logic                  cpha,
  output logic                  lsb_first,
  output logic                  rx_dis,
  output logic                  tx_dis,

  output logic [15:0]           prescale,
  output logic [5:0]            data_bits,
  output logic [NUM_SLAVES-1:0] cs_pol,

  output logic                  cs_auto_en,
  output logic [1:0]            cs_sel,
  output logic [NUM_SLAVES-1:0] manual_ss,
  output logic                  keep_cs_default,

  output logic [7:0]            t_css,
  output logic [7:0]            t_csh,
  output logic [15:0]           t_idle,

  output logic [5:0]            tx_wm,
  output logic [5:0]            rx_wm,
  output logic                  tx_fifo_flush,
  output logic                  rx_fifo_flush,

  // FIFO Port Connections
  output logic                  tx_fifo_wr_en,
  output logic [35:0]           tx_fifo_din,
  input  logic                  tx_fifo_full,
  input  logic                  tx_fifo_empty,
  input  logic [$clog2(FIFO_DEPTH+1)-1:0] tx_fifo_count,

  output logic                  rx_fifo_rd_en,
  input  logic [31:0]           rx_fifo_dout,
  input  logic                  rx_fifo_full,
  input  logic                  rx_fifo_empty,
  input  logic [$clog2(FIFO_DEPTH+1)-1:0] rx_fifo_count,

  // Core Status & Pulses
  input  logic                  busy,
  input  logic                  ss_active,
  input  logic                  xfer_done_pulse,
  input  logic                  rx_overrun_pulse,
  input  logic                  tx_underrun_pulse,

  // Interrupt Line
  output logic                  irq
);

  // --------------------------------------------------------------------------
  // Register Declarations
  // --------------------------------------------------------------------------
  logic [7:0]   reg_cr;
  logic [15:0]  reg_prescale;
  logic [5:0]   reg_data_bits;
  logic [3:0]   reg_cs_pol;
  logic         reg_cs_auto_en;
  logic [1:0]   reg_cs_sel;
  logic [3:0]   reg_manual_ss;
  logic         reg_keep_cs_default;
  logic [7:0]   reg_t_css;
  logic [7:0]   reg_t_csh;
  logic [15:0]  reg_t_idle;
  logic [5:0]   reg_tx_wm;
  logic [5:0]   reg_rx_wm;
  logic [INTR_COUNT-1:0] reg_ier;
  logic [INTR_COUNT-1:0] reg_isr;

  logic rx_overrun_sticky;
  logic tx_underrun_sticky;

  // --------------------------------------------------------------------------
  // Output Signal Drive
  // --------------------------------------------------------------------------
  assign core_en         = reg_cr[CR_CORE_EN_BIT];
  assign irq_en          = reg_cr[CR_IRQ_EN_BIT];
  assign loopback_en     = reg_cr[CR_LOOPBACK_EN_BIT];
  assign cpol            = reg_cr[CR_CPOL_BIT];
  assign cpha            = reg_cr[CR_CPHA_BIT];
  assign lsb_first       = reg_cr[CR_LSB_FIRST_BIT];
  assign rx_dis          = reg_cr[CR_RX_DIS_BIT];
  assign tx_dis          = reg_cr[CR_TX_DIS_BIT];

  assign prescale        = reg_prescale;
  assign data_bits       = reg_data_bits;
  assign cs_pol          = reg_cs_pol;

  assign cs_auto_en      = reg_cs_auto_en;
  assign cs_sel          = reg_cs_sel;
  assign manual_ss       = reg_manual_ss;
  assign keep_cs_default = reg_keep_cs_default;

  assign t_css           = reg_t_css;
  assign t_csh           = reg_t_csh;
  assign t_idle          = reg_t_idle;

  assign tx_wm           = reg_tx_wm;
  assign rx_wm           = reg_rx_wm;

  // --------------------------------------------------------------------------
  // TX FIFO Write Port & RX FIFO Read Port
  // --------------------------------------------------------------------------
  assign tx_fifo_wr_en = (reg_wr_en && (reg_wr_addr == OFFSET_TX_DATA) && !tx_fifo_full);
  assign tx_fifo_din   = {reg_keep_cs_default, reg_cs_sel, reg_cr[CR_RX_DIS_BIT], reg_wdata};

  assign rx_fifo_rd_en = (reg_rd_en && (reg_rd_addr == OFFSET_RX_DATA) && !rx_fifo_empty);

  // --------------------------------------------------------------------------
  // Status Register (SR) Assembly
  // --------------------------------------------------------------------------
  logic [31:0] reg_sr_val;
  always_comb begin
    reg_sr_val = 32'd0;
    reg_sr_val[SR_BUSY_BIT]        = busy;
    reg_sr_val[SR_TX_EMPTY_BIT]    = tx_fifo_empty;
    reg_sr_val[SR_TX_FULL_BIT]     = tx_fifo_full;
    reg_sr_val[SR_RX_EMPTY_BIT]    = rx_fifo_empty;
    reg_sr_val[SR_RX_FULL_BIT]     = rx_fifo_full;
    reg_sr_val[SR_RX_OVERRUN_BIT]  = rx_overrun_sticky;
    reg_sr_val[SR_TX_UNDERRUN_BIT] = tx_underrun_sticky;
    reg_sr_val[SR_SS_ACTIVE_BIT]   = ss_active;
  end

  // --------------------------------------------------------------------------
  // FIFO Status Register Assembly
  // --------------------------------------------------------------------------
  logic [31:0] reg_fifo_stat_val;
  assign reg_fifo_stat_val = {8'(FIFO_DEPTH), 8'(FIFO_DEPTH), 8'(rx_fifo_count), 8'(tx_fifo_count)};

  // --------------------------------------------------------------------------
  // Interrupt Condition Monitoring & IRQ Generation
  // --------------------------------------------------------------------------
  logic isr_tx_wm_cond;
  logic isr_rx_wm_cond;

  assign isr_tx_wm_cond = (6'(tx_fifo_count) <= reg_tx_wm);
  assign isr_rx_wm_cond = (6'(rx_fifo_count) >= reg_rx_wm);

  assign irq = irq_en && (|(reg_ier & reg_isr));

  // --------------------------------------------------------------------------
  // Register Read Multiplexer
  // --------------------------------------------------------------------------
  always_comb begin
    case (reg_rd_addr)
      OFFSET_CR:        reg_rdata = {24'd0, reg_cr};
      OFFSET_SR:        reg_rdata = reg_sr_val;
      OFFSET_TX_DATA:   reg_rdata = 32'd0;
      OFFSET_RX_DATA:   reg_rdata = rx_fifo_dout;
      OFFSET_PRESCALE:  reg_rdata = {16'd0, reg_prescale};
      OFFSET_CFG:       reg_rdata = {20'd0, reg_cs_pol, 2'd0, reg_data_bits};
      OFFSET_CS_CTRL:   reg_rdata = {23'd0, reg_keep_cs_default, reg_manual_ss, 1'b0, reg_cs_sel, reg_cs_auto_en};
      OFFSET_DELAY:     reg_rdata = {reg_t_idle, reg_t_csh, reg_t_css};
      OFFSET_FIFO_CTRL: reg_rdata = {14'd0, 2'b00, 2'd0, reg_rx_wm, 2'd0, reg_tx_wm};
      OFFSET_FIFO_STAT: reg_rdata = reg_fifo_stat_val;
      OFFSET_IER:       reg_rdata = {25'd0, reg_ier};
      OFFSET_ISR:       reg_rdata = {25'd0, reg_isr};
      default:          reg_rdata = 32'd0;
    endcase
  end

  // --------------------------------------------------------------------------
  // Register Write Logic & State Updates
  // --------------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      reg_cr              <= 8'h01; // Default CORE_EN = 1
      reg_prescale        <= DEFAULT_PRESCALE;
      reg_data_bits       <= DEFAULT_DATA_BITS;
      reg_cs_pol          <= DEFAULT_CS_POL;
      reg_cs_auto_en      <= 1'b1;
      reg_cs_sel          <= 2'd0;
      reg_manual_ss       <= 4'b1111;
      reg_keep_cs_default <= 1'b0;
      reg_t_css           <= DEFAULT_T_CSS;
      reg_t_csh           <= DEFAULT_T_CSH;
      reg_t_idle          <= DEFAULT_T_IDLE;
      reg_tx_wm           <= DEFAULT_TX_WM;
      reg_rx_wm           <= DEFAULT_RX_WM;
      tx_fifo_flush       <= 1'b0;
      rx_fifo_flush       <= 1'b0;
      reg_ier             <= '0;
      reg_isr             <= '0;
      rx_overrun_sticky   <= 1'b0;
      tx_underrun_sticky  <= 1'b0;
    end else begin
      // Self-clearing flush strobes
      tx_fifo_flush <= 1'b0;
      rx_fifo_flush <= 1'b0;

      // Event Interrupt Latching
      if (isr_tx_wm_cond)                reg_isr[INTR_TX_WATERMARK_BIT] <= 1'b1;
      if (isr_rx_wm_cond)                reg_isr[INTR_RX_WATERMARK_BIT] <= 1'b1;
      if (tx_fifo_empty)                 reg_isr[INTR_TX_EMPTY_BIT]     <= 1'b1;
      if (rx_fifo_full)                  reg_isr[INTR_RX_FULL_BIT]      <= 1'b1;
      if (xfer_done_pulse)               reg_isr[INTR_XFER_DONE_BIT]    <= 1'b1;
      if (rx_overrun_pulse) begin
        reg_isr[INTR_RX_OVERRUN_BIT] <= 1'b1;
        rx_overrun_sticky            <= 1'b1;
      end
      if (tx_underrun_pulse) begin
        reg_isr[INTR_TX_UNDERRUN_BIT] <= 1'b1;
        tx_underrun_sticky            <= 1'b1;
      end

      // Write-1-to-Clear for ISR
      if (reg_wr_en && (reg_wr_addr == OFFSET_ISR)) begin
        reg_isr <= reg_isr & ~(reg_wdata[INTR_COUNT-1:0]);
        if (reg_wdata[INTR_RX_OVERRUN_BIT])  rx_overrun_sticky  <= 1'b0;
        if (reg_wdata[INTR_TX_UNDERRUN_BIT]) tx_underrun_sticky <= 1'b0;
      end

      // Register Writes
      if (reg_wr_en) begin
        case (reg_wr_addr)
          OFFSET_CR: begin
            reg_cr <= reg_wdata[7:0];
          end
          OFFSET_PRESCALE: begin
            reg_prescale <= reg_wdata[15:0];
          end
          OFFSET_CFG: begin
            reg_data_bits <= reg_wdata[5:0];
            reg_cs_pol    <= reg_wdata[11:8];
          end
          OFFSET_CS_CTRL: begin
            reg_cs_auto_en      <= reg_wdata[0];
            reg_cs_sel          <= reg_wdata[2:1];
            reg_manual_ss       <= reg_wdata[7:4];
            reg_keep_cs_default <= reg_wdata[8];
          end
          OFFSET_DELAY: begin
            reg_t_css  <= reg_wdata[7:0];
            reg_t_csh  <= reg_wdata[15:8];
            reg_t_idle <= reg_wdata[31:16];
          end
          OFFSET_FIFO_CTRL: begin
            reg_tx_wm     <= reg_wdata[5:0];
            reg_rx_wm     <= reg_wdata[13:8];
            tx_fifo_flush <= reg_wdata[16];
            rx_fifo_flush <= reg_wdata[17];
          end
          OFFSET_IER: begin
            reg_ier <= reg_wdata[INTR_COUNT-1:0];
          end
          default: ;
        endcase
      end
    end
  end

endmodule
