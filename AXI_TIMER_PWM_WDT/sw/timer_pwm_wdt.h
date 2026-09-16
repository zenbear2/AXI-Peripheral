// ============================================================================
// File: timer_pwm_wdt.h
// Description: C/C++ Driver Header & Register Definitions for
//              AXI4-Lite 1 Timer + 4 PWM + Watchdog Integrated IP Core
// Project: AXI_TIMER_PWM_WDT
// ============================================================================

#ifndef _TIMER_PWM_WDT_H_
#define _TIMER_PWM_WDT_H_

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// ----------------------------------------------------------------------------
// IP Identification Constants
// ----------------------------------------------------------------------------
#define TPW_IP_ID_MAGIC             0x54505701UL // "TPW" v1.0

// ----------------------------------------------------------------------------
// Register Byte Offsets
// ----------------------------------------------------------------------------
// Global & Interrupt Registers
#define TPW_REG_IP_ID_VER           0x00
#define TPW_REG_GLOBAL_CTRL         0x04
#define TPW_REG_INTR_RAW            0x08
#define TPW_REG_INTR_EN             0x0C
#define TPW_REG_INTR_MASKED         0x10
#define TPW_REG_INTR_CLR            0x14

// Timer Subsystem Registers
#define TPW_REG_TIM_CTRL            0x20
#define TPW_REG_TIM_PRESCALER       0x24
#define TPW_REG_TIM_COUNTER         0x28
#define TPW_REG_TIM_AUTORELOAD      0x2C
#define TPW_REG_TIM_CAPTURE         0x30
#define TPW_REG_TIM_STATUS          0x34

// PWM Subsystem Registers
#define TPW_REG_PWM_CTRL            0x40
#define TPW_REG_PWM_PRESCALER       0x44
#define TPW_REG_PWM_PERIOD          0x48
#define TPW_REG_PWM_COUNTER         0x4C
#define TPW_REG_PWM_CH0_CMP         0x50
#define TPW_REG_PWM_CH1_CMP         0x54
#define TPW_REG_PWM_CH2_CMP         0x58
#define TPW_REG_PWM_CH3_CMP         0x5C
#define TPW_REG_PWM_CH_CFG          0x60
#define TPW_REG_PWM_DEADTIME        0x64
#define TPW_REG_PWM_FAULT_CFG       0x68
#define TPW_REG_PWM_STATUS          0x6C

// Watchdog Subsystem Registers
#define TPW_REG_WDT_CTRL            0x80
#define TPW_REG_WDT_KEY             0x84
#define TPW_REG_WDT_TIMEOUT_VAL     0x88
#define TPW_REG_WDT_WINDOW_VAL      0x8C
#define TPW_REG_WDT_WARN_VAL        0x90
#define TPW_REG_WDT_COUNTER         0x94
#define TPW_REG_WDT_STATUS          0x98
#define TPW_REG_WDT_RST_WIDTH       0x9C

// ----------------------------------------------------------------------------
// Watchdog Safety Key Definitions
// ----------------------------------------------------------------------------
#define TPW_WDT_KEY_FEED            0x55AACAFEUL // Reload / Service Watchdog
#define TPW_WDT_KEY_LOCK            0xDEADBEEFUL // Hardware Lockout Protection

// ----------------------------------------------------------------------------
// Interrupt Flag Bitmasks
// ----------------------------------------------------------------------------
#define TPW_INTR_TIM_OVF_MASK       (1UL << 0)
#define TPW_INTR_TIM_CAP_MASK       (1UL << 1)
#define TPW_INTR_PWM_PERIOD_MASK    (1UL << 2)
#define TPW_INTR_PWM_CH0_MASK       (1UL << 3)
#define TPW_INTR_PWM_CH1_MASK       (1UL << 4)
#define TPW_INTR_PWM_CH2_MASK       (1UL << 5)
#define TPW_INTR_PWM_CH3_MASK       (1UL << 6)
#define TPW_INTR_PWM_FAULT_MASK     (1UL << 7)
#define TPW_INTR_WDT_WARN_MASK      (1UL << 8)
#define TPW_INTR_WDT_WIN_FAIL_MASK  (1UL << 9)
#define TPW_INTR_WDT_TIMEOUT_MASK   (1UL << 10)

