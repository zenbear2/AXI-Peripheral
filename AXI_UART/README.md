# AXI4-Lite UART IP Core (`AXI_UART`)

[![Bus Interface](https://img.shields.io/badge/Bus-AXI4--Lite%2032--bit-brightgreen)](#)
[![Language](https://img.shields.io/badge/Language-SystemVerilog-orange)](#)
[![Verification](https://img.shields.io/badge/Verification-100%25%20Passed-success)](#)
[![Vivado](https://img.shields.io/badge/Vivado-IP%20Packaged-red)](#)
[![License](https://img.shields.io/badge/License-Apache%202.0-lightgrey)](LICENSE)

A high-performance, modular, and configurable **32-bit AXI4-Lite UART IP Core (`axi_uart_top`)** designed for FPGA and ASIC SoC designs (such as AMD / Xilinx MicroBlaze, RISC-V, and Arm processors).

Written in standard SystemVerilog, this IP features a full AXI4-Lite slave interface, independent 16-entry TX/RX FIFOs, 16x oversampling with 3-sample majority voting center sampling, internal digital loopback self-test mode, hardware interrupt (IRQ) signaling, and pre-packaged AMD Vivado IP catalog support with baremetal Vitis drivers.

---

## 1. Key Architectural Features

- **Standard AXI4-Lite 32-bit Slave Interface**: Independent read/write address and data channels with standard `OKAY` handshake responses.
- **Flexible Line Control**:
  - **Data Bits**: 5, 6, 7, or 8 bits.
  - **Stop Bits**: 1 or 2 stop bits.
  - **Parity**: Odd, Even, or None (disabled).
  - **Baud Rate Generator**: 16-bit programmable prescaler supporting any standard baud rate (e.g., 9600, 115200, 921600 bps).
- **FIFO Buffering**: Dual parameterized synchronous FIFOs (default 16-byte TX, 16-byte RX) with programmable watermark threshold interrupts.
- **Reliability & Noise Filtering**:
  - RX engine utilizes 16x clock oversampling with 3-sample majority voting at midpoint to reject noise spikes.
  - Automatic detection and reporting of Framing Errors, Parity Errors, and FIFO Overrun Errors.
- **Interrupt Controller**:
  - Supports TX Empty, RX Data Ready / Watermark, Framing Error, and Overrun Error hardware IRQ assertions.
  - Write-1-to-Clear (W1C) interrupt status clearing mechanism.
- **Diagnostic Loopback Mode**: Software-controlled internal serial loopback mode for runtime self-testing without external wiring.
- **Toolchain Ready**: Pre-packaged with Vivado IP definition (`component.xml`, `xgui/`), and complete standalone drivers for AMD Vitis (`drivers/axi_uart_v1_0`).

---

## 2. Register Map

Base address is 32-bit word aligned. All offsets are in bytes:

| Offset | Register Name | Access | Reset Value | Description |
| :---: | :--- | :---: | :---: | :--- |
| `0x00` | **`TX_RX_DATA`** | R/W | `0x0000_0000` | **[W]** Write 8-bit byte to TX FIFO<br>**[R]** Read 8-bit byte from RX FIFO |
| `0x04` | **`STATUS`** | RO | `0x0000_0001` | **[0]**: TX FIFO Empty<br>**[1]**: TX FIFO Full<br>**[2]**: RX FIFO Valid (Not Empty)<br>**[3]**: RX FIFO Full<br>**[4]**: TX Engine Busy<br>**[5]**: RX Engine Busy<br>**[6]**: Framing Error<br>**[7]**: Parity Error<br>**[8]**: Overrun Error |
| `0x08` | **`CTRL`** | R/W | `0x0000_001B` | **[0]**: TX Enable (`1` = Enable)<br>**[1]**: RX Enable (`1` = Enable)<br>**[2]**: Loopback Enable (`1` = Enable)<br>**[4:3]**: Data Bits (`00`=5b, `01`=6b, `10`=7b, `11`=8b)<br>**[5]**: Parity Enable (`1` = Enable)<br>**[6]**: Parity Select (`0`=Even, `1`=Odd)<br>**[7]**: Stop Bits (`0`=1 bit, `1`=2 bits) |
| `0x0C` | **`BAUD_DIV`** | R/W | `0x0000_0036` | 16-bit Baud Rate Prescaler Divisor:<br>$$\text{BAUD\_DIV} = \frac{f_{\text{clk}}}{16 \times \text{Baud\_Rate}}$$ |
| `0x10` | **`FIFO_STAT`** | R/W | `0x0101_0000` | **[7:0]**: Current TX FIFO Count<br>**[15:8]**: Current RX FIFO Count<br>**[23:16]**: TX Watermark Threshold<br>**[31:24]**: RX Watermark Threshold |
| `0x14` | **`INTR_EN`** | R/W | `0x0000_0000` | Interrupt Enable Mask:<br>**[0]**: TX Empty Interrupt Enable<br>**[1]**: RX Ready / Watermark Interrupt Enable<br>**[2]**: Framing Error Interrupt Enable<br>**[3]**: Overrun Error Interrupt Enable |
| `0x18` | **`INTR_STATUS`** | R/W1C | `0x0000_0000` | **[RO]** Active Interrupt Status Flags<br>**[W1C]** Write `1` to clear Framing Error [2] and Overrun Error [3] |

---

## 3. Baud Rate Prescaler Calculation

For a given system clock frequency $f_{\text{clk}}$ and target baud rate $\text{Baud\_Rate}$:

$$\text{BAUD\_DIV} = \text{round}\left(\frac{f_{\text{clk}}}{16 \times \text{Baud\_Rate}}\right)$$

### Examples:
- **At $f_{\text{clk}} = 50\text{ MHz}$ and $115200\text{ bps}$**:
  $$\text{BAUD\_DIV} = \frac{50,000,000}{16 \times 115200} \approx 27 \quad (\text{0x001B})$$
- **At $f_{\text{clk}} = 100\text{ MHz}$ and $115200\text{ bps}$**:
  $$\text{BAUD\_DIV} = \frac{100,000,000}{16 \times 115200} \approx 54 \quad (\text{0x0036})$$

---

## 4. Verification & Build Commands

Run the following commands within the `AXI_UART/` directory:

```bash
# 1. Run Verilator syntax and static lint analysis
make lint

# 2. Compile simulation model
make build

# 3. Execute the full automated test suite
make test

# 4. Run testbench and generate VCD waveform file (uart_sim.vcd)
make wave

# 5. Clean temporary build and simulation artifacts
make clean
```

---

## 5. SystemVerilog Instantiation Example

```systemverilog
axi_uart_top #(
  .FIFO_DEPTH(16)
) u_uart_ip (
  .clk           (sys_clk),
  .rst_n         (sys_rst_n),
  .uart_rx_pin   (uart_rx_external),
  .uart_tx_pin   (uart_tx_external),
  .irq           (cpu_uart_irq),

  // AXI4-Lite Interface
  .s_axi_awaddr  (axi_awaddr),
  .s_axi_awprot  (axi_awprot),
  .s_axi_awvalid (axi_awvalid),
  .s_axi_awready (axi_awready),
  .s_axi_wdata   (axi_wdata),
  .s_axi_wstrb   (axi_wstrb),
  .s_axi_wvalid  (axi_wvalid),
  .s_axi_wready  (axi_wready),
  .s_axi_bresp   (axi_bresp),
  .s_axi_bvalid  (axi_bvalid),
  .s_axi_bready  (axi_bready),
  .s_axi_araddr  (axi_araddr),
  .s_axi_arprot  (axi_arprot),
  .s_axi_arvalid (axi_arvalid),
  .s_axi_arready (axi_arready),
  .s_axi_rdata   (axi_rdata),
  .s_axi_rresp   (axi_rresp),
  .s_axi_rvalid  (axi_rvalid),
  .s_axi_rready  (axi_rready)
);
```
