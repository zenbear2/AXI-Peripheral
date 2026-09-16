// ============================================================================
// File: test_axi_reg.hpp
// Description: Test 1: AXI4-Lite Register Read/Write Access & Defaults Test
// Project: AZ_V_UART
// ============================================================================

#ifndef TEST_AXI_REG_HPP
#define TEST_AXI_REG_HPP

#include <iostream>
#include <cassert>

template <typename Driver>
bool run_test_axi_reg(Driver& drv) {
    std::cout << "\n[TEST 1] Starting AXI4-Lite Register Read/Write Access Test..." << std::endl;

    // 1. Read default Control Register (0x08) -> expected 0x0000001B (TX_EN=1, RX_EN=1, 8-bit)
    uint32_t val = drv.axi_read(0x08);
    std::cout << "  - Default CTRL Reg: 0x" << std::hex << val << std::dec << std::endl;
    if ((val & 0x1F) != 0x1B) {
        std::cerr << "  [ERROR] CTRL default value mismatch!" << std::endl;
        return false;
    }

    // 2. Read default Baud Divisor Register (0x0C) -> expected 27 (0x1B)
    val = drv.axi_read(0x0C);
    std::cout << "  - Default BAUD_DIV Reg: " << val << std::endl;
    if (val != 27) {
        std::cerr << "  [ERROR] BAUD_DIV default mismatch!" << std::endl;
        return false;
    }

    // 3. Write and Read back BAUD_DIV Register (0x0C) -> write 434 (for 115200 @ 80MHz)
    drv.axi_write(0x0C, 434);
    val = drv.axi_read(0x0C);
    std::cout << "  - Updated BAUD_DIV Reg: " << val << std::endl;
    if (val != 434) {
        std::cerr << "  [ERROR] BAUD_DIV readback mismatch!" << std::endl;
        return false;
    }

    // Reset back to small Baud Divisor for fast simulation (e.g., 2)
    drv.axi_write(0x0C, 2);

    // 4. Test FIFO_STAT (0x10) Watermark configuration
    // Write TX Watermark = 4, RX Watermark = 8
    uint32_t watermark_cfg = (8 << 24) | (4 << 16);
    drv.axi_write(0x10, watermark_cfg);
    val = drv.axi_read(0x10);
    uint32_t read_tx_wm = (val >> 16) & 0xFF;
    uint32_t read_rx_wm = (val >> 24) & 0xFF;
    std::cout << "  - Watermark Config: TX_WM=" << read_tx_wm << ", RX_WM=" << read_rx_wm << std::endl;
    if (read_tx_wm != 4 || read_rx_wm != 8) {
        std::cerr << "  [ERROR] Watermark readback mismatch!" << std::endl;
        return false;
    }

    std::cout << "  => [PASSED] AXI4-Lite Register Test successful!\n" << std::endl;
    return true;
}

#endif // TEST_AXI_REG_HPP
