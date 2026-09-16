// ============================================================================
// File: tb_i2c_top.cpp
// Description: Verilator C++ Automated Test Suite Runner for AXI_I2C IP Core
// Project: AXI_I2C
// ============================================================================

#include <iostream>
#include <iomanip>
#include <vector>
#include <cassert>
#include <cstring>
#include <memory>
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vi2c_tb.h"

// ANSI Color Codes for pretty terminal output
#define COLOR_RESET   "\033[0m"
#define COLOR_RED     "\033[31;1m"
#define COLOR_GREEN   "\033[32;1m"
#define COLOR_YELLOW  "\033[33;1m"
#define COLOR_CYAN    "\033[36;1m"
#define COLOR_BLUE    "\033[34;1m"

double sc_time_stamp() { return 0; }

// Register Offsets
#define I2C_CR          0x00
#define I2C_SR          0x04
#define I2C_TX_CMD      0x08
#define I2C_RX_DATA     0x0C
#define I2C_PRESCALE    0x10
#define I2C_TIMING      0x14
#define I2C_FILTER      0x18
#define I2C_FIFO_CTRL   0x1C
#define I2C_FIFO_STAT   0x20
#define I2C_IER         0x24
#define I2C_ISR         0x28
#define I2C_TIMEOUT     0x2C

// Command Flags
#define CMD_START       (1 << 8)
#define CMD_STOP        (1 << 9)
#define CMD_READ        (1 << 10)
#define CMD_NACK        (1 << 11)

// Status Flags
#define SR_BUSY         (1 << 0)
#define SR_BUS_BUSY     (1 << 1)
#define SR_TX_EMPTY     (1 << 2)
#define SR_TX_FULL      (1 << 3)
#define SR_RX_EMPTY     (1 << 4)
#define SR_RX_FULL      (1 << 5)
#define SR_NACK_RECV    (1 << 6)
#define SR_ARB_LOST     (1 << 7)
#define SR_SCL_HELD     (1 << 8)
#define SR_BUS_ERROR    (1 << 9)

// Interrupt Flags
#define INTR_TX_WM      (1 << 0)
#define INTR_RX_WM      (1 << 1)
#define INTR_TX_EMPTY   (1 << 2)
#define INTR_RX_FULL    (1 << 3)
#define INTR_DONE       (1 << 4)
#define INTR_NACK       (1 << 5)
#define INTR_ARB_LOST   (1 << 6)
#define INTR_BUS_ERROR  (1 << 7)
#define INTR_TIMEOUT    (1 << 8)

class I2CTestbench {
public:
    std::unique_ptr<Vi2c_tb> dut;
    std::unique_ptr<VerilatedVcdC> trace;
    uint64_t sim_time;
    bool trace_enabled;

    I2CTestbench(bool enable_trace = false) : sim_time(0), trace_enabled(enable_trace) {
        dut = std::make_unique<Vi2c_tb>();
        if (trace_enabled) {
            Verilated::traceEverOn(true);
            trace = std::make_unique<VerilatedVcdC>();
            dut->trace(trace.get(), 99);
            trace->open("i2c_sim.vcd");
        }
        init_signals();
    }

    ~I2CTestbench() {
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
        dut->force_slave_nack = 0;
        dut->force_slave_stretch = 0;
        dut->force_bus_sda_stuck_low = 0;
        dut->force_bus_scl_stuck_low = 0;
    }

    void tick() {
        dut->clk = 0;
        dut->eval();
        if (trace) trace->dump(sim_time * 10);
        sim_time++;

        dut->clk = 1;
        dut->eval();
        if (trace) trace->dump(sim_time * 10);
        sim_time++;
    }

    void reset(int cycles = 10) {
        dut->rst_n = 0;
        for (int i = 0; i < cycles; ++i) tick();
        dut->rst_n = 1;
        tick();
    }

    void wait_cycles(int cycles) {
        for (int i = 0; i < cycles; ++i) tick();
    }

    // ------------------------------------------------------------------------
    // AXI4-Lite Transaction Helpers
    // ------------------------------------------------------------------------
    void axi_write(uint32_t addr, uint32_t data, uint8_t strb = 0xF) {
        dut->s_axi_awaddr = addr;
        dut->s_axi_awvalid = 1;
        dut->s_axi_wdata = data;
        dut->s_axi_wstrb = strb;
        dut->s_axi_wvalid = 1;

        bool aw_done = false, w_done = false;
        while (!aw_done || !w_done) {
            tick();
            if (dut->s_axi_awready) aw_done = true;
            if (dut->s_axi_wready) w_done = true;
            if (aw_done) dut->s_axi_awvalid = 0;
            if (w_done) dut->s_axi_wvalid = 0;
        }

        while (!dut->s_axi_bvalid) {
            tick();
        }
        tick();
    }

    uint32_t axi_read(uint32_t addr) {
        dut->s_axi_araddr = addr;
        dut->s_axi_arvalid = 1;

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

    // Wait until I2C FSM Busy bit clears with safety timeout
    bool wait_for_idle(int max_cycles = 100000) {
        for (int i = 0; i < max_cycles; ++i) {
            uint32_t sr = axi_read(I2C_SR);
            if (!(sr & SR_BUSY)) {
                return true;
            }
            tick();
        }
        return false;
    }

    // Wait until FSM reaches specific state with safety timeout
    bool wait_for_state(uint32_t target_state, int max_cycles = 10000) {
        for (int i = 0; i < max_cycles; ++i) {
            if (dut->dbg_fsm_state == target_state) {
                return true;
            }
            tick();
        }
        return false;
    }
};

// ----------------------------------------------------------------------------
// Test 1: AXI4-Lite Register Read/Write Access & Reset Values
// ----------------------------------------------------------------------------
bool test_axi_registers(I2CTestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 1] Starting AXI4-Lite Register Read/Write Access Test..." << COLOR_RESET << std::endl;
    tb.reset();

    // Verify Default Reset Values
    uint32_t cr = tb.axi_read(I2C_CR);
    uint32_t prescale = tb.axi_read(I2C_PRESCALE);
    uint32_t timing = tb.axi_read(I2C_TIMING);
    uint32_t filter = tb.axi_read(I2C_FILTER);
    uint32_t sr = tb.axi_read(I2C_SR);

    std::cout << "  - Default CR: 0x" << std::hex << cr << " (Expected: 0x21)" << std::endl;
    std::cout << "  - Default PRESCALE: 0x" << std::hex << prescale << " (Expected: 0x7c)" << std::endl;
    std::cout << "  - Default TIMING: 0x" << std::hex << timing << " (Expected: 0x0202)" << std::endl;
    std::cout << "  - Default FILTER: 0x" << std::hex << filter << " (Expected: 0x03)" << std::endl;
    std::cout << "  - Default SR: 0x" << std::hex << sr << " (TX_EMPTY=1, RX_EMPTY=1)" << std::endl;

    if ((cr != 0x21) || (prescale != 0x7C) || (timing != 0x0202) || (filter != 0x03)) {
        std::cout << COLOR_RED << "  [FAIL] Register reset values mismatch!" << COLOR_RESET << std::endl;
        return false;
    }

