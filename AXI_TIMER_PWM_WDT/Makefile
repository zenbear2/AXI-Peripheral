# ============================================================================
# File: Makefile
# Description: Build, Lint & Automated Test Suite Runner for AXI_TIMER_PWM_WDT IP
# Project: AXI_TIMER_PWM_WDT
# ============================================================================

VERILATOR = verilator
VERILATOR_FLAGS = -Wall -Wno-fatal -Wno-TIMESCALEMOD --trace -Irtl/pkg -Irtl/core -Irtl/axi -Irtl/top -Itb

RTL_SRCS = \
	rtl/pkg/timer_pwm_wdt_pkg.sv \
	rtl/axi/axi_lite_slave.sv \
	rtl/core/timer_core.sv \
	rtl/core/pwm_deadtime.sv \
	rtl/core/pwm_channel.sv \
	rtl/core/pwm_core.sv \
	rtl/core/wdt_core.sv \
	rtl/core/timer_pwm_wdt_regs.sv \
	rtl/top/axi_timer_pwm_wdt_top.sv

TB_SRCS = \
	tb/tb_timer_pwm_wdt.sv \
	tb/tb_timer_pwm_wdt.cpp

OBJ_DIR = obj_dir
TARGET = $(OBJ_DIR)/Vtb_timer_pwm_wdt

.PHONY: all lint build test wave clean

all: lint build test

lint:
	@echo "===> Running Verilator Lint Check on AXI_TIMER_PWM_WDT RTL..."
	$(VERILATOR) --lint-only $(VERILATOR_FLAGS) --top-module tb_timer_pwm_wdt $(RTL_SRCS) tb/tb_timer_pwm_wdt.sv
	@echo "===> Lint check completed cleanly!"

build: $(TARGET)

$(TARGET): $(RTL_SRCS) $(TB_SRCS)
	@echo "===> Compiling SystemVerilog RTL and C++ Testbench with Verilator..."
	mkdir -p $(OBJ_DIR)
	$(VERILATOR) -cc $(VERILATOR_FLAGS) --exe --top-module tb_timer_pwm_wdt $(RTL_SRCS) tb/tb_timer_pwm_wdt.sv tb/tb_timer_pwm_wdt.cpp
	$(MAKE) -C $(OBJ_DIR) -f Vtb_timer_pwm_wdt.mk Vtb_timer_pwm_wdt
	@echo "===> Build completed successfully!"

test: build
	@echo "===> Running Automated Test Suite..."
	./$(TARGET)

wave: build
	@echo "===> Running Simulation with VCD Waveform Generation..."
	./$(TARGET) --trace
	@echo "===> Waveform saved to timer_pwm_wdt_sim.vcd"

clean:
	@echo "===> Cleaning build artifacts..."
	rm -rf $(OBJ_DIR) timer_pwm_wdt_sim.vcd
