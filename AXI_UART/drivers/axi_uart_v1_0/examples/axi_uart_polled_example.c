/******************************************************************************
* Copyright (C) 2026 Zenbear. All Rights Reserved.
* SPDX-License-Identifier: Apache-2.0
******************************************************************************/
/**
 * @file axi_uart_polled_example.c
 * @brief Polled Mode Example for MicroBlaze using custom AXI4-Lite UART IP.
 ******************************************************************************/

#include <stdio.h>
#include "xparameters.h"
#include "xil_printf.h"
#include "axi_uart.h"

/* Define Base Address & CPU Clock Frequency */
#ifndef UART_BASEADDR
    #ifdef XPAR_AXI_UART_0_BASEADDR
        #define UART_BASEADDR XPAR_AXI_UART_0_BASEADDR
    #else
        #define UART_BASEADDR 0x40600000U
    #endif
#endif

#ifndef CPU_CLOCK_HZ
    #ifdef XPAR_CPU_CORE_CLOCK_FREQ_HZ
        #define CPU_CLOCK_HZ XPAR_CPU_CORE_CLOCK_FREQ_HZ
    #else
        #define CPU_CLOCK_HZ 100000000U /* 100 MHz */
    #endif
#endif

#define TEST_BAUDRATE 115200U

static AXI_Uart UartInstance;

int main(void) {
    int Status;

    xil_printf("\r\n=== Custom AXI-UART Polled Demo on MicroBlaze ===\r\n");

    /* 1. Initialize custom UART instance */
    Status = AXI_Uart_Initialize(&UartInstance, UART_BASEADDR, CPU_CLOCK_HZ);
    if (Status != XST_SUCCESS) {
        xil_printf("ERROR: UART initialization failed (%d)!\r\n", Status);
        return XST_FAILURE;
    }

    /* 2. Run Built-in Loopback Self-Test */
    xil_printf("Running Hardware Loopback Self-Test... ");
    Status = AXI_Uart_SelfTest(&UartInstance);
    if (Status != XST_SUCCESS) {
        xil_printf("FAILED!\r\n");
        return XST_FAILURE;
    }
    xil_printf("PASSED!\r\n");

    /* 3. Set Baud Rate to 115200 bps */
    Status = AXI_Uart_SetBaudRate(&UartInstance, TEST_BAUDRATE);
    if (Status != XST_SUCCESS) {
        xil_printf("ERROR: Failed to set baud rate (%d)!\r\n", Status);
        return XST_FAILURE;
    }

    /* 4. Configure Line Control: 8 data bits, no parity, 1 stop bit (8N1) */
    Status = AXI_Uart_SetLineControl(&UartInstance,
                                     AXI_UART_DATABITS_8,
                                     AXI_UART_PARITY_NONE,
                                     AXI_UART_STOPBITS_1);
    if (Status != XST_SUCCESS) {
        xil_printf("ERROR: Failed to set line control (%d)!\r\n", Status);
        return XST_FAILURE;
    }

    /* 5. Transmit Banner message */
    const char Banner[] = "\r\nAXI-UART IP Ready! Type any characters to Echo back:\r\n";
    AXI_Uart_SendBlocking(&UartInstance, (const u8 *)Banner, sizeof(Banner) - 1);

    /* 6. Polled Echo Loop */
    while (1) {
        u8 RxChar;
        /* Non-blocking check for received characters */
        if (AXI_Uart_RecvByteNonBlocking(UART_BASEADDR, &RxChar)) {
            /* Echo character back */
            AXI_Uart_SendByte(UART_BASEADDR, RxChar);

            /* Also send CR if newline received */
            if (RxChar == '\r') {
                AXI_Uart_SendByte(UART_BASEADDR, '\n');
            }
        }
    }

    return XST_SUCCESS;
}
