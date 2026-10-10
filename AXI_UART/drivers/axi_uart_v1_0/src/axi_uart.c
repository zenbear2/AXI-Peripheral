/******************************************************************************
* Copyright (C) 2026 Zenbear. All Rights Reserved.
* SPDX-License-Identifier: Apache-2.0
******************************************************************************/
/**
 * @file axi_uart.c
 * @brief Core implementation for custom AXI4-Lite UART driver on MicroBlaze.
 ******************************************************************************/

/***************************** Include Files *********************************/
#include "axi_uart.h"

/************************** Function Implementations *************************/

int AXI_Uart_Initialize(AXI_Uart *InstancePtr, UINTPTR BaseAddress, u32 ClockFreqHz) {
    if (InstancePtr == NULL || BaseAddress == 0 || ClockFreqHz == 0) {
        return XST_INVALID_PARAM;
    }

    InstancePtr->BaseAddress         = BaseAddress;
    InstancePtr->ClockFreqHz         = ClockFreqHz;
    InstancePtr->BaudRate            = 115200U;
    InstancePtr->SendBufferPtr       = NULL;
    InstancePtr->SendRequestedBytes  = 0;
    InstancePtr->SendRemainingBytes  = 0;
    InstancePtr->RecvBufferPtr       = NULL;
    InstancePtr->RecvRequestedBytes  = 0;
    InstancePtr->RecvRemainingBytes  = 0;
    InstancePtr->SendHandler         = NULL;
    InstancePtr->RecvHandler         = NULL;
    InstancePtr->ErrorHandler        = NULL;
    InstancePtr->CallBackRef         = NULL;

    /* Disable all interrupts initially */
    AXI_UART_WRITE_REG(BaseAddress, AXI_UART_INTR_EN_OFFSET, 0x00U);

    /* Clear any pending W1C error interrupts (Framing Err bit 2, Overrun bit 3) */
    AXI_UART_WRITE_REG(BaseAddress, AXI_UART_INTR_STATUS_OFFSET,
                       AXI_UART_IXR_FRAME_ERR | AXI_UART_IXR_OVERRUN);

    /* Set default baud rate: 115200 */
    int Status = AXI_Uart_SetBaudRate(InstancePtr, InstancePtr->BaudRate);
    if (Status != XST_SUCCESS) {
        return Status;
    }

    /* Set default line format: 8 Data bits, No Parity, 1 Stop bit */
    Status = AXI_Uart_SetLineControl(InstancePtr,
                                     AXI_UART_DATABITS_8,
                                     AXI_UART_PARITY_NONE,
                                     AXI_UART_STOPBITS_1);
    if (Status != XST_SUCCESS) {
        return Status;
    }

    /* Set default FIFO watermarks: TX=1, RX=1 */
    AXI_Uart_SetWatermarks(InstancePtr, 1, 1);

    InstancePtr->IsReady = 0x55AA55AAU;
    return XST_SUCCESS;
}

int AXI_Uart_CfgInitialize(AXI_Uart *InstancePtr, const AXI_Uart_Config *ConfigPtr) {
    if (InstancePtr == NULL || ConfigPtr == NULL) {
        return XST_INVALID_PARAM;
    }

    int Status = AXI_Uart_Initialize(InstancePtr, ConfigPtr->BaseAddress, ConfigPtr->ClockFreqHz);
    if (Status != XST_SUCCESS) {
        return Status;
    }

    if (ConfigPtr->BaudRate != 0) {
        Status = AXI_Uart_SetBaudRate(InstancePtr, ConfigPtr->BaudRate);
        if (Status != XST_SUCCESS) {
            return Status;
        }
    }

    Status = AXI_Uart_SetLineControl(InstancePtr,
                                     ConfigPtr->DataBits,
                                     ConfigPtr->Parity,
                                     ConfigPtr->StopBits);
    if (Status != XST_SUCCESS) {
        return Status;
    }

    AXI_Uart_SetWatermarks(InstancePtr, ConfigPtr->TxWatermark, ConfigPtr->RxWatermark);
    return XST_SUCCESS;
}