    // Test writing Prescaler, Timing, Filter, IER
    tb.axi_write(I2C_PRESCALE, 0x001E); // 400kHz prescale
    tb.axi_write(I2C_TIMING, 0x0303);
    tb.axi_write(I2C_FILTER, 0x05);
    tb.axi_write(I2C_IER, 0x01FF);

    if (tb.axi_read(I2C_PRESCALE) != 0x001E ||
        tb.axi_read(I2C_TIMING) != 0x0303 ||
        tb.axi_read(I2C_FILTER) != 0x05 ||
        tb.axi_read(I2C_IER) != 0x01FF) {
        std::cout << COLOR_RED << "  [FAIL] Register readback mismatch after write!" << COLOR_RESET << std::endl;
        return false;
    }

    std::cout << COLOR_GREEN << "  => [PASSED] AXI4-Lite Register Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ----------------------------------------------------------------------------
// Test 2: Prescaler & Fast Micro-Timing Config Test
// ----------------------------------------------------------------------------
bool test_timing_prescaler(I2CTestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 2] Starting Fast Timing Prescaler Config Test..." << COLOR_RESET << std::endl;
    tb.reset();

    // Configure fast prescaler for simulation speed (prescale=4 -> 20 clk cycles per SCL bit)
    tb.axi_write(I2C_PRESCALE, 4);
    tb.axi_write(I2C_TIMING, 0x0000);
    tb.axi_write(I2C_FILTER, 2);
    tb.axi_write(I2C_CR, 0x23); // CORE_EN=1, IRQ_EN=1, STRETCH_EN=1

    uint32_t p = tb.axi_read(I2C_PRESCALE);
    if (p != 4) {
        std::cout << COLOR_RED << "  [FAIL] Prescaler write failed!" << COLOR_RESET << std::endl;
        return false;
    }

    std::cout << COLOR_GREEN << "  => [PASSED] Timing Prescaler Config Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ----------------------------------------------------------------------------
// Test 3: Master Single-Byte Write to Slave Test (DevAddr=0x50, Reg=0x10, Data=0xA5)
// ----------------------------------------------------------------------------
bool test_master_write(I2CTestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 3] Starting Master Single-Byte Write to Slave Test..." << COLOR_RESET << std::endl;
    tb.reset();
    tb.axi_write(I2C_PRESCALE, 4);
    tb.axi_write(I2C_TIMING, 0x0000);
    tb.axi_write(I2C_FILTER, 1);
    tb.axi_write(I2C_CR, 0x21); // Enable Core

    uint8_t dev_addr = 0x50;
    uint8_t reg_addr = 0x10;
    uint8_t write_data = 0xA5;

    std::cout << "  - Writing to Slave 0x" << std::hex << (int)dev_addr
              << ", Reg 0x" << (int)reg_addr << ", Data: 0x" << (int)write_data << std::endl;

    // Push 3 entries into TX_CMD FIFO:
    // 1. START + DevAddr (Write)
    tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1));
    // 2. Reg Address
    tb.axi_write(I2C_TX_CMD, reg_addr);
    // 3. STOP + Data
    tb.axi_write(I2C_TX_CMD, CMD_STOP | write_data);

    if (!tb.wait_for_idle()) {
        std::cout << COLOR_RED << "  [FAIL] Transaction timed out waiting for IDLE!" << COLOR_RESET << std::endl;
        return false;
    }

    uint32_t sr = tb.axi_read(I2C_SR);
    if (sr & SR_NACK_RECV) {
        std::cout << COLOR_RED << "  [FAIL] Unexpected NACK received from slave during write!" << COLOR_RESET << std::endl;
        return false;
    }

    std::cout << "  - Transaction completed successfully with ACK from Slave!" << std::endl;
    std::cout << COLOR_GREEN << "  => [PASSED] Master Single-Byte Write Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ----------------------------------------------------------------------------
// Test 4: Master Single-Byte Read with Repeated START Test (Write Reg -> Repeated START -> Read)
// ----------------------------------------------------------------------------
bool test_master_read_repeated_start(I2CTestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 4] Starting Master Single-Byte Read (Repeated START) Test..." << COLOR_RESET << std::endl;
    // Step 1: First write 0x5A to register 0x20
    uint8_t dev_addr = 0x50;
    uint8_t reg_addr = 0x20;
    uint8_t expected_data = 0x5A;

    tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1));
    tb.axi_write(I2C_TX_CMD, reg_addr);
    tb.axi_write(I2C_TX_CMD, CMD_STOP | expected_data);
    tb.wait_for_idle();

    std::cout << "  - Pre-wrote 0x" << std::hex << (int)expected_data << " to Slave Reg 0x" << (int)reg_addr << std::endl;

    // Step 2: Now perform Combined Read (START -> Write Reg -> Repeated START -> Read Data + NACK + STOP)
    tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1));
    tb.axi_write(I2C_TX_CMD, reg_addr);
    tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1 | 1)); // Repeated START + Read Addr
    tb.axi_write(I2C_TX_CMD, CMD_READ | CMD_NACK | CMD_STOP);

    if (!tb.wait_for_idle()) {
        std::cout << COLOR_RED << "  [FAIL] Read transaction timed out waiting for IDLE!" << COLOR_RESET << std::endl;
        return false;
    }

    uint32_t read_val = tb.axi_read(I2C_RX_DATA) & 0xFF;
    std::cout << "  - Read Data from RX FIFO: 0x" << std::hex << read_val
              << " (Expected: 0x" << (int)expected_data << ")" << std::endl;

    if (read_val != expected_data) {
        std::cout << COLOR_RED << "  [FAIL] Read data mismatch!" << COLOR_RESET << std::endl;
        return false;
    }

    std::cout << COLOR_GREEN << "  => [PASSED] Master Repeated START Read Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ----------------------------------------------------------------------------
// Test 5: Multi-Byte Sequential Write & Read Test
// ----------------------------------------------------------------------------
bool test_multibyte_sequential(I2CTestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 5] Starting Multi-Byte Sequential Transfer Test (8 Bytes)..." << COLOR_RESET << std::endl;
    uint8_t dev_addr = 0x50;
    uint8_t start_reg = 0x30;
    std::vector<uint8_t> test_bytes = {0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88};

    // 1. Sequential Write 8 Bytes
    tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1));
    tb.axi_write(I2C_TX_CMD, start_reg);
    for (size_t i = 0; i < test_bytes.size(); ++i) {
        uint32_t cmd = test_bytes[i];
        if (i == test_bytes.size() - 1) cmd |= CMD_STOP;
        tb.axi_write(I2C_TX_CMD, cmd);
    }

    if (!tb.wait_for_idle()) {
        std::cout << COLOR_RED << "  [FAIL] Multi-byte write timed out!" << COLOR_RESET << std::endl;
        return false;
    }

    std::cout << "  - Sequential Write of 8 bytes completed successfully." << std::endl;

    // 2. Sequential Read 8 Bytes back
    tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1));
    tb.axi_write(I2C_TX_CMD, start_reg);
    tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1 | 1)); // Repeated START

    for (size_t i = 0; i < test_bytes.size(); ++i) {
        uint32_t cmd = CMD_READ;
        if (i == test_bytes.size() - 1) {
            cmd |= CMD_NACK | CMD_STOP; // NACK + STOP on last byte
        }
        tb.axi_write(I2C_TX_CMD, cmd);
    }

    if (!tb.wait_for_idle()) {
        std::cout << COLOR_RED << "  [FAIL] Multi-byte read timed out!" << COLOR_RESET << std::endl;
        return false;
    }

    // Read 8 bytes from RX FIFO and verify
    std::cout << "  - Verifying readback bytes:" << std::endl;
    for (size_t i = 0; i < test_bytes.size(); ++i) {
        uint8_t r = tb.axi_read(I2C_RX_DATA) & 0xFF;
        std::cout << "    [" << i << "] Read: 0x" << std::hex << (int)r
                  << " Expected: 0x" << (int)test_bytes[i] << std::endl;
        if (r != test_bytes[i]) {
            std::cout << COLOR_RED << "  [FAIL] Byte " << i << " mismatch!" << COLOR_RESET << std::endl;
            return false;
        }
    }

    std::cout << COLOR_GREEN << "  => [PASSED] Multi-Byte Sequential Transfer Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ----------------------------------------------------------------------------
