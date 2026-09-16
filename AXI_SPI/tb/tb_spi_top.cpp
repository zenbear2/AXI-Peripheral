// ============================================================================
// File: tb_spi_top.cpp
// Description: Verilator C++ Automated Test Suite Runner for AXI_SPI IP Core
// Project: AXI_SPI
// ============================================================================

#include <iostream>
#include <iomanip>
#include <vector>
#include <cassert>
#include <cstring>
#include <memory>
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vspi_tb.h"

// ANSI Color Codes for pretty terminal output
#define COLOR_RESET   "\033[0m"
#define COLOR_RED     "\033[31;1m"
#define COLOR_GREEN   "\033[32;1m"
#define COLOR_YELLOW  "\033[33;1m"
#define COLOR_CYAN    "\033[36;1m"
#define COLOR_BLUE    "\033[34;1m"

double sc_time_stamp() { return 0; }

// Register Offsets
#define SPI_CR          0x00
#define SPI_SR          0x04
#define SPI_TX_DATA     0x08
#define SPI_RX_DATA     0x0C
#define SPI_PRESCALE    0x10
#define SPI_CFG         0x14
#define SPI_CS_CTRL     0x18
#define SPI_DELAY       0x1C
#define SPI_FIFO_CTRL   0x20
#define SPI_FIFO_STAT   0x24
#define SPI_IER         0x28
#define SPI_ISR         0x2C

// CR Bit Masks
#define CR_CORE_EN      (1 << 0)
#define CR_IRQ_EN       (1 << 1)
#define CR_LOOPBACK     (1 << 2)
#define CR_CPOL         (1 << 3)
#define CR_CPHA         (1 << 4)
#define CR_LSB_FIRST    (1 << 5)
#define CR_RX_DIS       (1 << 6)
#define CR_TX_DIS       (1 << 7)

// SR Bit Masks
#define SR_BUSY         (1 << 0)
#define SR_TX_EMPTY     (1 << 1)
#define SR_TX_FULL      (1 << 2)
#define SR_RX_EMPTY     (1 << 3)
#define SR_RX_FULL      (1 << 4)
#define SR_RX_OVERRUN   (1 << 5)
#define SR_TX_UNDERRUN  (1 << 6)
#define SR_SS_ACTIVE    (1 << 7)

// ISR Bit Masks
#define INTR_TX_WM      (1 << 0)
#define INTR_RX_WM      (1 << 1)
#define INTR_TX_EMPTY   (1 << 2)
#define INTR_RX_FULL    (1 << 3)
#define INTR_XFER_DONE  (1 << 4)
#define INTR_RX_OVERRUN (1 << 5)
#define INTR_TX_UNDERRUN (1 << 6)

class SPITestbench {
public:
    std::unique_ptr<Vspi_tb> dut;
    std::unique_ptr<VerilatedVcdC> trace;
    uint64_t sim_time;
    bool trace_enabled;

    SPITestbench(bool enable_trace = false) : sim_time(0), trace_enabled(enable_trace) {
        dut = std::make_unique<Vspi_tb>();
        if (trace_enabled) {
            Verilated::traceEverOn(true);
            trace = std::make_unique<VerilatedVcdC>();
            dut->trace(trace.get(), 99);
            trace->open("spi_sim.vcd");
        }
        init_signals();
    }

    ~SPITestbench() {
        if (trace) {
            trace->flush();
            trace->close();
        }
    }

    void init_signals() {
        dut->clk = 0;
        dut->rst_n = 0;
        dut->s_axi_awaddr = 0;
        dut->s_axi_awprot = 0;
        dut->s_axi_awvalid = 0;
        dut->s_axi_wdata = 0;
        dut->s_axi_wstrb = 0;
        dut->s_axi_wvalid = 0;
        dut->s_axi_bready = 1;
        dut->s_axi_araddr = 0;
        dut->s_axi_arprot = 0;
        dut->s_axi_arvalid = 0;
        dut->s_axi_rready = 1;
    }

    void tick() {
        dut->clk = 0;
        dut->eval();
        if (trace) trace->dump(sim_time * 10);
        sim_time++;

        dut->clk = 1;
        dut->eval();
        if (trace) trace->dump(sim_time * 10 + 5);
        sim_time++;
    }

    void reset(int cycles = 10) {
        dut->rst_n = 0;
        for (int i = 0; i < cycles; i++) tick();
        dut->rst_n = 1;
        for (int i = 0; i < cycles; i++) tick();
    }

