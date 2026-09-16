// ============================================================================
// File: test_loopback.hpp
// Description: Test 2: UART Serial Internal Loopback Transmission Test
// Project: AZ_V_UART
// ============================================================================

#ifndef TEST_LOOPBACK_HPP
#define TEST_LOOPBACK_HPP

#include <iostream>
#include <string>

template <typename Driver>
bool run_test_loopback(Driver& drv) {
    std::cout << "\n[TEST 2] Starting UART Internal Loopback Test..." << std::endl;

    // 1. Set fast simulation baud prescaler (baud_div = 4)
    drv.axi_write(0x0C, 4);

    // 2. Enable Loopback Mode with 8-bit data (CTRL: TX_EN=1, RX_EN=1, LOOPBACK=1, DATA_BITS=8b -> 0x1F)
    drv.axi_write(0x08, 0x1F);

    std::string test_msg = "Hello AZ_V RISC-V SoC UART!";
    std::cout << "  - Sending String: \"" << test_msg << "\"" << std::endl;

    // Send string byte by byte
    for (char c : test_msg) {
        // Wait if TX FIFO Full
        while ((drv.axi_read(0x04) & 0x02) != 0) {
            drv.clock_ticks(10);
        }
        drv.axi_write(0x00, static_cast<uint32_t>(c));
    }

    // Wait until RX FIFO receives all characters
    std::string rx_msg = "";
    int timeout_cycles = 100000;
    while (rx_msg.length() < test_msg.length() && timeout_cycles > 0) {
        uint32_t status = drv.axi_read(0x04);
        if (status & 0x04) { // RX Valid (Not Empty)
            uint32_t rx_data = drv.axi_read(0x00) & 0xFF;
            std::cout << "    [RX DEBUG] Read byte: 0x" << std::hex << rx_data << std::dec << " ('" << static_cast<char>(rx_data) << "')" << std::endl;
            rx_msg += static_cast<char>(rx_data);
        }
        drv.clock_ticks(10);
        timeout_cycles -= 10;
    }

    std::cout << "  - Received String: \"" << rx_msg << "\"" << std::endl;

    if (rx_msg != test_msg) {
        std::cerr << "  [ERROR] Loopback mismatch!" << std::endl;
        std::cerr << "    Expected: " << test_msg << std::endl;
        std::cerr << "    Got     : " << rx_msg << std::endl;
        return false;
    }

    std::cout << "  => [PASSED] Internal Loopback Test successful!\n" << std::endl;
    return true;
}

#endif // TEST_LOOPBACK_HPP