// Test 6: Clock Stretching Robustness Test
// ----------------------------------------------------------------------------
bool test_clock_stretching(I2CTestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 6] Starting Slave Clock Stretching Test..." << COLOR_RESET << std::endl;
    tb.reset();
    tb.axi_write(I2C_PRESCALE, 4);
    tb.axi_write(I2C_TIMING, 0x0000);
    tb.axi_write(I2C_FILTER, 1);
    tb.axi_write(I2C_CR, 0x21); // Enable Core & Clock Stretching

    // Configure Slave to stretch SCL for 30 clock cycles on each falling edge
    tb.dut->force_slave_stretch = 30;
    std::cout << "  - Injected 30-cycle Slave Clock Stretching on SCL line." << std::endl;

    uint8_t dev_addr = 0x50;
    uint8_t reg_addr = 0x40;
    uint8_t data_val = 0x7E;

    tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1));
    tb.axi_write(I2C_TX_CMD, reg_addr);
    tb.axi_write(I2C_TX_CMD, CMD_STOP | data_val);

    if (!tb.wait_for_idle(200000)) {
        std::cout << COLOR_RED << "  [FAIL] Transaction timed out during clock stretching!" << COLOR_RESET << std::endl;
        return false;
    }

    tb.dut->force_slave_stretch = 0; // Disable stretching injection

    // Verify written data by reading back
    tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1));
    tb.axi_write(I2C_TX_CMD, reg_addr);
    tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1 | 1));
    tb.axi_write(I2C_TX_CMD, CMD_READ | CMD_NACK | CMD_STOP);
    tb.wait_for_idle();

    uint8_t read_back = tb.axi_read(I2C_RX_DATA) & 0xFF;
    std::cout << "  - Readback under stretching: 0x" << std::hex << (int)read_back << std::endl;

    if (read_back != data_val) {
        std::cout << COLOR_RED << "  [FAIL] Data corrupted during clock stretching!" << COLOR_RESET << std::endl;
        return false;
    }

    std::cout << COLOR_GREEN << "  => [PASSED] Clock Stretching Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ----------------------------------------------------------------------------
// Test 7: Slave NACK Detection & Auto-Abort Test
// ----------------------------------------------------------------------------
bool test_nack_detection(I2CTestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 7] Starting Slave NACK Detection & Error Handling Test..." << COLOR_RESET << std::endl;
    tb.reset();
    tb.axi_write(I2C_PRESCALE, 4);
    tb.axi_write(I2C_TIMING, 0x0000);
    tb.axi_write(I2C_FILTER, 1);
    tb.axi_write(I2C_CR, 0x21); // Enable Core

    // Force Slave to respond with NACK
    tb.dut->force_slave_nack = 1;
    std::cout << "  - Forced Slave NACK injection on address byte." << std::endl;

    tb.axi_write(I2C_TX_CMD, CMD_START | (0x50 << 1));
    tb.axi_write(I2C_TX_CMD, 0x00);

    if (!tb.wait_for_idle()) {
        std::cout << COLOR_RED << "  [FAIL] Timed out waiting for abort on NACK!" << COLOR_RESET << std::endl;
        return false;
    }

    uint32_t sr = tb.axi_read(I2C_SR);
    uint32_t isr = tb.axi_read(I2C_ISR);
    std::cout << "  - Status Register: 0x" << std::hex << sr << " (NACK_RECV bit: " << ((sr & SR_NACK_RECV) ? 1 : 0) << ")" << std::endl;
    std::cout << "  - Interrupt Status: 0x" << std::hex << isr << " (INTR_NACK bit: " << ((isr & INTR_NACK) ? 1 : 0) << ")" << std::endl;

    tb.dut->force_slave_nack = 0; // Release NACK force

    if (!(sr & SR_NACK_RECV) || !(isr & INTR_NACK)) {
        std::cout << COLOR_RED << "  [FAIL] NACK was not detected or flagged correctly!" << COLOR_RESET << std::endl;
        return false;
    }

    // Clear NACK in ISR (W1C)
    tb.axi_write(I2C_ISR, INTR_NACK);
    isr = tb.axi_read(I2C_ISR);
    if (isr & INTR_NACK) {
        std::cout << COLOR_RED << "  [FAIL] ISR NACK bit failed to clear on W1C!" << COLOR_RESET << std::endl;
        return false;
    }

    std::cout << COLOR_GREEN << "  => [PASSED] Slave NACK Detection Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ----------------------------------------------------------------------------
// Test 8: FIFO Watermark & Hardware Interrupt (IRQ) Test
// ----------------------------------------------------------------------------
bool test_fifo_watermark_irq(I2CTestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 8] Starting FIFO Watermark & Hardware Interrupt (IRQ) Test..." << COLOR_RESET << std::endl;
    tb.reset();
    tb.axi_write(I2C_PRESCALE, 4);
    tb.axi_write(I2C_TIMING, 0x0000);
    tb.axi_write(I2C_FILTER, 1);
    tb.axi_write(I2C_FIFO_CTRL, 0x02040000); // TX_WM=4, RX_WM=2
    tb.axi_write(I2C_IER, INTR_TX_WM | INTR_RX_WM | INTR_DONE);
    tb.axi_write(I2C_CR, 0x23); // CORE_EN=1, IRQ_EN=1

    // 1. Initial State: TX FIFO is empty (0 <= 4), so TX_WM IRQ should be asserted
    tb.wait_cycles(5);
    if (!tb.dut->irq) {
        std::cout << COLOR_RED << "  [FAIL] Expected IRQ to be asserted on initial TX Watermark!" << COLOR_RESET << std::endl;
        return false;
    }
    std::cout << "  - Initial TX Watermark IRQ asserted correctly." << std::endl;

    // Mask TX_WM interrupt and verify IRQ deasserts
    tb.axi_write(I2C_IER, INTR_RX_WM | INTR_DONE);
    tb.wait_cycles(5);
    if (tb.dut->irq) {
        std::cout << COLOR_RED << "  [FAIL] IRQ did not deassert after masking TX_WM!" << COLOR_RESET << std::endl;
        return false;
    }
    std::cout << "  - IRQ deasserted cleanly when TX_WM masked." << std::endl;

    // 2. Perform 2-byte read to trigger RX_WM (>= 2 bytes)
    tb.axi_write(I2C_TX_CMD, CMD_START | (0x50 << 1));
    tb.axi_write(I2C_TX_CMD, 0x00);
    tb.axi_write(I2C_TX_CMD, CMD_START | (0x50 << 1 | 1));
    tb.axi_write(I2C_TX_CMD, CMD_READ);
    tb.axi_write(I2C_TX_CMD, CMD_READ | CMD_NACK | CMD_STOP);

    tb.wait_for_idle();
    tb.wait_cycles(5);

    if (!tb.dut->irq) {
        std::cout << COLOR_RED << "  [FAIL] Expected IRQ on RX Watermark (2 bytes)!" << COLOR_RESET << std::endl;
        return false;
    }
    std::cout << "  - RX Watermark IRQ triggered successfully after reading 2 bytes!" << std::endl;

    // Drain RX FIFO
    tb.axi_read(I2C_RX_DATA);
    tb.axi_read(I2C_RX_DATA);
    tb.axi_write(I2C_ISR, INTR_DONE); // Clear DONE
    tb.wait_cycles(5);

    if (tb.dut->irq) {
        std::cout << COLOR_RED << "  [FAIL] IRQ did not deassert after draining RX FIFO!" << COLOR_RESET << std::endl;
        return false;
    }
    std::cout << "  - IRQ deasserted after draining RX FIFO." << std::endl;

    std::cout << COLOR_GREEN << "  => [PASSED] FIFO Watermark & IRQ Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ----------------------------------------------------------------------------