int AXI_Uart_SetBaudRate(AXI_Uart *InstancePtr, u32 BaudRate) {
    if (InstancePtr == NULL || BaudRate == 0 || InstancePtr->ClockFreqHz == 0) {
        return XST_INVALID_PARAM;
    }

    /*
     * Prescaler calculation with half-tick rounding:
     * Div = (f_clk + (8 * BaudRate)) / (16 * BaudRate)
     */
    u32 Denominator = 16U * BaudRate;
    u32 Prescaler = (InstancePtr->ClockFreqHz + (8U * BaudRate)) / Denominator;

    if (Prescaler == 0) {
        Prescaler = 1;
    } else if (Prescaler > 0xFFFFU) {
        /* Exceeds 16-bit hardware register width */
        return XST_INVALID_PARAM;
    }

    AXI_UART_WRITE_REG(InstancePtr->BaseAddress, AXI_UART_BAUD_DIV_OFFSET, Prescaler);
    InstancePtr->BaudRate = BaudRate;

    return XST_SUCCESS;
}

int AXI_Uart_SetLineControl(AXI_Uart *InstancePtr, u8 DataBits, u8 Parity, u8 StopBits) {
    if (InstancePtr == NULL) {
        return XST_INVALID_PARAM;
    }

    u32 CtrlReg = AXI_UART_READ_REG(InstancePtr->BaseAddress, AXI_UART_CTRL_OFFSET);

    /* Preserve TX_EN, RX_EN, and LOOPBACK bits */
    CtrlReg &= (AXI_UART_CR_TX_EN_MASK | AXI_UART_CR_RX_EN_MASK | AXI_UART_CR_LOOPBACK_MASK);

    /* 1. Configure Data Bits (5, 6, 7, 8) */
    switch (DataBits) {
        case 5:
            CtrlReg |= AXI_UART_CR_DATA_BITS_5;
            break;
        case 6:
            CtrlReg |= AXI_UART_CR_DATA_BITS_6;
            break;
        case 7:
            CtrlReg |= AXI_UART_CR_DATA_BITS_7;
            break;
        case 8:
            CtrlReg |= AXI_UART_CR_DATA_BITS_8;
            break;
        default:
            return XST_INVALID_PARAM;
    }

    /* 2. Configure Parity */
    switch (Parity) {
        case AXI_UART_PARITY_NONE:
            /* Parity bit disabled */
            break;
        case AXI_UART_PARITY_EVEN:
            CtrlReg |= AXI_UART_CR_PARITY_EN_MASK; /* Odd bit is 0 for Even */
            break;
        case AXI_UART_PARITY_ODD:
            CtrlReg |= (AXI_UART_CR_PARITY_EN_MASK | AXI_UART_CR_PARITY_ODD_MASK);
            break;
        default:
            return XST_INVALID_PARAM;
    }

    /* 3. Configure Stop Bits (1 or 2) */
    switch (StopBits) {
        case 1:
            CtrlReg |= AXI_UART_CR_STOP_BITS_1;
            break;
        case 2:
            CtrlReg |= AXI_UART_CR_STOP_BITS_2;
            break;
        default:
            return XST_INVALID_PARAM;
    }

    /* Ensure TX and RX engines are enabled by default */
    CtrlReg |= (AXI_UART_CR_TX_EN_MASK | AXI_UART_CR_RX_EN_MASK);

    AXI_UART_WRITE_REG(InstancePtr->BaseAddress, AXI_UART_CTRL_OFFSET, CtrlReg);
    return XST_SUCCESS;
}

