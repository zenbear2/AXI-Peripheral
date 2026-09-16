# ============================================================================
# File: Makefile
# Description: Build, Lint & Automated Test Suite Runner for AXI_I2C IP Core
# Project: AXI_I2C
# ============================================================================

VERILATOR = verilator
VERILATOR_FLAGS = -Wall -Wno-fatal -Wno-TIMESCALEMOD --trace -Irtl/pkg -Irtl/core -Irtl/axi -Irtl/top -Itb

RTL_SRCS = \
	rtl/pkg/i2c_pkg.sv \
	rtl/core/sync_fifo.sv \
	rtl/core/i2c_input_filter.sv \
	rtl/core/i2c_timing_gen.sv \
	rtl/core/i2c_bus_monitor.sv \
	rtl/core/i2c_fsm_core.sv \
	rtl/core/i2c_regs.sv \
	rtl/axi/axi_lite_slave.sv \
	rtl/top/axi_i2c_top.sv

TB_SRCS = \
	tb/i2c_slave_model.sv \
	tb/i2c_tb.sv \
	tb/tb_i2c_top.cpp

OBJ_DIR = obj_dir
TARGET = $(OBJ_DIR)/Vi2c_tb

.PHONY: all lint build test wave clean

all: lint build test

lint:
	@echo "===> Running Verilator Lint Check on AZ_V_I2C RTL..."
	$(VERILATOR) --lint-only $(VERILATOR_FLAGS) --top-module i2c_tb $(RTL_SRCS) tb/i2c_slave_model.sv tb/i2c_tb.sv
	@echo "===> Lint check completed cleanly!"

build: $(TARGET)

$(TARGET): $(RTL_SRCS) $(TB_SRCS)
	@echo "===> Compiling SystemVerilog RTL and C++ Testbench with Verilator..."
	mkdir -p $(OBJ_DIR)
	$(VERILATOR) -cc $(VERILATOR_FLAGS) --exe --top-module i2c_tb $(RTL_SRCS) tb/i2c_slave_model.sv tb/i2c_tb.sv tb/tb_i2c_top.cpp
	$(MAKE) -C $(OBJ_DIR) -f Vi2c_tb.mk Vi2c_tb
	@echo "===> Build completed successfully!"

test: build
	@echo "===> Running Automated Test Suite..."
	./$(TARGET)

wave: build
	@echo "===> Running Simulation with VCD Waveform Generation..."
	./$(TARGET) --trace
	@echo "===> Waveform saved to i2c_sim.vcd"

clean:
	@echo "===> Cleaning build artifacts..."
	rm -rf $(OBJ_DIR) i2c_sim.vcd
