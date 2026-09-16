// ============================================================================
// File: test_fifo_watermark.hpp
// Description: Test 3: FIFO Count, Watermark & Overflow Error Test
// Project: AZ_V_UART
// ============================================================================

#ifndef TEST_FIFO_WATERMARK_HPP
#define TEST_FIFO_WATERMARK_HPP

#include <iostream>

template <typename Driver>
bool run_test_fifo_watermark(Driver& drv) {
    std::cout << "\n[TEST 3] Starting FIFO Watermark & Overflow Test..." << std::endl;

    // Disable UART Core to hold data in TX FIFO without transmitting
    drv.axi_write(0x08, 0x00);

    // Read STATUS (0x04) -> TX Empty should be 1
    uint32_t status = drv.axi_read(0x04);
    std::cout << "  - Initial Status: 0x" << std::hex << status << std::dec << std::endl;
    if ((status & 0x01) == 0) { // TX_EMPTY bit
        std::cerr << "  [ERROR] TX FIFO should be empty initially!" << std::endl;
        return false;
    }

    // Fill TX FIFO with 16 bytes
    std::cout << "  - Filling TX FIFO with 16 bytes..." << std::endl;
    for (int i = 0; i < 16; ++i) {
        drv.axi_write(0x00, 0xA0 + i);
    }

    // Read STATUS -> TX Full should be 1
    status = drv.axi_read(0x04);
    std::cout << "  - Full TX FIFO Status: 0x" << std::hex << status << std::dec << std::endl;
    if ((status & 0x02) == 0) { // TX_FULL bit
        std::cerr << "  [ERROR] TX FIFO should be FULL!" << std::endl;
        return false;
    }

    // Attempt writing 17th byte (overrun)
    std::cout << "  - Writing 17th byte to trigger overrun..." << std::endl;
    drv.axi_write(0x00, 0xFF);

    status = drv.axi_read(0x04);
    std::cout << "  - Overrun Status: 0x" << std::hex << status << std::dec << std::endl;
    if ((status & (1 << 8)) == 0) { // Overrun error bit
        std::cerr << "  [ERROR] Overrun error bit not set on FIFO overflow!" << std::endl;
        return false;
    }

    // Enable UART TX to drain FIFO
    drv.axi_write(0x0C, 2); // fast baud
    drv.axi_write(0x08, 0x07); // TX_EN + RX_EN + Loopback

    // Wait cycles for transmit
    drv.clock_ticks(10000);

    // Empty RX FIFO
    while ((drv.axi_read(0x04) & 0x04) != 0) {
        drv.axi_read(0x00);
    }

    std::cout << "  => [PASSED] FIFO Watermark & Overflow Test successful!\n" << std::endl;
    return true;
}

#endif // TEST_FIFO_WATERMARK_HPP