// Test 9: Bus Stuck 9-Clock Recovery Test
// ----------------------------------------------------------------------------
bool test_bus_recovery_9clock(I2CTestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 9] Starting 9-Clock Bus Stuck Recovery Test..." << COLOR_RESET << std::endl;
    tb.reset();
    tb.axi_write(I2C_PRESCALE, 4);
    tb.axi_write(I2C_TIMING, 0x0000);
    tb.axi_write(I2C_FILTER, 1);
    tb.axi_write(I2C_CR, 0x21); // Enable Core

    // Simulate external bus fault: SDA pulled low by stuck device
    tb.dut->force_bus_sda_stuck_low = 1;
    std::cout << "  - External bus fault: SDA stuck low." << std::endl;

    // Trigger Manual Recovery: write 1 to CR[4] (MANUAL_RECOVER)
    tb.axi_write(I2C_CR, 0x21 | (1 << 4));

    // Wait for recovery state machine to execute 9 SCL pulses
    tb.wait_cycles(300);

    // Release stuck SDA
    tb.dut->force_bus_sda_stuck_low = 0;
    tb.wait_for_idle();

    uint32_t sr = tb.axi_read(I2C_SR);
    std::cout << "  - Post-Recovery SR: 0x" << std::hex << sr << " (BUS_BUSY: " << ((sr & SR_BUS_BUSY) ? 1 : 0) << ")" << std::endl;

    std::cout << COLOR_GREEN << "  => [PASSED] 9-Clock Recovery Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ----------------------------------------------------------------------------
// Test 10: Direct Multi-Byte Read without Repeated START Test
// (START -> DevAddr(Read) -> ACK -> Read Byte 0 (ACK) -> Read Byte 1 (ACK) -> Read Byte 2 (NACK+STOP))
// ----------------------------------------------------------------------------
bool test_direct_read_no_restart(I2CTestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 10] Starting Direct Multi-Byte Read Without Restart Test..." << COLOR_RESET << std::endl;
    tb.reset();
    tb.axi_write(I2C_PRESCALE, 4);
    tb.axi_write(I2C_TIMING, 0x0000);
    tb.axi_write(I2C_FILTER, 1);
    tb.axi_write(I2C_CR, 0x21); // Enable Core

    uint8_t dev_addr = 0x50;

    // 1. Direct Read of 3 bytes from current EEPROM pointer without Repeated START
    tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1 | 1)); // START + DevAddr (Read)
    tb.axi_write(I2C_TX_CMD, CMD_READ);                       // Read Byte 0, ACK
    tb.axi_write(I2C_TX_CMD, CMD_READ);                       // Read Byte 1, ACK
    tb.axi_write(I2C_TX_CMD, CMD_READ | CMD_NACK | CMD_STOP); // Read Byte 2, NACK + STOP

    if (!tb.wait_for_idle()) {
        std::cout << COLOR_RED << "  [FAIL] Direct Read without restart timed out waiting for IDLE!" << COLOR_RESET << std::endl;
        return false;
    }

    uint8_t b0 = tb.axi_read(I2C_RX_DATA) & 0xFF;
    uint8_t b1 = tb.axi_read(I2C_RX_DATA) & 0xFF;
    uint8_t b2 = tb.axi_read(I2C_RX_DATA) & 0xFF;

    std::cout << "  - Received Bytes: 0x" << std::hex << (int)b0 << ", 0x" << (int)b1 << ", 0x" << (int)b2 << std::endl;

    std::cout << COLOR_GREEN << "  => [PASSED] Direct Multi-Byte Read Without Restart Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ----------------------------------------------------------------------------
// Test 11: Byte-by-Byte Sequential Write with Delays (ST_HOLD validation)
// (START -> DevAddr -> ACK -> [Pause & Hold SCL Low] -> RegAddr -> ACK -> [Pause] -> STOP+Data)
// ----------------------------------------------------------------------------
bool test_hold_byte_by_byte_write(I2CTestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 11] Starting Byte-by-Byte Write with Delays (ST_HOLD Bus Hold) Test..." << COLOR_RESET << std::endl;
    tb.reset();
    tb.axi_write(I2C_PRESCALE, 4);
    tb.axi_write(I2C_TIMING, 0x0000);
    tb.axi_write(I2C_FILTER, 1);
    tb.axi_write(I2C_CR, 0x21); // Enable Core

    uint8_t dev_addr = 0x50;
    uint8_t reg_addr = 0x60;
    uint8_t data_val = 0x3C;

    // Push 1st byte: START + DevAddr (Write)
    tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1));

    // Wait until TX FIFO is empty and FSM enters ST_HOLD (state 13)
    if (!tb.wait_for_state(13)) {
        std::cout << COLOR_RED << "  [FAIL] FSM did not hold in ST_HOLD when TX FIFO empty after 1st byte!" << COLOR_RESET << std::endl;
        return false;
    }

    // Verify SCL is held LOW
    if (tb.dut->i2c_scl_line != 0) {
        std::cout << COLOR_RED << "  [FAIL] SCL was not held LOW in ST_HOLD!" << COLOR_RESET << std::endl;
        return false;
    }
    std::cout << "  - SCL line correctly held LOW during inter-byte pause." << std::endl;

    // Delay 100 cycles to simulate slow CPU
    tb.wait_cycles(100);

    // Push 2nd byte: Reg Address (no START, no STOP)
    tb.axi_write(I2C_TX_CMD, reg_addr);

    // Wait for 2nd byte to transmit and enter ST_HOLD
    if (!tb.wait_for_state(13)) {
        std::cout << COLOR_RED << "  [FAIL] FSM did not re-enter ST_HOLD after 2nd byte!" << COLOR_RESET << std::endl;
        return false;
    }

    // Delay 100 cycles
    tb.wait_cycles(100);

    // Push 3rd byte: Data with STOP
    tb.axi_write(I2C_TX_CMD, CMD_STOP | data_val);

    if (!tb.wait_for_idle()) {
        std::cout << COLOR_RED << "  [FAIL] Transaction timed out waiting for IDLE!" << COLOR_RESET << std::endl;
        return false;
    }

    // Verify written data by reading back
    tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1));
    tb.axi_write(I2C_TX_CMD, reg_addr);
    tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1 | 1));
    tb.axi_write(I2C_TX_CMD, CMD_READ | CMD_NACK | CMD_STOP);
    tb.wait_for_idle();

    uint8_t read_back = tb.axi_read(I2C_RX_DATA) & 0xFF;
    std::cout << "  - Read back written value: 0x" << std::hex << (int)read_back
              << " (Expected: 0x" << (int)data_val << ")" << std::endl;

    if (read_back != data_val) {
        std::cout << COLOR_RED << "  [FAIL] Data read back mismatch!" << COLOR_RESET << std::endl;
        return false;
    }

    std::cout << COLOR_GREEN << "  => [PASSED] Byte-by-Byte Write with Delays (ST_HOLD) Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ----------------------------------------------------------------------------
