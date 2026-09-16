// ============================================================================
// File: uart_pkg.sv
// Description: Package for AXI4-Lite UART IP Package Definitions & Constants
// Project: AXI_UART
// ============================================================================

package uart_pkg;

  // --------------------------------------------------------------------------
  // Register Offsets
  // --------------------------------------------------------------------------
  // Explicit 6-bit byte address offsets
  localparam logic [5:0] OFFSET_TX_RX_DATA  = 6'h00;
  localparam logic [5:0] OFFSET_STATUS      = 6'h04;
  localparam logic [5:0] OFFSET_CTRL        = 6'h08;
  localparam logic [5:0] OFFSET_BAUD_DIV    = 6'h0C;
  localparam logic [5:0] OFFSET_FIFO_STAT   = 6'h10;
  localparam logic [5:0] OFFSET_INTR_EN     = 6'h14;
  localparam logic [5:0] OFFSET_INTR_STATUS = 6'h18;

  // --------------------------------------------------------------------------
  // Control Register Bit Masks & Fields
  // --------------------------------------------------------------------------
  localparam int CTRL_TX_EN_BIT       = 0;
  localparam int CTRL_RX_EN_BIT       = 1;
  localparam int CTRL_LOOPBACK_BIT    = 2;
  localparam int CTRL_DATA_BITS_LSB   = 3; // 2 bits: 00=5b, 01=6b, 10=7b, 11=8b
  localparam int CTRL_PARITY_EN_BIT   = 5;
  localparam int CTRL_PARITY_ODD_BIT  = 6; // 0=Even, 1=Odd
  localparam int CTRL_STOP_BITS_BIT   = 7; // 0=1 stop bit, 1=2 stop bits

  // --------------------------------------------------------------------------
  // Status Register Bit Masks
  // --------------------------------------------------------------------------
  localparam int STATUS_TX_EMPTY_BIT  = 0;
  localparam int STATUS_TX_FULL_BIT   = 1;
  localparam int STATUS_RX_VALID_BIT  = 2;
  localparam int STATUS_RX_FULL_BIT   = 3;
  localparam int STATUS_TX_BUSY_BIT   = 4;
  localparam int STATUS_RX_BUSY_BIT   = 5;
  localparam int STATUS_FRAME_ERR_BIT = 6;
  localparam int STATUS_PARITY_ERR_BIT= 7;
  localparam int STATUS_OVERRUN_ERR_BIT=8;

  // --------------------------------------------------------------------------
  // Interrupt Bit Masks
  // --------------------------------------------------------------------------
  localparam int INTR_TX_EMPTY_BIT    = 0;
  localparam int INTR_RX_READY_BIT    = 1;
  localparam int INTR_FRAME_ERR_BIT   = 2;
  localparam int INTR_OVERRUN_BIT     = 3;

  // Default Prescaler Value for 115200 baud @ 50MHz System Clock
  // 50,000,000 / (115,200 * 16) = ~27 (27.126)
  localparam logic [15:0] DEFAULT_BAUD_DIV = 16'd27;

endpackage
