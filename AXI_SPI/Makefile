# ============================================================================
# File: Makefile
# Description: Build, Lint & Automated Test Suite Runner for AXI_SPI IP Core
# Project: AXI_SPI
# ============================================================================

VERILATOR = verilator
VERILATOR_FLAGS = -Wall -Wno-fatal -Wno-TIMESCALEMOD --trace -Irtl/pkg -Irtl/core -Irtl/axi -Irtl/top -Itb

RTL_SRCS = \
	rtl/pkg/spi_pkg.sv \
	rtl/core/sync_fifo.sv \
	rtl/core/spi_timing_gen.sv \
	rtl/core/spi_fsm_core.sv \
	rtl/core/spi_regs.sv \
	rtl/axi/axi_lite_slave.sv \
	rtl/top/axi_spi_top.sv

TB_SRCS = \
	tb/spi_slave_model.sv \
	tb/spi_tb.sv \
	tb/tb_spi_top.cpp

OBJ_DIR = obj_dir
TARGET = $(OBJ_DIR)/Vspi_tb

.PHONY: all lint build test wave clean

all: lint build test

lint:
	@echo "===> Running Verilator Lint Check on AZ_V_SPI RTL..."
	$(VERILATOR) --lint-only $(VERILATOR_FLAGS) --top-module spi_tb $(RTL_SRCS) tb/spi_slave_model.sv tb/spi_tb.sv
	@echo "===> Lint check completed cleanly!"

build: $(TARGET)

$(TARGET): $(RTL_SRCS) $(TB_SRCS)
	@echo "===> Compiling SystemVerilog RTL and C++ Testbench with Verilator..."
	mkdir -p $(OBJ_DIR)
	$(VERILATOR) -cc $(VERILATOR_FLAGS) --exe --top-module spi_tb $(RTL_SRCS) tb/spi_slave_model.sv tb/spi_tb.sv tb/tb_spi_top.cpp
	$(MAKE) -C $(OBJ_DIR) -f Vspi_tb.mk Vspi_tb
	@echo "===> Build completed successfully!"

test: build
	@echo "===> Running Automated Test Suite..."
	./$(TARGET)

wave: build
	@echo "===> Running Simulation with VCD Waveform Generation..."
	./$(TARGET) --trace
	@echo "===> Waveform saved to spi_sim.vcd"

clean:
	@echo "===> Cleaning build artifacts..."
	rm -rf $(OBJ_DIR) spi_sim.vcd