// Test 12: Byte-by-Byte Sequential Read with Delays (ST_HOLD validation)
// ----------------------------------------------------------------------------
bool test_hold_byte_by_byte_read(I2CTestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 12] Starting Byte-by-Byte Read with Delays (ST_HOLD Bus Hold) Test..." << COLOR_RESET << std::endl;
    tb.reset();
    tb.axi_write(I2C_PRESCALE, 4);
    tb.axi_write(I2C_TIMING, 0x0000);
    tb.axi_write(I2C_FILTER, 1);
    tb.axi_write(I2C_CR, 0x21);

    uint8_t dev_addr = 0x50;

    // Send START + DevAddr (Read)
    tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1 | 1));

    // Wait until DevAddr is ACKed and FSM holds in ST_HOLD
    if (!tb.wait_for_state(13)) {
        std::cout << COLOR_RED << "  [FAIL] FSM did not hold in ST_HOLD after DevAddr(Read) ACK!" << COLOR_RESET << std::endl;
        return false;
    }

    // Delay 100 cycles
    tb.wait_cycles(100);

    // Issue Read 1st byte (ACK)
    tb.axi_write(I2C_TX_CMD, CMD_READ);

    // Wait until 1st byte read & ACK completed, entering ST_HOLD
    if (!tb.wait_for_state(13)) {
        std::cout << COLOR_RED << "  [FAIL] FSM did not hold in ST_HOLD after 1st byte read!" << COLOR_RESET << std::endl;
        return false;
    }

    // Delay 100 cycles
    tb.wait_cycles(100);

    // Issue Read 2nd byte (NACK + STOP)
    tb.axi_write(I2C_TX_CMD, CMD_READ | CMD_NACK | CMD_STOP);

    if (!tb.wait_for_idle()) {
        std::cout << COLOR_RED << "  [FAIL] Timed out waiting for IDLE after 2nd byte read!" << COLOR_RESET << std::endl;
        return false;
    }

    uint8_t b0 = tb.axi_read(I2C_RX_DATA) & 0xFF;
    uint8_t b1 = tb.axi_read(I2C_RX_DATA) & 0xFF;

    std::cout << "  - Read Bytes: 0x" << std::hex << (int)b0 << ", 0x" << (int)b1 << std::endl;

    std::cout << COLOR_GREEN << "  => [PASSED] Byte-by-Byte Read with Delays (ST_HOLD) Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ----------------------------------------------------------------------------
// Test 13: Multi-Master Arbitration Loss Detection Test
// ----------------------------------------------------------------------------
bool test_arbitration_loss(I2CTestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 13] Starting Multi-Master Arbitration Loss Detection Test..." << COLOR_RESET << std::endl;
    tb.reset();
    tb.axi_write(I2C_PRESCALE, 8);
    tb.axi_write(I2C_TIMING, 0x0000);
    tb.axi_write(I2C_FILTER, 1);
    tb.axi_write(I2C_IER, INTR_ARB_LOST);
    tb.axi_write(I2C_CR, 0x23); // CORE_EN=1, IRQ_EN=1, STRETCH_EN=1

    // Transmit START + 0xFE (11111110b -> bits 7..1 are '1', so DUT releases SDA to '1')
    tb.axi_write(I2C_TX_CMD, CMD_START | 0xFE);

    // Wait until FSM enters ST_TX_BYTE (state 5) and reaches PH_HIGH (phase 2)
    bool injected = false;
    for (int i = 0; i < 500; ++i) {
        tb.tick();
        if (tb.dut->dbg_fsm_state == 5 && tb.dut->dbg_phase == 2) {
            // In Phase HIGH of bit 7: DUT expected SDA is '1'.
            // Inject another master driving SDA LOW ('0')
            tb.dut->force_bus_sda_stuck_low = 1;
            injected = true;
            break;
        }
    }

    if (!injected) {
        std::cout << COLOR_RED << "  [FAIL] Did not reach ST_TX_BYTE PH_HIGH to inject arbitration collision!" << COLOR_RESET << std::endl;
        tb.dut->force_bus_sda_stuck_low = 0;
        return false;
    }

    // Tick a few cycles to let DUT detect collision and abort
    for (int i = 0; i < 20; ++i) tb.tick();
    tb.dut->force_bus_sda_stuck_low = 0;

    if (!tb.wait_for_idle()) {
        std::cout << COLOR_RED << "  [FAIL] FSM did not return to IDLE after losing arbitration!" << COLOR_RESET << std::endl;
        return false;
    }

    uint32_t sr = tb.axi_read(I2C_SR);
    uint32_t isr = tb.axi_read(I2C_ISR);

    std::cout << "  - Status Register: 0x" << std::hex << sr << " (ARB_LOST bit: " << ((sr & SR_ARB_LOST) ? 1 : 0) << ")" << std::endl;
    std::cout << "  - Interrupt Status: 0x" << std::hex << isr << " (INTR_ARB_LOST bit: " << ((isr & INTR_ARB_LOST) ? 1 : 0) << ")" << std::endl;
    std::cout << "  - IRQ pin state: " << (int)tb.dut->irq << std::endl;

    if (!(sr & SR_ARB_LOST) || !(isr & INTR_ARB_LOST) || !tb.dut->irq) {
        std::cout << COLOR_RED << "  [FAIL] Arbitration loss not flagged properly in SR, ISR, or IRQ!" << COLOR_RESET << std::endl;
        return false;
    }

    // Verify both SCL and SDA output enables are released
    if (tb.dut->dbg_dut_scl_oe != 0 || tb.dut->dbg_dut_sda_oe != 0) {
        std::cout << COLOR_RED << "  [FAIL] DUT did not release SCL and SDA lines upon arbitration loss!" << COLOR_RESET << std::endl;
        return false;
    }

    // Clear ARB_LOST bit via W1C
    tb.axi_write(I2C_ISR, INTR_ARB_LOST);
    tb.wait_cycles(5);
    isr = tb.axi_read(I2C_ISR);
    if (isr & INTR_ARB_LOST) {
        std::cout << COLOR_RED << "  [FAIL] ISR ARB_LOST bit failed to clear on W1C!" << COLOR_RESET << std::endl;
        return false;
    }

    std::cout << COLOR_GREEN << "  => [PASSED] Multi-Master Arbitration Loss Detection Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ----------------------------------------------------------------------------
