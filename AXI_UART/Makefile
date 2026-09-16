# ============================================================================
# File: Makefile
# Description: Build, Lint & Automated Test Suite Runner for AXI_UART IP
# Project: AXI_UART
# ============================================================================

VERILATOR = verilator
VERILATOR_FLAGS = -Wall -Wno-fatal -Wno-TIMESCALEMOD --trace -Irtl/pkg -Irtl/core -Irtl/axi -Irtl/top -Itb/tests

RTL_SRCS = \
	rtl/pkg/uart_pkg.sv \
	rtl/core/baud_rate_gen.sv \
	rtl/core/sync_fifo.sv \
	rtl/core/uart_tx.sv \
	rtl/core/uart_rx.sv \
	rtl/axi/axi_lite_slave.sv \
	rtl/top/axi_uart_top.sv

TB_SRCS = \
	tb/uart_tb.sv \
	tb/tb_uart_top.cpp

OBJ_DIR = obj_dir
TARGET = $(OBJ_DIR)/Vuart_tb

.PHONY: all lint build test wave clean

all: lint build test

lint:
	@echo "===> Running Verilator Lint Check..."
	$(VERILATOR) --lint-only $(VERILATOR_FLAGS) --top-module uart_tb $(RTL_SRCS) tb/uart_tb.sv
	@echo "===> Lint check completed cleanly!"

build: $(TARGET)

$(TARGET): $(RTL_SRCS) $(TB_SRCS)
	@echo "===> Compiling SystemVerilog RTL and C++ Testbench with Verilator..."
	mkdir -p $(OBJ_DIR)
	$(VERILATOR) -cc $(VERILATOR_FLAGS) --exe --top-module uart_tb $(RTL_SRCS) tb/uart_tb.sv tb/tb_uart_top.cpp
	$(MAKE) -C $(OBJ_DIR) -f Vuart_tb.mk Vuart_tb
	@echo "===> Build completed successfully!"

test: build
	@echo "===> Running Automated Test Suite..."
	./$(TARGET)

wave: build
	@echo "===> Running Simulation with VCD Waveform Generation..."
	./$(TARGET) --trace
	@echo "===> Waveform saved to uart_sim.vcd"

clean:
	@echo "===> Cleaning build artifacts..."
	rm -rf $(OBJ_DIR) uart_sim.vcd
