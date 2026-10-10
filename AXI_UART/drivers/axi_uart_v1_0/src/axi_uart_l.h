/******************************************************************************
* Copyright (C) 2026 Zenbear. All Rights Reserved.
* SPDX-License-Identifier: Apache-2.0
******************************************************************************/
/**
 * @file axi_uart_l.h
 * @brief Low-level hardware definitions, register map and inline I/O macros
 *        for custom AXI4-Lite UART IP Core on MicroBlaze / RISC-V platforms.
 *
 * This header provides lightweight, direct register access macros and polled
 * transfer primitives with zero memory overhead. Compatible with Xilinx Standalone
 * BSP (`xil_io.h`) as well as bare-metal memory-mapped I/O environments.
 ******************************************************************************/

#ifndef AXI_UART_L_H
#define AXI_UART_L_H

#ifdef __cplusplus
extern "C" {
#endif

/***************************** Include Files *********************************/
#if defined(__MICROBLAZE__) || defined(XPAR_XIL_IO_H) || defined(__XIL_IO_H__)
    #include "xil_types.h"
    #include "xil_io.h"
    #define AXI_UART_READ_REG(addr, offset)        Xil_In32((addr) + (offset))
    #define AXI_UART_WRITE_REG(addr, offset, val)  Xil_Out32((addr) + (offset), (u32)(val))
#else
    #include <stdint.h>
    typedef uint8_t   u8;
    typedef uint16_t  u16;
    typedef uint32_t  u32;
    typedef uintptr_t UINTPTR;

    #define AXI_UART_READ_REG(addr, offset) \
        (*(volatile u32 *)((UINTPTR)(addr) + (UINTPTR)(offset)))
    #define AXI_UART_WRITE_REG(addr, offset, val) \
        (*(volatile u32 *)((UINTPTR)(addr) + (UINTPTR)(offset)) = (u32)(val))
#endif

/************************** Register Offsets *********************************/
/**
 * Register Byte Offsets (32-bit word aligned)
 */
#define AXI_UART_TX_RX_DATA_OFFSET   0x00U  /**< [W] TX Data (7:0) / [R] RX Data (7:0) */
#define AXI_UART_STATUS_OFFSET       0x04U  /**< [R] Status Register */
#define AXI_UART_CTRL_OFFSET         0x08U  /**< [R/W] Control Register */
#define AXI_UART_BAUD_DIV_OFFSET     0x0CU  /**< [R/W] Baud Rate Prescaler Register */
#define AXI_UART_FIFO_STAT_OFFSET    0x10U  /**< [R/W] FIFO Counts & Watermark Thresholds */
#define AXI_UART_INTR_EN_OFFSET      0x14U  /**< [R/W] Interrupt Enable Register */
#define AXI_UART_INTR_STATUS_OFFSET  0x18U  /**< [R/W1C] Interrupt Status Register */

/************************** Register Bit Definitions *************************/

/**
 * STATUS Register (0x04) Bit Masks
 */
#define AXI_UART_SR_TX_EMPTY_MASK    0x00000001U  /**< Bit 0: TX FIFO is empty (1 = empty) */
#define AXI_UART_SR_TX_FULL_MASK     0x00000002U  /**< Bit 1: TX FIFO is full (1 = full) */
#define AXI_UART_SR_RX_VALID_MASK    0x00000004U  /**< Bit 2: RX FIFO has data (1 = not empty) */
#define AXI_UART_SR_RX_FULL_MASK     0x00000008U  /**< Bit 3: RX FIFO is full */
#define AXI_UART_SR_TX_BUSY_MASK     0x00000010U  /**< Bit 4: TX Core Engine is transmitting */
#define AXI_UART_SR_RX_BUSY_MASK     0x00000020U  /**< Bit 5: RX Core Engine is receiving */
#define AXI_UART_SR_FRAME_ERR_MASK   0x00000040U  /**< Bit 6: Stop bit framing error detected */
#define AXI_UART_SR_PARITY_ERR_MASK  0x00000080U  /**< Bit 7: Parity check error detected */
#define AXI_UART_SR_OVERRUN_ERR_MASK 0x00000100U  /**< Bit 8: RX/TX FIFO Overflow detected */

#define AXI_UART_SR_ERR_ALL_MASK     (AXI_UART_SR_FRAME_ERR_MASK | \
                                      AXI_UART_SR_PARITY_ERR_MASK | \
                                      AXI_UART_SR_OVERRUN_ERR_MASK)

/**
 * CTRL Register (0x08) Bit Masks
 */
#define AXI_UART_CR_TX_EN_MASK       0x00000001U  /**< Bit 0: TX Transmitter Enable */
#define AXI_UART_CR_RX_EN_MASK       0x00000002U  /**< Bit 1: RX Receiver Enable */
#define AXI_UART_CR_LOOPBACK_MASK    0x00000004U  /**< Bit 2: Internal Serial Loopback Enable */
#define AXI_UART_CR_DATA_BITS_MASK   0x00000018U  /**< Bits [4:3]: Data Bits config */
#define AXI_UART_CR_DATA_BITS_5      (0x0U << 3)  /**< 5 Data Bits */
#define AXI_UART_CR_DATA_BITS_6      (0x1U << 3)  /**< 6 Data Bits */
#define AXI_UART_CR_DATA_BITS_7      (0x2U << 3)  /**< 7 Data Bits */
#define AXI_UART_CR_DATA_BITS_8      (0x3U << 3)  /**< 8 Data Bits */
#define AXI_UART_CR_PARITY_EN_MASK   0x00000020U  /**< Bit 5: Parity Bit Enable */
#define AXI_UART_CR_PARITY_ODD_MASK  0x00000040U  /**< Bit 6: Parity Select (0: Even, 1: Odd) */
#define AXI_UART_CR_STOP_BITS_MASK   0x00000080U  /**< Bit 7: Stop Bits (0: 1-bit, 1: 2-bit) */

