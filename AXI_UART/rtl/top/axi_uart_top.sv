// ============================================================================
// File: axi_uart_top.sv
// Description: Top-Level Module for AXI4-Lite UART IP Core (AXI_UART)
// Project: AXI_UART
// ============================================================================

module axi_uart_top #(
  parameter int FIFO_DEPTH       = 16,
  parameter int DEFAULT_BAUD_DIV = 27   // 50MHz / (16 * 115200) ~= 27
)(
  input  logic        clk,
  input  logic        rst_n,

  // UART External Pins
  input  logic        uart_rx_pin,
  output logic        uart_tx_pin,
  output logic        irq,

  // AXI4-Lite Slave Interface Channels
  // AW
  input  logic [31:0] s_axi_awaddr,
  input  logic [2:0]  s_axi_awprot,
  input  logic        s_axi_awvalid,
  output logic        s_axi_awready,
  // W
  input  logic [31:0] s_axi_wdata,
  input  logic [3:0]  s_axi_wstrb,
  input  logic        s_axi_wvalid,
  output logic        s_axi_wready,
  // B
  output logic [1:0]  s_axi_bresp,
  output logic        s_axi_bvalid,
  input  logic        s_axi_bready,
  // AR
  input  logic [31:0] s_axi_araddr,
  input  logic [2:0]  s_axi_arprot,
  input  logic        s_axi_arvalid,
  output logic        s_axi_arready,
  // R
  output logic [31:0] s_axi_rdata,
  output logic [1:0]  s_axi_rresp,
  output logic        s_axi_rvalid,
  input  logic        s_axi_rready
);

  import uart_pkg::*;

  // --------------------------------------------------------------------------
  // Internal Registers & Signals
  // --------------------------------------------------------------------------
  logic [31:0] ctrl_reg;
  logic [15:0] baud_div_reg;
  logic [7:0]  tx_watermark;
  logic [7:0]  rx_watermark;
  logic [31:0] intr_en_reg;
  logic [3:0]  intr_status_reg;

  // Local AXI register interface wires
  logic        reg_wr_en;
  logic [5:0]  reg_wr_addr;
  logic [31:0] reg_wdata;
  /* verilator lint_off UNUSED */
  logic [3:0]  reg_wstrb;
  /* verilator lint_on UNUSED */
  logic        reg_rd_en;
  logic [5:0]  reg_rd_addr;
  logic [31:0] reg_rdata;

  // Baud rate generator tick
  logic tick;

  // TX & RX FIFO signals
  logic        tx_fifo_wr_en, tx_fifo_rd_en;
  logic [7:0]  tx_fifo_din,   tx_fifo_dout;
  logic        tx_fifo_full,  tx_fifo_empty, tx_fifo_overflow;
  logic [$clog2(FIFO_DEPTH+1)-1:0] tx_fifo_count;

  logic        rx_fifo_wr_en, rx_fifo_rd_en;
  logic [7:0]  rx_fifo_din,   rx_fifo_dout;
  logic        rx_fifo_full,  rx_fifo_empty, rx_fifo_overflow;
  logic [$clog2(FIFO_DEPTH+1)-1:0] rx_fifo_count;

  // Core TX/RX signals
  /* verilator lint_off UNUSED */
  logic tx_done;
  /* verilator lint_on UNUSED */
  logic tx_start, tx_busy, internal_tx_out;
  logic rx_valid, rx_busy, rx_frame_err, rx_parity_err;
  logic [7:0] rx_core_data;
  logic serial_rx_input;

  // Control register fields decoding
  logic tx_enable, rx_enable, loopback_en, parity_en, parity_odd, stop_bits;
  logic [1:0] data_bits;

  assign tx_enable   = ctrl_reg[CTRL_TX_EN_BIT];
  assign rx_enable   = ctrl_reg[CTRL_RX_EN_BIT];
  assign loopback_en = ctrl_reg[CTRL_LOOPBACK_BIT];
  assign data_bits   = ctrl_reg[CTRL_DATA_BITS_LSB+1 : CTRL_DATA_BITS_LSB];
  assign parity_en   = ctrl_reg[CTRL_PARITY_EN_BIT];
  assign parity_odd  = ctrl_reg[CTRL_PARITY_ODD_BIT];
  assign stop_bits   = ctrl_reg[CTRL_STOP_BITS_BIT];

  assign uart_tx_pin     = internal_tx_out;
  assign serial_rx_input = loopback_en ? internal_tx_out : uart_rx_pin;

  // --------------------------------------------------------------------------
  // Submodule Instantiations
  // --------------------------------------------------------------------------

  // 1. AXI4-Lite Slave Adapter
  axi_lite_slave u_axi_slave (
    .clk           (clk),
    .rst_n         (rst_n),
    .s_axi_awaddr  (s_axi_awaddr),
    .s_axi_awprot  (s_axi_awprot),
    .s_axi_awvalid (s_axi_awvalid),
    .s_axi_awready (s_axi_awready),
    .s_axi_wdata   (s_axi_wdata),
    .s_axi_wstrb   (s_axi_wstrb),
    .s_axi_wvalid  (s_axi_wvalid),
    .s_axi_wready  (s_axi_wready),
    .s_axi_bresp   (s_axi_bresp),
    .s_axi_bvalid  (s_axi_bvalid),
    .s_axi_bready  (s_axi_bready),
    .s_axi_araddr  (s_axi_araddr),
    .s_axi_arprot  (s_axi_arprot),
    .s_axi_arvalid (s_axi_arvalid),
    .s_axi_arready (s_axi_arready),
    .s_axi_rdata   (s_axi_rdata),
    .s_axi_rresp   (s_axi_rresp),
    .s_axi_rvalid  (s_axi_rvalid),
    .s_axi_rready  (s_axi_rready),
    .reg_wr_en     (reg_wr_en),
    .reg_wr_addr   (reg_wr_addr),
    .reg_wdata     (reg_wdata),
    .reg_wstrb     (reg_wstrb),
    .reg_rd_en     (reg_rd_en),
    .reg_rd_addr   (reg_rd_addr),
    .reg_rdata     (reg_rdata)
  );

  // 2. Baud Rate Prescaler
  baud_rate_gen u_baud_gen (
    .clk      (clk),
    .rst_n    (rst_n),
    .baud_div (baud_div_reg),
    .tick     (tick)
  );

  // 3. TX Synchronous FIFO
  sync_fifo #(
    .DATA_WIDTH (8),
    .DEPTH      (FIFO_DEPTH)
  ) u_tx_fifo (
    .clk      (clk),
    .rst_n    (rst_n),
    .clear    (1'b0),
    .wr_en    (tx_fifo_wr_en),
    .din      (tx_fifo_din),
    .rd_en    (tx_fifo_rd_en),
    .dout     (tx_fifo_dout),
    .full     (tx_fifo_full),
    .empty    (tx_fifo_empty),
    .count    (tx_fifo_count),
    .overflow (tx_fifo_overflow)
  );

  // 4. RX Synchronous FIFO
  sync_fifo #(
    .DATA_WIDTH (8),
    .DEPTH      (FIFO_DEPTH)
  ) u_rx_fifo (
    .clk      (clk),
    .rst_n    (rst_n),
    .clear    (1'b0),
    .wr_en    (rx_fifo_wr_en),
    .din      (rx_fifo_din),
    .rd_en    (rx_fifo_rd_en),
    .dout     (rx_fifo_dout),
    .full     (rx_fifo_full),
    .empty    (rx_fifo_empty),
    .count    (rx_fifo_count),
    .overflow (rx_fifo_overflow)
  );

  // 5. UART Transmitter Engine
  uart_tx u_tx_core (
    .clk        (clk),
    .rst_n      (rst_n),
    .tx_enable  (tx_enable),
    .tick       (tick),
    .tx_start   (tx_start),
    .tx_data    (tx_fifo_dout),
    .data_bits  (data_bits),
    .parity_en  (parity_en),
    .parity_odd (parity_odd),
    .stop_bits  (stop_bits),
    .tx_out     (internal_tx_out),
    .tx_busy    (tx_busy),
    .tx_done    (tx_done)
  );

  // 6. UART Receiver Engine
  uart_rx u_rx_core (
    .clk        (clk),
    .rst_n      (rst_n),
    .rx_enable  (rx_enable),
    .tick       (tick),
    .rx_in      (serial_rx_input),
    .data_bits  (data_bits),
    .parity_en  (parity_en),
    .parity_odd (parity_odd),
    .stop_bits  (stop_bits),
    .rx_data    (rx_core_data),
    .rx_valid   (rx_valid),
    .rx_busy    (rx_busy),
    .frame_err  (rx_frame_err),
    .parity_err (rx_parity_err)
  );

  // --------------------------------------------------------------------------
  // TX Start Logic & FIFO Control
  // --------------------------------------------------------------------------
  logic tx_trigger_pending;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_trigger_pending <= 1'b0;
    end else begin
      if (!tx_enable) begin
        tx_trigger_pending <= 1'b0;
      end else if (!tx_fifo_empty && !tx_busy && !tx_start) begin
        tx_trigger_pending <= 1'b1;
      end else if (tx_start) begin
        tx_trigger_pending <= 1'b0;
      end
    end
  end

  assign tx_start      = tx_trigger_pending && !tx_busy;
  assign tx_fifo_rd_en = tx_start;

  assign rx_fifo_wr_en = rx_valid;
  assign rx_fifo_din   = rx_core_data;

  // --------------------------------------------------------------------------
  // Register Read Decoding
  // --------------------------------------------------------------------------
  always_comb begin
    case (reg_rd_addr)
      OFFSET_TX_RX_DATA: begin
        reg_rdata = {24'd0, rx_fifo_dout};
      end
      OFFSET_STATUS: begin
        reg_rdata = 32'd0;
        reg_rdata[STATUS_TX_EMPTY_BIT]   = tx_fifo_empty;
        reg_rdata[STATUS_TX_FULL_BIT]    = tx_fifo_full;
        reg_rdata[STATUS_RX_VALID_BIT]   = !rx_fifo_empty;
        reg_rdata[STATUS_RX_FULL_BIT]    = rx_fifo_full;
        reg_rdata[STATUS_TX_BUSY_BIT]    = tx_busy;
        reg_rdata[STATUS_RX_BUSY_BIT]    = rx_busy;
        reg_rdata[STATUS_FRAME_ERR_BIT]  = rx_frame_err;
        reg_rdata[STATUS_PARITY_ERR_BIT] = rx_parity_err;
        reg_rdata[STATUS_OVERRUN_ERR_BIT]= rx_fifo_overflow | tx_fifo_overflow;
      end
      OFFSET_CTRL: begin
        reg_rdata = ctrl_reg;
      end
      OFFSET_BAUD_DIV: begin
        reg_rdata = {16'd0, baud_div_reg};
      end
      OFFSET_FIFO_STAT: begin
        reg_rdata = {rx_watermark, tx_watermark, 8'(rx_fifo_count), 8'(tx_fifo_count)};
      end
      OFFSET_INTR_EN: begin
        reg_rdata = intr_en_reg;
      end
      OFFSET_INTR_STATUS: begin
        reg_rdata = {28'd0, intr_status_reg};
      end
      default: reg_rdata = 32'd0;
    endcase
  end

  localparam int COUNT_W = $clog2(FIFO_DEPTH+1);
  typedef logic [COUNT_W-1:0] count_width_t;

  // RX FIFO Pop on AXI Read to DATA reg
  assign rx_fifo_rd_en = reg_rd_en && (reg_rd_addr == OFFSET_TX_RX_DATA) && !rx_fifo_empty;

  // --------------------------------------------------------------------------
  // Register Write Logic
  // --------------------------------------------------------------------------
  assign tx_fifo_wr_en = reg_wr_en && (reg_wr_addr == OFFSET_TX_RX_DATA);
  assign tx_fifo_din   = reg_wdata[7:0];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ctrl_reg        <= 32'h0000_001B; // Default TX_EN=1, RX_EN=1, 8N1
      baud_div_reg    <= 16'(DEFAULT_BAUD_DIV);
      tx_watermark    <= 8'd1;
      rx_watermark    <= 8'd1;
      intr_en_reg     <= 32'd0;
      intr_status_reg <= 4'd0;
    end else begin
      // Update hardware-asserted interrupt status bits
      intr_status_reg[INTR_TX_EMPTY_BIT] <= tx_fifo_empty;

      if ((8'(rx_fifo_count) >= rx_watermark && rx_watermark > 0) || (!rx_fifo_empty && rx_watermark == 8'd0)) begin
        intr_status_reg[INTR_RX_READY_BIT] <= 1'b1;
      end else begin
        intr_status_reg[INTR_RX_READY_BIT] <= 1'b0;
      end

      if (rx_valid && rx_frame_err) begin
        intr_status_reg[INTR_FRAME_ERR_BIT] <= 1'b1;
      end

      if (rx_fifo_overflow || tx_fifo_overflow) begin
        intr_status_reg[INTR_OVERRUN_BIT] <= 1'b1;
      end

      // AXI Register Write
      if (reg_wr_en) begin
        case (reg_wr_addr)
          OFFSET_CTRL: begin
            ctrl_reg <= reg_wdata;
          end
          OFFSET_BAUD_DIV: begin
            baud_div_reg <= reg_wdata[15:0];
          end
          OFFSET_FIFO_STAT: begin
            tx_watermark <= reg_wdata[23:16];
            rx_watermark <= reg_wdata[31:24];
          end
          OFFSET_INTR_EN: begin
            intr_en_reg <= reg_wdata;
          end
          OFFSET_INTR_STATUS: begin
            // Write-1-to-Clear for W1C bits (Frame Err, Overrun)
            if (reg_wdata[INTR_FRAME_ERR_BIT]) intr_status_reg[INTR_FRAME_ERR_BIT] <= 1'b0;
            if (reg_wdata[INTR_OVERRUN_BIT])   intr_status_reg[INTR_OVERRUN_BIT]   <= 1'b0;
          end
          default: ;
        endcase
      end
    end
  end

  // Interrupt Output Line
  assign irq = |(intr_status_reg & intr_en_reg[3:0]);

endmodule
