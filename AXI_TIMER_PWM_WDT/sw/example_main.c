// ============================================================================
// File: example_main.c
// Description: Embedded Firmware Example Application for AXI_TIMER_PWM_WDT IP
// Project: AXI_TIMER_PWM_WDT
// ============================================================================

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include "timer_pwm_wdt.h"

#define TPW_BASE_ADDR 0x10001000UL

// Simulated Hardware IRQ Handler
void tpw_isr_handler(uintptr_t base_addr) {
    tpw_regs_t *dev = (tpw_regs_t *)base_addr;
    uint32_t raw = dev->INTR_RAW;
    uint32_t masked = dev->INTR_MASKED;

    printf("[ISR] Interrupt triggered! RAW=0x%08X, MASKED=0x%08X\n", raw, masked);

    if (masked & TPW_INTR_TIM_OVF_MASK) {
        printf("  -> Timer Overflow / Periodic Event Occurred\n");
    }
    if (masked & TPW_INTR_TIM_CAP_MASK) {
        printf("  -> Timer Input Capture Event! Timestamp = %u\n", dev->TIM_CAPTURE);
    }
    if (masked & TPW_INTR_PWM_FAULT_MASK) {
        printf("  -> [EMERGENCY] PWM Brake / Fault Sensor Triggered! Outputs Locked.\n");
        // Clear fault status
        dev->PWM_FAULT_CFG = 0x1;
    }
    if (masked & TPW_INTR_WDT_WARN_MASK) {
        printf("  -> [WARNING] Watchdog Pre-warning Early Interrupt! WDT_CNT=%u\n", dev->WDT_COUNTER);
        // Feed watchdog immediately
        tpw_wdt_feed(base_addr);
        printf("  -> Watchdog refreshed with safety key.\n");
    }

    // Acknowledge and Clear Interrupts (Write-1-to-Clear)
    dev->INTR_CLR = masked;
}

int main(void) {
    printf("============================================================\n");
    printf("  AXI4-Lite Timer + 4 PWM + Watchdog IP Demo Application     \n");
    printf("============================================================\n");

    // 1. Check IP Identification
    uint32_t ver = tpw_get_version(TPW_BASE_ADDR);
    printf("[Init] Detected IP Core ID / Version: 0x%08X\n", ver);

    // 2. Initialize General Purpose Timer
    // 50 MHz clock -> 1 MHz timer tick (prescaler = 49), 1000 ticks = 1 ms period
    printf("[Timer] Initializing 1 ms periodic timer...\n");
    tpw_timer_init(TPW_BASE_ADDR, 49, 1000, true, false);
    tpw_timer_start(TPW_BASE_ADDR);

    // 3. Initialize 4-Channel Center-Aligned PWM with Dead-Time for Half-Bridge Motor Control
    // Period = 1000 cycles (50 kHz PWM frequency at 50 MHz system clock)
    // Dead-time = 20 cycles (400 ns deadband)
    printf("[PWM] Initializing 4-Channel Center-Aligned 50 kHz PWM with 400ns Dead-Time...\n");
    tpw_pwm_init(TPW_BASE_ADDR, 0, 1000, true, 20);

    // Set Motor Phase A (CH0): 50% Duty Cycle with complementary output
    tpw_pwm_set_channel(TPW_BASE_ADDR, 0, 500, true, false, true);
    // Set Motor Phase B (CH1): 25% Duty Cycle with complementary output
    tpw_pwm_set_channel(TPW_BASE_ADDR, 1, 250, true, false, true);
    // Set Motor Phase C (CH2): 75% Duty Cycle with complementary output
    tpw_pwm_set_channel(TPW_BASE_ADDR, 2, 750, true, false, true);
    // Set Auxiliary Channel (CH3): 10% Duty Cycle standard output
    tpw_pwm_set_channel(TPW_BASE_ADDR, 3, 100, true, false, false);

    // 4. Initialize Safety Watchdog Subsystem (WWDG)
    // Timeout = 50,000,000 cycles (1.0 second)
    // Window = 30,000,000 cycles (Feeding allowed only after 0.4s has elapsed)
    // Pre-warning = 5,000,000 cycles (NMI triggered at 100ms before reset)
    printf("[WDT] Initializing Windowed Watchdog (1.0s timeout, windowed rate control)...\n");
    tpw_wdt_init(TPW_BASE_ADDR, 50000000, 30000000, 5000000, true, true, true);

    // Lock configuration against accidental corruption
    printf("[WDT] Locking Watchdog registers against software tamper...\n");
    tpw_wdt_lock(TPW_BASE_ADDR);

    printf("[System] Initialization complete. Entering main control loop.\n");
    return 0;
}