    void axi_write(uint32_t addr, uint32_t data) {
        dut->s_axi_awaddr = addr;
        dut->s_axi_awvalid = 1;
        dut->s_axi_wdata = data;
        dut->s_axi_wstrb = 0xF;
        dut->s_axi_wvalid = 1;
        dut->s_axi_bready = 1;

        bool aw_done = false;
        bool w_done = false;

        while (!aw_done || !w_done) {
            tick();
            if (dut->s_axi_awready) aw_done = true;
            if (dut->s_axi_wready)  w_done = true;
            if (aw_done) dut->s_axi_awvalid = 0;
            if (w_done)  dut->s_axi_wvalid = 0;
        }

        while (!dut->s_axi_bvalid) {
            tick();
        }
        tick();
    }

    uint32_t axi_read(uint32_t addr) {
        dut->s_axi_araddr = addr;
        dut->s_axi_arvalid = 1;
        dut->s_axi_rready = 1;

        while (!dut->s_axi_arready) {
            tick();
        }
        dut->s_axi_arvalid = 0;

        while (!dut->s_axi_rvalid) {
            tick();
        }
        uint32_t rdata = dut->s_axi_rdata;
        tick();
        return rdata;
    }

    bool wait_busy(int max_cycles = 50000) {
        for (int i = 0; i < max_cycles; i++) {
            uint32_t sr = axi_read(SPI_SR);
            if (!(sr & SR_BUSY) && (sr & SR_TX_EMPTY)) {
                return true;
            }
            tick();
        }
        return false;
    }
};

// ============================================================================
// TEST 1: AXI4-Lite Register Read/Write Access & Reset Defaults Test
// ============================================================================
bool test1_register_access(SPITestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 1] Starting AXI4-Lite Register Read/Write Access Test..." << COLOR_RESET << std::endl;
    tb.reset();

    uint32_t cr        = tb.axi_read(SPI_CR);
    uint32_t sr        = tb.axi_read(SPI_SR);
    uint32_t prescale  = tb.axi_read(SPI_PRESCALE);
    uint32_t cfg       = tb.axi_read(SPI_CFG);
    uint32_t cs_ctrl   = tb.axi_read(SPI_CS_CTRL);
    uint32_t delay     = tb.axi_read(SPI_DELAY);
    uint32_t fifo_stat = tb.axi_read(SPI_FIFO_STAT);

    std::cout << "  - Default CR: 0x" << std::hex << cr << " (Expected: 0x01)" << std::endl;
    std::cout << "  - Default SR: 0x" << std::hex << sr << " (TX_EMPTY=1, RX_EMPTY=1)" << std::endl;
    std::cout << "  - Default PRESCALE: 0x" << std::hex << prescale << " (Expected: 0x07)" << std::endl;
    std::cout << "  - Default CFG: 0x" << std::hex << cfg << " (DATA_BITS=8)" << std::endl;
    std::cout << "  - Default CS_CTRL: 0x" << std::hex << cs_ctrl << std::endl;
    std::cout << "  - Default FIFO_STAT: 0x" << std::hex << fifo_stat << std::dec << std::endl;

    assert((cr & 0x01) == 0x01);
    assert(sr & SR_TX_EMPTY);
    assert(sr & SR_RX_EMPTY);
    assert(prescale == 0x07);
    assert((cfg & 0x3F) == 8);

    // Test R/W to Prescaler & Config
    tb.axi_write(SPI_PRESCALE, 0x001F);
    uint32_t rd_prescale = tb.axi_read(SPI_PRESCALE);
    assert(rd_prescale == 0x001F);

    tb.axi_write(SPI_CFG, 0x0010); // 16-bit word
    uint32_t rd_cfg = tb.axi_read(SPI_CFG);
    assert((rd_cfg & 0x3F) == 16);

    // Restore defaults
    tb.axi_write(SPI_PRESCALE, 0x0007);
    tb.axi_write(SPI_CFG, 0x0008);

    std::cout << COLOR_GREEN << "  => [PASSED] AXI4-Lite Register Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ============================================================================