// ----------------------------------------------------------------------------
// Memory-Mapped Register Structure
// ----------------------------------------------------------------------------
typedef struct {
    volatile uint32_t IP_ID_VER;        // 0x00
    volatile uint32_t GLOBAL_CTRL;      // 0x04
    volatile uint32_t INTR_RAW;         // 0x08
    volatile uint32_t INTR_EN;          // 0x0C
    volatile uint32_t INTR_MASKED;      // 0x10
    volatile uint32_t INTR_CLR;         // 0x14
    volatile uint32_t _reserved0[2];    // 0x18 - 0x1C

    // Timer Subsystem (0x20 - 0x3C)
    volatile uint32_t TIM_CTRL;         // 0x20
    volatile uint32_t TIM_PRESCALER;    // 0x24
    volatile uint32_t TIM_COUNTER;      // 0x28
    volatile uint32_t TIM_AUTORELOAD;   // 0x2C
    volatile uint32_t TIM_CAPTURE;      // 0x30
    volatile uint32_t TIM_STATUS;       // 0x34
    volatile uint32_t _reserved1[2];    // 0x38 - 0x3C

    // PWM Subsystem (0x40 - 0x7C)
    volatile uint32_t PWM_CTRL;         // 0x40
    volatile uint32_t PWM_PRESCALER;    // 0x44
    volatile uint32_t PWM_PERIOD;       // 0x48
    volatile uint32_t PWM_COUNTER;      // 0x4C
    volatile uint32_t PWM_CH0_CMP;      // 0x50
    volatile uint32_t PWM_CH1_CMP;      // 0x54
    volatile uint32_t PWM_CH2_CMP;      // 0x58
    volatile uint32_t PWM_CH3_CMP;      // 0x5C
    volatile uint32_t PWM_CH_CFG;       // 0x60
    volatile uint32_t PWM_DEADTIME;     // 0x64
    volatile uint32_t PWM_FAULT_CFG;    // 0x68
    volatile uint32_t PWM_STATUS;       // 0x6C
    volatile uint32_t _reserved2[4];    // 0x70 - 0x7C

    // Watchdog Subsystem (0x80 - 0x9C)
    volatile uint32_t WDT_CTRL;         // 0x80
    volatile uint32_t WDT_KEY;          // 0x84
    volatile uint32_t WDT_TIMEOUT_VAL;  // 0x88
    volatile uint32_t WDT_WINDOW_VAL;   // 0x8C
    volatile uint32_t WDT_WARN_VAL;     // 0x90
    volatile uint32_t WDT_COUNTER;      // 0x94
    volatile uint32_t WDT_STATUS;       // 0x98
    volatile uint32_t WDT_RST_WIDTH;    // 0x9C
} tpw_regs_t;

// ----------------------------------------------------------------------------
// Inline Helper Driver API Functions
// ----------------------------------------------------------------------------
static inline uint32_t tpw_get_version(uintptr_t base_addr) {
    tpw_regs_t *dev = (tpw_regs_t *)base_addr;
    return dev->IP_ID_VER;
}

static inline void tpw_timer_init(uintptr_t base_addr, uint32_t prescaler, uint32_t reload_val, bool periodic, bool down_count) {
    tpw_regs_t *dev = (tpw_regs_t *)base_addr;
    dev->TIM_PRESCALER = prescaler;
    dev->TIM_AUTORELOAD = reload_val;
    uint32_t ctrl = 0;
    if (!periodic) ctrl |= (1U << 1); // One-shot
    if (down_count) ctrl |= (1U << 2);
    dev->TIM_CTRL = ctrl;
}

static inline void tpw_timer_start(uintptr_t base_addr) {
    tpw_regs_t *dev = (tpw_regs_t *)base_addr;
    dev->TIM_CTRL |= 0x1;
}

static inline void tpw_timer_stop(uintptr_t base_addr) {
    tpw_regs_t *dev = (tpw_regs_t *)base_addr;
    dev->TIM_CTRL &= ~0x1;
}

static inline void tpw_pwm_init(uintptr_t base_addr, uint32_t prescaler, uint32_t period, bool center_align, uint16_t deadtime) {
    tpw_regs_t *dev = (tpw_regs_t *)base_addr;
    dev->PWM_PRESCALER = prescaler;
    dev->PWM_PERIOD = period;
    dev->PWM_DEADTIME = (uint32_t)deadtime;
    uint32_t ctrl = (1U << 0); // Master Enable
    if (center_align) ctrl |= (1U << 1);
    dev->PWM_CTRL = ctrl;
}

static inline void tpw_pwm_set_channel(uintptr_t base_addr, uint8_t ch, uint32_t cmp_val, bool enable, bool invert, bool comp_enable) {
    tpw_regs_t *dev = (tpw_regs_t *)base_addr;
    if (ch == 0) dev->PWM_CH0_CMP = cmp_val;
    else if (ch == 1) dev->PWM_CH1_CMP = cmp_val;
    else if (ch == 2) dev->PWM_CH2_CMP = cmp_val;
    else if (ch == 3) dev->PWM_CH3_CMP = cmp_val;

    uint32_t cfg = dev->PWM_CH_CFG;
    if (enable) cfg |= (1U << ch);
    else cfg &= ~(1U << ch);

    if (invert) cfg |= (1U << (ch + 4));
    else cfg &= ~(1U << (ch + 4));
    dev->PWM_CH_CFG = cfg;

    uint32_t ctrl = dev->PWM_CTRL;
    if (comp_enable) ctrl |= (1U << (ch + 8));
    else ctrl &= ~(1U << (ch + 8));
    dev->PWM_CTRL = ctrl;
}

static inline void tpw_wdt_init(uintptr_t base_addr, uint32_t timeout, uint32_t window, uint32_t warn_val, bool win_en, bool rst_en, bool warn_irq_en) {
    tpw_regs_t *dev = (tpw_regs_t *)base_addr;
    dev->WDT_TIMEOUT_VAL = timeout;
    dev->WDT_WINDOW_VAL = window;
    dev->WDT_WARN_VAL = warn_val;

    uint32_t ctrl = (1U << 0); // Enable
    if (win_en) ctrl |= (1U << 1);
    if (rst_en) ctrl |= (1U << 2);
    if (warn_irq_en) ctrl |= (1U << 3);
    dev->WDT_CTRL = ctrl;
}

static inline void tpw_wdt_feed(uintptr_t base_addr) {
    tpw_regs_t *dev = (tpw_regs_t *)base_addr;
    dev->WDT_KEY = TPW_WDT_KEY_FEED;
}

static inline void tpw_wdt_lock(uintptr_t base_addr) {
    tpw_regs_t *dev = (tpw_regs_t *)base_addr;
    dev->WDT_KEY = TPW_WDT_KEY_LOCK;
}

#ifdef __cplusplus
}
#endif

#endif // _TIMER_PWM_WDT_H_
