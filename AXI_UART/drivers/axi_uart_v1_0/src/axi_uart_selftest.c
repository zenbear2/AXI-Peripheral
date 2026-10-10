/******************************************************************************
* Copyright (C) 2026 Zenbear. All Rights Reserved.
* SPDX-License-Identifier: Apache-2.0
******************************************************************************/
/**
 * @file axi_uart_selftest.c
 * @brief Self-test diagnostic using hardware internal serial loopback.
 ******************************************************************************/

/***************************** Include Files *********************************/
#include "axi_uart.h"

/************************** Function Implementations *************************/

int AXI_Uart_SelfTest(AXI_Uart *InstancePtr) {
    if (InstancePtr == NULL || InstancePtr->IsReady != 0x55AA55AAU) {
        return XST_INVALID_PARAM;
    }

    UINTPTR BaseAddress = InstancePtr->BaseAddress;
    u32 SavedCtrl = AXI_UART_READ_REG(BaseAddress, AXI_UART_CTRL_OFFSET);

    /* 1. Flush any leftover bytes in RX FIFO */
    while (AXI_Uart_HasData(BaseAddress)) {
        (void)AXI_UART_READ_REG(BaseAddress, AXI_UART_TX_RX_DATA_OFFSET);
    }

    /* 2. Enable Internal Serial Loopback mode (8N1) */
    u32 LoopbackCtrl = SavedCtrl | AXI_UART_CR_LOOPBACK_MASK |
                       AXI_UART_CR_TX_EN_MASK | AXI_UART_CR_RX_EN_MASK;
    AXI_UART_WRITE_REG(BaseAddress, AXI_UART_CTRL_OFFSET, LoopbackCtrl);

    /* 3. Prepare test pattern vector */
    static const u8 TestVector[4] = {0x55U, 0xAAU, 0x3CU, 0xC3U};

    /* 4. Transmit test patterns */
    for (int i = 0; i < 4; i++) {
        AXI_Uart_SendByte(BaseAddress, TestVector[i]);
    }

    /* 5. Read back with timeout check */
    int Success = 1;
    for (int i = 0; i < 4; i++) {
        u32 Timeout = 100000U;
        while (!AXI_Uart_HasData(BaseAddress) && (--Timeout > 0)) {
            /* Spin wait for loopback byte transmission to finish */
        }

        if (Timeout == 0) {
            Success = 0;
            break;
        }

        u8 RecvByte = (u8)(AXI_UART_READ_REG(BaseAddress, AXI_UART_TX_RX_DATA_OFFSET) & 0xFFU);
        if (RecvByte != TestVector[i]) {
            Success = 0;
            break;
        }
    }

    /* 6. Verify no error flags occurred */
    u32 Status = AXI_UART_READ_REG(BaseAddress, AXI_UART_STATUS_OFFSET);
    if (Status & AXI_UART_SR_ERR_ALL_MASK) {
        Success = 0;
    }

    /* 7. Restore original control register configuration */
    AXI_UART_WRITE_REG(BaseAddress, AXI_UART_CTRL_OFFSET, SavedCtrl);

    return Success ? XST_SUCCESS : XST_FAILURE;
}