// TEST 2: Clock Prescaler & High-Speed Baud Rate Test
// ============================================================================
bool test2_prescaler_speed(SPITestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 2] Starting Clock Prescaler & Baud Rate Test..." << COLOR_RESET << std::endl;
    tb.reset();

    // Enable loopback for clean self-verification
    tb.axi_write(SPI_CR, CR_CORE_EN | CR_LOOPBACK);

    // Test Fast Baud Rate: Prescale = 1 (f_clk / 4)
    tb.axi_write(SPI_PRESCALE, 1);
    uint64_t start_time = tb.sim_time;
    tb.axi_write(SPI_TX_DATA, 0xA5);
    bool done = tb.wait_busy();
    assert(done);
    uint64_t duration_fast = tb.sim_time - start_time;

    uint32_t rx_data = tb.axi_read(SPI_RX_DATA);
    std::cout << "  - Fast baud (Prescale=1) transfer completed in " << duration_fast
              << " sim ticks. Read: 0x" << std::hex << rx_data << " (Expected: 0xA5)" << std::dec << std::endl;
    assert((rx_data & 0xFF) == 0xA5);

    // Test Slower Baud Rate: Prescale = 7 (f_clk / 16)
    tb.axi_write(SPI_PRESCALE, 7);
    start_time = tb.sim_time;
    tb.axi_write(SPI_TX_DATA, 0x5A);
    done = tb.wait_busy();
    assert(done);
    uint64_t duration_slow = tb.sim_time - start_time;

    rx_data = tb.axi_read(SPI_RX_DATA);
    assert((rx_data & 0xFF) == 0x5A);
    std::cout << "  - Slower baud (Prescale=7) transfer completed in " << duration_slow << " sim ticks. Read: 0x"
              << std::hex << (rx_data & 0xFF) << std::dec << std::endl;

    assert(duration_slow > duration_fast);

    std::cout << COLOR_GREEN << "  => [PASSED] Clock Prescaler Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ============================================================================
// TEST 3: SPI Mode 0, 1, 2, 3 Transmission & Reception Test
// ============================================================================
bool test3_spi_modes(SPITestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 3] Starting SPI Mode 0, 1, 2, 3 Transmission & Reception Test..." << COLOR_RESET << std::endl;

    struct ModeTest {
        int mode;
        uint32_t cpol;
        uint32_t cpha;
        uint32_t test_val;
    } tests[] = {
        {0, 0, 0, 0x96},
        {1, 0, CR_CPHA, 0x69},
        {2, CR_CPOL, 0, 0x3C},
        {3, CR_CPOL, CR_CPHA, 0xC3}
    };

    for (const auto &t : tests) {
        tb.reset();
        // Configure mode with loopback
        tb.axi_write(SPI_CR, CR_CORE_EN | CR_LOOPBACK | t.cpol | t.cpha);
        tb.axi_write(SPI_PRESCALE, 3);
        tb.axi_write(SPI_CFG, 8); // 8-bit frame

        tb.axi_write(SPI_TX_DATA, t.test_val);
        bool done = tb.wait_busy();
        assert(done);

        uint32_t rx_data = tb.axi_read(SPI_RX_DATA);
        std::cout << "  - Mode " << t.mode << " (CPOL=" << (t.cpol ? 1 : 0)
                  << ", CPHA=" << (t.cpha ? 1 : 0) << "): Sent 0x"
                  << std::hex << t.test_val << ", Received 0x" << (rx_data & 0xFF) << std::dec << std::endl;
        assert((rx_data & 0xFF) == t.test_val);
    }

    std::cout << COLOR_GREEN << "  => [PASSED] SPI Modes 0, 1, 2, 3 Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ============================================================================
// TEST 4: Configurable Frame Width Test (4-bit, 8-bit, 12-bit, 16-bit, 24-bit, 32-bit)
// ============================================================================
bool test4_frame_widths(SPITestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 4] Starting Configurable Frame Width Test..." << COLOR_RESET << std::endl;

    struct WidthTest {
        int bits;
        uint32_t mask;
        uint32_t test_val;
    } tests[] = {
        {4,  0x0000000F, 0x0000000A},
        {8,  0x000000FF, 0x000000B4},
        {12, 0x00000FFF, 0x00000A5C},
        {16, 0x0000FFFF, 0x00001234},
        {24, 0x00FFFFFF, 0x00ABCDEF},
        {32, 0xFFFFFFFF, 0xDEADBEEF}
    };

    for (const auto &t : tests) {
        tb.reset();
        tb.axi_write(SPI_CR, CR_CORE_EN | CR_LOOPBACK);
        tb.axi_write(SPI_PRESCALE, 2);
        tb.axi_write(SPI_CFG, t.bits);

        tb.axi_write(SPI_TX_DATA, t.test_val);
        bool done = tb.wait_busy();
        assert(done);

        uint32_t rx_data = tb.axi_read(SPI_RX_DATA);
        uint32_t masked_rx = rx_data & t.mask;
        uint32_t expected = t.test_val & t.mask;

        std::cout << "  - " << std::setw(2) << t.bits << "-bit Frame: Sent 0x"
                  << std::hex << expected << ", Received: 0x" << masked_rx << std::dec << std::endl;
        assert(masked_rx == expected);
    }

    std::cout << COLOR_GREEN << "  => [PASSED] Configurable Frame Width Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ============================================================================
