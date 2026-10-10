/******************************************************************************
* Copyright (C) 2026 Zenbear. All Rights Reserved.
* SPDX-License-Identifier: Apache-2.0
******************************************************************************/
/**
 * @file axi_uart.h
 * @brief High-Level Device Driver API for custom AXI4-Lite UART IP Core.
 *
 * This driver supports:
 *  - MicroBlaze Standalone BSP (and other RISC-V/ARM cores).
 *  - Dynamic Baud Rate reconfiguration via 16-bit prescaler.
 *  - Configurable Line Control (5/6/7/8 data bits, Parity None/Odd/Even, 1/2 stop bits).
 *  - Synchronous / Blocking and Non-Blocking Polled Transfers.
 *  - Full Interrupt-Driven background TX and RX with callback registration.
 *  - FIFO Watermark threshold configuration.
 *  - Hardware internal loopback diagnostic self-test.
 ******************************************************************************/

#ifndef AXI_UART_H
#define AXI_UART_H

#ifdef __cplusplus
extern "C" {
#endif

/***************************** Include Files *********************************/
#include "axi_uart_l.h"

#if defined(__MICROBLAZE__) || defined(XPAR_XIL_IO_H) || defined(__XIL_IO_H__)
    #include "xstatus.h"
#else
    #ifndef XST_SUCCESS
        #define XST_SUCCESS       0
        #define XST_FAILURE       1
        #define XST_INVALID_PARAM 2
        #define XST_DEVICE_BUSY   3
    #endif
#endif

/************************** Constant Definitions *****************************/

/**
 * Data Bits Selection
 */
typedef enum {
    AXI_UART_DATABITS_5 = 5,
    AXI_UART_DATABITS_6 = 6,
    AXI_UART_DATABITS_7 = 7,
    AXI_UART_DATABITS_8 = 8
} AXI_Uart_DataBits;

/**
 * Parity Selection
 */
typedef enum {
    AXI_UART_PARITY_NONE = 0,
    AXI_UART_PARITY_EVEN = 1,
    AXI_UART_PARITY_ODD  = 2
} AXI_Uart_Parity;

/**
 * Stop Bits Selection
 */
typedef enum {
    AXI_UART_STOPBITS_1 = 1,
    AXI_UART_STOPBITS_2 = 2
} AXI_Uart_StopBits;

/**
 * Interrupt Event Callback Function Signatures
 */
typedef void (*AXI_Uart_Handler)(void *CallBackRef, u32 EventData);
typedef void (*AXI_Uart_ErrorHandler)(void *CallBackRef, u32 ErrorMask);

/**************************** Type Definitions *******************************/

/**
 * Hardware Configuration Structure
 */
typedef struct {
    UINTPTR BaseAddress;   /**< Memory-mapped base address of the IP core */
    u32     ClockFreqHz;   /**< AXI / System Clock frequency in Hz */
    u32     BaudRate;      /**< Target Baud rate (e.g. 115200) */
    u8      DataBits;      /**< 5, 6, 7, 8 */
    u8      Parity;        /**< 0: None, 1: Even, 2: Odd */
    u8      StopBits;      /**< 1, 2 */
    u8      TxWatermark;   /**< TX FIFO Watermark (0-16) */
    u8      RxWatermark;   /**< RX FIFO Watermark (0-16) */
} AXI_Uart_Config;

/**
 * Driver Instance Structure
 */
typedef struct {
    UINTPTR BaseAddress;         /**< Base address */
    u32     IsReady;             /**< Device initialized flag */
    u32     ClockFreqHz;         /**< System clock frequency */
    u32     BaudRate;            /**< Current baud rate */

    /* Non-blocking / Interrupt Buffer Tracking */
    const u8 *SendBufferPtr;     /**< Pointer to transmit buffer */
    u32       SendRequestedBytes;/**< Total bytes requested to send */
    u32       SendRemainingBytes;/**< Remaining bytes left to send */

    u8       *RecvBufferPtr;     /**< Pointer to receive buffer */
    u32       RecvRequestedBytes;/**< Total bytes requested to receive */
    u32       RecvRemainingBytes;/**< Remaining bytes left to receive */

    /* User Callback Functions */
    AXI_Uart_Handler      SendHandler;      /**< TX completion callback */
    AXI_Uart_Handler      RecvHandler;      /**< RX completion callback */
    AXI_Uart_ErrorHandler ErrorHandler;     /**< Error callback */
    void                 *CallBackRef;      /**< User callback context argument */
} AXI_Uart;

/************************** Function Prototypes ******************************/

/**
 * @brief Initialize the UART instance with base address and system clock.
 *
 * @param InstancePtr Pointer to driver instance.
 * @param BaseAddress AXI base address of the IP.
 * @param ClockFreqHz System clock frequency driving the UART IP core.
 * @return XST_SUCCESS on success, error code otherwise.
 */
int AXI_Uart_Initialize(AXI_Uart *InstancePtr, UINTPTR BaseAddress, u32 ClockFreqHz);

/**
 * @brief Initialize using a configuration structure.
 *
 * @param InstancePtr Pointer to driver instance.
 * @param ConfigPtr Pointer to configuration struct.
 * @return XST_SUCCESS on success, error code otherwise.
 */
int AXI_Uart_CfgInitialize(AXI_Uart *InstancePtr, const AXI_Uart_Config *ConfigPtr);

/**
 * @brief Configure baud rate.
 *
 * @param InstancePtr Pointer to driver instance.
 * @param BaudRate Desired baud rate (e.g. 9600, 115200, 921600).
 * @return XST_SUCCESS on success, XST_INVALID_PARAM if baud rate cannot be satisfied.
 */
int AXI_Uart_SetBaudRate(AXI_Uart *InstancePtr, u32 BaudRate);

/**
 * @brief Configure line control parameters (Data bits, Parity, Stop bits).
 *
 * @param InstancePtr Pointer to driver instance.
 * @param DataBits 5, 6, 7, or 8.
 * @param Parity AXI_UART_PARITY_NONE, EVEN, or ODD.
 * @param StopBits 1 or 2.
 * @return XST_SUCCESS on success, XST_INVALID_PARAM on invalid arguments.
 */
int AXI_Uart_SetLineControl(AXI_Uart *InstancePtr, u8 DataBits, u8 Parity, u8 StopBits);

/**
 * @brief Enable or disable internal hardware serial loopback mode.
 *
 * @param InstancePtr Pointer to driver instance.
 * @param Enable 1 to enable internal loopback, 0 to disable (external mode).
 */
void AXI_Uart_SetLoopback(AXI_Uart *InstancePtr, int Enable);

/**
 * @brief Configure FIFO watermark thresholds.
 *
 * @param InstancePtr Pointer to driver instance.
 * @param TxWatermark TX FIFO watermark threshold.
 * @param RxWatermark RX FIFO watermark threshold.
 */
void AXI_Uart_SetWatermarks(AXI_Uart *InstancePtr, u8 TxWatermark, u8 RxWatermark);

/**
 * @brief Read current FIFO fill levels.
 *
 * @param InstancePtr Pointer to driver instance.
 * @param TxCountPtr Output pointer for current TX FIFO entry count (can be NULL).
 * @param RxCountPtr Output pointer for current RX FIFO entry count (can be NULL).
 */
void AXI_Uart_GetFifoCounts(AXI_Uart *InstancePtr, u8 *TxCountPtr, u8 *RxCountPtr);

/**
 * @brief Read status register.
 *
 * @param InstancePtr Pointer to driver instance.
 * @return 32-bit status register content.
 */
static inline u32 AXI_Uart_GetStatus(AXI_Uart *InstancePtr) {
    return AXI_UART_READ_REG(InstancePtr->BaseAddress, AXI_UART_STATUS_OFFSET);
}

/************************* Polled Transfer APIs ******************************/

/**
 * @brief Send a buffer using blocking polled mode (waits for FIFO space).
 *
 * @param InstancePtr Pointer to driver instance.
 * @param BufferPtr Pointer to source buffer.
 * @param NumBytes Number of bytes to transmit.
 * @return Number of bytes transmitted.
 */
u32 AXI_Uart_SendBlocking(AXI_Uart *InstancePtr, const u8 *BufferPtr, u32 NumBytes);

/**
 * @brief Receive a buffer using blocking polled mode (waits for RX data).
 *
 * @param InstancePtr Pointer to driver instance.
 * @param BufferPtr Pointer to destination buffer.
 * @param NumBytes Number of bytes to receive.
 * @return Number of bytes received.
 */
u32 AXI_Uart_RecvBlocking(AXI_Uart *InstancePtr, u8 *BufferPtr, u32 NumBytes);

/**
 * @brief Non-blocking burst polled send (fills TX FIFO up to FIFO capacity).
 *
 * @param InstancePtr Pointer to driver instance.
 * @param BufferPtr Pointer to source data.
 * @param NumBytes Number of bytes requested.
 * @return Actual number of bytes placed into TX FIFO.
 */
u32 AXI_Uart_Send(AXI_Uart *InstancePtr, const u8 *BufferPtr, u32 NumBytes);

/**
 * @brief Non-blocking burst polled receive (drains RX FIFO).
 *
 * @param InstancePtr Pointer to driver instance.
 * @param BufferPtr Pointer to destination buffer.
 * @param NumBytes Maximum bytes to receive.
 * @return Actual number of bytes extracted from RX FIFO.
 */
u32 AXI_Uart_Recv(AXI_Uart *InstancePtr, u8 *BufferPtr, u32 NumBytes);

/*********************** Interrupt Driven Transfer APIs **********************/

/**
 * @brief Configure interrupt enable mask.
 *
 * @param InstancePtr Pointer to driver instance.
 * @param IntrMask Bitmask of interrupts to enable (AXI_UART_IXR_*).
 */
void AXI_Uart_EnableInterrupts(AXI_Uart *InstancePtr, u32 IntrMask);

/**
 * @brief Disable specified interrupts.
 *
 * @param InstancePtr Pointer to driver instance.
 * @param IntrMask Bitmask of interrupts to disable.
 */
void AXI_Uart_DisableInterrupts(AXI_Uart *InstancePtr, u32 IntrMask);

/**
 * @brief Register user callback functions for interrupt events.
 *
 * @param InstancePtr Pointer to driver instance.
 * @param SendHandler Callback called when SendAsync completes.
 * @param RecvHandler Callback called when RecvAsync completes.
 * @param ErrorHandler Callback called when parity/framing/overrun errors occur.
 * @param CallBackRef User-defined context reference.
 */
void AXI_Uart_SetHandlers(AXI_Uart *InstancePtr,
                          AXI_Uart_Handler SendHandler,
                          AXI_Uart_Handler RecvHandler,
                          AXI_Uart_ErrorHandler ErrorHandler,
                          void *CallBackRef);

/**
 * @brief Start non-blocking asynchronous transmission using interrupts.
 *
 * @param InstancePtr Pointer to driver instance.
 * @param BufferPtr Pointer to transmit buffer.
 * @param NumBytes Number of bytes to send.
 * @return XST_SUCCESS if queued, XST_DEVICE_BUSY if prior transfer in progress.
 */
int AXI_Uart_SendAsync(AXI_Uart *InstancePtr, const u8 *BufferPtr, u32 NumBytes);

/**
 * @brief Start non-blocking asynchronous reception using interrupts.
 *
 * @param InstancePtr Pointer to driver instance.
 * @param BufferPtr Pointer to buffer to receive incoming bytes.
 * @param NumBytes Number of bytes expected.
 * @return XST_SUCCESS if queued, XST_DEVICE_BUSY if prior reception in progress.
 */
int AXI_Uart_RecvAsync(AXI_Uart *InstancePtr, u8 *BufferPtr, u32 NumBytes);

/**
 * @brief Primary Interrupt Service Routine (ISR) for MicroBlaze interrupt controller.
 *
 * Hook this function to the MicroBlaze Interrupt Controller (XIntc) table.
 *
 * @param InstancePtr Void pointer cast of AXI_Uart instance.
 */
void AXI_Uart_IntrHandler(void *InstancePtr);

/************************* Self-Test Diagnostic API **************************/

/**
 * @brief Hardware Self-Test using internal serial loopback mode.
 *
 * Transmits test patterns in internal loopback and verifies correct reception.
 * Preserves original register configurations upon completion.
 *
 * @param InstancePtr Pointer to driver instance.
 * @return XST_SUCCESS if self-test passes, XST_FAILURE otherwise.
 */
int AXI_Uart_SelfTest(AXI_Uart *InstancePtr);

#ifdef __cplusplus
}
#endif

#endif /* AXI_UART_H */
