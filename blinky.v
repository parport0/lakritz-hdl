module top (
	input CLK_48,
	output LED,
//	output [6:0] pmod_a,
//	output pmod_a10,
	output ddmi_clk_p,
	output ddmi_d0_p,
	output ddmi_d1_p,
	output ddmi_d2_p,
	);

	reg [31:0] counter;
	assign LED = ~counter[25];
	always @(posedge CLK_48) begin
		counter <= counter + 1;
	end

//	wire [7:0] segment_display_numbers;
//	segment_2x7 segment (
//		.clk(CLK_48),
//		.number(segment_display_numbers),
//		.pmod_a(pmod_a),
//		.pmod_a10(pmod_a10)
//	);
//	//assign segment_display_numbers = counter[31:24];

	wire CLK_250;
	wire CLK_25;
	wire CLK_166;
	wire PLL_LOCK;
	pll_48_250_25_166 pll_inst
	(
		.clkin(CLK_48),
		.clkout0(CLK_250),
		.clkout1(CLK_25),
		.clkout2(CLK_166),
		.locked(PLL_LOCK)
	);

	ddmi ddmi_inst
	(
		.clk_tmds(CLK_250),
		.clk_pixel(CLK_25),
		.ddmi_clk_p(ddmi_clk_p),
		.ddmi_d0_p(ddmi_d0_p),
		.ddmi_d1_p(ddmi_d1_p),
		.ddmi_d2_p(ddmi_d2_p)
	);

//	sdram sdram_inst
//	(
//		.clk_166(CLK_166),
//		.dram_clk(dram_clk),
//		.dram_cas(dram_cas),
//		.dram_cke(dram_cke),
//		.dram_cs(dram_cs ),
//		.dram_ras(dram_ras),
//		.dram_we(dram_we ),
//		.dram_ldqm(dram_ldqm),
//		.dram_udqm(dram_udqm),
//		.dram_bs(dram_bs),
//		.dram_a(dram_a),
//		.dram_dq(dram_dq),
//		.out_number(segment_display_numbers)
//	);

endmodule