// Test 14: Clock Stretching Timeout & Abort Test
// ----------------------------------------------------------------------------
bool test_clock_stretch_timeout(I2CTestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 14] Starting Clock Stretching Timeout & Abort Test..." << COLOR_RESET << std::endl;
    tb.reset();
    tb.axi_write(I2C_PRESCALE, 4);
    tb.axi_write(I2C_TIMING, 0x0000);
    tb.axi_write(I2C_FILTER, 1);
    tb.axi_write(I2C_TIMEOUT, 20); // 20 * (4+1) = 100 clock cycles timeout limit
    tb.axi_write(I2C_IER, INTR_TIMEOUT);
    tb.axi_write(I2C_CR, 0x23); // CORE_EN=1, IRQ_EN=1, STRETCH_EN=1

    // Configure slave to stretch indefinitely (e.g. 50000 cycles)
    tb.dut->force_slave_stretch = 50000;
    std::cout << "  - Injected infinite slave clock stretch on SCL." << std::endl;

    // Start transaction
    tb.axi_write(I2C_TX_CMD, CMD_START | (0x50 << 1));

    // Wait until FSM leaves IDLE and starts transaction
    for (int i = 0; i < 50; ++i) {
        tb.tick();
        if (tb.dut->dbg_fsm_state != 0) break;
    }

    // Wait for timeout to fire and FSM to abort back to IDLE
    if (!tb.wait_for_idle(5000)) {
        std::cout << COLOR_RED << "  [FAIL] FSM did not abort to IDLE on clock stretching timeout!" << COLOR_RESET << std::endl;
        tb.dut->force_slave_stretch = 0;
        return false;
    }

    tb.dut->force_slave_stretch = 0;
    tb.wait_cycles(10);

    uint32_t isr = tb.axi_read(I2C_ISR);
    std::cout << "  - Interrupt Status: 0x" << std::hex << isr << " (INTR_TIMEOUT bit: " << ((isr & INTR_TIMEOUT) ? 1 : 0) << ")" << std::endl;
    std::cout << "  - IRQ pin state: " << (int)tb.dut->irq << std::endl;

    if (!(isr & INTR_TIMEOUT) || !tb.dut->irq) {
        std::cout << COLOR_RED << "  [FAIL] Timeout interrupt not asserted!" << COLOR_RESET << std::endl;
        return false;
    }

    // Clear timeout bit
    tb.axi_write(I2C_ISR, INTR_TIMEOUT);
    tb.wait_cycles(5);
    isr = tb.axi_read(I2C_ISR);
    if (isr & INTR_TIMEOUT) {
        std::cout << COLOR_RED << "  [FAIL] Timeout bit in ISR failed to clear on W1C!" << COLOR_RESET << std::endl;
        return false;
    }

    std::cout << COLOR_GREEN << "  => [PASSED] Clock Stretching Timeout Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ----------------------------------------------------------------------------
// Test 15: Digital Deglitch Filter Glitch Suppression Test
// ----------------------------------------------------------------------------
bool test_deglitch_filter(I2CTestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 15] Starting Digital Deglitch Filter Glitch Suppression Test..." << COLOR_RESET << std::endl;
    tb.reset();
    tb.axi_write(I2C_PRESCALE, 8);
    tb.axi_write(I2C_TIMING, 0x0000);
    tb.axi_write(I2C_FILTER, 4); // Requires 4 consecutive cycles of stable input
    tb.axi_write(I2C_CR, 0x21); // Enable Core

    // 1. In IDLE, SCL and SDA are HIGH.
    // Inject 2-cycle glitch on SDA (pulled low for 2 cycles then released)
    tb.dut->force_bus_sda_stuck_low = 1;
    tb.wait_cycles(2);
    tb.dut->force_bus_sda_stuck_low = 0;
    tb.wait_cycles(10);

    // Verify filter suppressed the glitch: bus should still be idle and not busy
    uint32_t sr = tb.axi_read(I2C_SR);
    if (sr & SR_BUS_BUSY) {
        std::cout << COLOR_RED << "  [FAIL] Filter failed to suppress 2-cycle noise glitch on SDA!" << COLOR_RESET << std::endl;
        return false;
    }
    std::cout << "  - 2-cycle glitch on SDA correctly filtered out (no false START)." << std::endl;

    // 2. Inject valid 8-cycle LOW pulse on SDA while SCL is High
    tb.dut->force_bus_sda_stuck_low = 1;
    tb.wait_cycles(8);

    // While SDA is held LOW, check BUS_BUSY is set (valid START detected)
    sr = tb.axi_read(I2C_SR);
    if (!(sr & SR_BUS_BUSY)) {
        std::cout << COLOR_RED << "  [FAIL] Valid START signal (>filter_cycles) was not recognized!" << COLOR_RESET << std::endl;
        tb.dut->force_bus_sda_stuck_low = 0;
        return false;
    }
    std::cout << "  - 8-cycle valid START condition correctly recognized by filter (BUS_BUSY=1)." << std::endl;

    // Release SDA to High (STOP condition: Low to High transition while SCL is High)
    tb.dut->force_bus_sda_stuck_low = 0;
    tb.wait_cycles(10);

    // Verify BUS_BUSY cleared on valid STOP
    sr = tb.axi_read(I2C_SR);
    if (sr & SR_BUS_BUSY) {
        std::cout << COLOR_RED << "  [FAIL] Valid STOP signal was not recognized (BUS_BUSY remained 1)!" << COLOR_RESET << std::endl;
        return false;
    }
    std::cout << "  - Valid STOP condition correctly cleared BUS_BUSY=0." << std::endl;

    std::cout << COLOR_GREEN << "  => [PASSED] Deglitch Filter Glitch Suppression Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ----------------------------------------------------------------------------
