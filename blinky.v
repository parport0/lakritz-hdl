module top (
	input CLK_48,
	output LED,
	output [6:0] pmod_a,
	output pmod_a10,
	//output ddmi_clk_p,
	//output ddmi_d0_p,
	//output ddmi_d1_p,
	//output ddmi_d2_p,
	output dram_clk,
	output dram_cke,
	output dram_cs,
	output dram_we,
	output dram_cas,
	output dram_ras,
	output dram_ldqm,
	output dram_udqm,
	output [1:0] dram_bs,
	output [12:0] dram_a,
	inout [15:0] dram_dq
	);

	wire [7:0] segment_display_numbers;
	segment_2x7 segment (
		.clk(CLK_48),
		.number(segment_display_numbers),
		.pmod_a(pmod_a),
		.pmod_a10(pmod_a10)
	);

	wire CLK_250;
	wire CLK_25;
	wire CLK_83;
	wire PLL_LOCK;
	pll_48_250_25_83 pll_inst
	(
		.clkin(CLK_48),
		.clkout0(CLK_250),
		.clkout1(CLK_25),
		.clkout2(CLK_83),
		.locked(PLL_LOCK)
	);

	//ddmi ddmi_inst
	//(
	//	.clk_tmds(CLK_250),
	//	.clk_pixel(CLK_25),
	//	.ddmi_clk_p(ddmi_clk_p),
	//	.ddmi_d0_p(ddmi_d0_p),
	//	.ddmi_d1_p(ddmi_d1_p),
	//	.ddmi_d2_p(ddmi_d2_p)
	//);

	wire dram_fifo_to_dram_full_flag;
	wire dram_fifo_to_dram_empty_flag;
	wire dram_fifo_to_dram_read_flag;
	wire [40:0] dram_fifo_to_dram_data;
	wire dram_fifo_from_dram_full_flag;
	wire dram_fifo_from_dram_empty_flag;
	wire dram_fifo_from_dram_write_flag;
	wire [40:0] dram_fifo_from_dram_data;

	wire [40:0] requests_fifo_data;
	wire requests_fifo_write;
	wire requests_fifo_full;
	wire [40:0] responses_fifo_data;
	wire responses_fifo_read;
	wire responses_fifo_empty;

	fifo_sync fifo_to_dram
	(
		.clk(CLK_48),
		.data_in(requests_fifo_data),
		.data_out(dram_fifo_to_dram_data),
		.write_enable(requests_fifo_write),
		.read_enable(dram_fifo_to_dram_read_flag),
		.full(requests_fifo_full),
		.empty(dram_fifo_to_dram_empty_flag)
	);
	fifo_sync fifo_from_dram
	(
		.clk(CLK_48),
		.data_in(dram_fifo_from_dram_data),
		.data_out(responses_fifo_data),
		.write_enable(dram_fifo_from_dram_write_flag),
		.read_enable(responses_fifo_read),
		.full(dram_fifo_from_dram_full_flag),
		.empty(responses_fifo_empty)
	);

	wire [3:0] state_out;
	sdram sdram_inst
	(
		.clk_48(CLK_48),
		.dram_clk(dram_clk),
		.dram_cke(dram_cke),
		.dram_cs(dram_cs),
		.dram_we(dram_we),
		.dram_cas(dram_cas),
		.dram_ras(dram_ras),
		.dram_ldqm(dram_ldqm),
		.dram_udqm(dram_udqm),
		.dram_bs(dram_bs),
		.dram_a(dram_a),
		.dram_dq(dram_dq),
		.fifo_to_dram_data(dram_fifo_to_dram_data),
		.fifo_to_dram_read_flag(dram_fifo_to_dram_read_flag),
		.fifo_to_dram_empty_flag(dram_fifo_to_dram_empty_flag),
		.fifo_from_dram_data(dram_fifo_from_dram_data),
		.fifo_from_dram_write_flag(dram_fifo_from_dram_write_flag),
		.fifo_from_dram_full_flag(dram_fifo_from_dram_full_flag),
		.state_out(state_out)
	);

	reg [31:0] counter = 0;
	always @(posedge CLK_48) begin
		counter <= counter + 1;
	end
	assign LED = ~counter[25];

	reg [15:0] data_reg = 0;
	reg requests_fifo_write_reg = 0;
	reg responses_fifo_read_reg = 0;
	reg [40:0] requests_fifo_data_reg = 0;
	assign responses_fifo_read = responses_fifo_read_reg;
	assign requests_fifo_write = requests_fifo_write_reg;
	assign requests_fifo_data = requests_fifo_data_reg;
	// 0: writing to the dram
	// 1: reading the dram's OK response from the fifo
	// 2: reading from the dram
	// 3: reading the dram's data response from the fifo
	reg [1:0] state = 0;
	reg [23:0] address_to_rw = 0;
	reg [15:0] errors = 0;

	always @(posedge CLK_48) begin
		if (state == 0) begin
			errors <= 0;
			responses_fifo_read_reg <= 0;
			if (!requests_fifo_full) begin
				requests_fifo_data_reg <= {1'b1, // write
					address_to_rw, // bank -- 2 bits + address -- 13 + 9 bits
					address_to_rw[15:0]}; // data to write -- 16 bits
				requests_fifo_write_reg <= 1;
				state <= 1;
			end else begin
				requests_fifo_write_reg <= 0;
			end
		end

		if (state == 1) begin
			requests_fifo_write_reg <= 0;
			if (responses_fifo_empty == 1'b0) begin
				responses_fifo_read_reg <= 1;
				if (address_to_rw == 24'hffffff) begin
					address_to_rw <= 0;
					state <= 2;
				end else begin
					address_to_rw <= address_to_rw + 1;
					state <= 0;
				end
			end else begin
				responses_fifo_read_reg <= 0;
			end
		end

		if (state == 2) begin
			responses_fifo_read_reg <= 0;
			if (!requests_fifo_full) begin
				requests_fifo_data_reg <= {1'b0, // read
					address_to_rw, // bank -- 2 bits + address -- 13 + 9 bits
					{4{4'b0000}}}; // empty, we are reading
				requests_fifo_write_reg <= 1;
				state <= 3;
			end else begin
				requests_fifo_write_reg <= 0;
			end
		end

		if (state == 3) begin
			requests_fifo_write_reg <= 0;
			if (responses_fifo_empty == 1'b0) begin
				data_reg <= responses_fifo_data[15:0];
				responses_fifo_read_reg <= 1;
				if (address_to_rw == 24'hffffff) begin
					address_to_rw <= 0;
					state <= 0;
				end else begin
					address_to_rw <= address_to_rw + 1;
					state <= 2;
				end
				errors <= errors | (responses_fifo_data[15:0] ^ address_to_rw[15:0]);
			end else begin
				responses_fifo_read_reg <= 0;
			end
		end
	end

	assign segment_display_numbers = errors[15:8] | errors[7:0];

	//assign segment_display_numbers = data_reg[7:0];
	//assign segment_display_numbers = {state_out, state_out};
	//assign segment_display_numbers = {fifo_o_count_out, responses_fifo_empty,
	//	responses_fifo_read_reg, responses_fifo_read};
endmodule