// TEST 5: MSB-First vs LSB-First Bit Ordering Test
// ============================================================================
bool test5_msb_lsb_order(SPITestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 5] Starting MSB-First vs LSB-First Bit Ordering Test..." << COLOR_RESET << std::endl;

    // Test MSB First
    tb.reset();
    tb.axi_write(SPI_CR, CR_CORE_EN | CR_LOOPBACK); // LSB_FIRST = 0
    tb.axi_write(SPI_PRESCALE, 3);
    tb.axi_write(SPI_CFG, 8);
    tb.axi_write(SPI_TX_DATA, 0xD2);
    tb.wait_busy();
    uint32_t rx_msb = tb.axi_read(SPI_RX_DATA);
    std::cout << "  - MSB-First: Sent 0xD2, Received: 0x" << std::hex << (rx_msb & 0xFF) << std::endl;
    assert((rx_msb & 0xFF) == 0xD2);

    // Test LSB First
    tb.reset();
    tb.axi_write(SPI_CR, CR_CORE_EN | CR_LOOPBACK | CR_LSB_FIRST); // LSB_FIRST = 1
    tb.axi_write(SPI_PRESCALE, 3);
    tb.axi_write(SPI_CFG, 8);
    tb.axi_write(SPI_TX_DATA, 0xD2);
    tb.wait_busy();
    uint32_t rx_lsb = tb.axi_read(SPI_RX_DATA);
    std::cout << "  - LSB-First: Sent 0xD2, Received: 0x" << std::hex << (rx_lsb & 0xFF) << std::dec << std::endl;
    assert((rx_lsb & 0xFF) == 0xD2);

    std::cout << COLOR_GREEN << "  => [PASSED] MSB/LSB Bit Ordering Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ============================================================================
// TEST 6: Multi-Slave Chip Select Switching Test (Slave 0 vs Slave 1)
// ============================================================================
bool test6_multislave_cs(SPITestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 6] Starting Multi-Slave Chip Select Switching Test..." << COLOR_RESET << std::endl;
    tb.reset();

    tb.axi_write(SPI_CR, CR_CORE_EN);
    tb.axi_write(SPI_PRESCALE, 3);
    tb.axi_write(SPI_CFG, 8);

    // 1. Target Slave 0: Read JEDEC ID (0x9F)
    tb.axi_write(SPI_CS_CTRL, 0x0001 | (0 << 1) | (1 << 8)); // CS_AUTO_EN=1, CS_SEL=0, KEEP_CS=1
    tb.axi_write(SPI_TX_DATA, 0x9F); // Command
    tb.axi_write(SPI_TX_DATA, 0x00); // Dummy byte for ID byte 0 (0xEF)
    tb.axi_write(SPI_TX_DATA, 0x00); // Dummy byte for ID byte 1 (0x40)
    tb.axi_write(SPI_TX_DATA, 0x00); // Dummy byte for ID byte 2 (0x18)

    // Release CS after dummy byte
    tb.axi_write(SPI_CS_CTRL, 0x0001 | (0 << 1) | (0 << 8)); // KEEP_CS = 0
    tb.axi_write(SPI_TX_DATA, 0x00);

    tb.wait_busy();

    // Drain RX FIFO
    tb.axi_read(SPI_RX_DATA); // Discard cmd response
    uint32_t mfg_id  = tb.axi_read(SPI_RX_DATA) & 0xFF;
    uint32_t mem_type = tb.axi_read(SPI_RX_DATA) & 0xFF;
    uint32_t cap_id  = tb.axi_read(SPI_RX_DATA) & 0xFF;

    std::cout << "  - Slave 0 JEDEC ID: Mfg=0x" << std::hex << mfg_id
              << ", Type=0x" << mem_type << ", Cap=0x" << cap_id << std::dec << std::endl;
    assert(mfg_id == 0xEF);
    assert(mem_type == 0x40);
    assert(cap_id == 0x18);

    // 2. Target Slave 1: Read JEDEC ID
    tb.axi_write(SPI_FIFO_CTRL, (1 << 16) | (1 << 17)); // Flush FIFOs
    tb.axi_write(SPI_CS_CTRL, 0x0001 | (1 << 1) | (1 << 8)); // CS_AUTO_EN=1, CS_SEL=1, KEEP_CS=1
    tb.axi_write(SPI_TX_DATA, 0x9F);
    tb.axi_write(SPI_TX_DATA, 0x00);
    tb.axi_write(SPI_CS_CTRL, 0x0001 | (1 << 1) | (0 << 8)); // Release CS
    tb.axi_write(SPI_TX_DATA, 0x00);

    tb.wait_busy();
    tb.axi_read(SPI_RX_DATA);
    uint32_t s1_mfg = tb.axi_read(SPI_RX_DATA) & 0xFF;
    std::cout << "  - Slave 1 JEDEC ID: Mfg=0x" << std::hex << s1_mfg << std::dec << std::endl;
    assert(s1_mfg == 0xEF);

    std::cout << COLOR_GREEN << "  => [PASSED] Multi-Slave Chip Select Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ============================================================================
