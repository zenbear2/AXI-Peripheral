/******************************************************************************
* Copyright (C) 2026 Zenbear. All Rights Reserved.
* SPDX-License-Identifier: Apache-2.0
******************************************************************************/
/**
 * @file axi_uart_intr_example.c
 * @brief Interrupt Mode Example for MicroBlaze using custom AXI4-Lite UART IP.
 ******************************************************************************/

#include <stdio.h>
#include "xparameters.h"
#include "xil_printf.h"
#include "xil_exception.h"
#include "axi_uart.h"

#ifdef XPAR_INTC_0_DEVICE_ID
    #include "xintc.h"
    #define INTC_DEVICE_ID  XPAR_INTC_0_DEVICE_ID
    static XIntc IntcInstance;
#endif

#ifndef UART_BASEADDR
    #ifdef XPAR_AXI_UART_0_BASEADDR
        #define UART_BASEADDR XPAR_AXI_UART_0_BASEADDR
    #else
        #define UART_BASEADDR 0x40600000U
    #endif
#endif

#ifndef UART_INTR_ID
    #ifdef XPAR_INTC_0_AXI_UART_0_VEC_ID
        #define UART_INTR_ID  XPAR_INTC_0_AXI_UART_0_VEC_ID
    #else
        #define UART_INTR_ID  0U
    #endif
#endif

#ifndef CPU_CLOCK_HZ
    #ifdef XPAR_CPU_CORE_CLOCK_FREQ_HZ
        #define CPU_CLOCK_HZ XPAR_CPU_CORE_CLOCK_FREQ_HZ
    #else
        #define CPU_CLOCK_HZ 100000000U
    #endif
#endif

#define BUFFER_SIZE 64

static AXI_Uart UartInstance;
static u8 TxBuffer[BUFFER_SIZE];
static u8 RxBuffer[BUFFER_SIZE];

static volatile int TxDone = 0;
static volatile int RxDone = 0;
static volatile u32 ErrorOccurred = 0;

/* Transmit Callback */
static void UartSendHandler(void *CallBackRef, u32 EventData) {
    (void)CallBackRef;
    (void)EventData;
    TxDone = 1;
}

/* Receive Callback */
static void UartRecvHandler(void *CallBackRef, u32 EventData) {
    (void)CallBackRef;
    (void)EventData;
    RxDone = 1;
}

/* Error Callback */
static void UartErrorHandler(void *CallBackRef, u32 ErrorMask) {
    (void)CallBackRef;
    ErrorOccurred = ErrorMask;
}

int main(void) {
    int Status;

    xil_printf("\r\n=== Custom AXI-UART Interrupt Demo on MicroBlaze ===\r\n");

    /* 1. Initialize custom UART instance */
    Status = AXI_Uart_Initialize(&UartInstance, UART_BASEADDR, CPU_CLOCK_HZ);
    if (Status != XST_SUCCESS) {
        xil_printf("UART Init Failed!\r\n");
        return XST_FAILURE;
    }

    /* 2. Configure Callback Handlers */
    AXI_Uart_SetHandlers(&UartInstance,
                         UartSendHandler,
                         UartRecvHandler,
                         UartErrorHandler,
                         &UartInstance);

#ifdef XPAR_INTC_0_DEVICE_ID
    /* 3. Setup MicroBlaze AXI Interrupt Controller (XIntc) */
    Status = XIntc_Initialize(&IntcInstance, INTC_DEVICE_ID);
    if (Status != XST_SUCCESS) {
        xil_printf("INTC Init Failed!\r\n");
        return XST_FAILURE;
    }

    /* Connect AXI_UART ISR to Interrupt Controller Vector */
    Status = XIntc_Connect(&IntcInstance, UART_INTR_ID,
                           (XInterruptHandler)AXI_Uart_IntrHandler,
                           &UartInstance);
    if (Status != XST_SUCCESS) {
        xil_printf("INTC Connect Failed!\r\n");
        return XST_FAILURE;
    }

    /* Start Interrupt Controller & Enable UART line */
    Status = XIntc_Start(&IntcInstance, XIN_REAL_MODE);
    if (Status != XST_SUCCESS) {
        return XST_FAILURE;
    }
    XIntc_Enable(&IntcInstance, UART_INTR_ID);

    /* Initialize MicroBlaze exception table & enable hardware interrupts */
    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                                 (Xil_ExceptionHandler)XIntc_InterruptHandler,
                                 &IntcInstance);
    Xil_ExceptionEnable();
#endif

    /* 4. Trigger Asynchronous Transmission */
    snprintf((char *)TxBuffer, BUFFER_SIZE, "Hello from MicroBlaze via Interrupt AXI-UART!\r\n");
    TxDone = 0;
    AXI_Uart_SendAsync(&UartInstance, TxBuffer, strlen((char *)TxBuffer));

    /* Wait for transmission completion via interrupt */
    while (!TxDone && !ErrorOccurred);

    if (ErrorOccurred) {
        xil_printf("Error during TX: 0x%08X\r\n", ErrorOccurred);
        return XST_FAILURE;
    }
    xil_printf("Interrupt TX complete!\r\n");

    /* 5. Asynchronous Receive 10 bytes */
    xil_printf("Waiting for 10 incoming bytes via interrupt...\r\n");
    RxDone = 0;
    AXI_Uart_RecvAsync(&UartInstance, RxBuffer, 10);

    while (!RxDone && !ErrorOccurred);

    if (RxDone) {
        xil_printf("Received 10 bytes: ");
        for (int i = 0; i < 10; i++) {
            outbyte((char)RxBuffer[i]);
        }
        xil_printf("\r\n");
    }

    return XST_SUCCESS;
}
