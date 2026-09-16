// ============================================================================
// File: i2c_pkg.sv
// Description: Package for AXI4-Lite I2C Master IP Definitions & Constants
// Project: AXI_I2C
// ============================================================================

package i2c_pkg;

  // --------------------------------------------------------------------------
  // Register Byte Offsets (32-bit Aligned)
  // --------------------------------------------------------------------------
  localparam logic [5:0] OFFSET_CR        = 6'h00; // Control Register (R/W)
  localparam logic [5:0] OFFSET_SR        = 6'h04; // Status Register (RO)
  localparam logic [5:0] OFFSET_TX_CMD    = 6'h08; // Command & TX Data FIFO Write Port (WO)
  localparam logic [5:0] OFFSET_RX_DATA   = 6'h0C; // RX Data FIFO Read Port (RO)
  localparam logic [5:0] OFFSET_PRESCALE  = 6'h10; // Clock Prescaler Register (R/W)
  localparam logic [5:0] OFFSET_TIMING    = 6'h14; // SCL High/Low Timing Register (R/W)
  localparam logic [5:0] OFFSET_FILTER    = 6'h18; // Deglitch Filter Cycles (R/W)
  localparam logic [5:0] OFFSET_FIFO_CTRL = 6'h1C; // FIFO Watermark & Flush Register (R/W)
  localparam logic [5:0] OFFSET_FIFO_STAT = 6'h20; // FIFO Entry Counts Status (RO)
  localparam logic [5:0] OFFSET_IER       = 6'h24; // Interrupt Enable Register (R/W)
  localparam logic [5:0] OFFSET_ISR       = 6'h28; // Interrupt Status Register (R/W1C)
  localparam logic [5:0] OFFSET_TIMEOUT   = 6'h2C; // Clock Stretching Timeout Register (R/W)

  // --------------------------------------------------------------------------
  // Control Register (CR) Bit Allocations
  // --------------------------------------------------------------------------
  localparam int CR_CORE_EN_BIT        = 0; // 1 = Enable Core
  localparam int CR_IRQ_EN_BIT         = 1; // 1 = Enable Global IRQ
  localparam int CR_LOOPBACK_EN_BIT    = 2; // 1 = Internal Loopback Mode
  localparam int CR_AUTO_RECOVER_BIT   = 3; // 1 = Automatic 9-Pulse Recovery on Stuck SDA
  localparam int CR_MANUAL_RECOVER_BIT = 4; // W1S = Trigger 9-Pulse Recovery
  localparam int CR_STRETCH_EN_BIT     = 5; // 1 = Clock Stretching Support

  // --------------------------------------------------------------------------
  // Status Register (SR) Bit Allocations
  // --------------------------------------------------------------------------
  localparam int SR_BUSY_BIT           = 0; // 1 = FSM is Busy
  localparam int SR_BUS_BUSY_BIT       = 1; // 1 = I2C Bus is Busy (START to STOP)
  localparam int SR_TX_EMPTY_BIT       = 2; // 1 = TX FIFO is Empty
  localparam int SR_TX_FULL_BIT        = 3; // 1 = TX FIFO is Full
  localparam int SR_RX_EMPTY_BIT       = 4; // 1 = RX FIFO is Empty
  localparam int SR_RX_FULL_BIT        = 5; // 1 = RX FIFO is Full
  localparam int SR_NACK_RECV_BIT      = 6; // 1 = Last Transferred Byte Received NACK
  localparam int SR_ARB_LOST_BIT       = 7; // 1 = Arbitration Lost Flag
  localparam int SR_SCL_HELD_BIT       = 8; // 1 = SCL Held Low (Clock Stretching active)
  localparam int SR_BUS_ERROR_BIT      = 9; // 1 = Bus Error Detected

  // --------------------------------------------------------------------------
  // Command-Tagged TX FIFO Bit Allocations
  // --------------------------------------------------------------------------
  localparam int CMD_START_BIT         = 8;  // Generate START (or Repeated START)
  localparam int CMD_STOP_BIT          = 9;  // Generate STOP
  localparam int CMD_READ_BIT          = 10; // 1 = Master Read, 0 = Master Write
  localparam int CMD_NACK_BIT          = 11; // When CMD_READ=1: 1 = NACK response, 0 = ACK response

  // --------------------------------------------------------------------------
  // Interrupt Register (IER / ISR) Bit Allocations
  // --------------------------------------------------------------------------
  localparam int INTR_TX_WATERMARK_BIT = 0; // TX FIFO count <= watermark
  localparam int INTR_RX_WATERMARK_BIT = 1; // RX FIFO count >= watermark
  localparam int INTR_TX_EMPTY_BIT     = 2; // TX FIFO empty and FSM idle
  localparam int INTR_RX_FULL_BIT      = 3; // RX FIFO full
  localparam int INTR_DONE_BIT         = 4; // Transaction with STOP completed
  localparam int INTR_NACK_BIT         = 5; // Slave NACK received
  localparam int INTR_ARB_LOST_BIT     = 6; // Multi-master arbitration lost
  localparam int INTR_BUS_ERROR_BIT    = 7; // Bus error detected
  localparam int INTR_TIMEOUT_BIT      = 8; // Clock stretch timeout

  localparam int INTR_COUNT            = 9;

  // --------------------------------------------------------------------------
  // Timing 4-Phase Micro-State Definitions
  // --------------------------------------------------------------------------
  typedef enum logic [1:0] {
    PH_LOW  = 2'b00, // Phase 0: SCL low, setup SDA
    PH_RISE = 2'b01, // Phase 1: SCL released, stretch check
    PH_HIGH = 2'b10, // Phase 2: SCL high, sample SDA / arb check
    PH_FALL = 2'b11  // Phase 3: SCL pull down transition
  } i2c_phase_t;

  // --------------------------------------------------------------------------
  // I2C Core FSM States
  // --------------------------------------------------------------------------
  typedef enum logic [3:0] {
    ST_IDLE         = 4'd0,
    ST_START_1      = 4'd1,
    ST_START_2      = 4'd2,
    ST_RESTART_1    = 4'd3,
    ST_RESTART_2    = 4'd4,
    ST_TX_BYTE      = 4'd5,
    ST_RX_ACK       = 4'd6,
    ST_RX_BYTE      = 4'd7,
    ST_TX_ACK       = 4'd8,
    ST_STOP_1       = 4'd9,
    ST_STOP_2       = 4'd10,
    ST_RECOVERY     = 4'd11,
    ST_ARB_LOST     = 4'd12,
    ST_HOLD         = 4'd13
  } i2c_fsm_state_t;

  // Default Prescaler Value (50MHz system clock, 100kHz standard mode: 50M/(4*100k)-1 = 124 = 0x007C)
  localparam logic [15:0] DEFAULT_PRESCALE = 16'd124;
  localparam logic [15:0] DEFAULT_TIMING   = 16'h0202;
  localparam logic [7:0]  DEFAULT_FILTER   = 8'd3;
  localparam logic [15:0] DEFAULT_TIMEOUT  = 16'hFFFF;

endpackage
