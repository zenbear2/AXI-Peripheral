/******************************************************************************
* Copyright (C) 2026 Zenbear. All Rights Reserved.
* SPDX-License-Identifier: Apache-2.0
******************************************************************************/
/**
 * @file axi_uart_intr.c
 * @brief Interrupt management and ISR handlers for custom AXI4-Lite UART IP.
 ******************************************************************************/

/***************************** Include Files *********************************/
#include "axi_uart.h"

/************************** Function Implementations *************************/

void AXI_Uart_EnableInterrupts(AXI_Uart *InstancePtr, u32 IntrMask) {
    if (InstancePtr == NULL) return;

    u32 CurrentMask = AXI_UART_READ_REG(InstancePtr->BaseAddress, AXI_UART_INTR_EN_OFFSET);
    CurrentMask |= (IntrMask & AXI_UART_IXR_ALL);
    AXI_UART_WRITE_REG(InstancePtr->BaseAddress, AXI_UART_INTR_EN_OFFSET, CurrentMask);
}

void AXI_Uart_DisableInterrupts(AXI_Uart *InstancePtr, u32 IntrMask) {
    if (InstancePtr == NULL) return;

    u32 CurrentMask = AXI_UART_READ_REG(InstancePtr->BaseAddress, AXI_UART_INTR_EN_OFFSET);
    CurrentMask &= ~(IntrMask & AXI_UART_IXR_ALL);
    AXI_UART_WRITE_REG(InstancePtr->BaseAddress, AXI_UART_INTR_EN_OFFSET, CurrentMask);
}

void AXI_Uart_SetHandlers(AXI_Uart *InstancePtr,
                          AXI_Uart_Handler SendHandler,
                          AXI_Uart_Handler RecvHandler,
                          AXI_Uart_ErrorHandler ErrorHandler,
                          void *CallBackRef) {
    if (InstancePtr == NULL) return;

    InstancePtr->SendHandler  = SendHandler;
    InstancePtr->RecvHandler  = RecvHandler;
    InstancePtr->ErrorHandler = ErrorHandler;
    InstancePtr->CallBackRef  = CallBackRef;
}

int AXI_Uart_SendAsync(AXI_Uart *InstancePtr, const u8 *BufferPtr, u32 NumBytes) {
    if (InstancePtr == NULL || BufferPtr == NULL || NumBytes == 0) {
        return XST_INVALID_PARAM;
    }

    /* Check if previous send is still in progress */
    if (InstancePtr->SendRemainingBytes > 0) {
        return XST_DEVICE_BUSY;
    }

    InstancePtr->SendBufferPtr        = BufferPtr;
    InstancePtr->SendRequestedBytes   = NumBytes;
    InstancePtr->SendRemainingBytes   = NumBytes;

    /* Prime the TX FIFO with initial bytes up to FIFO depth */
    while (InstancePtr->SendRemainingBytes > 0 && !AXI_Uart_IsTxFull(InstancePtr->BaseAddress)) {
        AXI_UART_WRITE_REG(InstancePtr->BaseAddress,
                           AXI_UART_TX_RX_DATA_OFFSET,
                           (u32)(*InstancePtr->SendBufferPtr));
        InstancePtr->SendBufferPtr++;
        InstancePtr->SendRemainingBytes--;
    }

    /* Enable TX Empty interrupt to refill remaining bytes or signal completion when FIFO empties */
    AXI_Uart_EnableInterrupts(InstancePtr, AXI_UART_IXR_TX_EMPTY);

    return XST_SUCCESS;
}

