proc generate {drv_handle} {
    xdefine_include_file $drv_handle "xparameters.h" "AXI_UART" \
        "NUM_INSTANCES" \
        "DEVICE_ID" \
        "C_S_AXI_BASEADDR" \
        "C_S_AXI_HIGHADDR" \
        "CLOCK_FREQ_HZ"

    xdefine_config_file $drv_handle "axi_uart_g.c" "AXI_UART" \
        "DEVICE_ID" \
        "C_S_AXI_BASEADDR" \
        "CLOCK_FREQ_HZ"

    xdefine_canonical_xpars $drv_handle "xparameters.h" "AXI_UART" \
        "DEVICE_ID" \
        "C_S_AXI_BASEADDR" \
        "C_S_AXI_HIGHADDR" \
        "CLOCK_FREQ_HZ"
}