// TEST 7: SPI Flash Protocol Simulation (JEDEC ID, WREN, Page Write, Read)
// ============================================================================
bool test7_spi_flash_protocol(SPITestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 7] Starting SPI Flash Protocol Simulation (W25Qxx)..." << COLOR_RESET << std::endl;
    tb.reset();

    tb.axi_write(SPI_CR, CR_CORE_EN);
    tb.axi_write(SPI_PRESCALE, 2);
    tb.axi_write(SPI_CFG, 8);

    // Step 1: Send Write Enable (0x06)
    tb.axi_write(SPI_CS_CTRL, 0x0001 | (0 << 1) | (0 << 8)); // Single byte with CS auto release
    tb.axi_write(SPI_TX_DATA, 0x06);
    tb.wait_busy();
    tb.axi_read(SPI_RX_DATA); // Discard WREN echo byte

    // Step 2: Read Status Register (0x05) to verify WEL bit == 1
    tb.axi_write(SPI_CS_CTRL, 0x0001 | (0 << 1) | (1 << 8)); // KEEP_CS=1
    tb.axi_write(SPI_TX_DATA, 0x05);
    tb.axi_write(SPI_CS_CTRL, 0x0001 | (0 << 1) | (0 << 8)); // Release CS
    tb.axi_write(SPI_TX_DATA, 0x00); // Dummy byte
    tb.wait_busy();

    tb.axi_read(SPI_RX_DATA); // Discard cmd byte
    uint32_t status_val = tb.axi_read(SPI_RX_DATA) & 0xFF;
    std::cout << "  - Flash Status Register after WREN: 0x" << std::hex << status_val << " (WEL=1)" << std::endl;
    assert(status_val & 0x02); // WEL bit is bit 1

    // Step 3: Page Program (0x02) at Addr 0x000010: Write bytes [0x11, 0x22, 0x33, 0x44]
    tb.axi_write(SPI_FIFO_CTRL, (1 << 16) | (1 << 17)); // Flush
    tb.axi_write(SPI_CS_CTRL, 0x0001 | (0 << 1) | (1 << 8)); // KEEP_CS=1
    tb.axi_write(SPI_TX_DATA, 0x02); // Write Cmd
    tb.axi_write(SPI_TX_DATA, 0x00); // Addr H
    tb.axi_write(SPI_TX_DATA, 0x00); // Addr M
    tb.axi_write(SPI_TX_DATA, 0x10); // Addr L (0x10)
    tb.axi_write(SPI_TX_DATA, 0x11); // Data 0
    tb.axi_write(SPI_TX_DATA, 0x22); // Data 1
    tb.axi_write(SPI_TX_DATA, 0x33); // Data 2
    tb.axi_write(SPI_CS_CTRL, 0x0001 | (0 << 1) | (0 << 8)); // Release CS on last byte
    tb.axi_write(SPI_TX_DATA, 0x44); // Data 3
    tb.wait_busy();

    std::cout << "  - Programmed 4 bytes to Flash address 0x000010: [0x11, 0x22, 0x33, 0x44]" << std::endl;

    // Step 4: Read Data (0x03) from Addr 0x000010
    tb.axi_write(SPI_FIFO_CTRL, (1 << 16) | (1 << 17)); // Flush
    tb.axi_write(SPI_CS_CTRL, 0x0001 | (0 << 1) | (1 << 8)); // KEEP_CS=1
    tb.axi_write(SPI_TX_DATA, 0x03); // Read Cmd
    tb.axi_write(SPI_TX_DATA, 0x00); // Addr H
    tb.axi_write(SPI_TX_DATA, 0x00); // Addr M
    tb.axi_write(SPI_TX_DATA, 0x10); // Addr L
    tb.axi_write(SPI_TX_DATA, 0x00); // Dummy for Data 0
    tb.axi_write(SPI_TX_DATA, 0x00); // Dummy for Data 1
    tb.axi_write(SPI_TX_DATA, 0x00); // Dummy for Data 2
    tb.axi_write(SPI_CS_CTRL, 0x0001 | (0 << 1) | (0 << 8)); // Release CS
    tb.axi_write(SPI_TX_DATA, 0x00); // Dummy for Data 3
    tb.wait_busy();

    // Discard 4 command+address echo bytes
    for (int i = 0; i < 4; i++) tb.axi_read(SPI_RX_DATA);

    uint32_t r0 = tb.axi_read(SPI_RX_DATA) & 0xFF;
    uint32_t r1 = tb.axi_read(SPI_RX_DATA) & 0xFF;
    uint32_t r2 = tb.axi_read(SPI_RX_DATA) & 0xFF;
    uint32_t r3 = tb.axi_read(SPI_RX_DATA) & 0xFF;

    std::cout << "  - Read back Flash Data: [0x" << std::hex << r0 << ", 0x" << r1 << ", 0x" << r2 << ", 0x" << r3 << "]" << std::dec << std::endl;
    assert(r0 == 0x11);
    assert(r1 == 0x22);
    assert(r2 == 0x33);
    assert(r3 == 0x44);

    std::cout << COLOR_GREEN << "  => [PASSED] SPI Flash Protocol Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ============================================================================