/** Default Reset Control Word: TX_EN | RX_EN | 8 Data Bits | No Parity | 1 Stop Bit */
#define AXI_UART_CR_DEFAULT_8N1      (AXI_UART_CR_TX_EN_MASK | \
                                      AXI_UART_CR_RX_EN_MASK | \
                                      AXI_UART_CR_DATA_BITS_8)

/**
 * FIFO_STAT Register (0x10) Fields
 */
#define AXI_UART_FIFO_TX_COUNT_MASK  0x000000FFU  /**< Bits [7:0]: Current TX FIFO Entry Count */
#define AXI_UART_FIFO_RX_COUNT_MASK  0x0000FF00U  /**< Bits [15:8]: Current RX FIFO Entry Count */
#define AXI_UART_FIFO_TX_WM_MASK     0x00FF0000U  /**< Bits [23:16]: TX Watermark Threshold */
#define AXI_UART_FIFO_RX_WM_MASK     0xFF000000U  /**< Bits [31:24]: RX Watermark Threshold */

#define AXI_UART_GET_TX_COUNT(reg)   ((u8)((reg) & 0xFFU))
#define AXI_UART_GET_RX_COUNT(reg)   ((u8)(((reg) >> 8) & 0xFFU))
#define AXI_UART_SET_WM(tx_wm, rx_wm) \
    ((((u32)(rx_wm) & 0xFFU) << 24) | (((u32)(tx_wm) & 0xFFU) << 16))

/**
 * INTR_EN (0x14) & INTR_STATUS (0x18) Bit Masks
 */
#define AXI_UART_IXR_TX_EMPTY        0x00000001U  /**< Bit 0: TX FIFO Empty Interrupt */
#define AXI_UART_IXR_RX_READY        0x00000002U  /**< Bit 1: RX Data Ready / Watermark Met */
#define AXI_UART_IXR_FRAME_ERR       0x00000004U  /**< Bit 2: Framing Error Interrupt (W1C) */
#define AXI_UART_IXR_OVERRUN         0x00000008U  /**< Bit 3: Overrun Error Interrupt (W1C) */
#define AXI_UART_IXR_ALL             0x0000000FU  /**< All interrupt sources mask */

/**************************** Inline Polled Macros ***************************/

/**
 * Check if the TX FIFO is full.
 */
#define AXI_Uart_IsTxFull(BaseAddress) \
    ((AXI_UART_READ_REG((BaseAddress), AXI_UART_STATUS_OFFSET) & AXI_UART_SR_TX_FULL_MASK) != 0U)

/**
 * Check if the TX FIFO is completely empty.
 */
#define AXI_Uart_IsTxEmpty(BaseAddress) \
    ((AXI_UART_READ_REG((BaseAddress), AXI_UART_STATUS_OFFSET) & AXI_UART_SR_TX_EMPTY_MASK) != 0U)

/**
 * Check if the RX FIFO contains valid received data (not empty).
 */
#define AXI_Uart_HasData(BaseAddress) \
    ((AXI_UART_READ_REG((BaseAddress), AXI_UART_STATUS_OFFSET) & AXI_UART_SR_RX_VALID_MASK) != 0U)

/**
 * Blocking polled byte send.
 */
static inline void AXI_Uart_SendByte(UINTPTR BaseAddress, u8 Data) {
    while (AXI_Uart_IsTxFull(BaseAddress)) {
        /* Wait until TX FIFO has room */
    }
    AXI_UART_WRITE_REG(BaseAddress, AXI_UART_TX_RX_DATA_OFFSET, (u32)Data);
}

/**
 * Blocking polled byte receive.
 */
static inline u8 AXI_Uart_RecvByte(UINTPTR BaseAddress) {
    while (!AXI_Uart_HasData(BaseAddress)) {
        /* Wait until RX FIFO has data */
    }
    return (u8)(AXI_UART_READ_REG(BaseAddress, AXI_UART_TX_RX_DATA_OFFSET) & 0xFFU);
}

/**
 * Non-blocking byte send. Returns 1 if written, 0 if FIFO was full.
 */
static inline int AXI_Uart_SendByteNonBlocking(UINTPTR BaseAddress, u8 Data) {
    if (AXI_Uart_IsTxFull(BaseAddress)) {
        return 0;
    }
    AXI_UART_WRITE_REG(BaseAddress, AXI_UART_TX_RX_DATA_OFFSET, (u32)Data);
    return 1;
}

/**
 * Non-blocking byte receive. Returns 1 if byte read into *DataPtr, 0 if RX empty.
 */
static inline int AXI_Uart_RecvByteNonBlocking(UINTPTR BaseAddress, u8 *DataPtr) {
    if (!AXI_Uart_HasData(BaseAddress)) {
        return 0;
    }
    *DataPtr = (u8)(AXI_UART_READ_REG(BaseAddress, AXI_UART_TX_RX_DATA_OFFSET) & 0xFFU);
    return 1;
}

#ifdef __cplusplus
}
#endif

#endif /* AXI_UART_L_H */
