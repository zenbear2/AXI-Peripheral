# AXI_SPI: AXI4-Lite SPI Master IP Core

![Status](https://img.shields.io/badge/Status-Fully%20Verified-brightgreen)
![Bus](https://img.shields.io/badge/Bus-AXI4--Lite%2032--bit-blue)
![Protocol](https://img.shields.io/badge/Protocol-SPI%20Modes%200%2C1%2C2%2C3-orange)
![Frame](https://img.shields.io/badge/Frame-4--32%20bits-yellow)
![Language](https://img.shields.io/badge/HDL-SystemVerilog-purple)

工業級高效能、高擴充性 **32-bit AXI4-Lite SPI Master IP 核心 (`axi_spi_top`)**，專為 **RISC-V SoC (如 AZ_V_SoC)** 與高效能嵌入式微處理器架構設計。支援全雙工同步序列通訊、SPI 四大工作模式、動態幀長、多晶片選擇 (Multi-Slave)、FIFO 緩衝佇列、靈活時脈除頻、硬體中斷與內建自我測試迴路 (BIST Loopback)。

---

## 1. 核心功能亮點 (Key Highlights)

- **標準 AXI4-Lite 32-bit Slave 介面**：獨立讀寫位址通道、資料通道與標準 `OKAY` 回應握手協定。
- **全模式 SPI 支援 (Modes 0, 1, 2, 3)**：
  - 具備可程式化 **CPOL**（時脈極性：Idle Low / High）與 **CPHA**（時脈相位：Leading / Trailing Edge 取樣）。
- **動態可變字長 (Variable Frame Width)**：
  - 支援 **4-bit 至 32-bit** 任意位元長度（可程式化 `DATA_BITS`，預設 8-bit），完美相容各式 SPI Flash、EEPROM、ADC/DAC、感測器與顯示模組。
- **位元傳輸方向彈性 (Bit Ordering)**：
  - 支援 **MSB-First**（高位優先）與 **LSB-First**（低位優先）模式切換。
- **多通道晶片選擇 (Multi-Slave CS / SS)**：
  - 內建 4 條獨立 Slave Select 輸出（`spi_ss_n[3:0]`），支援獨立主動電位極性配置（`CS_POL`）。
  - **Auto-CS 模式**：硬體自動在傳輸開始時拉低 CS、在連續 FIFO 突發傳輸中保持 CS，並於結束時自動釋放。
  - **Manual-CS 模式**：軟體可直接寫入暫存器控制各 CS 腳位電位。
- **可程式化微時序延遲 (Programmable Timing Delays)**：
  - 支援 $T_{\text{CSS}}$ (CS Setup Time)、$T_{\text{CSH}}$ (CS Hold Time) 與 $T_{\text{IDLE}}$ (CS Deassert Recovery Time) 硬體計時微調。
- **雙向獨立 FIFO 緩衝子系統**：
  - 參數化深度 TX 與 RX FIFO（預設各 16 筆，每筆 32-bit 資料 + 4-bit 控制標籤）。
  - 支援可程式化 Watermark 水位臨界值中斷與軟體 FIFO Flush（清空）功能。
  - 提供即時 FIFO 深度狀態（`TX_LEVEL`, `RX_LEVEL`）與 Overrun / Underrun 錯誤偵測。
- **硬體中斷系統 (IRQ)**：
  - 整合 TX/RX Watermark、TX Empty、RX Full、XFER Done、RX Overrun 與 TX Underrun 等中斷事件，具備 W1C（寫 1 清除）狀態暫存器。
- **內建自我測試迴路 (BIST Loopback)**：
  - 支援內部 MOSI 迴接 MISO，無需外接硬體即可進行全雙工自我診斷。

---

## 2. 暫存器映射表 (Memory-Mapped Registers)

基底位址：`0x2001_0000`（32-bit 對齊，Byte 偏移）

| 偏移 (Offset) | 暫存器名稱 | 讀/寫 | 預設值 (Reset) | 功能說明 |
| :--- | :--- | :---: | :---: | :--- |
| `0x00` | **`SPI_CR`** | R/W | `0x0000_0001` | 控制暫存器 (`CORE_EN`, `IRQ_EN`, `LOOPBACK`, `CPOL`, `CPHA`, `LSB_FIRST`, `RX_DIS`, `TX_DIS`) |
| `0x04` | **`SPI_SR`** | RO | `0x0000_000A` | 狀態暫存器 (`BUSY`, `TX_EMPTY`, `TX_FULL`, `RX_EMPTY`, `RX_FULL`, `RX_OVERRUN`, `TX_UNDERRUN`, `SS_ACTIVE`) |
| `0x08` | **`SPI_TX_DATA`**| WO | `0x0000_0000` | TX 資料與命令 FIFO 寫入埠 (Data[31:0]) |
| `0x0C` | **`SPI_RX_DATA`**| RO | `0x0000_0000` | RX 接收資料 FIFO 讀取埠 (Data[31:0]) |
| `0x10` | **`SPI_PRESCALE`**| R/W | `0x0000_0007` | Baud Rate 除頻暫存器 ($f_{\text{SCK}} = \frac{f_{\text{clk}}}{2 \times (\text{PRESCALE} + 1)}$) |
| `0x14` | **`SPI_CFG`** | R/W | `0x0000_0008` | 幀格式設定暫存器 (`DATA_BITS` [5:0] = 4..32, `CS_POL` [11:8]) |
| `0x18` | **`SPI_CS_CTRL`**| R/W | `0x0000_00F1` | 晶片選擇控制 (`CS_AUTO_EN`, `CS_SEL` [2:1], `MANUAL_SS` [7:4], `KEEP_CS_DEFAULT` [8]) |
| `0x1C` | **`SPI_DELAY`** | R/W | `0x0001_0101` | 時序延遲設定 (`T_CSS` [7:0], `T_CSH` [15:8], `T_IDLE` [31:16]) |
| `0x20` | **`SPI_FIFO_CTRL`**| R/W | `0x0004_0400` | FIFO 水位臨界值 (`TX_WM` [5:0], `RX_WM` [13:8]) 與 Flush 控制 (`TX_FLUSH` [16], `RX_FLUSH` [17]) |
| `0x24` | **`SPI_FIFO_STAT`**| RO | `0x1010_0000` | FIFO 即時深度狀態 (`TX_LEVEL` [7:0], `RX_LEVEL` [15:8], `MAX_DEPTH` [31:16]) |
| `0x28` | **`SPI_IER`** | R/W | `0x0000_0000` | 中斷致能暫存器 |
| `0x2C` | **`SPI_ISR`** | R/W1C| `0x0000_0000` | 中斷狀態與清除暫存器 (Write-1-to-Clear) |

---

## 3. 模組架構組織 (Architecture Hierarchy)

```
AXI_SPI/
├── rtl/
│   ├── pkg/
│   │   └── spi_pkg.sv              # 暫存器偏移、位元遮罩、狀態與巨集定義
│   ├── axi/
│   │   └── axi_lite_slave.sv       # 32-bit AXI4-Lite Slave 通道控制與握手邏輯
│   ├── core/
│   │   ├── sync_fifo.sv            # 參數化同步 FIFO (TX 36-bit, RX 32-bit)
│   │   ├── spi_timing_gen.sv       # Baud Rate 半週期時脈 Tick 產生器
│   │   ├── spi_fsm_core.sv         # SPI 協定主狀態機 (Modes 0-3, 變長幀, SerDes)
│   │   └── spi_regs.sv             # 暫存器檔案、FIFO 水位監控與中斷控制器
│   └── top/
│       └── axi_spi_top.sv          # AXI4-Lite SPI Master IP 頂層模組
├── tb/
│   ├── spi_slave_model.sv          # 虛擬 SPI NOR Flash (W25Qxx 相容) / Slave 模型
│   ├── spi_tb.sv                   # SystemVerilog 頂層測試平台 (含雙 Slave 接腳)
│   └── tb_spi_top.cpp              # Verilator C++ 全自動化測試驅動程式 (12 大測試套件)
├── Makefile                        # 支援 make lint, make build, make test, make wave
└── README.md                       # 專案說明文件
```

---

## 4. SPI 模式工作原理 (SPI Modes 0, 1, 2, 3)

| SPI 模式 | CPOL (時脈極性) | CPHA (時脈相位) | SCK 閒置狀態 | 資料取樣邊緣 (Sample Edge) | 資料變換邊緣 (Shift Edge) |
| :---: | :---: | :---: | :---: | :---: | :---: |
| **Mode 0** | 0 | 0 | Low (0) | 前緣 (Rising Edge, $\uparrow$) | 後緣 (Falling Edge, $\downarrow$) |
| **Mode 1** | 0 | 1 | Low (0) | 後緣 (Falling Edge, $\downarrow$) | 前緣 (Rising Edge, $\uparrow$) |
| **Mode 2** | 1 | 0 | High (1) | 前緣 (Falling Edge, $\downarrow$) | 後緣 (Rising Edge, $\uparrow$) |
| **Mode 3** | 1 | 1 | High (1) | 後緣 (Rising Edge, $\uparrow$) | 前緣 (Falling Edge, $\downarrow$) |

---

## 5. 建置與自動化測試 (Build & Verification)

本 IP 附帶基於 **Verilator** 的 C++ 自動化驗證套件，包含 12 大測試套件，涵蓋暫存器存取、所有 SPI 模式、變長字元幀、JEDEC Flash 讀寫、FIFO 突發傳輸、Watermark 中斷及 Overrun 防護機制。

```bash
# 1. 執行 Verilator 靜態 Lint 檢查 (0 warnings, 0 errors)
make lint

# 2. 編譯並執行全部 12 大自動化測試套件
make test

# 3. 產生 VCD 波形檔進行時序分析
make wave
```

### 測試套件項目 (Automated Test Suites)
1. **`[TEST 1]` AXI4-Lite Register Read/Write Access & Reset Defaults Test**
2. **`[TEST 2]` Clock Prescaler & High-Speed Baud Rate Test**
3. **`[TEST 3]` SPI Mode 0, 1, 2, 3 Transmission & Reception Test**
4. **`[TEST 4]` Configurable Frame Width Test (4, 8, 12, 16, 24, 32 bits)**
5. **`[TEST 5]` MSB-First vs LSB-First Bit Ordering Test**
6. **`[TEST 6]` Multi-Slave Chip Select Switching Test (Slave 0 vs Slave 1)**
7. **`[TEST 7]` SPI Flash Protocol Simulation (JEDEC ID, WREN, Page Write, Read)**
8. **`[TEST 8]` High-Throughput Burst Multi-Word Transfer (FIFO Pipeline Test)**
9. **`[TEST 9]` Hardware Interrupts (IRQ) & Watermark Generation Test**
10. **`[TEST 10]` Error Handling & Overrun Flag Test**
11. **`[TEST 11]` Auto-CS vs Manual-CS Control Test**
12. **`[TEST 12]` Internal Loopback Self-Test (BIST Mode)**

---

## 6. 韌體使用範例 (C Driver Example)

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

// 初始化 SPI 控制器 (Mode 0, 8-bit, 預設 Prescale)
void spi_init(uint32_t prescaler) {
    SPI_CR = 0x00;                           // 暫時關閉核心
    SPI_PRESCALE = prescaler;                 // 設定時脈除頻
    SPI_CFG = 8;                              // 8-bit 幀長
    SPI_CS_CTRL = 0x0001;                     // 致能 Auto-CS, 目標 Slave 0
    SPI_CR = 0x01;                           // 致能 SPI 核心 (Mode 0)
}

// 等待傳輸完成
static inline void spi_wait_idle(void) {
    while ((SPI_SR & SR_BUSY) || !(SPI_SR & SR_TX_EMPTY));
}

// 讀取 SPI NOR Flash JEDEC ID (0x9F)
uint32_t spi_flash_read_jedec_id(uint8_t slave_id) {
    SPI_FIFO_CTRL = (1 << 16) | (1 << 17);   // 清空 TX/RX FIFO
    
    // 設定 Auto-CS 傳輸 4 Bytes，前 3 Bytes 保持 CS (KEEP_CS=1)
    SPI_CS_CTRL = 0x0001 | (slave_id << 1) | (1 << 8);
    SPI_TX_DATA = 0x9F;                      // 命令：Read JEDEC ID
    SPI_TX_DATA = 0x00;                      // Dummy byte for Mfg ID
    SPI_TX_DATA = 0x00;                      // Dummy byte for Memory Type
    
    // 最後 1 Byte 釋放 CS (KEEP_CS=0)
    SPI_CS_CTRL = 0x0001 | (slave_id << 1) | (0 << 8);
    SPI_TX_DATA = 0x00;                      // Dummy byte for Capacity
    
    spi_wait_idle();
    
    (void)SPI_RX_DATA;                       // 捨棄命令回傳
    uint8_t mfg  = (uint8_t)(SPI_RX_DATA & 0xFF);
    uint8_t type = (uint8_t)(SPI_RX_DATA & 0xFF);
    uint8_t cap  = (uint8_t)(SPI_RX_DATA & 0xFF);
    
    return ((uint32_t)mfg << 16) | ((uint32_t)type << 8) | cap;
}

// 連續讀取 SPI Flash 資料 (Read Data 0x03)
void spi_flash_read(uint8_t slave_id, uint32_t addr, uint8_t *buf, int len) {
    if (len <= 0) return;
    SPI_FIFO_CTRL = (1 << 16) | (1 << 17);
    
    // 發送命令與 24-bit 位址
    SPI_CS_CTRL = 0x0001 | (slave_id << 1) | (1 << 8);
    SPI_TX_DATA = 0x03;
    SPI_TX_DATA = (addr >> 16) & 0xFF;
    SPI_TX_DATA = (addr >> 8) & 0xFF;
    SPI_TX_DATA = addr & 0xFF;
    
    // 讀取資料串流
    for (int i = 0; i < len; i++) {
        if (i == len - 1) {
            SPI_CS_CTRL = 0x0001 | (slave_id << 1) | (0 << 8); // 最後一個 Byte 釋放 CS
        }
        SPI_TX_DATA = 0x00;                  // 發送 Dummy Clock
    }
    
    spi_wait_idle();
    
    // 捨棄前 4 個命令與位址回傳字元
    for (int i = 0; i < 4; i++) (void)SPI_RX_DATA;
    
    // 讀取接收緩衝區
    for (int i = 0; i < len; i++) {
        buf[i] = (uint8_t)(SPI_RX_DATA & 0xFF);
    }
}
```
