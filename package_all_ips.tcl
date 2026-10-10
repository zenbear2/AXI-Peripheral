# ============================================================================
# Script: package_all_ips.tcl
# Description: Automated Vivado IP Packager script for all AXI-Peripheral cores
# Supported Cores:
#   1. AXI_UART          (AXI4-Lite Slave)
#   2. AXI_I2C           (AXI4-Lite Slave)
#   3. AXI_SPI           (AXI4-Lite Slave)
#   4. AXI_TIMER_PWM_WDT (AXI4-Lite Slave)
#
# Usage:
#   vivado -mode batch -source package_all_ips.tcl -nolog -nojournal
# ============================================================================

set script_dir [file normalize [file dirname [info script]]]
puts "AXI-Peripheral Root: $script_dir"

set ip_definitions [list \
    [dict create \
        name        "AXI_UART" \
        dir         "AXI_UART" \
        top         "axi_uart_top" \
        display     "AXI4-Lite UART" \
        desc        "AXI4-Lite 16550-compatible UART IP core with FIFO and interrupt" \
        bus_type    "axi"] \
    [dict create \
        name        "AXI_I2C" \
        dir         "AXI_I2C" \
        top         "axi_i2c_top" \
        display     "AXI4-Lite I2C Master" \
        desc        "AXI4-Lite I2C Master IP core with clock stretching, deglitch filter, and FIFO" \
        bus_type    "axi"] \
    [dict create \
        name        "AXI_SPI" \
        dir         "AXI_SPI" \
        top         "axi_spi_top" \
        display     "AXI4-Lite SPI Master" \
        desc        "AXI4-Lite SPI Master IP core with multi-slave select and FIFO" \
        bus_type    "axi"] \
    [dict create \
        name        "AXI_TIMER_PWM_WDT" \
        dir         "AXI_TIMER_PWM_WDT" \
        top         "axi_timer_pwm_wdt_top" \
        display     "AXI4-Lite Timer / PWM / WDT" \
        desc        "AXI4-Lite 32-bit Timer, 4-Channel PWM with deadtime, and Watchdog Timer" \
        bus_type    "axi"] \
]

set tmp_base [file normalize "$script_dir/../MB_DDR4.tmp"]
file mkdir $tmp_base

set success_count 0
set total_count [llength $ip_definitions]

foreach ip_def $ip_definitions {
    set name     [dict get $ip_def name]
    set dir      [dict get $ip_def dir]
    set top      [dict get $ip_def top]
    set display  [dict get $ip_def display]
    set desc     [dict get $ip_def desc]
    set bus_type [dict get $ip_def bus_type]

    puts "\n=================================================================="
    puts ">>> Packaging IP: $name (Top: $top)"
    puts "=================================================================="

    set ip_path [file normalize "$script_dir/$dir"]
    set tmp_proj_dir "$tmp_base/proj_pkg_$name"
    file delete -force $tmp_proj_dir

    create_project -force $name $tmp_proj_dir -part xc7a100tcsg324-1

    # Add RTL source files
    set src_files [glob -nocomplain "$ip_path/rtl/*/*.sv"]
    if {[llength $src_files] == 0} {
        puts "ERROR: No source files found in $ip_path/rtl"
        continue
    }
    add_files -norecurse $src_files
    update_compile_order -fileset sources_1
    set_property top $top [current_fileset]
    update_compile_order -fileset sources_1

    # Package the IP project
    ipx::package_project -root_dir $ip_path -vendor user.org -library user -taxonomy /UserIP -set_current true
    set core [ipx::current_core]

    # Configure metadata
    set_property display_name $display $core
    set_property description $desc $core
    set_property vendor_display_name "User IPs" $core
    set_property company_url "https://github.com" $core

    # Ensure Clock & Reset interface parameters
    if {$bus_type == "axi"} {
        set aclk_if [ipx::get_bus_interfaces s_axi_aclk -of_objects $core]
        if {$aclk_if != ""} {
            set busif_p [ipx::get_bus_parameters ASSOCIATED_BUSIF -of_objects $aclk_if]
            if {$busif_p != ""} {
                set_property value "s_axi" $busif_p
            } else {
                set p [ipx::add_bus_parameter ASSOCIATED_BUSIF $aclk_if]
                set_property value "s_axi" $p
            }
            set rst_p [ipx::get_bus_parameters ASSOCIATED_RESET -of_objects $aclk_if]
            if {$rst_p != ""} {
                set_property value "s_axi_aresetn" $rst_p
            } else {
                set p [ipx::add_bus_parameter ASSOCIATED_RESET $aclk_if]
                set_property value "s_axi_aresetn" $p
            }
        }
        set aresetn_if [ipx::get_bus_interfaces s_axi_aresetn -of_objects $core]
        if {$aresetn_if != ""} {
            set pol_p [ipx::get_bus_parameters POLARITY -of_objects $aresetn_if]
            if {$pol_p != ""} {
                set_property value "ACTIVE_LOW" $pol_p
            } else {
                set p [ipx::add_bus_parameter POLARITY $aresetn_if]
                set_property value "ACTIVE_LOW" $p
            }
        }
    }

    # Check and infer interrupt interfaces for any irq_* or irq signals
    foreach port [ipx::get_ports -of_objects $core] {
        set pname [get_property name $port]
        set pdir  [get_property direction $port]
        if {$pdir == "out" && [string match "irq*" $pname]} {
            set existing_if [ipx::get_bus_interfaces $pname -of_objects $core]
            if {$existing_if == ""} {
                set intr_if [ipx::add_bus_interface $pname $core]
                set_property abstraction_type_vlnv xilinx.com:signal:interrupt_rtl:1.0 $intr_if
                set_property bus_type_vlnv xilinx.com:signal:interrupt:1.0 $intr_if
                set_property interface_mode master $intr_if
                set port_map [ipx::add_port_map INTERRUPT $intr_if]
                set_property physical_name $pname $port_map
                set param [ipx::add_bus_parameter SENSITIVITY $intr_if]
                set_property value LEVEL_HIGH $param
            }
        }
    }

    # Set default driver value = 0 for optional input pins so they can be left unconnected
    foreach opt_port {tim_capture_in pwm_fault_in} {
        set p [ipx::get_ports $opt_port -of_objects $core]
        if {$p != ""} {
            set_property driver_value "0" $p
        }
    }

    # Update checksums and save
    ipx::update_checksums $core
    ipx::save_core $core

    # Check integrity
    set integrity [ipx::check_integrity $core]
    if {$integrity == 1} {
        puts ">>> \[SUCCESS\] $name packaged and verified successfully!"
        incr success_count
    } else {
        puts ">>> \[FAILED\] $name integrity check failed!"
    }

    close_project -delete
}

puts "\n=================================================================="
puts "SUMMARY: $success_count / $total_count IPs packaged successfully!"
puts "=================================================================="

if {$success_count == $total_count} {
    exit 0
} else {
    exit 1
}
