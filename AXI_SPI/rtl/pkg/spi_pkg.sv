// ============================================================================
// File: spi_pkg.sv
// Description: Package for AXI4-Lite SPI Master IP Definitions & Constants
// Project: AXI_SPI
// ============================================================================

package spi_pkg;

  // --------------------------------------------------------------------------
  // Register Byte Offsets (32-bit Aligned)
  // --------------------------------------------------------------------------
  localparam logic [5:0] OFFSET_CR        = 6'h00; // Control Register (R/W)
  localparam logic [5:0] OFFSET_SR        = 6'h04; // Status Register (RO)
  localparam logic [5:0] OFFSET_TX_DATA   = 6'h08; // TX Data/Cmd FIFO Write Port (WO)
  localparam logic [5:0] OFFSET_RX_DATA   = 6'h0C; // RX Data FIFO Read Port (RO)
  localparam logic [5:0] OFFSET_PRESCALE  = 6'h10; // Clock Prescaler Register (R/W)
  localparam logic [5:0] OFFSET_CFG       = 6'h14; // Frame Config (DATA_BITS, CS_POL) (R/W)
  localparam logic [5:0] OFFSET_CS_CTRL   = 6'h18; // Chip Select Control (R/W)
  localparam logic [5:0] OFFSET_DELAY     = 6'h1C; // Timing Delays (CSS, CSH, IDLE) (R/W)
  localparam logic [5:0] OFFSET_FIFO_CTRL = 6'h20; // FIFO Watermark & Flush (R/W)
  localparam logic [5:0] OFFSET_FIFO_STAT = 6'h24; // FIFO Level Counts (RO)
  localparam logic [5:0] OFFSET_IER       = 6'h28; // Interrupt Enable Register (R/W)
  localparam logic [5:0] OFFSET_ISR       = 6'h2C; // Interrupt Status Register (R/W1C)

  // --------------------------------------------------------------------------
  // Control Register (CR) Bit Allocations
  // --------------------------------------------------------------------------
  localparam int CR_CORE_EN_BIT     = 0; // 1 = Enable SPI Core
  localparam int CR_IRQ_EN_BIT      = 1; // 1 = Enable Global IRQ Output
  localparam int CR_LOOPBACK_EN_BIT = 2; // 1 = Internal Loopback Mode (MOSI -> MISO)
  localparam int CR_CPOL_BIT        = 3; // Clock Polarity (0 = Idle Low, 1 = Idle High)
  localparam int CR_CPHA_BIT        = 4; // Clock Phase (0 = Leading Edge Sample, 1 = Trailing Edge Sample)
  localparam int CR_LSB_FIRST_BIT   = 5; // 0 = MSB-First, 1 = LSB-First
  localparam int CR_RX_DIS_BIT      = 6; // 1 = Discard RX Data (Do not push to RX FIFO)
  localparam int CR_TX_DIS_BIT      = 7; // 1 = Disable MOSI output (keep high/idle)

  // --------------------------------------------------------------------------
  // Status Register (SR) Bit Allocations
  // --------------------------------------------------------------------------
  localparam int SR_BUSY_BIT        = 0; // 1 = SPI transfer in progress
  localparam int SR_TX_EMPTY_BIT    = 1; // 1 = TX FIFO is Empty
  localparam int SR_TX_FULL_BIT     = 2; // 1 = TX FIFO is Full
  localparam int SR_RX_EMPTY_BIT    = 3; // 1 = RX FIFO is Empty
  localparam int SR_RX_FULL_BIT     = 4; // 1 = RX FIFO is Full
  localparam int SR_RX_OVERRUN_BIT  = 5; // 1 = RX FIFO Overrun Error
  localparam int SR_TX_UNDERRUN_BIT = 6; // 1 = TX FIFO Underrun Error
  localparam int SR_SS_ACTIVE_BIT   = 7; // 1 = Any Slave Select (CS) is active

  // --------------------------------------------------------------------------
  // Interrupt Register (IER / ISR) Bit Allocations
  // --------------------------------------------------------------------------
  localparam int INTR_TX_WATERMARK_BIT = 0; // TX FIFO count <= TX_WM
  localparam int INTR_RX_WATERMARK_BIT = 1; // RX FIFO count >= RX_WM
  localparam int INTR_TX_EMPTY_BIT     = 2; // TX FIFO is empty
  localparam int INTR_RX_FULL_BIT      = 3; // RX FIFO is full
  localparam int INTR_XFER_DONE_BIT    = 4; // Transfer completed & Bus idle
  localparam int INTR_RX_OVERRUN_BIT   = 5; // RX FIFO overrun error
  localparam int INTR_TX_UNDERRUN_BIT  = 6; // TX FIFO underrun error

  localparam int INTR_COUNT            = 7;

  // --------------------------------------------------------------------------
  // Chip Select (CS) Constants
  // --------------------------------------------------------------------------
  localparam int NUM_SLAVES            = 4;

  // --------------------------------------------------------------------------
  // SPI FSM State Machine Definitions
  // --------------------------------------------------------------------------
  typedef enum logic [2:0] {
    ST_IDLE        = 3'd0,
    ST_CS_SETUP    = 3'd1,
    ST_TRANSFER    = 3'd2,
    ST_CS_HOLD     = 3'd3,
    ST_INTER_FRAME = 3'd4,
    ST_CS_IDLE     = 3'd5
  } spi_fsm_state_t;

  // --------------------------------------------------------------------------
  // Default Configuration Values
  // --------------------------------------------------------------------------
  localparam logic [15:0] DEFAULT_PRESCALE  = 16'd7;     // (f_clk / 16) baud rate
  localparam logic [5:0]  DEFAULT_DATA_BITS = 6'd8;     // 8-bit standard SPI word
  localparam logic [3:0]  DEFAULT_CS_POL    = 4'b0000;  // Active-Low Chip Select
  localparam logic [7:0]  DEFAULT_T_CSS     = 8'd1;     // 1 prescaled half-cycle setup
  localparam logic [7:0]  DEFAULT_T_CSH     = 8'd1;     // 1 prescaled half-cycle hold
  localparam logic [15:0] DEFAULT_T_IDLE    = 16'd1;    // 1 prescaled half-cycle idle
  localparam logic [5:0]  DEFAULT_TX_WM     = 6'd4;
  localparam logic [5:0]  DEFAULT_RX_WM     = 6'd4;

endpackage