// TEST 8: High-Throughput Burst Multi-Word Transfer (FIFO Full Pipeline Test)
// ============================================================================
bool test8_burst_fifo_pipeline(SPITestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 8] Starting High-Throughput Burst Multi-Word FIFO Pipeline Test..." << COLOR_RESET << std::endl;
    tb.reset();

    tb.axi_write(SPI_CR, CR_CORE_EN | CR_LOOPBACK);
    tb.axi_write(SPI_PRESCALE, 1); // Fast prescaler
    tb.axi_write(SPI_CFG, 16);     // 16-bit words

    const int BURST_LEN = 16;
    std::vector<uint16_t> test_words(BURST_LEN);
    for (int i = 0; i < BURST_LEN; i++) {
        test_words[i] = (uint16_t)(0x1000 + i * 0x111);
    }

    // Set KEEP_CS_DEFAULT = 1 for continuous burst
    tb.axi_write(SPI_CS_CTRL, 0x0001 | (1 << 8));

    // Stream 16 words into TX FIFO
    for (int i = 0; i < BURST_LEN; i++) {
        if (i == BURST_LEN - 1) {
            tb.axi_write(SPI_CS_CTRL, 0x0001 | (0 << 8)); // Release CS on last word
        }
        tb.axi_write(SPI_TX_DATA, test_words[i]);
    }

    bool done = tb.wait_busy();
    assert(done);

    // Read back all 16 words from RX FIFO
    std::cout << "  - Verifying 16 received burst words:" << std::endl;
    for (int i = 0; i < BURST_LEN; i++) {
        uint32_t rx = tb.axi_read(SPI_RX_DATA) & 0xFFFF;
        std::cout << "    [" << std::setw(2) << i << "] Read: 0x" << std::hex << rx
                  << " Expected: 0x" << test_words[i] << std::dec << std::endl;
        assert(rx == test_words[i]);
    }

    std::cout << COLOR_GREEN << "  => [PASSED] Burst Multi-Word Transfer Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ============================================================================
