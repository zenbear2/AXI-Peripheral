# ============================================================================
# File: Makefile
# Description: Top-Level Makefile for AXI-Peripheral Library
# Components: AXI_I2C, AXI_SPI, AXI_TIMER_PWM_WDT, AXI_UART
# ============================================================================

SUBDIRS = AXI_I2C AXI_SPI AXI_TIMER_PWM_WDT AXI_UART

.PHONY: all test-all lint-all clean help package-all \
        test-i2c test-spi test-timer test-uart \
        lint-i2c lint-spi lint-timer lint-uart

all: test-all

help:
	@echo "======================================================================"
	@echo "                     AXI-Peripheral Build System                      "
	@echo "======================================================================"
	@echo "Targets:"
	@echo "  make package-all - Run Vivado IP Packager for all 4 peripheral IPs"
	@echo "  make test-all    - Run test suites for all 4 peripheral IPs"
	@echo "  make lint-all    - Run Verilator lint checks for all peripheral IPs"
	@echo "  make clean       - Remove all simulation and build artifacts"
	@echo "  make test-i2c    - Run automated test suite for AXI_I2C"
	@echo "  make test-spi    - Run automated test suite for AXI_SPI"
	@echo "  make test-timer  - Run automated test suite for AXI_TIMER_PWM_WDT"
	@echo "  make test-uart   - Run automated test suite for AXI_UART"
	@echo "  make lint-i2c    - Run Verilator lint for AXI_I2C"
	@echo "  make lint-spi    - Run Verilator lint for AXI_SPI"
	@echo "  make lint-timer  - Run Verilator lint for AXI_TIMER_PWM_WDT"
	@echo "  make lint-uart   - Run Verilator lint for AXI_UART"
	@echo "======================================================================"

test-all:
	@echo "======================================================================"
	@echo ">>> Starting Automated Verification for All AXI-Peripheral IPs       "
	@echo "======================================================================"
	@$(MAKE) -C AXI_I2C test
	@$(MAKE) -C AXI_SPI test
	@$(MAKE) -C AXI_TIMER_PWM_WDT test
	@$(MAKE) -C AXI_UART test
	@echo "======================================================================"
	@echo ">>> ALL AXI-PERIPHERAL MODULE TESTS COMPLETED AND PASSED!            "
	@echo "======================================================================"

lint-all:
	@echo "======================================================================"
	@echo ">>> Running Verilator Lint Checks on All Peripheral IPs               "
	@echo "======================================================================"
	@$(MAKE) -C AXI_I2C lint
	@$(MAKE) -C AXI_SPI lint
	@$(MAKE) -C AXI_TIMER_PWM_WDT lint
	@$(MAKE) -C AXI_UART lint
	@echo "======================================================================"
	@echo ">>> ALL AXI-PERIPHERAL MODULE LINT CHECKS PASSED!                    "
	@echo "======================================================================"

test-i2c:
	@$(MAKE) -C AXI_I2C test

test-spi:
	@$(MAKE) -C AXI_SPI test

test-timer:
	@$(MAKE) -C AXI_TIMER_PWM_WDT test

test-uart:
	@$(MAKE) -C AXI_UART test

lint-i2c:
	@$(MAKE) -C AXI_I2C lint

lint-spi:
	@$(MAKE) -C AXI_SPI lint

lint-timer:
	@$(MAKE) -C AXI_TIMER_PWM_WDT lint

lint-uart:
	@$(MAKE) -C AXI_UART lint

package-all:
	@echo "======================================================================"
	@echo ">>> Packaging All AXI Peripheral IPs with Vivado IP Packager          "
	@echo "======================================================================"
	vivado -mode batch -source package_all_ips.tcl -nolog -nojournal

clean:
	@for dir in $(SUBDIRS); do \
		$(MAKE) -C $$dir clean; \
	done
	@echo "===> All peripheral build artifacts cleaned."
