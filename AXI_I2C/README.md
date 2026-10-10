# AXI_I2C: AXI4-Lite I2C Master IP Core

[![Status](https://img.shields.io/badge/Status-Fully%20Verified-brightgreen)](#)
[![Bus](https://img.shields.io/badge/Bus-AXI4--Lite%2032--bit-blue)](#)
[![Protocol](https://img.shields.io/badge/Protocol-I2C%20v2.1%20%7C%20SMBus-orange)](#)
[![Speed](https://img.shields.io/badge/Speed-Sm(100k)%20%7C%20Fm(400k)%20%7C%20Fm%2B(1M)-yellow)](#)
[![Vivado](https://img.shields.io/badge/Vivado-IP%20Packaged-red)](#)
[![Language](https://img.shields.io/badge/HDL-SystemVerilog-purple)](#)

An industrial-grade, high-reliability **32-bit AXI4-Lite I2C Master IP Core (`axi_i2c_top`)** designed for FPGA and ASIC SoC designs (such as AMD / Xilinx MicroBlaze, RISC-V, and Arm processors).

---

## 1. Key Architectural Features

- **Standard AXI4-Lite 32-bit Slave Interface**: Independent read/write address and data channels with standard `OKAY` handshake responses.
- **Command-Tagged FIFO (12-bit Entry)**:
  - Packs command control tags (`CMD_START`, `CMD_STOP`, `CMD_READ`, `CMD_NACK`) along with 8-bit data bytes.
  - Allows the CPU to queue entire multi-byte transactions (including Repeated START) in a single burst without byte-by-byte interrupt overhead.
- **4-Phase Micro-Timing Generator & Prescaler**:
  - SCL High and Low periods are subdivided into 4 distinct phases (`PH_LOW`, `PH_RISE`, `PH_HIGH`, `PH_FALL`).
  - Supports Standard-mode (100 kbps), Fast-mode (400 kbps), and Fast-mode Plus (1.0 Mbps).
- **Slave Clock Stretching Support & Timeout Guard**:
  - Automatically detects slave SCL hold-down and freezes internal micro-timing, seamlessly resuming when the slave releases SCL.
  - Equipped with a hardware timeout counter (`I2C_TIMEOUT`) to prevent bus lockups.
- **Digital Deglitch Noise Filter**:
  - 2-Stage DFF synchronizer with programmable sample counter to eliminate $\le 50\text{ ns}$ noise spikes on SDA and SCL.
- **Multi-Master Bus Arbitration Loss Detection**:
  - Compares SDA output against sampled bus level during SCL High; immediately surrenders bus ownership and asserts an interrupt upon collision.
- **Hardware Bus Stuck Recovery (9-Clock Pulse)**:
  - Generates 9 SCL recovery clock pulses to reset and unhang slaves holding SDA low.
- **Pre-Packaged Vivado Support**: Fully packaged with `component.xml` and `xgui/` for direct Block Design drag-and-drop.

---

## 2. Memory-Mapped Registers

Base Address is 32-bit aligned. Byte offsets:

| Offset | Register Name | Access | Reset Value | Description |
| :---: | :--- | :---: | :---: | :--- |
| `0x00` | **`I2C_CR`** | R/W | `0x0000_0021` | Control Register (`CORE_EN`, `IRQ_EN`, `LOOPBACK`, `RECOVER`, `STRETCH`) |
| `0x04` | **`I2C_SR`** | RO | `0x0000_0014` | Status Register (`BUSY`, `BUS_BUSY`, `TX_EMPTY`, `TX_FULL`, `RX_EMPTY`, `RX_FULL`, `NACK`, `ARB_LOST`) |
| `0x08` | **`I2C_TX_CMD`** | WO | `0x0000_0000` | Command & TX Data FIFO Write Port (12-bit: `Cmd[11:8]` + `Data[7:0]`) |
| `0x0C` | **`I2C_RX_DATA`** | RO | `0x0000_0000` | RX Data FIFO Read Port (8-bit Data) |
| `0x10` | **`I2C_PRESCALE`** | R/W | `0x0000_007C` | Clock Prescaler Register ($\text{Prescaler} = \frac{f_{\text{clk}}}{4 \times f_{\text{SCL}}} - 1$) |
| `0x14` | **`I2C_TIMING`** | R/W | `0x0000_0202` | SCL High / Low Fine Timing Adjustment Register |
| `0x18` | **`I2C_FILTER`** | R/W | `0x0000_0003` | Deglitch Filter Sampling Cycles (default 3 cycles) |
| `0x1C` | **`I2C_FIFO_CTRL`** | R/W | `0x0004_0400` | FIFO Watermark Thresholds and Software Flush Control |
| `0x20` | **`I2C_FIFO_STAT`** | RO | `0x0404_0000` | Real-time TX and RX FIFO Entry Counts |
| `0x24` | **`I2C_IER`** | R/W | `0x0000_0000` | Interrupt Enable Mask Register |
| `0x28` | **`I2C_ISR`** | R/W1C | `0x0000_0000` | Interrupt Status Flags (Write-1-to-Clear) |
| `0x2C` | **`I2C_TIMEOUT`** | R/W | `0x0000_FFFF` | Clock Stretching Timeout Threshold |

---

## 3. Module Architecture Hierarchy

```text
AXI_I2C/
├── component.xml                   # AMD / Xilinx Vivado IP definition
├── xgui/
│   └── axi_i2c_top_v1_0.tcl        # Vivado GUI parameter customization script
├── rtl/
│   ├── pkg/
│   │   └── i2c_pkg.sv              # Registers, bitmasks, states, and constants
│   ├── axi/
│   │   └── axi_lite_slave.sv       # 32-bit AXI4-Lite slave channel logic
│   ├── core/
│   │   ├── sync_fifo.sv            # Synchronous FIFO (TX 12-bit, RX 8-bit)
│   │   ├── i2c_input_filter.sv     # 2-stage DFF and deglitch filter
│   │   ├── i2c_timing_gen.sv       # 4-phase micro-timing generator & stretch detector
│   │   ├── i2c_bus_monitor.sv      # Bus busy / idle and arbitration loss detector
│   │   ├── i2c_fsm_core.sv         # Protocol FSM (START/STOP, SerDes, ACK/NACK)
│   │   └── i2c_regs.sv             # Register file, interrupts, and watermark logic
│   └── top/
│       └── axi_i2c_top.sv          # Top-level AXI4-Lite I2C Master module
├── tb/
│   ├── i2c_slave_model.sv          # Virtual I2C Slave / EEPROM model
│   ├── i2c_tb.sv                   # SystemVerilog top-level testbench
│   └── tb_i2c_top.cpp              # Verilator C++ automated test driver (21 test suites)
├── Makefile                        # Supports lint, build, test, wave, clean
└── README.md                       # Documentation
```

---

## 4. Verification & Automated Test Suites

This IP features a comprehensive, self-checking automated verification suite covering **21 protocol test cases**:

| Test ID | Test Case | Target Specification Verified |
| :---: | :--- | :--- |
| **TEST 1** | **AXI4-Lite Register Access & Reset Defaults** | Verifies default reset values and read/write accessibility of all registers |
| **TEST 2** | **Prescaler Configuration** | Validates SCL micro-timing prescaler programming |
| **TEST 3** | **Single-Byte Write to Slave** | Tests 7-bit addressing, write flag, slave ACK, and STOP sequence |
| **TEST 4** | **Single-Byte Read with Repeated START** | Tests write pointer, Repeated START, read data, NACK, and STOP |
| **TEST 5** | **Multi-Byte Burst Transfer (8 Bytes)** | Verifies multi-byte sequential write and continuous read data integrity |
| **TEST 6** | **Slave Clock Stretching Support** | Validates timing suspension when slave pulls SCL low and seamless resume |
| **TEST 7** | **Slave NACK Detection & Auto-Abort** | Verifies hardware interrupt assertion and automatic STOP generation on NACK |
| **TEST 8** | **FIFO Watermarks & Hardware IRQ** | Validates TX/RX watermark IRQ assertion, masking, and clearing |
| **TEST 9** | **Bus Stuck 9-Pulse Recovery** | Tests 9 SCL pulse emission when external SDA line is held low |
| **TEST 10** | **Direct Multi-Byte Read without Restart** | Validates direct read command sequences without preceding write phase |
| **TEST 11** | **Byte-by-Byte Delayed Write (ST_HOLD)** | Tests bus retention (SCL low) when TX FIFO becomes temporarily empty |
| **TEST 12** | **Byte-by-Byte Delayed Read (ST_HOLD)** | Tests bus retention during multi-byte reads when waiting for next read command |
| **TEST 13** | **Multi-Master Arbitration Loss** | Verifies immediate bus release when SDA contention is detected during SCL High |
| **TEST 14** | **Clock Stretching Timeout Guard** | Verifies hardware timeout interrupt when slave holds SCL low excessively |
| **TEST 15** | **Digital Deglitch Filter Verification** | Tests rejection of noise glitches $\le 4$ clock cycles on SDA/SCL |
| **TEST 16** | **Fast-mode (400k) & Fm+ (1M) Timing** | Validates timing and signal integrity under 400 kbps and 1.0 Mbps modes |
| **TEST 17** | **Back-to-Back Transactions & Bus Free ($t_{BUF}$)**| Verifies bus idle time ($t_{BUF}$) between successive transactions |
| **TEST 18** | **10-Bit Addressing Protocol Framing** | Validates 10-bit address header (`11110xx`) and 2-byte address frame transmission |
| **TEST 19** | **FIFO Flush & Overflow Protection** | Verifies software FIFO flush controls and full/empty flag status |
| **TEST 20** | **Bus Error Detection** | Tests hardware detection and IRQ reporting of unexpected START/STOP conditions |
| **TEST 21** | **Internal Loopback Self-Test** | Validates internal loopback diagnostic channel operation |

```bash
# 1. Run Verilator static lint check
make lint

# 2. Compile and run all 21 automated protocol test suites
make test

# 3. Generate VCD waveform file for timing analysis
make wave
```

---

## 5. Firmware C Driver Example

```c
#include <stdint.h>

#define I2C_BASE        0x20000000
#define I2C_CR          (*(volatile uint32_t *)(I2C_BASE + 0x00))
#define I2C_SR          (*(volatile uint32_t *)(I2C_BASE + 0x04))
#define I2C_TX_CMD      (*(volatile uint32_t *)(I2C_BASE + 0x08))
#define I2C_RX_DATA     (*(volatile uint32_t *)(I2C_BASE + 0x0C))
#define I2C_PRESCALE    (*(volatile uint32_t *)(I2C_BASE + 0x10))

#define CMD_START       (1 << 8)
#define CMD_STOP        (1 << 9)
#define CMD_READ        (1 << 10)
#define CMD_NACK        (1 << 11)

// Write a byte to an I2C slave register
int i2c_write_reg(uint8_t dev_addr, uint8_t reg_addr, uint8_t data) {
    I2C_TX_CMD = CMD_START | (dev_addr << 1); // START + DevAddr (Write)
    I2C_TX_CMD = reg_addr;                   // Register Offset
    I2C_TX_CMD = CMD_STOP | data;            // STOP + Data
    while (I2C_SR & 0x01);                   // Wait until Busy == 0
    return (I2C_SR & (1 << 6)) ? -1 : 0;     // Return -1 on NACK
}

// Read a byte from an I2C slave register (Combined Format)
int i2c_read_reg(uint8_t dev_addr, uint8_t reg_addr, uint8_t *val) {
    I2C_TX_CMD = CMD_START | (dev_addr << 1);      // START + DevAddr (Write)
    I2C_TX_CMD = reg_addr;                        // Register Offset
    I2C_TX_CMD = CMD_START | (dev_addr << 1 | 1); // Repeated START + DevAddr (Read)
    I2C_TX_CMD = CMD_READ | CMD_NACK | CMD_STOP; // Read 1 Byte with NACK & STOP
    while (I2C_SR & 0x01);                        // Wait until Busy == 0
    if (I2C_SR & (1 << 6)) return -1;             // Return -1 on NACK
    *val = (uint8_t)(I2C_RX_DATA & 0xFF);
    return 0;
}
```