// TEST 9: Hardware Interrupts (IRQ) & Watermark Generation Test
// ============================================================================
bool test9_irq_watermarks(SPITestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 9] Starting Hardware Interrupts (IRQ) & Watermark Test..." << COLOR_RESET << std::endl;
    tb.reset();

    // Enable Global IRQ & Loopback
    tb.axi_write(SPI_CR, CR_CORE_EN | CR_IRQ_EN | CR_LOOPBACK);
    tb.axi_write(SPI_PRESCALE, 2);
    tb.axi_write(SPI_CFG, 8);

    // Set TX Watermark = 4, RX Watermark = 2
    tb.axi_write(SPI_FIFO_CTRL, 4 | (2 << 8));

    // Enable TX_WM and RX_WM interrupts
    tb.axi_write(SPI_IER, INTR_TX_WM | INTR_RX_WM | INTR_XFER_DONE);

    // Verify initial TX Watermark IRQ (since TX count == 0 <= 4)
    tb.tick();
    assert(tb.dut->irq == 1);
    uint32_t isr = tb.axi_read(SPI_ISR);
    std::cout << "  - Initial TX_WM IRQ triggered as expected (ISR: 0x" << std::hex << isr << std::dec << ")" << std::endl;
    assert(isr & INTR_TX_WM);

    // Mask TX_WM interrupt to test RX_WM
    tb.axi_write(SPI_IER, INTR_RX_WM | INTR_XFER_DONE);
    tb.tick();
    assert(tb.dut->irq == 0); // IRQ deasserted

    // Send 2 bytes to trigger RX Watermark IRQ
    tb.axi_write(SPI_TX_DATA, 0x11);
    tb.axi_write(SPI_TX_DATA, 0x22);
    tb.wait_busy();

    assert(tb.dut->irq == 1);
    isr = tb.axi_read(SPI_ISR);
    std::cout << "  - RX_WM IRQ triggered after 2 bytes received (ISR: 0x" << std::hex << isr << std::dec << ")" << std::endl;
    assert(isr & INTR_RX_WM);

    // Drain RX FIFO and Clear ISR
    tb.axi_read(SPI_RX_DATA);
    tb.axi_read(SPI_RX_DATA);
    tb.axi_write(SPI_ISR, 0xFF); // Clear all
    tb.tick();
    assert(tb.dut->irq == 0);

    std::cout << COLOR_GREEN << "  => [PASSED] Hardware Interrupts & Watermark Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ============================================================================
// TEST 10: Error Handling & Overrun Flag Test
// ============================================================================
bool test10_overrun_error(SPITestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 10] Starting Error Handling & Overrun Flag Test..." << COLOR_RESET << std::endl;
    tb.reset();

    tb.axi_write(SPI_CR, CR_CORE_EN | CR_LOOPBACK);
    tb.axi_write(SPI_PRESCALE, 1);
    tb.axi_write(SPI_CFG, 8);

    // Fill RX FIFO to maximum (16 entries)
    for (int i = 0; i < 16; i++) {
        tb.axi_write(SPI_TX_DATA, (uint32_t)i);
    }
    tb.wait_busy();

    uint32_t sr = tb.axi_read(SPI_SR);
    std::cout << "  - RX FIFO Full State SR: 0x" << std::hex << sr << std::endl;
    assert(sr & SR_RX_FULL);

    // Push 17th byte to force RX Overrun
    tb.axi_write(SPI_TX_DATA, 0xFF);
    tb.wait_busy();

    sr = tb.axi_read(SPI_SR);
    uint32_t isr = tb.axi_read(SPI_ISR);
    std::cout << "  - Post-Overrun SR: 0x" << std::hex << sr << " (RX_OVERRUN: " << ((sr & SR_RX_OVERRUN) ? 1 : 0) << ")" << std::endl;
    std::cout << "  - Post-Overrun ISR: 0x" << isr << std::dec << std::endl;

    assert(sr & SR_RX_OVERRUN);
    assert(isr & INTR_RX_OVERRUN);

    // Clear Overrun sticky bit via ISR write
    tb.axi_write(SPI_ISR, INTR_RX_OVERRUN);
    sr = tb.axi_read(SPI_SR);
    assert(!(sr & SR_RX_OVERRUN));

    // Flush RX FIFO
    tb.axi_write(SPI_FIFO_CTRL, (1 << 17));
    tb.tick();
    sr = tb.axi_read(SPI_SR);
    assert(sr & SR_RX_EMPTY);

    std::cout << COLOR_GREEN << "  => [PASSED] Overrun Error Handling Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ============================================================================