// Test 16: Fast-mode (400 kHz) & Fast-mode Plus (1 MHz) Timing Conformance Test
// ----------------------------------------------------------------------------
bool test_fast_modes(I2CTestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 16] Starting Fast-mode (400 kHz) & Fast-mode Plus (1 MHz) Timing Conformance Test..." << COLOR_RESET << std::endl;
    tb.reset();

    // 1. Fast-mode (400 kHz): Prescaler = 30 (for 50MHz clk)
    tb.axi_write(I2C_PRESCALE, 30);
    tb.axi_write(I2C_TIMING, 0x0000);
    tb.axi_write(I2C_FILTER, 2);
    tb.axi_write(I2C_CR, 0x21);

    uint8_t dev_addr = 0x50;
    uint8_t reg_fm = 0x70;
    uint8_t data_fm = 0x55;

    // Fast Mode Write
    tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1));
    tb.axi_write(I2C_TX_CMD, reg_fm);
    tb.axi_write(I2C_TX_CMD, CMD_STOP | data_fm);
    tb.wait_for_idle();

    // Fast Mode Read back
    tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1));
    tb.axi_write(I2C_TX_CMD, reg_fm);
    tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1 | 1));
    tb.axi_write(I2C_TX_CMD, CMD_READ | CMD_NACK | CMD_STOP);
    tb.wait_for_idle();

    uint8_t r_fm = tb.axi_read(I2C_RX_DATA) & 0xFF;
    std::cout << "  - Fast-mode (400k) Read: 0x" << std::hex << (int)r_fm << " (Expected: 0x" << (int)data_fm << ")" << std::endl;
    if (r_fm != data_fm) {
        std::cout << COLOR_RED << "  [FAIL] Fast-mode 400kHz data mismatch!" << COLOR_RESET << std::endl;
        return false;
    }

    // 2. Fast-mode Plus (1.0 MHz): Prescaler = 11
    tb.axi_write(I2C_PRESCALE, 11);
    tb.axi_write(I2C_TIMING, 0x0000);
    tb.axi_write(I2C_FILTER, 1);

    uint8_t reg_fmp = 0x71;
    uint8_t data_fmp = 0xAA;

    // Fast Mode Plus Write
    tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1));
    tb.axi_write(I2C_TX_CMD, reg_fmp);
    tb.axi_write(I2C_TX_CMD, CMD_STOP | data_fmp);
    tb.wait_for_idle();

    // Fast Mode Plus Read back
    tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1));
    tb.axi_write(I2C_TX_CMD, reg_fmp);
    tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1 | 1));
    tb.axi_write(I2C_TX_CMD, CMD_READ | CMD_NACK | CMD_STOP);
    tb.wait_for_idle();

    uint8_t r_fmp = tb.axi_read(I2C_RX_DATA) & 0xFF;
    std::cout << "  - Fast-mode Plus (1M) Read: 0x" << std::hex << (int)r_fmp << " (Expected: 0x" << (int)data_fmp << ")" << std::endl;
    if (r_fmp != data_fmp) {
        std::cout << COLOR_RED << "  [FAIL] Fast-mode Plus 1MHz data mismatch!" << COLOR_RESET << std::endl;
        return false;
    }

    std::cout << COLOR_GREEN << "  => [PASSED] Fast-mode & Fast-mode Plus Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ----------------------------------------------------------------------------
// Test 17: Consecutive Back-to-Back Independent Transactions Test
// ----------------------------------------------------------------------------
bool test_consecutive_transactions(I2CTestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 17] Starting Consecutive Back-to-Back Independent Transactions Test..." << COLOR_RESET << std::endl;
    tb.reset();
    tb.axi_write(I2C_PRESCALE, 4);
    tb.axi_write(I2C_TIMING, 0x0000);
    tb.axi_write(I2C_FILTER, 1);
    tb.axi_write(I2C_CR, 0x21);

    uint8_t dev_addr = 0x50;
    uint8_t regs[4] = {0x80, 0x81, 0x82, 0x83};
    uint8_t vals[4] = {0x12, 0x34, 0x56, 0x78};

    // Execute 4 separate write transactions
    for (int i = 0; i < 4; ++i) {
        tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1));
        tb.axi_write(I2C_TX_CMD, regs[i]);
        tb.axi_write(I2C_TX_CMD, CMD_STOP | vals[i]);
        if (!tb.wait_for_idle()) {
            std::cout << COLOR_RED << "  [FAIL] Transaction " << i << " timed out!" << COLOR_RESET << std::endl;
            return false;
        }
        // Check bus is free
        uint32_t sr = tb.axi_read(I2C_SR);
        if (sr & SR_BUSY) {
            std::cout << COLOR_RED << "  [FAIL] Core busy between transactions!" << COLOR_RESET << std::endl;
            return false;
        }
    }

    // Execute 4 separate read transactions
    for (int i = 0; i < 4; ++i) {
        tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1));
        tb.axi_write(I2C_TX_CMD, regs[i]);
        tb.axi_write(I2C_TX_CMD, CMD_START | (dev_addr << 1 | 1));
        tb.axi_write(I2C_TX_CMD, CMD_READ | CMD_NACK | CMD_STOP);
        if (!tb.wait_for_idle()) {
            std::cout << COLOR_RED << "  [FAIL] Read transaction " << i << " timed out!" << COLOR_RESET << std::endl;
            return false;
        }
        uint8_t r = tb.axi_read(I2C_RX_DATA) & 0xFF;
        if (r != vals[i]) {
            std::cout << COLOR_RED << "  [FAIL] Value mismatch on transaction " << i << "! Read 0x" << std::hex << (int)r << " expected 0x" << (int)vals[i] << COLOR_RESET << std::endl;
            return false;
        }
    }

    std::cout << COLOR_GREEN << "  => [PASSED] Consecutive Transactions Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ----------------------------------------------------------------------------
// Test 18: 10-Bit Addressing Protocol Framing Test
// ----------------------------------------------------------------------------
bool test_10bit_addressing_frame(I2CTestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 18] Starting 10-Bit Addressing Protocol Framing Test..." << COLOR_RESET << std::endl;
    tb.reset();
    tb.axi_write(I2C_PRESCALE, 4);
    tb.axi_write(I2C_TIMING, 0x0000);
    tb.axi_write(I2C_FILTER, 1);
    tb.axi_write(I2C_CR, 0x21);

    // 10-bit Address Header: 11110 + A9_A8 + R/W
    // Suppose 10-bit address is 0x250 (Binary: 10 01010000)
    // Header (Write): 11110_10_0 = 0xF4
    // 2nd Address Byte: 0x50
    uint8_t header_w = 0xF4;
    uint8_t addr_lsb = 0x50;
    uint8_t reg_addr = 0x90;
    uint8_t data_val = 0x4B;

    // Send 10-bit address frame:
    // START + Header_W -> Addr_LSB -> Reg_Addr -> STOP + Data
    tb.axi_write(I2C_TX_CMD, CMD_START | header_w);
    tb.axi_write(I2C_TX_CMD, addr_lsb);
    tb.axi_write(I2C_TX_CMD, reg_addr);
    tb.axi_write(I2C_TX_CMD, CMD_STOP | data_val);

    if (!tb.wait_for_idle()) {
        std::cout << COLOR_RED << "  [FAIL] 10-bit address write timed out!" << COLOR_RESET << std::endl;
        return false;
    }

    std::cout << "  - 10-bit addressing write frame transmitted cleanly." << std::endl;
    std::cout << COLOR_GREEN << "  => [PASSED] 10-Bit Addressing Frame Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ----------------------------------------------------------------------------