int AXI_Uart_RecvAsync(AXI_Uart *InstancePtr, u8 *BufferPtr, u32 NumBytes) {
    if (InstancePtr == NULL || BufferPtr == NULL || NumBytes == 0) {
        return XST_INVALID_PARAM;
    }

    /* Check if previous receive is still in progress */
    if (InstancePtr->RecvRemainingBytes > 0) {
        return XST_DEVICE_BUSY;
    }

    InstancePtr->RecvBufferPtr        = BufferPtr;
    InstancePtr->RecvRequestedBytes   = NumBytes;
    InstancePtr->RecvRemainingBytes   = NumBytes;

    /* Drain any bytes already present in the RX FIFO */
    while (InstancePtr->RecvRemainingBytes > 0 && AXI_Uart_HasData(InstancePtr->BaseAddress)) {
        *InstancePtr->RecvBufferPtr = (u8)(AXI_UART_READ_REG(InstancePtr->BaseAddress,
                                                             AXI_UART_TX_RX_DATA_OFFSET) & 0xFFU);
        InstancePtr->RecvBufferPtr++;
        InstancePtr->RecvRemainingBytes--;
    }

    if (InstancePtr->RecvRemainingBytes > 0) {
        /* Still waiting for more bytes; enable RX Ready interrupt */
        AXI_Uart_EnableInterrupts(InstancePtr, AXI_UART_IXR_RX_READY);
    } else {
        /* Completed from existing FIFO contents */
        if (InstancePtr->RecvHandler != NULL) {
            InstancePtr->RecvHandler(InstancePtr->CallBackRef, InstancePtr->RecvRequestedBytes);
        }
    }

    return XST_SUCCESS;
}

void AXI_Uart_IntrHandler(void *InstancePtrVoid) {
    AXI_Uart *InstancePtr = (AXI_Uart *)InstancePtrVoid;
    if (InstancePtr == NULL || InstancePtr->IsReady != 0x55AA55AAU) {
        return;
    }

    UINTPTR BaseAddress = InstancePtr->BaseAddress;
    u32 IntrEn     = AXI_UART_READ_REG(BaseAddress, AXI_UART_INTR_EN_OFFSET);
    u32 IntrStatus = AXI_UART_READ_REG(BaseAddress, AXI_UART_INTR_STATUS_OFFSET);
    u32 ActiveIntr = IntrStatus & IntrEn;

    /* 1. Handle Framing / Overrun Errors */
    if (ActiveIntr & (AXI_UART_IXR_FRAME_ERR | AXI_UART_IXR_OVERRUN)) {
        u32 ErrorMask = ActiveIntr & (AXI_UART_IXR_FRAME_ERR | AXI_UART_IXR_OVERRUN);

        /* Write-1-to-Clear W1C error status bits */
        AXI_UART_WRITE_REG(BaseAddress, AXI_UART_INTR_STATUS_OFFSET, ErrorMask);

        if (InstancePtr->ErrorHandler != NULL) {
            InstancePtr->ErrorHandler(InstancePtr->CallBackRef, ErrorMask);
        }
    }

    /* 2. Handle RX Ready / Watermark Met */
    if (ActiveIntr & AXI_UART_IXR_RX_READY) {
        while (InstancePtr->RecvRemainingBytes > 0 && AXI_Uart_HasData(BaseAddress)) {
            *InstancePtr->RecvBufferPtr = (u8)(AXI_UART_READ_REG(BaseAddress,
                                                                 AXI_UART_TX_RX_DATA_OFFSET) & 0xFFU);
            InstancePtr->RecvBufferPtr++;
            InstancePtr->RecvRemainingBytes--;
        }

        /* Check if receive buffer request has been completely fulfilled */
        if (InstancePtr->RecvRemainingBytes == 0) {
            AXI_Uart_DisableInterrupts(InstancePtr, AXI_UART_IXR_RX_READY);
            if (InstancePtr->RecvHandler != NULL) {
                InstancePtr->RecvHandler(InstancePtr->CallBackRef, InstancePtr->RecvRequestedBytes);
            }
        }
    }

    /* 3. Handle TX Empty */
    if (ActiveIntr & AXI_UART_IXR_TX_EMPTY) {
        while (InstancePtr->SendRemainingBytes > 0 && !AXI_Uart_IsTxFull(BaseAddress)) {
            AXI_UART_WRITE_REG(BaseAddress,
                               AXI_UART_TX_RX_DATA_OFFSET,
                               (u32)(*InstancePtr->SendBufferPtr));
            InstancePtr->SendBufferPtr++;
            InstancePtr->SendRemainingBytes--;
        }

        /* Check if transmit buffer request is completed */
        if (InstancePtr->SendRemainingBytes == 0) {
            AXI_Uart_DisableInterrupts(InstancePtr, AXI_UART_IXR_TX_EMPTY);
            if (InstancePtr->SendHandler != NULL) {
                InstancePtr->SendHandler(InstancePtr->CallBackRef, InstancePtr->SendRequestedBytes);
            }
        }
    }
}