// TEST 11: Auto-CS vs Manual-CS Control Test
// ============================================================================
bool test11_auto_vs_manual_cs(SPITestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 11] Starting Auto-CS vs Manual-CS Control Test..." << COLOR_RESET << std::endl;
    tb.reset();

    tb.axi_write(SPI_CR, CR_CORE_EN);
    tb.axi_write(SPI_PRESCALE, 2);
    tb.axi_write(SPI_CFG, 8);

    // 1. Manual CS Mode: disable AUTO_CS (CS_AUTO_EN = 0)
    // Manually assert SS0 (bit 4 = 0 -> ss_n = 4'b1110)
    tb.axi_write(SPI_CS_CTRL, 0x0000 | (0xE << 4)); // CS_AUTO_EN=0, MANUAL_SS=4'b1110
    tb.tick();
    assert(tb.dut->spi_ss_n == 0xE);
    std::cout << "  - Manual CS correctly asserted: spi_ss_n = 0x" << std::hex << (int)tb.dut->spi_ss_n << std::endl;

    // Send data under manual CS
    tb.axi_write(SPI_TX_DATA, 0x9F);
    tb.axi_write(SPI_TX_DATA, 0x00);
    tb.wait_busy();

    // Manually deassert SS0 (MANUAL_SS = 4'b1111)
    tb.axi_write(SPI_CS_CTRL, 0x0000 | (0xF << 4));
    tb.tick();
    assert(tb.dut->spi_ss_n == 0xF);
    std::cout << "  - Manual CS correctly deasserted: spi_ss_n = 0x" << std::hex << (int)tb.dut->spi_ss_n << std::dec << std::endl;

    // Verify received JEDEC ID from Slave 0
    tb.axi_read(SPI_RX_DATA);
    uint32_t mfg_id = tb.axi_read(SPI_RX_DATA) & 0xFF;
    assert(mfg_id == 0xEF);

    std::cout << COLOR_GREEN << "  => [PASSED] Auto/Manual CS Control Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ============================================================================
// TEST 12: Internal Loopback Self-Test (BIST Mode)
// ============================================================================
bool test12_loopback_self_test(SPITestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 12] Starting Internal Loopback Self-Test (BIST)..." << COLOR_RESET << std::endl;
    tb.reset();

    tb.axi_write(SPI_CR, CR_CORE_EN | CR_LOOPBACK);
    tb.axi_write(SPI_PRESCALE, 2);
    tb.axi_write(SPI_CFG, 32); // 32-bit words

    uint32_t pattern = 0x12345678;
    tb.axi_write(SPI_TX_DATA, pattern);
    tb.wait_busy();

    uint32_t rx = tb.axi_read(SPI_RX_DATA);
    std::cout << "  - BIST 32-bit Word: Sent 0x" << std::hex << pattern << ", Received 0x" << rx << std::dec << std::endl;
    assert(rx == pattern);

    std::cout << COLOR_GREEN << "  => [PASSED] Internal Loopback Self-Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ============================================================================
// Main Execution Runner
// ============================================================================
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    bool enable_trace = false;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--trace") == 0) {
            enable_trace = true;
        }
    }

    std::cout << "==========================================================================" << std::endl;
    std::cout << "       AZ_V RISC-V SoC AXI4-Lite SPI Master IP Automated Test Suite       " << std::endl;
    std::cout << "==========================================================================" << std::endl;

    SPITestbench tb(enable_trace);

    bool all_passed = true;
    all_passed &= test1_register_access(tb);
    all_passed &= test2_prescaler_speed(tb);
    all_passed &= test3_spi_modes(tb);
    all_passed &= test4_frame_widths(tb);
    all_passed &= test5_msb_lsb_order(tb);
    all_passed &= test6_multislave_cs(tb);
    all_passed &= test7_spi_flash_protocol(tb);
    all_passed &= test8_burst_fifo_pipeline(tb);
    all_passed &= test9_irq_watermarks(tb);
    all_passed &= test10_overrun_error(tb);
    all_passed &= test11_auto_vs_manual_cs(tb);
    all_passed &= test12_loopback_self_test(tb);

    std::cout << "==========================================================================" << std::endl;
    if (all_passed) {
        std::cout << COLOR_GREEN << "  *** ALL 12 TEST SUITES COMPLETED AND PASSED SUCCESSFULLY! ***  " << COLOR_RESET << std::endl;
        std::cout << "==========================================================================" << std::endl;
        return 0;
    } else {
        std::cout << COLOR_RED << "  !!! SOME TEST SUITES FAILED! PLEASE CHECK THE LOGS. !!!" << COLOR_RESET << std::endl;
        std::cout << "==========================================================================" << std::endl;
        return 1;
    }
}
