// ============================================================================
// File: tb_uart_top.cpp
// Description: Main Verilator C++ Simulation Driver & Automated Test Runner
// Project: AZ_V_UART
// ============================================================================

#include <iostream>
#include <memory>
#include <cstdint>
#include <cstdlib>

#include "Vuart_tb.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

// Include Test Suites
#include "tests/test_axi_reg.hpp"
#include "tests/test_loopback.hpp"
#include "tests/test_fifo_watermark.hpp"
#include "tests/test_interrupt.hpp"

class UartDriver {
private:
    std::unique_ptr<Vuart_tb> top;
    std::unique_ptr<VerilatedVcdC> tfp;
    vluint64_t main_time;
    bool trace_enabled;

public:
    UartDriver(bool enable_trace = false)
        : top(std::make_unique<Vuart_tb>()),
          tfp(nullptr),
          main_time(0),
          trace_enabled(enable_trace)
    {
        if (trace_enabled) {
            Verilated::traceEverOn(true);
            tfp = std::make_unique<VerilatedVcdC>();
            top->trace(tfp.get(), 99);
            tfp->open("uart_sim.vcd");
        }

        // Initialize signals
        top->clk = 0;
        top->rst_n = 0;
        top->uart_rx_pin = 1;

        top->s_axi_awaddr = 0;
        top->s_axi_awprot = 0;
        top->s_axi_awvalid = 0;
        top->s_axi_wdata = 0;
        top->s_axi_wstrb = 0;
        top->s_axi_wvalid = 0;
        top->s_axi_bready = 0;

        top->s_axi_araddr = 0;
        top->s_axi_arprot = 0;
        top->s_axi_arvalid = 0;
        top->s_axi_rready = 0;

        // Reset pulse
        clock_ticks(5);
        top->rst_n = 1;
        clock_ticks(5);
    }

    ~UartDriver() {
        if (tfp) {
            tfp->close();
        }
        top->final();
    }

    void clock_ticks(int count = 1) {
        for (int i = 0; i < count; ++i) {
            top->clk = 0;
            top->eval();
            if (tfp) tfp->dump(main_time);
            main_time += 5;

            top->clk = 1;
            top->eval();
            if (tfp) tfp->dump(main_time);
            main_time += 5;
        }
    }

    void axi_write(uint32_t addr, uint32_t data, uint8_t strb = 0xF) {
        top->s_axi_awaddr  = addr;
        top->s_axi_awvalid = 1;
        top->s_axi_wdata   = data;
        top->s_axi_wstrb   = strb;
        top->s_axi_wvalid  = 1;
        top->s_axi_bready  = 1;

        bool aw_done = false;
        bool w_done  = false;

        int timeout = 1000;
        while ((!aw_done || !w_done) && timeout > 0) {
            top->clk = 0; top->eval(); if (tfp) tfp->dump(main_time); main_time += 5;
            top->clk = 1; top->eval(); if (tfp) tfp->dump(main_time); main_time += 5;

            if (top->s_axi_awready) {
                aw_done = true;
                top->s_axi_awvalid = 0;
            }
            if (top->s_axi_wready) {
                w_done = true;
                top->s_axi_wvalid = 0;
            }
            timeout--;
        }

        // Wait BVALID
        timeout = 1000;
        while (!top->s_axi_bvalid && timeout > 0) {
            top->clk = 0; top->eval(); if (tfp) tfp->dump(main_time); main_time += 5;
            top->clk = 1; top->eval(); if (tfp) tfp->dump(main_time); main_time += 5;
            timeout--;
        }

        top->s_axi_bready = 0;
        clock_ticks(1);
    }

    uint32_t axi_read(uint32_t addr) {
        top->s_axi_araddr  = addr;
        top->s_axi_arvalid = 1;
        top->s_axi_rready  = 1;

        int timeout = 1000;
        while (!top->s_axi_arready && timeout > 0) {
            top->clk = 0; top->eval(); if (tfp) tfp->dump(main_time); main_time += 5;
            top->clk = 1; top->eval(); if (tfp) tfp->dump(main_time); main_time += 5;
            timeout--;
        }

        top->s_axi_arvalid = 0;

        uint32_t rdata = 0;
        timeout = 1000;
        while (!top->s_axi_rvalid && timeout > 0) {
            top->clk = 0; top->eval(); if (tfp) tfp->dump(main_time); main_time += 5;
            top->clk = 1; top->eval(); if (tfp) tfp->dump(main_time); main_time += 5;
            timeout--;
        }

        rdata = top->s_axi_rdata;
        top->s_axi_rready = 0;
        clock_ticks(1);
        return rdata;
    }

    bool get_irq() const {
        return (top->irq != 0);
    }
};

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    bool enable_trace = false;

    for (int i = 1; i < argc; ++i) {
        if (std::string(argv[i]) == "--trace") {
            enable_trace = true;
        }
    }

    std::cout << "==========================================================================" << std::endl;
    std::cout << "          AZ_V RISC-V SoC AXI4-Lite UART IP Automated Test Suite          " << std::endl;
    std::cout << "==========================================================================" << std::endl;

    UartDriver drv(enable_trace);

    bool all_passed = true;

    if (!run_test_axi_reg(drv))         all_passed = false;
    if (!run_test_loopback(drv))        all_passed = false;
    if (!run_test_fifo_watermark(drv))  all_passed = false;
    if (!run_test_interrupt(drv))       all_passed = false;

    std::cout << "==========================================================================" << std::endl;
    if (all_passed) {
        std::cout << "  >>> ALL TEST SUITES PASSED SUCCESSFULLY! (AZ_V_UART READY) <<<  " << std::endl;
        std::cout << "==========================================================================" << std::endl;
        return 0;
    } else {
        std::cerr << "  !!! SOME TEST SUITES FAILED! PLEASE CHECK LOGS. !!!  " << std::endl;
        std::cout << "==========================================================================" << std::endl;
        return 1;
    }
}
