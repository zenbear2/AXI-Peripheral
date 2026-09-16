# AXI4-Lite UART IP Core (AXI_UART)

本專案提供一個專為 **RISC-V 32-bit CPU/SoC** 設計的高效能、可配置 **AXI4-Lite UART IP 核心 (`axi_uart_top`)**。該 IP 以原生 SystemVerilog 撰寫，具備完整的 AXI4-Lite Slave 介面、獨立 16-entry TX/RX FIFO 緩衝區、16x 過採樣多數決中點採樣、內部/外部 Loopback 測試與硬體中斷 (IRQ) 訊號。

---

## 1. 主要架構特點 (Features)

- **AXI4-Lite Slave 介面**：相容標準 AXI4-Lite 32-bit 通訊協定 (獨立 Write/Read 通道與 Handshake 機制)。
- **靈活控制 (Configurable Line Control)**：
  - 資料位元：5, 6, 7, 8 bits
  - 停止位元：1 或 2 stop bits
  - 奇偶檢驗：奇檢驗 (Odd)、偶檢驗 (Even) 或無檢驗 (None)
  - 波特率 (Baud Rate)：內建 16-bit Prescaler，支援任何標準波特率 (如 9600, 115200, 921600 bps)。
- **FIFO 緩衝機制**：參數化同步 FIFO (預設 TX 16 bytes, RX 16 bytes)，支援可程式化 Watermark 臨界值。
- **可靠性設計**：
  - RX 端採用 16x 過採樣與 3-sample 多數決 (Majority Voting) 濾除雜訊。
  - 自動偵測 Framing Error、Parity Error 與 Overrun Error。
- **中斷控制器 (Interrupt Controller)**：支援 TX Empty、RX Data Ready/Watermark、Framing Error 及 Overrun Error 硬體 IRQ 斷言與 Write-1-to-Clear 清除機制。
- **測試模式 (Loopback Mode)**：可透過暫存器設定啟用內部 Serial Loopback 測試模式。

---

## 2. 暫存器地圖 (Register Map)

基址 (Base Address) 採 32-bit 對齊，所有 Offset 以 Byte 為單位：

| Offset | 暫存器名稱 | 讀/寫 | 欄位說明 |
| :--- | :--- | :---: | :--- |
| `0x00` | `TX_RX_DATA` | R/W | **[W]** 寫入 8-bit 資料至 TX FIFO<br>**[R]** 從 RX FIFO 讀取 8-bit 資料 |
| `0x04` | `STATUS` | R | **[0]**: TX FIFO Empty<br>**[1]**: TX FIFO Full<br>**[2]**: RX FIFO Valid (Not Empty)<br>**[3]**: RX FIFO Full<br>**[4]**: TX Engine Busy<br>**[5]**: RX Engine Busy<br>**[6]**: Framing Error<br>**[7]**: Parity Error<br>**[8]**: Overrun Error |
| `0x08` | `CTRL` | R/W | **[0]**: TX Enable (`1` = Enable)<br>**[1]**: RX Enable (`1` = Enable)<br>**[2]**: Loopback Enable (`1` = Enable)<br>**[4:3]**: Data Bits (`00`=5b, `01`=6b, `10`=7b, `11`=8b)<br>**[5]**: Parity Enable (`1` = Enable)<br>**[6]**: Parity Select (`0`=Even, `1`=Odd)<br>**[7]**: Stop Bits (`0`=1 bit, `1`=2 bits) |
| `0x0C` | `BAUD_DIV` | R/W | 16-bit 波特率 Prescaler 除頻數：<br>$$\text{BAUD\_DIV} = \frac{f_{\text{clk}}}{16 \times \text{Baud\_Rate}}$$ |
| `0x10` | `FIFO_STAT` | R/W | **[7:0]**: TX FIFO Count<br>**[15:8]**: RX FIFO Count<br>**[23:16]**: TX Watermark Threshold<br>**[31:24]**: RX Watermark Threshold |
| `0x14` | `INTR_EN` | R/W | 中斷致能遮罩：<br>**[0]**: TX Empty Interrupt Enable<br>**[1]**: RX Ready / Watermark Interrupt Enable<br>**[2]**: Framing Error Interrupt Enable<br>**[3]**: Overrun Error Interrupt Enable |
| `0x18` | `INTR_STATUS` | R/W1C | **[R]** 中斷狀態標籤<br>**[W1C]** 寫入 `1` 清除 Framing Err [2] 及 Overrun Err [3] |

---

## 3. 時脈除頻計算範例 (Baud Rate Calculation)

當系統主時脈 $f_{\text{clk}} = 50\text{ MHz}$ 且目標波特率為 $115200\text{ bps}$ 時：

$$\text{BAUD\_DIV} = \frac{50,000,000}{16 \times 115200} = 27.126 \approx 27 \quad (\text{0x001B})$$

若系統主時脈 $f_{\text{clk}} = 100\text{ MHz}$：

$$\text{BAUD\_DIV} = \frac{100,000,000}{16 \times 115200} = 54.253 \approx 54 \quad (\text{0x0036})$$

---

## 4. 自動化編譯與驗證指令 (Build & Run)

在 `/home/user/workspace/AXI_UART` 目錄下執行：

1. **語法與 Lint 檢測**：
   ```bash
   make lint
   ```
2. **編譯 Verilator 仿真模型**：
   ```bash
   make build
   ```
3. **執行全套自動化單元測試**：
   ```bash
   make test
   ```
4. **執行仿真並輸出 VCD 波形圖 (uart_sim.vcd)**：
   ```bash
   make wave
   ```
5. **清理編譯檔**：
   ```bash
   make clean
   ```

---

## 5. SoC 整合範例

在 SoC 頂層架構中，將 `axi_uart_top` 實例化並介接至 AXI Interconnect 或 CPU Memory Bus：

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
