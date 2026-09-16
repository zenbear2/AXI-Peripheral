# AXI_I2C: AXI4-Lite I2C Master IP Core

![Status](https://img.shields.io/badge/Status-Fully%20Verified-brightgreen)
![Bus](https://img.shields.io/badge/Bus-AXI4--Lite%2032--bit-blue)
![Protocol](https://img.shields.io/badge/Protocol-I2C%20v2.1%20%7C%20SMBus-orange)
![Speed](https://img.shields.io/badge/Speed-Sm(100k)%20%7C%20Fm(400k)%20%7C%20Fm%2B(1M)-yellow)
![Language](https://img.shields.io/badge/HDL-SystemVerilog-purple)

工業級高效能、高可靠度 **32-bit AXI4-Lite I2C Master IP 核心 (`axi_i2c_top`)**，專為 **RISC-V SoC** 與嵌入式微處理器架構設計。

---

## 1. 核心功能亮點 (Key Highlights)

- **標準 AXI4-Lite 32-bit Slave 介面**：獨立讀寫位址、資料通道與 OKAY 回應握手。
- **Command-Tagged FIFO (12-bit entry)**：
  - 同時打包控制標籤（`CMD_START`, `CMD_STOP`, `CMD_READ`, `CMD_NACK`）與 8-bit 資料。
  - CPU 可一次性提交多 Byte 連續交易（含 Repeated START），無需頻繁逐 Byte 中斷。
- **4-Phase 微時序產生器與 Prescaler**：
  - SCL 高低週期各細分為 4 個微階段（`PH_LOW`, `PH_RISE`, `PH_HIGH`, `PH_FALL`）。
  - 支援 Standard-mode (100 kbps)、Fast-mode (400 kbps) 及 Fast-mode Plus (1.0 Mbps)。
- **Clock Stretching 感知與超時防護**：
  - 自動偵測 Slave 拉低 SCL 並暫停內部微時序，Slave 釋放後即時無縫接續。
  - 具備硬體超時計數器（`I2C_TIMEOUT`）。
- **數位去突波濾波器 (Digital Deglitch Filter)**：
  - 2-Stage DFF 同步與可程式化取樣計數器，有效壓制 $\le 50\text{ ns}$ 突波雜訊。
- **多主機仲裁與衝突偵測 (Arbitration Loss Detector)**：
  - SCL 高電位期間即時比對 SDA 輸出與回讀，偵測衝突立即釋放匯流排並觸發 IRQ。
- **匯流排死鎖 9-Pulse 自動/手動復原 (Bus Stuck Recovery)**：
  - 當 SDA 被卡死拉低時，送出 9 個 SCL Clock 脈衝以喚醒/重置卡死之 Slave。

---

## 2. 暫存器映射表 (Memory-Mapped Registers)

基底位址：`0x2000_0000`（32-bit 對齊，Byte 偏移）

| 偏移 (Offset) | 暫存器名稱 | 讀/寫 | 預設值 (Reset) | 功能說明 |
| :--- | :--- | :---: | :---: | :--- |
| `0x00` | **`I2C_CR`** | R/W | `0x0000_0021` | 控制暫存器 (CORE_EN, IRQ_EN, LOOPBACK, RECOVER, STRETCH) |
| `0x04` | **`I2C_SR`** | RO | `0x0000_0014` | 狀態暫存器 (BUSY, BUS_BUSY, TX/RX EMPTY/FULL, NACK, ARB_LOST) |
| `0x08` | **`I2C_TX_CMD`** | WO | `0x0000_0000` | 命令/發送資料 FIFO 寫入埠 (12-bit: Cmd[11:8] + Data[7:0]) |
| `0x0C` | **`I2C_RX_DATA`**| RO | `0x0000_0000` | 接收資料 FIFO 讀取埠 (8-bit Data) |
| `0x10` | **`I2C_PRESCALE`**| R/W | `0x0000_007C` | 時脈除頻暫存器 (Prescaler = $f_{\text{clk}}/(4 \times f_{\text{SCL}}) - 1$) |
| `0x14` | **`I2C_TIMING`** | R/W | `0x0000_0202` | SCL 高低電位微調暫存器 |
| `0x18` | **`I2C_FILTER`** | R/W | `0x0000_0003` | 去突波濾波取樣週期數 (預設 3 cycles) |
| `0x1C` | **`I2C_FIFO_CTRL`**| R/W | `0x0004_0400` | FIFO 水位臨界值與 Flush 控制 |
| `0x20` | **`I2C_FIFO_STAT`**| RO | `0x0404_0000` | FIFO 即時深度狀態計數 |
| `0x24` | **`I2C_IER`** | R/W | `0x0000_0000` | 中斷致能暫存器 |
| `0x28` | **`I2C_ISR`** | R/W1C| `0x0000_0000` | 中斷狀態與清除暫存器 (Write-1-to-Clear) |
| `0x2C` | **`I2C_TIMEOUT`**| R/W | `0x0000_FFFF` | Clock Stretching 超時臨界值 |

---

## 3. 模組架構組織

```
AXI_I2C/
├── rtl/
│   ├── pkg/
│   │   └── i2c_pkg.sv              # 暫存器、欄位遮罩、狀態與巨集常數
│   ├── axi/
│   │   └── axi_lite_slave.sv        # 32-bit AXI4-Lite Slave 通道控制
│   ├── core/
│   │   ├── sync_fifo.sv            # 參數化同步 FIFO (TX 12-bit, RX 8-bit)
│   │   ├── i2c_input_filter.sv     # 雙階 DFF 同步與數位除突波濾波器
│   │   ├── i2c_timing_gen.sv       # 4-Phase 微時序產生器與 Clock Stretching 偵測
│   │   ├── i2c_bus_monitor.sv      # 匯流排忙碌/閒置、多主機仲裁遺失偵測
│   │   ├── i2c_fsm_core.sv         # 協定主狀態機 (START/STOP, SerDes, ACK/NACK)
│   │   └── i2c_regs.sv             # 暫存器檔案、中斷狀態與 Watermark 管理
│   └── top/
│       └── axi_i2c_top.sv          # AXI4-Lite I2C Master IP 頂層模組
├── tb/
│   ├── i2c_slave_model.sv          # 虛擬 I2C Slave / EEPROM 模型
│   ├── i2c_tb.sv                   # SystemVerilog 頂層測試平台 (含 Open-Drain 匯流排)
│   └── tb_i2c_top.cpp              # Verilator C++ 全自動化測試驅動程式
├── Makefile                        # 支援 make lint, make build, make test, make wave
└── README.md                       # 專案手冊
```

---

## 4. 建置與自動化測試 (Verification & Test Suite)

本專案具備完整且嚴謹的 **21 項 I2C / SMBus 協定規格全自動化驗證測試套件**：

| 編號 | 測試項目 (Test Case) | 規格驗證重點 (Protocol Verification Target) |
| :---: | :--- | :--- |
| **TEST 1** | **AXI4-Lite 暫存器讀寫與重置值驗證** | 驗證所有暫存器預設重置值與讀寫存取功能 |
| **TEST 2** | **時序除頻器 (Prescaler) 快速設定** | 驗證 SCL 微時序產生器之 Prescaler 程式化設定 |
| **TEST 3** | **Master 單 Byte 寫入 Slave** | 驗證標準 7-bit 位址、寫入標籤、ACK 握手與 STOP 時序 |
| **TEST 4** | **Master 單 Byte 讀取 (Repeated START)** | 驗證複合讀取交易、Repeated START、NACK 與 STOP 時序 |
| **TEST 5** | **多 Byte 連續傳輸 (8 Bytes)** | 驗證多 Byte 寫入與連續讀取資料完整性 |
| **TEST 6** | **Slave Clock Stretching 容錯支援** | 驗證 Slave 拉低 SCL 時 Master 暫停計時並即時接續時序 |
| **TEST 7** | **Slave NACK 偵測與自動終止** | 驗證 Slave 回應 NACK 時之硬體中斷與自動產生 STOP |
| **TEST 8** | **FIFO 水位臨界值與硬體中斷 (IRQ)** | 驗證 TX/RX Watermark 即時 IRQ 觸發、遮罩與清除 |
| **TEST 9** | **匯流排死鎖 9-Pulse 自動復原** | 驗證當外部 SDA 卡死時送出 9 個 SCL Pulse 喚醒 Slave |
| **TEST 10** | **直接連續讀取多 Byte (無 Restart)** | 驗證直接發送 Read 位址後連續讀取多 Byte 資料 |
| **TEST 11** | **Byte-by-Byte 延遲寫入 (ST_HOLD 保持)** | 驗證 FIFO 暫時為空時 Master 保持 SCL LOW 鎖住匯流排 |
| **TEST 12** | **Byte-by-Byte 延遲讀取 (ST_HOLD 保持)** | 驗證讀取過程 FIFO 為空時正確鎖住 SCL 直到下一指令 |
| **TEST 13** | **多主機仲裁遺失偵測 (Arbitration Loss)** | 驗證 Master 在 SCL High 偵測 SDA 衝突時即時釋放匯流排 |
| **TEST 14** | **Clock Stretching 超時防護 (Timeout)** | 驗證 Slave 長時間卡住 SCL 時硬體超時計數器自動中斷放棄 |
| **TEST 15** | **數位去突波濾波器 (Deglitch Filter)** | 驗證雙階 DFF 與濾波計數器濾除 $\le 4$ cycles 雜訊突波 |
| **TEST 16** | **Fast-mode (400k) / Fm+ (1M) 時序一致性** | 驗證 400 kbps 與 1.0 Mbps 高速模式時序與資料完整性 |
| **TEST 17** | **連續獨立交易與匯流排空閒時間 ($t_{BUF}$)** | 驗證多筆獨立交易連續執行時之 $t_{BUF}$ 與匯流排釋放正常 |
| **TEST 18** | **10-Bit Addressing 協定幀封裝** | 驗證 10-bit 位址前導標頭 (11110xx) 與資料封包傳輸 |
| **TEST 19** | **FIFO Flush 清空與溢位保護** | 驗證 TX FIFO 清空暫存器控制與滿載狀態旗標 |
| **TEST 20** | **匯流排錯誤偵測 (Bus Error)** | 驗證資料傳輸途中異常 START/STOP 雜訊的硬體偵測中斷 |
| **TEST 21** | **內部回環自檢模式 (Loopback)** | 驗證 `CR_LOOPBACK` 模式下的自我診斷與內部通道迴路 |

```bash
# 1. 執行 Verilator 靜態 Lint 檢查
make lint

# 2. 編譯並執行全部 21 大自動化協定測試套件
make test

# 3. 產生 VCD 波形檔進行時序分析
make wave
```

---

## 5. 韌體使用範例 (C Driver)

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

// 寫入 I2C Slave 暫存器
int i2c_write_reg(uint8_t dev_addr, uint8_t reg_addr, uint8_t data) {
    I2C_TX_CMD = CMD_START | (dev_addr << 1); // START + DevAddr (Write)
    I2C_TX_CMD = reg_addr;                   // Reg Offset
    I2C_TX_CMD = CMD_STOP | data;            // STOP + Data
    while (I2C_SR & 0x01);                   // Wait until Busy == 0
    return (I2C_SR & (1 << 6)) ? -1 : 0;     // Check NACK
}

// 讀取 I2C Slave 暫存器 (Combined Format)
int i2c_read_reg(uint8_t dev_addr, uint8_t reg_addr, uint8_t *val) {
    I2C_TX_CMD = CMD_START | (dev_addr << 1);      // START + DevAddr (Write)
    I2C_TX_CMD = reg_addr;                        // Reg Offset
    I2C_TX_CMD = CMD_START | (dev_addr << 1 | 1); // Repeated START + DevAddr (Read)
    I2C_TX_CMD = CMD_READ | CMD_NACK | CMD_STOP; // Read 1 Byte with NACK & STOP
    while (I2C_SR & 0x01);                        // Wait until Busy == 0
    if (I2C_SR & (1 << 6)) return -1;
    *val = (uint8_t)(I2C_RX_DATA & 0xFF);
    return 0;
}

// 連續讀取多位元組 (Direct Multi-Byte Read without Restart)
int i2c_read_bytes_direct(uint8_t dev_addr, uint8_t *buf, int len) {
    if (len <= 0) return 0;
    I2C_TX_CMD = CMD_START | (dev_addr << 1 | 1); // START + DevAddr (Read)
    for (int i = 0; i < len; i++) {
        uint32_t cmd = CMD_READ;
        if (i == len - 1) cmd |= CMD_NACK | CMD_STOP; // 最後一個 Byte 發送 NACK + STOP
        I2C_TX_CMD = cmd;
    }
    while (I2C_SR & 0x01);
    if (I2C_SR & (1 << 6)) return -1;
    for (int i = 0; i < len; i++) {
        buf[i] = (uint8_t)(I2C_RX_DATA & 0xFF);
    }
    return 0;
}
```
