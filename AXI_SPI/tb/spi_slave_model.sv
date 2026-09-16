// ============================================================================
// File: spi_slave_model.sv
// Description: Behavioral SPI Slave / NOR Flash (W25Qxx-compatible) Model
// Project: AXI_SPI
// ============================================================================

`timescale 1ns/1ps

module spi_slave_model (
  input  logic        sck,
  input  logic        mosi,
  output logic        miso,
  input  logic        ss_n,

  /* verilator lint_off UNUSED */
  input  logic        cpol,
  input  logic        cpha
  /* verilator lint_on UNUSED */
);

  // 256-byte internal memory array
  logic [7:0] mem [0:255];
  logic [7:0] status_reg;
  logic [7:0] cmd_byte;
  logic [23:0] addr_accum;
  /* verilator lint_off UNUSED */
  logic [7:0] mosi_shift;
  /* verilator lint_on UNUSED */
  logic [7:0] miso_shift;
  logic [2:0] bit_cnt;
  int         byte_cnt;
  logic       miso_drive;

  assign miso = (!ss_n) ? miso_drive : 1'bz;

  typedef enum logic [2:0] {
    IDLE        = 3'd0,
    RECV_CMD    = 3'd1,
    RECV_ADDR   = 3'd2,
    READ_DATA   = 3'd3,
    WRITE_DATA  = 3'd4,
    READ_ID     = 3'd5,
    READ_STATUS = 3'd6
  } slave_state_t;

  slave_state_t state;

  // Initialize memory and status
  initial begin
    for (int i = 0; i < 256; i++) begin
      mem[i] = 8'(i ^ 32'hA5);
    end
    status_reg = 8'h00;
    state      = IDLE;
    bit_cnt    = 3'd0;
    byte_cnt   = 0;
    miso_drive = 1'b0;
    mosi_shift = 8'd0;
    miso_shift = 8'd0;
    cmd_byte   = 8'd0;
    addr_accum = 24'd0;
  end

  // Active edges for Mode 0..3
  // Leading edge of SCK is (sck != cpol)
  // Mode 0 (CPOL=0, CPHA=0): Sample on rising (sck=1), Shift on falling (sck=0)
  // Mode 1 (CPOL=0, CPHA=1): Shift on rising (sck=1), Sample on falling (sck=0)
  // Mode 2 (CPOL=1, CPHA=0): Sample on falling (sck=0), Shift on rising (sck=1)
  // Mode 3 (CPOL=1, CPHA=1): Shift on falling (sck=0), Sample on rising (sck=1)

  always @(posedge sck or negedge sck or posedge ss_n) begin
    if (ss_n) begin
      state      <= IDLE;
      bit_cnt    <= 3'd0;
      byte_cnt   <= 0;
      miso_drive <= 1'b0;
      miso_shift <= 8'd0;
    end else begin
      logic is_sample_edge;
      logic is_shift_edge;

      is_sample_edge = (cpol ^ cpha) ? (!sck) : sck;
      is_shift_edge  = (cpol ^ cpha) ? sck    : (!sck);

      // ----------------------------------------------------------------------
      // Sample Edge: Sample MOSI
      // ----------------------------------------------------------------------
      if (is_sample_edge) begin
        mosi_shift <= {mosi_shift[6:0], mosi};
        bit_cnt    <= bit_cnt + 3'd1;

        if (bit_cnt == 3'd7) begin
          logic [7:0] rx_byte;
          rx_byte = {mosi_shift[6:0], mosi};

          case (state)
            IDLE, RECV_CMD: begin
              cmd_byte <= rx_byte;
              byte_cnt <= 0;
              case (rx_byte)
                8'h9F: begin // Read JEDEC ID (EF 40 18)
                  state      <= READ_ID;
                  miso_shift <= 8'hEF;
                end
                8'h05: begin // Read Status Register 1
                  state      <= READ_STATUS;
                  miso_shift <= status_reg;
                end
                8'h06: begin // Write Enable (WREN)
                  status_reg[1] <= 1'b1;
                  state         <= IDLE;
                end
                8'h04: begin // Write Disable (WRDI)
                  status_reg[1] <= 1'b0;
                  state         <= IDLE;
                end
                8'h02: begin // Page Program: [02] [A2] [A1] [A0] [D0]...
                  state <= RECV_ADDR;
                end
                8'h03: begin // Read Data: [03] [A2] [A1] [A0] [D0_out]...
                  state <= RECV_ADDR;
                end
                default: begin
                  state <= WRITE_DATA;
                  addr_accum <= 24'd0;
                end
              endcase
            end

            RECV_ADDR: begin
              if (byte_cnt == 0) begin
                addr_accum[23:16] <= rx_byte;
                byte_cnt <= 1;
              end else if (byte_cnt == 1) begin
                addr_accum[15:8] <= rx_byte;
                byte_cnt <= 2;
              end else if (byte_cnt == 2) begin
                addr_accum[7:0] <= rx_byte;
                byte_cnt <= 0;
                if (cmd_byte == 8'h03) begin
                  state      <= READ_DATA;
                  miso_shift <= mem[rx_byte];
                end else begin
                  state <= WRITE_DATA;
                end
              end
            end

            WRITE_DATA: begin
              mem[addr_accum[7:0]] <= rx_byte;
              addr_accum <= addr_accum + 24'd1;
            end

            READ_DATA: begin
              addr_accum <= addr_accum + 24'd1;
              miso_shift <= mem[addr_accum[7:0] + 8'd1];
            end

            READ_ID: begin
              byte_cnt <= byte_cnt + 1;
              if (byte_cnt == 0)      miso_shift <= 8'h40;
              else if (byte_cnt == 1) miso_shift <= 8'h18;
              else                    miso_shift <= 8'h00;
            end

            READ_STATUS: begin
              miso_shift <= status_reg;
            end

            default: state <= IDLE;
          endcase
        end
      end

      // ----------------------------------------------------------------------
      // Shift Edge: Output MISO
      // ----------------------------------------------------------------------
      if (is_shift_edge) begin
        miso_drive <= miso_shift[7];
        miso_shift <= {miso_shift[6:0], 1'b0};
      end
    end
  end

endmodule