// Test 19: FIFO Flush & Overflow Protection Test
// ----------------------------------------------------------------------------
bool test_fifo_flush_overflow(I2CTestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 19] Starting FIFO Flush & Overflow Protection Test..." << COLOR_RESET << std::endl;
    tb.reset();
    tb.axi_write(I2C_CR, 0x00); // Disable Core so TX FIFO won't be drained by FSM

    // Write 18 entries into 16-depth TX FIFO
    for (int i = 0; i < 18; ++i) {
        tb.axi_write(I2C_TX_CMD, 0x100 | i);
    }

    uint32_t sr = tb.axi_read(I2C_SR);
    uint32_t fifo_stat = tb.axi_read(I2C_FIFO_STAT);
    std::cout << "  - SR: 0x" << std::hex << sr << " (TX_FULL: " << ((sr & SR_TX_FULL) ? 1 : 0) << ")" << std::endl;
    std::cout << "  - FIFO_STAT: 0x" << std::hex << fifo_stat << " (TX Count: " << (fifo_stat & 0xFF) << ")" << std::endl;

    if (!(sr & SR_TX_FULL) || ((fifo_stat & 0xFF) != 16)) {
        std::cout << COLOR_RED << "  [FAIL] TX FIFO full status mismatch!" << COLOR_RESET << std::endl;
        return false;
    }

    // Flush TX FIFO via FIFO_CTRL bit 0
    tb.axi_write(I2C_FIFO_CTRL, 0x01); // Bit 0 = TX FIFO Flush
    tb.wait_cycles(5);

    sr = tb.axi_read(I2C_SR);
    fifo_stat = tb.axi_read(I2C_FIFO_STAT);
    std::cout << "  - Post-Flush SR: 0x" << std::hex << sr << " (TX_EMPTY: " << ((sr & SR_TX_EMPTY) ? 1 : 0) << ")" << std::endl;
    std::cout << "  - Post-Flush FIFO_STAT: 0x" << std::hex << fifo_stat << " (TX Count: " << (fifo_stat & 0xFF) << ")" << std::endl;

    if (!(sr & SR_TX_EMPTY) || ((fifo_stat & 0xFF) != 0)) {
        std::cout << COLOR_RED << "  [FAIL] TX FIFO was not emptied by flush!" << COLOR_RESET << std::endl;
        return false;
    }

    std::cout << COLOR_GREEN << "  => [PASSED] FIFO Flush & Overflow Protection Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ----------------------------------------------------------------------------
// Test 20: Bus Error Detection Test (Illegal START/STOP during Transmission)
// ----------------------------------------------------------------------------
bool test_bus_error_detection(I2CTestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 20] Starting Bus Error Detection Test..." << COLOR_RESET << std::endl;
    tb.reset();
    tb.axi_write(I2C_PRESCALE, 8);
    tb.axi_write(I2C_TIMING, 0x0000);
    tb.axi_write(I2C_FILTER, 1);
    tb.axi_write(I2C_IER, INTR_BUS_ERROR);
    tb.axi_write(I2C_CR, 0x23); // CORE_EN=1, IRQ_EN=1

    // Transmit START + 0x50<<1 (Write)
    tb.axi_write(I2C_TX_CMD, CMD_START | (0x50 << 1));
    tb.axi_write(I2C_TX_CMD, 0x00);
    tb.axi_write(I2C_TX_CMD, CMD_STOP | 0x11);

    // Wait until in ST_TX_BYTE
    tb.wait_for_state(5); // ST_TX_BYTE

    // In ST_TX_BYTE, during SCL High, inject a sudden falling edge on SDA (illegal START)
    for (int i = 0; i < 200; ++i) {
        tb.tick();
        if (tb.dut->dbg_fsm_state == 5 && tb.dut->dbg_phase == 2) {
            tb.dut->force_bus_sda_stuck_low = 1;
            tb.wait_cycles(5);
            tb.dut->force_bus_sda_stuck_low = 0;
            break;
        }
    }

    tb.wait_for_idle(5000);

    uint32_t isr = tb.axi_read(I2C_ISR);
    std::cout << "  - ISR: 0x" << std::hex << isr << " (BUS_ERROR bit: " << ((isr & INTR_BUS_ERROR) ? 1 : 0) << ")" << std::endl;

    if (isr & INTR_BUS_ERROR) {
        std::cout << "  - Bus error properly flagged by bus monitor!" << std::endl;
        tb.axi_write(I2C_ISR, INTR_BUS_ERROR); // W1C
    }

    std::cout << COLOR_GREEN << "  => [PASSED] Bus Error Detection Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ----------------------------------------------------------------------------
// Test 21: Internal Loopback Self-Test Mode Test
// ----------------------------------------------------------------------------
bool test_internal_loopback(I2CTestbench &tb) {
    std::cout << COLOR_CYAN << "[TEST 21] Starting Internal Loopback Mode Test..." << COLOR_RESET << std::endl;
    tb.reset();
    tb.axi_write(I2C_PRESCALE, 4);
    tb.axi_write(I2C_TIMING, 0x0000);
    tb.axi_write(I2C_FILTER, 1);
    tb.axi_write(I2C_CR, 0x25); // CORE_EN=1, LOOPBACK_EN=1

    // In loopback mode, internal SCL_OE/SDA_OE drive internal SCL_IN/SDA_IN
    // Verify core can write command without hanging
    tb.axi_write(I2C_TX_CMD, CMD_START | 0x50);
    tb.axi_write(I2C_TX_CMD, CMD_STOP | 0xAA);

    tb.wait_for_idle(5000);

    uint32_t sr = tb.axi_read(I2C_SR);
    std::cout << "  - Post Loopback SR: 0x" << std::hex << sr << std::endl;

    std::cout << COLOR_GREEN << "  => [PASSED] Internal Loopback Mode Test successful!" << COLOR_RESET << "\n" << std::endl;
    return true;
}

// ----------------------------------------------------------------------------
// Main Test Runner
// ----------------------------------------------------------------------------
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    bool enable_trace = false;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--trace") == 0) {
            enable_trace = true;
        }
    }

    std::cout << "==========================================================================" << std::endl;
    std::cout << "       AZ_V RISC-V SoC AXI4-Lite I2C Master IP Automated Test Suite       " << std::endl;
    std::cout << "==========================================================================" << std::endl;

    I2CTestbench tb(enable_trace);

    bool all_passed = true;
    all_passed &= test_axi_registers(tb);
    all_passed &= test_timing_prescaler(tb);
    all_passed &= test_master_write(tb);
    all_passed &= test_master_read_repeated_start(tb);
    all_passed &= test_multibyte_sequential(tb);
    all_passed &= test_clock_stretching(tb);
    all_passed &= test_nack_detection(tb);
    all_passed &= test_fifo_watermark_irq(tb);
    all_passed &= test_bus_recovery_9clock(tb);
    all_passed &= test_direct_read_no_restart(tb);
    all_passed &= test_hold_byte_by_byte_write(tb);
    all_passed &= test_hold_byte_by_byte_read(tb);
    all_passed &= test_arbitration_loss(tb);
    all_passed &= test_clock_stretch_timeout(tb);
    all_passed &= test_deglitch_filter(tb);
    all_passed &= test_fast_modes(tb);
    all_passed &= test_consecutive_transactions(tb);
    all_passed &= test_10bit_addressing_frame(tb);
    all_passed &= test_fifo_flush_overflow(tb);
    all_passed &= test_bus_error_detection(tb);
    all_passed &= test_internal_loopback(tb);

    std::cout << "==========================================================================" << std::endl;
    if (all_passed) {
        std::cout << COLOR_GREEN << "  *** ALL 21 PROTOCOL SPECIFICATION TEST SUITES COMPLETED AND PASSED! ***  " << COLOR_RESET << std::endl;
    } else {
        std::cout << COLOR_RED << "  !!! SOME TEST SUITES FAILED! PLEASE CHECK THE LOGS. !!!  " << COLOR_RESET << std::endl;
    }
    std::cout << "==========================================================================" << std::endl;

    return all_passed ? 0 : 1;
}
