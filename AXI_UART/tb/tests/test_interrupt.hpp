// ============================================================================
// File: test_interrupt.hpp
// Description: Test 4: Hardware IRQ Generation & Interrupt Clear Test
// Project: AZ_V_UART
// ============================================================================

#ifndef TEST_INTERRUPT_HPP
#define TEST_INTERRUPT_HPP

#include <iostream>

template <typename Driver>
bool run_test_interrupt(Driver& drv) {
    std::cout << "\n[TEST 4] Starting Hardware Interrupt (IRQ) Test..." << std::endl;

    // 1. Set fast prescaler
    drv.axi_write(0x0C, 2);

    // 2. Set RX Watermark = 2 in FIFO_STAT (0x10)
    drv.axi_write(0x10, (2 << 24) | (1 << 16));

    // 3. Enable TX Empty (bit 0) & RX Ready (bit 1) Interrupts
    drv.axi_write(0x14, 0x03);

    // Enable UART + Loopback
    drv.axi_write(0x08, 0x07);

    drv.clock_ticks(10);

    // Since TX FIFO is empty, IRQ pin should be ASSERTED (HIGH)
    if (!drv.get_irq()) {
        std::cerr << "  [ERROR] IRQ should be asserted when TX FIFO is empty and TX Empty interrupt is enabled!" << std::endl;
        return false;
    }
    std::cout << "  - TX Empty IRQ asserted correctly." << std::endl;

    // 4. Disable TX Empty interrupt, keep RX Ready interrupt enabled (INTR_EN = 0x02)
    drv.axi_write(0x14, 0x02);
    drv.clock_ticks(10);

    if (drv.get_irq()) {
        std::cerr << "  [ERROR] IRQ should be deasserted when only RX Ready is enabled and RX FIFO is empty!" << std::endl;
        return false;
    }
    std::cout << "  - IRQ deasserted after masking TX Empty IRQ." << std::endl;

    // 5. Send 2 bytes to trigger RX Watermark IRQ
    drv.axi_write(0x00, 0xDE);
    drv.axi_write(0x00, 0xAD);

    // Wait cycles for transfer
    int timeout = 5000;
    while (!drv.get_irq() && timeout > 0) {
        drv.clock_ticks(10);
        timeout -= 10;
    }

    if (!drv.get_irq()) {
        std::cerr << "  [ERROR] IRQ failed to trigger on RX Watermark!" << std::endl;
        return false;
    }
    std::cout << "  - RX Watermark IRQ triggered successfully!" << std::endl;

    // 6. Read out 2 bytes from RX FIFO
    uint32_t b1 = drv.axi_read(0x00) & 0xFF;
    uint32_t b2 = drv.axi_read(0x00) & 0xFF;
    std::cout << "  - Read RX Bytes: 0x" << std::hex << b1 << ", 0x" << b2 << std::dec << std::endl;

    drv.clock_ticks(10);
    if (drv.get_irq()) {
        std::cerr << "  [ERROR] IRQ failed to deassert after reading RX FIFO below watermark!" << std::endl;
        return false;
    }
    std::cout << "  - IRQ deasserted after draining RX FIFO." << std::endl;

    std::cout << "  => [PASSED] Hardware Interrupt (IRQ) Test successful!\n" << std::endl;
    return true;
}

#endif // TEST_INTERRUPT_HPP
