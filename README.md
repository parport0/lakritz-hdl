Two ways to flash:

To flash the SPI, `sudo dfu-util -a 0 -D output/blinky.bit && sudo dfu-util -a 0 -e`

To reconfigure the FPGA without flashing the SPI, `openocd -f flash.ocd`

To look at simulated waveforms, run `make simulation_ddmi` and then `gtkwave output/ddmi_test.vcd`
