# AXI_SPI: AXI4-Lite SPI Master IP Core

[![Status](https://img.shields.io/badge/Status-Fully%20Verified-brightgreen)](#)
[![Bus](https://img.shields.io/badge/Bus-AXI4--Lite%2032--bit-blue)](#)
[![Protocol](https://img.shields.io/badge/Protocol-SPI%20Modes%200%2C1%2C2%2C3-orange)](#)
[![Frame](https://img.shields.io/badge/Frame-4--32%20bits-yellow)](#)
[![Vivado](https://img.shields.io/badge/Vivado-IP%20Packaged-red)](#)
[![Language](https://img.shields.io/badge/HDL-SystemVerilog-purple)](#)

An industrial-grade, high-performance, and versatile **32-bit AXI4-Lite SPI Master IP Core (`axi_spi_top`)** designed for FPGA and ASIC SoC designs (such as AMD / Xilinx MicroBlaze, RISC-V, and Arm processors).

Supports full-duplex synchronous serial communication, all four SPI clock modes, dynamically adjustable frame widths, multi-slave chip-select control, dual FIFO buffering, hardware interrupts, and an internal BIST loopback diagnostic channel.

---

## 1. Key Architectural Features

- **Standard AXI4-Lite 32-bit Slave Interface**: Independent read/write address and data channels with standard `OKAY` handshake responses.
- **Full SPI Mode Coverage (Modes 0, 1, 2, 3)**:
  - Programmable **CPOL** (Clock Polarity: Idle Low / High) and **CPHA** (Clock Phase: Leading / Trailing Edge capture).
- **Dynamic Variable Frame Width**:
  - Supports arbitrary frame sizes from **4 to 32 bits** (programmable via `DATA_BITS`, default 8-bit), providing seamless compatibility with SPI Flash, EEPROM, ADC/DAC, sensors, and display controllers.
- **Flexible Bit Ordering**:
  - Software selectable **MSB-First** or **LSB-First** transmission order.
- **Multi-Slave Chip Select Management**:
  - 4 independent hardware Slave Select lines (`spi_ss_n[3:0]`) with configurable active polarity (`CS_POL`).
  - **Auto-CS Mode**: Automatically asserts CS at start of transmission, holds CS low during continuous FIFO bursts, and deasserts CS when complete.
  - **Manual-CS Mode**: Direct software register control of CS pin states.
- **Programmable Micro-Timing Delays**:
  - Fine hardware tuning of $T_{\text{CSS}}$ (CS Setup Time), $T_{\text{CSH}}$ (CS Hold Time), and $T_{\text{IDLE}}$ (CS Deassertion Recovery Time).
- **Dual Independent FIFO Subsystem**:
  - Parameterized TX and RX FIFOs (default 16 entries each, 32-bit data + control tags).
  - Programmable watermark threshold interrupts and software FIFO Flush controls.
  - Real-time FIFO depth tracking (`TX_LEVEL`, `RX_LEVEL`) with Overrun / Underrun error flags.
- **Hardware Interrupt Controller**:
  - Integrated IRQ generation for TX/RX Watermarks, TX Empty, RX Full, Transfer Done, and Overrun/Underrun events with Write-1-to-Clear (W1C) clearing.
- **Built-in Diagnostic Loopback (BIST)**:
  - Internal MOSI-to-MISO loopback path for self-test verification without external hardware.
- **Pre-Packaged Vivado Support**: Fully packaged with `component.xml` and `xgui/` for direct Block Design drag-and-drop.

---

## 2. Memory-Mapped Registers

Base Address is 32-bit aligned. Byte offsets:

| Offset | Register Name | Access | Reset Value | Description |
| :---: | :--- | :---: | :---: | :--- |
| `0x00` | **`SPI_CR`** | R/W | `0x0000_0001` | Control Register (`CORE_EN`, `IRQ_EN`, `LOOPBACK`, `CPOL`, `CPHA`, `LSB_FIRST`, `RX_DIS`, `TX_DIS`) |
| `0x04` | **`SPI_SR`** | RO | `0x0000_000A` | Status Register (`BUSY`, `TX_EMPTY`, `TX_FULL`, `RX_EMPTY`, `RX_FULL`, `RX_OVERRUN`, `TX_UNDERRUN`, `SS_ACTIVE`) |
| `0x08` | **`SPI_TX_DATA`** | WO | `0x0000_0000` | TX Data & Command FIFO Write Port (`Data[31:0]`) |
| `0x0C` | **`SPI_RX_DATA`** | RO | `0x0000_0000` | RX Data FIFO Read Port (`Data[31:0]`) |
| `0x10` | **`SPI_PRESCALE`** | R/W | `0x0000_0007` | Clock Prescaler Register ($f_{\text{SCK}} = \frac{f_{\text{clk}}}{2 \times (\text{PRESCALE} + 1)}$) |
| `0x14` | **`SPI_CFG`** | R/W | `0x0000_0008` | Frame Configuration (`DATA_BITS` [5:0] = 4..32, `CS_POL` [11:8]) |
| `0x18` | **`SPI_CS_CTRL`** | R/W | `0x0000_00F1` | Chip Select Control (`CS_AUTO_EN`, `CS_SEL` [2:1], `MANUAL_SS` [7:4], `KEEP_CS_DEFAULT` [8]) |
| `0x1C` | **`SPI_DELAY`** | R/W | `0x0001_0101` | Timing Delays (`T_CSS` [7:0], `T_CSH` [15:8], `T_IDLE` [31:16]) |
| `0x20` | **`SPI_FIFO_CTRL`** | R/W | `0x0004_0400` | FIFO Watermarks (`TX_WM` [5:0], `RX_WM` [13:8]) and Flush Controls (`TX_FLUSH` [16], `RX_FLUSH` [17]) |
| `0x24` | **`SPI_FIFO_STAT`** | RO | `0x1010_0000` | Real-time FIFO Depths (`TX_LEVEL` [7:0], `RX_LEVEL` [15:8], `MAX_DEPTH` [31:16]) |
| `0x28` | **`SPI_IER`** | R/W | `0x0000_0000` | Interrupt Enable Mask Register |
| `0x2C` | **`SPI_ISR`** | R/W1C | `0x0000_0000` | Interrupt Status Flags (Write-1-to-Clear) |

---

## 3. Architecture Hierarchy

```text
AXI_SPI/
├── component.xml                   # AMD / Xilinx Vivado IP definition
├── xgui/
│   └── axi_spi_top_v1_0.tcl        # Vivado GUI parameter customization script
├── rtl/
│   ├── pkg/
│   │   └── spi_pkg.sv              # Register offsets, bitmasks, states, and macros
│   ├── axi/
│   │   └── axi_lite_slave.sv       # 32-bit AXI4-Lite slave channel logic
│   ├── core/
│   │   ├── sync_fifo.sv            # Parameterized synchronous FIFO
│   │   ├── spi_timing_gen.sv       # Baud rate tick generator
│   │   ├── spi_fsm_core.sv         # SPI protocol FSM (Modes 0-3, variable frame, SerDes)
│   │   └── spi_regs.sv             # Register file, FIFO monitors, and interrupt controller
│   └── top/
│       └── axi_spi_top.sv          # Top-level AXI4-Lite SPI Master module
├── tb/
│   ├── spi_slave_model.sv          # Virtual SPI NOR Flash (W25Qxx compatible) slave model
│   ├── spi_tb.sv                   # SystemVerilog top-level testbench
│   └── tb_spi_top.cpp              # Verilator C++ automated test driver (12 test suites)
├── Makefile                        # Supports lint, build, test, wave, clean
└── README.md                       # Documentation
```

---

## 4. SPI Clock Modes Operation

| SPI Mode | CPOL (Polarity) | CPHA (Phase) | SCK Idle State | Data Sample Edge | Data Shift Edge |
| :---: | :---: | :---: | :---: | :---: | :---: |
| **Mode 0** | 0 | 0 | Low (0) | Leading Edge (Rising, $\uparrow$) | Trailing Edge (Falling, $\downarrow$) |
| **Mode 1** | 0 | 1 | Low (0) | Trailing Edge (Falling, $\downarrow$) | Leading Edge (Rising, $\uparrow$) |
| **Mode 2** | 1 | 0 | High (1) | Leading Edge (Falling, $\downarrow$) | Trailing Edge (Rising, $\uparrow$) |
| **Mode 3** | 1 | 1 | High (1) | Trailing Edge (Rising, $\uparrow$) | Leading Edge (Falling, $\downarrow$) |

---

## 5. Verification & Automated Test Suites

Accompanied by a comprehensive **Verilator-based C++ verification suite** covering 12 test suites:

```bash
# 1. Run Verilator static lint analysis (0 warnings, 0 errors)
make lint

# 2. Compile and execute all 12 automated test suites
make test

# 3. Generate VCD waveform file for timing debug
make wave
```

### Test Suite Summary
1. **`[TEST 1]` AXI4-Lite Register Read/Write Access & Reset Defaults**
2. **`[TEST 2]` Clock Prescaler & High-Speed Baud Rate Verification**
3. **`[TEST 3]` SPI Modes 0, 1, 2, and 3 Transmission & Reception**
4. **`[TEST 4]` Configurable Frame Width (4, 8, 12, 16, 24, 32 bits)**
5. **`[TEST 5]` MSB-First vs LSB-First Bit Ordering**
6. **`[TEST 6]` Multi-Slave Chip Select Switching (Slave 0 vs Slave 1)**
7. **`[TEST 7]` SPI Flash Protocol Simulation (JEDEC ID, WREN, Page Write, Read)**
8. **`[TEST 8]` High-Throughput Burst Multi-Word Transfer (FIFO Pipeline)**
9. **`[TEST 9]` Hardware Interrupts (IRQ) & Watermark Generation**
10. **`[TEST 10]` Error Handling & Overrun Flag Detection**
11. **`[TEST 11]` Auto-CS vs Manual-CS Control Modes**
12. **`[TEST 12]` Internal BIST Loopback Self-Test**

---

## 6. Firmware C Driver Example

```c
#include <stdint.h>

#define SPI_BASE        0x20010000
#define SPI_CR          (*(volatile uint32_t *)(SPI_BASE + 0x00))
#define SPI_SR          (*(volatile uint32_t *)(SPI_BASE + 0x04))
#define SPI_TX_DATA     (*(volatile uint32_t *)(SPI_BASE + 0x08))
#define SPI_RX_DATA     (*(volatile uint32_t *)(SPI_BASE + 0x0C))
#define SPI_PRESCALE    (*(volatile uint32_t *)(SPI_BASE + 0x10))
#define SPI_CFG         (*(volatile uint32_t *)(SPI_BASE + 0x14))
#define SPI_CS_CTRL     (*(volatile uint32_t *)(SPI_BASE + 0x18))
#define SPI_FIFO_CTRL   (*(volatile uint32_t *)(SPI_BASE + 0x20))

#define SR_BUSY         (1 << 0)
#define SR_TX_EMPTY     (1 << 1)

// Initialize SPI Controller (Mode 0, 8-bit frame)
void spi_init(uint32_t prescaler) {
    SPI_CR = 0x00;                           // Temporarily disable core
    SPI_PRESCALE = prescaler;                 // Program clock prescaler
    SPI_CFG = 8;                              // 8-bit frame size
    SPI_CS_CTRL = 0x0001;                     // Enable Auto-CS, target Slave 0
    SPI_CR = 0x01;                           // Enable core (Mode 0)
}

// Wait until SPI bus is idle
static inline void spi_wait_idle(void) {
    while ((SPI_SR & SR_BUSY) || !(SPI_SR & SR_TX_EMPTY));
}

// Read JEDEC ID from SPI NOR Flash (Command 0x9F)
uint32_t spi_flash_read_jedec_id(uint8_t slave_id) {
    SPI_FIFO_CTRL = (1 << 16) | (1 << 17);   // Flush TX and RX FIFOs
    
    // Auto-CS for 4 bytes: first 3 bytes hold CS low (KEEP_CS = 1)
    SPI_CS_CTRL = 0x0001 | (slave_id << 1) | (1 << 8);
    
    SPI_TX_DATA = 0x9F;                      // JEDEC ID Command opcode
    SPI_TX_DATA = 0x00;                      // Manufacturer ID dummy read
    SPI_TX_DATA = 0x00;                      // Memory Type dummy read
    
    // Last byte releases CS
    SPI_CS_CTRL = 0x0001 | (slave_id << 1);
    SPI_TX_DATA = 0x00;                      // Capacity dummy read
    
    spi_wait_idle();
    
    (void)SPI_RX_DATA;                       // Discard response to command byte
    uint8_t mfg_id = (uint8_t)SPI_RX_DATA;
    uint8_t mem_type = (uint8_t)SPI_RX_DATA;
    uint8_t cap_id = (uint8_t)SPI_RX_DATA;
    
    return ((uint32_t)mfg_id << 16) | ((uint32_t)mem_type << 8) | cap_id;
}
```
