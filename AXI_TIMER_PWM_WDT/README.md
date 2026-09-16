# AXI4-Lite 1 Timer + 4 PWM + Watchdog (WDT) 整合 IP

![IP Version](https://img.shields.io/badge/IP%20Version-v1.0-blue)
![Bus](https://img.shields.io/badge/Bus%20Interface-AXI4--Lite%2032--bit-brightgreen)
![Verification](https://img.shields.io/badge/Verification-100%25%20Passed%20(30%2F30)-success)
![Language](https://img.shields.io/badge/Language-SystemVerilog%20%2F%20C%2B%2B-orange)
![License](https://img.shields.io/badge/License-Apache%202.0-lightgrey)

**AXI_TIMER_PWM_WDT** 是一個專為高效能嵌入式系統、RISC-V SoC（如 `AZ_V_SoC`）以及工業馬達/電源控制打造的 **AXI4-Lite 整合週邊硬體 IP**。
此 IP 整合了 **1 組高精度 32-bit 通用定時器 (Timer / Input Capture)**、**4 通道進階 PWM 產生器 (Center/Edge-Aligned + 死區時間 + 緊急煞車保護)**，以及 **1 組工業級雙重安全防護看門狗 (Windowed Watchdog / WWDG + 預警中斷 + 硬體重置 + 暫存器鎖定)**。

---

## 1. 系統硬體架構圖 (Hardware Architecture)

```mermaid
graph TD
    subgraph AXI_BUS ["AXI4-Lite Master Interface (32-bit)"]
        AW["Write Address (AW)"]
        W["Write Data (W)"]
        B["Write Response (B)"]
        AR["Read Address (AR)"]
        R["Read Data (R)"]
    end

    subgraph AXI_TIMER_PWM_WDT ["axi_timer_pwm_wdt_top"]
        AXI_SLV["axi_lite_slave\n(Handshake & Zero-Wait Protocol)"]
        REGS["timer_pwm_wdt_regs\n(Register File & IRQ Arbiter)"]

        subgraph TIMER_BLOCK ["32-bit Timer Core (timer_core)"]
            T_PSC["32-bit Prescaler Divider"]
            T_CNT["32-bit Up/Down Counter"]
            T_CAP["Input Capture Unit (Dual-Edge Detect)"]
            T_RELOAD["Auto-Reload & Match Pulse Generator"]
        end

        subgraph PWM_BLOCK ["4-Channel Advanced PWM (pwm_core)"]
            P_PSC["32-bit PWM Prescaler"]
            P_CNT["Master Up/Down Counter\n(Edge / Center-Aligned Modes)"]
            P_CH0["PWM CH0 + DTG (Dead-Time Generator)"]
            P_CH1["PWM CH1 + DTG (Dead-Time Generator)"]
            P_CH2["PWM CH2 + DTG (Dead-Time Generator)"]
            P_CH3["PWM CH3 + DTG (Dead-Time Generator)"]
            P_BRAKE["Emergency Brake / Fault Latch Unit"]
        end

        subgraph WDT_BLOCK ["Safety Watchdog (wdt_core)"]
            W_KEY["Security Key Validator (0x55AACAFE)"]
            W_WIN["Window Violation Check (WWDG)"]
            W_CNT["32-bit Down Counter"]
            W_WARN["Pre-Warning Early IRQ (NMI)"]
            W_RST["Hardware Reset Pulse Generator (wdt_rst_n)"]
            W_LOCK["Hardware Lockout Protection (0xDEADBEEF)"]
        end

        AXI_SLV --> REGS
        REGS <--> TIMER_BLOCK
        REGS <--> PWM_BLOCK
        REGS <--> WDT_BLOCK
    end

    AW --> AXI_SLV
    W --> AXI_SLV
    AXI_SLV --> B
    AR --> AXI_SLV
    AXI_SLV --> R

    EXT_CAP["External Capture Pin"] -->|tim_capture_in| TIMER_BLOCK
    TIMER_BLOCK -->|tim_match_out| EXT_TRIG["Timer Match Trigger Out"]

    PWM_BLOCK -->|pwm_out[3:0]| EXT_PWM_P["PWM Primary Outputs (H-Bridge High-Side)"]
    PWM_BLOCK -->|pwm_out_n[3:0]| EXT_PWM_N["PWM Complementary Outputs (H-Bridge Low-Side)"]
    EXT_FAULT["Brake / Overcurrent Sensor"] -->|pwm_fault_in| PWM_BLOCK

    WDT_BLOCK -->|wdt_rst_n / wdt_reset_o| SYS_RST["SoC System Reset Controller"]

    REGS -->|irq_timer, irq_pwm, irq_wdt, irq_combined| CPU_INTR["CPU / PLIC Interrupt Lines"]
```

---

## 2. 核心功能規格亮點 (Key Features)

### A. AXI4-Lite Slave 介面 (`axi_lite_slave.sv`)
- 遵循 ARM AXI4-Lite 匯流排規範。
- 獨立讀寫狀態機，支援全速連續 Back-to-Back 零等待讀寫。
- 具備未對齊防護與 Byte-Strobe (`wstrb`) 控制。

### B. 32-bit 高精度通用定時器 (`timer_core.sv`)
- **32-bit Prescaler**：提供 $1 \sim 2^{32}$ 時脈分頻。
- **計數模式**：
  - **Auto-Reload (週期性自動重載)**：連續輸出定時中斷與觸發脈衝。
  - **One-Shot (單次觸發模式)**：計數至目標後自動停止並觸發事件。
  - **Up/Down Counting**：支援向上或向下計數。
- **輸入捕獲 (Input Capture)**：內建 2 階抗彈跳同步器，支援正緣 (Rising)、負緣 (Falling)、雙緣 (Both) 觸發捕獲，瞬間鎖存當前定時器計數值並發送中斷。
- **外部事件輸出**：每次溢位/匹配時輸出單週期脈衝 `tim_match_out`，可硬體觸發 ADC 或 DMA。

### C. 4 通道進階 PWM 產生器 (`pwm_core.sv` + `pwm_channel.sv` + `pwm_deadtime.sv`)
- **4 組獨立通道**：每通道獨立配置 32-bit 佔空比 (`CMP0` ~ `CMP3`)、獨立致能與輸出極性反相控制。
- **對齊模式 (Alignment Modes)**：
  - **邊緣對齊 (Edge-Aligned)**：單斜率向上計數 (Sawtooth)。
  - **中心對齊 (Center-Aligned / Symmetrical)**：雙斜率三角波計數 (Triangular Up-Down)，能有效抑制諧波、減少電磁干擾 (EMI)，為三相馬達與電力電子控制最佳選擇。
- **死區時間產生器 (Dead-Time Insertion / DTG)**：
  - 每通道輸出互補訊號對 (`pwm_out[x]` 與 `pwm_out_n[x]`)。
  - 可程式化死區週期 (0 ~ 65535 cycles)，在開關切換時強制插入上下臂雙 Low 空檔，100% 杜絕功率元件直通短路 (Shoot-Through)。
- **緊急煞車 / 故障保護 (Emergency Brake & Fault)**：
  - 外部 `pwm_fault_in` 故障/過流感測訊號觸發時，硬體於 1 週期內自動強制將所有 PWM 輸出鎖死為安全電位 (All-Low / All-High)，並產生中斷。

### D. 工業級雙重安全防護看門狗 (`wdt_core.sv`)
- **安全金鑰認證機制**：必須對 `WDT_KEY` 寫入 `0x55AACAFE` 方可餵狗/重載，防止軟體跑飛時隨意寫入暫存器誤餵狗。
- **視窗型看門狗模式 (Windowed Watchdog / WWDG)**：
  - 設有視窗上限與下限門檻。若程式在視窗開啟前「過早餵狗」（例如死迴圈狂刷）或「逾時未餵狗」，硬體均即刻判定系統異常並觸發處置。
- **雙階段預警與硬體重置 (Two-Stage Action)**：
  - **Stage 1 (Pre-Warning Early IRQ / NMI)**：倒數計數降至預警門檻時，提早送出預警中斷，讓 CPU 有機會保存 Crash Dump / Log。
  - **Stage 2 (Hardware Reset Pulse)**：逾時到達 0 時，由專屬硬體電路輸出指定寬度（如 16 cycles）之系統重置脈衝 `wdt_rst_n` (Active-Low) 與 `wdt_reset_o` (Active-High)。
- **硬體鎖定保護 (Lockout Protection)**：
  - 寫入 `0xDEADBEEF` 金鑰後硬體自動上鎖，所有 WDT 關鍵組態（致能、逾時時間、視窗限制）均不可再被軟體竄改或關閉，直到硬體冷重置。

---

## 3. 暫存器映射表 (Register Map)

基底位址 (Base Address) 依 SoC 連接定義（例如 `0x1000_1000`）。所有暫存器採 32-bit 對齊：

| 位移 (Offset) | 暫存器名稱 (Name) | 權限 | 預設值 | 說明 (Description) |
|---|---|---|---|---|
| `0x00` | `REG_IP_ID_VER` | RO | `0x5450_5701` | IP 辨識碼與版本號 ("TPW" v1.0) |
| `0x04` | `REG_GLOBAL_CTRL` | RW | `0x0000_0001` | Bit 0: Global Enable, Bit 1: Soft Reset |
| `0x08` | `REG_INTR_RAW` | RO | `0x0000_0000` | 原始中斷狀態旗標 (詳細見中斷表) |
| `0x0C` | `REG_INTR_EN` | RW | `0x0000_0000` | 中斷致能遮罩 |
| `0x10` | `REG_INTR_MASKED` | RO | `0x0000_0000` | 已遮罩中斷狀態 (`RAW & EN`) |
| `0x14` | `REG_INTR_CLR` | W1C | `0x0000_0000` | 中斷清除暫存器 (Write-1-to-Clear) |
| **0x20 - 0x34** | **--- 定時器 (Timer) ---** | | | |
| `0x20` | `REG_TIM_CTRL` | RW | `0x0000_0000` | Bit 0: EN, Bit 1: Mode (0=Periodic, 1=One-Shot), Bit 2: Dir (0=Up, 1=Down), Bit 3: CapEn, Bits [5:4]: CapEdge (00=Rise, 01=Fall, 10=Both), Bit 8: Soft Trigger |
| `0x24` | `REG_TIM_PRESCALER` | RW | `0x0000_0000` | 32-bit 定時器預分頻除數 (`div = Prescaler + 1`) |
| `0x28` | `REG_TIM_COUNTER` | RW | `0x0000_0000` | 32-bit 定時器當前即時計數值 (可讀可寫) |
| `0x2C` | `REG_TIM_AUTORELOAD` | RW | `0x0000_FFFF` | 32-bit 定時器自動重載週期 (ARR) |
| `0x30` | `REG_TIM_CAPTURE` | RO | `0x0000_0000` | 32-bit 外部脈衝輸入捕獲鎖存值 |
| `0x34` | `REG_TIM_STATUS` | RO | `0x0000_0000` | Bit 0: Running, Bit 1: Cap Flag, Bit 2: OVF Flag |
| **0x40 - 0x6C** | **--- 脈衝寬度調變 (PWM) ---** | | | |
| `0x40` | `REG_PWM_CTRL` | RW | `0x0000_0000` | Bit 0: Master EN, Bit 1: Center-Aligned Mode, Bit 2: Brake EN, Bit 3: Brake Pol, Bit 4: Safe Level, Bits [11:8]: Comp Out EN for CH0..3 |
| `0x44` | `REG_PWM_PRESCALER` | RW | `0x0000_0000` | 32-bit PWM 時脈預分頻除數 |
| `0x48` | `REG_PWM_PERIOD` | RW | `0x0000_03E8` | 32-bit PWM 週期長度 (ARR, 預設 1000) |
| `0x4C` | `REG_PWM_COUNTER` | RO | `0x0000_0000` | 32-bit PWM 當前計數值 |
| `0x50` | `REG_PWM_CH0_CMP` | RW | `0x0000_0000` | 通道 0 佔空比比較值 |
| `0x54` | `REG_PWM_CH1_CMP` | RW | `0x0000_0000` | 通道 1 佔空比比較值 |
| `0x58` | `REG_PWM_CH2_CMP` | RW | `0x0000_0000` | 通道 2 佔空比比較值 |
| `0x5C` | `REG_PWM_CH3_CMP` | RW | `0x0000_0000` | 通道 3 佔空比比較值 |
| `0x60` | `REG_PWM_CH_CFG` | RW | `0x0000_0000` | Bits [3:0]: CH0..3 EN, Bits [7:4]: CH0..3 Polarity |
| `0x64` | `REG_PWM_DEADTIME` | RW | `0x0000_0000` | Bits [15:0]: 互補通道死區時間插入時脈數 |
| `0x68` | `REG_PWM_FAULT_CFG` | RW | `0x0000_0000` | Bit 0: Fault Clear (Write 1 to clear latched fault) |
| `0x6C` | `REG_PWM_STATUS` | RO | `0x0000_0000` | Bit 0: Fault Active, Bits [4:1]: CH0..3 Match, Bit 5: Period Match |
| **0x80 - 0x9C** | **--- 看門狗 (Watchdog) ---** | | | |
| `0x80` | `REG_WDT_CTRL` | RW | `0x0000_0004` | Bit 0: WDT EN, Bit 1: Window EN, Bit 2: Reset EN (預設 1), Bit 3: Pre-Warn IRQ EN |
| `0x84` | `REG_WDT_KEY` | WO | - | 寫入 `0x55AACAFE` (餵狗重載), 寫入 `0xDEADBEEF` (硬體鎖定) |
| `0x88` | `REG_WDT_TIMEOUT_VAL`| RW | `0x0000_FFFF` | 32-bit 看門狗逾時倒數初始值 |
| `0x8C` | `REG_WDT_WINDOW_VAL` | RW | `0x0000_7FFF` | 32-bit 視窗型上限門檻值 (在此值以上餵狗視為違規) |
| `0x90` | `REG_WDT_WARN_VAL` | RW | `0x0000_1000` | 32-bit 預警中斷觸發門檻值 |
| `0x94` | `REG_WDT_COUNTER` | RO | `0x0000_FFFF` | 32-bit 看門狗當前倒數計數值 |
| `0x98` | `REG_WDT_STATUS` | RO | `0x0000_0000` | Bit 0: Locked, Bit 1: Timeout Flag, Bit 2: Window Violation Flag, Bit 3: Pre-Warn Flag |
| `0x9C` | `REG_WDT_RST_WIDTH` | RW | `0x0000_0010` | 8-bit 看門狗硬體重置輸出脈衝寬度 (預設 16 cycles) |

---

## 4. 中斷分配表 (Interrupt Map)

在 `INTR_RAW`、`INTR_EN`、`INTR_MASKED` 與 `INTR_CLR` 中的位元定義：

| 位元 (Bit) | 中斷來源 (Source) | 觸發條件 (Trigger Condition) | 所屬子模組 |
|---|---|---|---|
| `Bit 0` | `INTR_TIM_OVF` | 定時器計數溢位 / 匹配自動重載 | Timer |
| `Bit 1` | `INTR_TIM_CAP` | 外部 `tim_capture_in` 捕獲邊緣事件 | Timer |
| `Bit 2` | `INTR_PWM_PERIOD` | PWM 主計數器週期結束 / 新週期開始 | PWM |
| `Bit 3` | `INTR_PWM_CH0` | PWM 通道 0 佔空比比較匹配 | PWM |
| `Bit 4` | `INTR_PWM_CH1` | PWM 通道 1 佔空比比較匹配 | PWM |
| `Bit 5` | `INTR_PWM_CH2` | PWM 通道 2 佔空比比較匹配 | PWM |
| `Bit 6` | `INTR_PWM_CH3` | PWM 通道 3 佔空比比較匹配 | PWM |
| `Bit 7` | `INTR_PWM_FAULT` | PWM 緊急煞車 / 故障感測觸發 | PWM |
| `Bit 8` | `INTR_WDT_WARN` | 看門狗倒數觸及預警門檻 (Pre-Warning Early IRQ) | Watchdog |
| `Bit 9` | `INTR_WDT_WIN_FAIL` | 視窗型看門狗過早餵狗違規 (Window Violation) | Watchdog |
| `Bit 10`| `INTR_WDT_TIMEOUT` | 看門狗逾時歸零 (Timeout) | Watchdog |

---

## 5. 模組外部腳位 (Pinout Description)

```
                       +-------------------------+
                       |   axi_timer_pwm_wdt_top |
    s_axi_awaddr [31:0]|===>                     |
    s_axi_wdata  [31:0]|===>                     |===> pwm_out   [3:0] (Primary PWM)
    s_axi_araddr [31:0]|===>                     |===> pwm_out_n [3:0] (Dead-Time Complementary)
    s_axi_rdata  [31:0]|<===                     |
                       |                         |---> tim_match_out
    tim_capture_in     |--->                     |---> wdt_reset_o (Active-High Reset)
    pwm_fault_in       |--->                     |---> wdt_rst_n   (Active-Low Reset)
                       |                         |
                       |                         |---> irq_timer
                       |                         |---> irq_pwm
                       |                         |---> irq_wdt
                       |                         |---> irq_combined
                       +-------------------------+
```

---

## 6. 自動化測試與驗證結果 (Verification Suite)

本專案建置了包含 **13 項完整驗證測試套件 (涵蓋 30 個精細斷言檢查)** 的 C++ Verilator 自動化驗證環境：

```bash
cd /home/user/workspace/AXI_TIMER_PWM_WDT
make test
```

### 測試執行輸出結果：
```
================================================================================
  AXI4-Lite 1 Timer + 4 PWM + Watchdog Integrated IP - Automated Test Suite     
================================================================================

--- Test Suite 1: IP Identification & Register R/W ---
  [PASS] IP Identification Read (Expected: 0x54505701, Got: 0x1414551297)
  [PASS] Timer Auto-Reload Register Write/Read
  [PASS] PWM Period Register Write/Read
  [PASS] WDT Timeout Register Write/Read

--- Test Suite 2: Timer Prescaler & Auto-Reload Periodic Mode ---
  [PASS] Timer Prescaler Dividing Rate Check (Counter: 3)
  [PASS] Timer Overflow Interrupt Assertion (INTR_RAW: 0x1)
  [PASS] Timer Overflow Interrupt W1C Clear

--- Test Suite 3: Timer One-Shot & Down-Counting Mode ---
  [PASS] Timer Down-Counting Progress
  [PASS] Timer One-Shot Halt at 0 (Running bit: 0)

--- Test Suite 4: Timer Input Capture Event ---
  [PASS] Timer Input Capture Latch Value (Captured: 21)
  [PASS] Timer Input Capture Interrupt Flag

--- Test Suite 5: 4-Channel PWM Independent Duty Cycles ---
  [PASS] PWM CH0 Duty Cycle (~25%) (Measured: 25%)
  [PASS] PWM CH1 Duty Cycle (~50%) (Measured: 50%)
  [PASS] PWM CH2 Duty Cycle (~75%) (Measured: 75%)
  [PASS] PWM CH3 Duty Cycle (100%) (Measured: 100%)

--- Test Suite 6: PWM Center-Aligned Mode ---
  [PASS] PWM Center-Aligned Dual-Slope Operation (Verified Up-Down triangular ramp)

--- Test Suite 7: PWM Complementary Outputs & Dead-Time Insertion ---
  [PASS] No Shoot-Through Violation (p & n never simultaneously HIGH)
  [PASS] Dead-Time Non-Overlapping Gap Insertion Observed (Both-Low transition cycles: 60)

--- Test Suite 8: PWM Emergency Brake / Fault Protection ---
  [PASS] Emergency Brake Instant Kill PWM Outputs
  [PASS] Emergency Brake Fault Interrupt Generated
  [PASS] Fault Status Cleared

--- Test Suite 9: Watchdog Key Feeding & Service ---
  [PASS] WDT Countdown Active (Counter: 61)
  [PASS] WDT Service Key Reload Success (Reloaded Counter: 98)

--- Test Suite 10: Watchdog Timeout & Hardware Reset Pulse ---
  [PASS] WDT Pre-Warning Early Interrupt Fired (INTR_RAW: 0x1280, WDT_CNT: 15, WARN_REG: 10, CTRL_REG: 0x13)
  [PASS] WDT Hardware Reset Output Pulse Generated

--- Test Suite 11: Watchdog Window Violation (WWDG) ---
  [PASS] WDT Early Feed Window Violation Detected

--- Test Suite 12: Watchdog Lockout Protection ---
  [PASS] WDT Hardware Lock Bit Asserted
  [PASS] WDT Configuration Tamper-Proof Against Software Writes (CTRL: 0x5, TO: 0x4096)

--- Test Suite 13: Interrupt Matrix & Masking ---
  [PASS] Interrupt Masking Suppresses irq_combined Line
  [PASS] Interrupt Unmasking Immediately Asserts Output

================================================================================
  Automated Verification Summary: 30 PASSED, 0 FAILED
================================================================================
```

---

## 7. 軟體驅動與使用範例 (C Driver & Quickstart)

包含完整的 C 驅動標頭檔 [`sw/timer_pwm_wdt.h`](file:///home/user/workspace/AXI_TIMER_PWM_WDT/sw/timer_pwm_wdt.h) 與範例程式 [`sw/example_main.c`](file:///home/user/workspace/AXI_TIMER_PWM_WDT/sw/example_main.c)。

### 快速初始化範例：
```c
#include "timer_pwm_wdt.h"
#define TPW_BASE 0x10001000UL

void app_init(void) {
    // 1. 初始化 1ms 定時器 (50MHz / 50 = 1MHz, 1000 count = 1ms)
    tpw_timer_init(TPW_BASE, 49, 1000, true, false);
    tpw_timer_start(TPW_BASE);

    // 2. 初始化 4 通道中心對齊 50kHz PWM 並插入 400ns 死區 (20 cycles)
    tpw_pwm_init(TPW_BASE, 0, 1000, true, 20);
    tpw_pwm_set_channel(TPW_BASE, 0, 500, true, false, true); // CH0: 50% 互補輸出 (Half-Bridge)
    tpw_pwm_set_channel(TPW_BASE, 1, 250, true, false, true); // CH1: 25% 互補輸出

    // 3. 初始化視窗型看門狗 (1.0s 逾時, 0.4s 視窗保護, 100ms 預警中斷)
    tpw_wdt_init(TPW_BASE, 50000000, 30000000, 5000000, true, true, true);
    tpw_wdt_lock(TPW_BASE); // 鎖定防篡改
}

// 主迴圈定期餵狗
void loop(void) {
    tpw_wdt_feed(TPW_BASE);
}
```

---

## 8. 專案目錄結構

```
AXI_TIMER_PWM_WDT/
├── Makefile                          # 自動化建置、Lint、測試與波形生成腳本
├── README.md                         # 本規格書與使用指南
├── rtl/
│   ├── pkg/
│   │   └── timer_pwm_wdt_pkg.sv      # 常數、位址位移、金鑰與位元定義
│   ├── axi/
│   │   └── axi_lite_slave.sv         # AXI4-Lite Slave 匯流排握手控制器
│   ├── core/
│   │   ├── timer_core.sv             # 32-bit 定時器 / 輸入捕獲 / 預分頻核心
│   │   ├── pwm_deadtime.sv           # 死區時間產生器 (Non-overlapping deadband)
│   │   ├── pwm_channel.sv            # 單通道比較器、極性與死區整合
│   │   ├── pwm_core.sv               # 4 通道 PWM 產生器 (中心/邊緣對齊 + 煞車保護)
│   │   ├── wdt_core.sv               # 視窗型看門狗 (金鑰解鎖/預警中斷/硬體重置)
│   │   └── timer_pwm_wdt_regs.sv     # 統一暫存器映射與中斷仲裁矩陣
│   └── top/
│       └── axi_timer_pwm_wdt_top.sv  # 頂層整合模組
├── tb/
│   ├── tb_timer_pwm_wdt.sv           # SystemVerilog 測試台封裝頂層
│   └── tb_timer_pwm_wdt.cpp          # C++ Verilator 30 項全自動化測試套件
└── sw/
    ├── timer_pwm_wdt.h               # C/C++ 驅動程式標頭檔與暫存器結構
    └── example_main.c                # 驅動範例應用程式
```