void AXI_Uart_SetLoopback(AXI_Uart *InstancePtr, int Enable) {
    if (InstancePtr == NULL) return;

    u32 CtrlReg = AXI_UART_READ_REG(InstancePtr->BaseAddress, AXI_UART_CTRL_OFFSET);
    if (Enable) {
        CtrlReg |= AXI_UART_CR_LOOPBACK_MASK;
    } else {
        CtrlReg &= ~AXI_UART_CR_LOOPBACK_MASK;
    }
    AXI_UART_WRITE_REG(InstancePtr->BaseAddress, AXI_UART_CTRL_OFFSET, CtrlReg);
}

void AXI_Uart_SetWatermarks(AXI_Uart *InstancePtr, u8 TxWatermark, u8 RxWatermark) {
    if (InstancePtr == NULL) return;

    u32 WmReg = AXI_UART_SET_WM(TxWatermark, RxWatermark);
    AXI_UART_WRITE_REG(InstancePtr->BaseAddress, AXI_UART_FIFO_STAT_OFFSET, WmReg);
}

void AXI_Uart_GetFifoCounts(AXI_Uart *InstancePtr, u8 *TxCountPtr, u8 *RxCountPtr) {
    if (InstancePtr == NULL) return;

    u32 FifoStat = AXI_UART_READ_REG(InstancePtr->BaseAddress, AXI_UART_FIFO_STAT_OFFSET);
    if (TxCountPtr != NULL) {
        *TxCountPtr = AXI_UART_GET_TX_COUNT(FifoStat);
    }
    if (RxCountPtr != NULL) {
        *RxCountPtr = AXI_UART_GET_RX_COUNT(FifoStat);
    }
}

u32 AXI_Uart_SendBlocking(AXI_Uart *InstancePtr, const u8 *BufferPtr, u32 NumBytes) {
    if (InstancePtr == NULL || BufferPtr == NULL || NumBytes == 0) {
        return 0;
    }

    for (u32 i = 0; i < NumBytes; i++) {
        AXI_Uart_SendByte(InstancePtr->BaseAddress, BufferPtr[i]);
    }
    return NumBytes;
}

u32 AXI_Uart_RecvBlocking(AXI_Uart *InstancePtr, u8 *BufferPtr, u32 NumBytes) {
    if (InstancePtr == NULL || BufferPtr == NULL || NumBytes == 0) {
        return 0;
    }

    for (u32 i = 0; i < NumBytes; i++) {
        BufferPtr[i] = AXI_Uart_RecvByte(InstancePtr->BaseAddress);
    }
    return NumBytes;
}

u32 AXI_Uart_Send(AXI_Uart *InstancePtr, const u8 *BufferPtr, u32 NumBytes) {
    if (InstancePtr == NULL || BufferPtr == NULL || NumBytes == 0) {
        return 0;
    }

    u32 BytesSent = 0;
    while (BytesSent < NumBytes) {
        if (AXI_Uart_IsTxFull(InstancePtr->BaseAddress)) {
            break; /* FIFO full, stop non-blocking push */
        }
        AXI_UART_WRITE_REG(InstancePtr->BaseAddress,
                           AXI_UART_TX_RX_DATA_OFFSET,
                           (u32)BufferPtr[BytesSent]);
        BytesSent++;
    }
    return BytesSent;
}

u32 AXI_Uart_Recv(AXI_Uart *InstancePtr, u8 *BufferPtr, u32 NumBytes) {
    if (InstancePtr == NULL || BufferPtr == NULL || NumBytes == 0) {
        return 0;
    }

    u32 BytesRecv = 0;
    while (BytesRecv < NumBytes) {
        if (!AXI_Uart_HasData(InstancePtr->BaseAddress)) {
            break; /* No more data in RX FIFO */
        }
        BufferPtr[BytesRecv] = (u8)(AXI_UART_READ_REG(InstancePtr->BaseAddress,
                                                      AXI_UART_TX_RX_DATA_OFFSET) & 0xFFU);
        BytesRecv++;
    }
    return BytesRecv;
}
