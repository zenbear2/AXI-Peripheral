/******************************************************************************
* Copyright (C) 2026 Zenbear. All Rights Reserved.
* SPDX-License-Identifier: Apache-2.0
******************************************************************************/
/**
 * @file axi_uart_stdout.c
 * @brief Standard I/O retargeting functions (outbyte/inbyte) for MicroBlaze
 *        allowing direct use with xil_printf() and standard printf().
 ******************************************************************************/

#include "axi_uart_l.h"

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Default Base Address used by outbyte / inbyte if not overridden.
 * Users can update this variable at runtime:
 *   AxiUart_Stdout_BaseAddress = 0x40600000;
 */
#ifndef STDOUT_BASEADDRESS
#define STDOUT_BASEADDRESS 0x40600000U
#endif

volatile UINTPTR AxiUart_Stdout_BaseAddress = STDOUT_BASEADDRESS;

/**
 * @brief Transmit a single character over the custom AXI-UART IP.
 * Used by MicroBlaze xil_printf() and stdio printf().
 */
void outbyte(char c) {
    /* Handle carriage return for standard line feeds */
    if (c == '\n') {
        AXI_Uart_SendByte(AxiUart_Stdout_BaseAddress, (u8)'\r');
    }
    AXI_Uart_SendByte(AxiUart_Stdout_BaseAddress, (u8)c);
}

/**
 * @brief Receive a single character over the custom AXI-UART IP.
 * Used by MicroBlaze scanf() and getchar().
 */
char inbyte(void) {
    return (char)AXI_Uart_RecvByte(AxiUart_Stdout_BaseAddress);
}

#ifdef __cplusplus
}
#endif
