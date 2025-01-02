VERILOGS ?= blinky.v sdram.v pll_250.v segment_2x7.v fifo_sync.v # ddmi.v

blinky_lakritz: $(VERILOGS)
	mkdir -p output
	yosys -q -p "synth_ecp5 -top top -json output/blinky.json" $^
	nextpnr-ecp5 --25k --package CABGA256 --lpf lakritz_v0.lpf --json output/blinky.json --textcfg output/blinky_out.config
	ecppack -v --compress --freq 2.4 output/blinky_out.config --bit output/blinky.bit --svf output/blinky.svf

simulation_ddmi: ddmi.v ddmi_test.v
	iverilog -Wall -o output/ddmi_test $^
	cd output && vvp ddmi_test

simulation_sdram: sdram.v sdram_test.v fifo_sync.v
	iverilog -Wall -o output/sdram_test $^
	cd output && vvp sdram_test

all: blinky_lakritz
