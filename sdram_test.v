module test;

  /* Make a reset that pulses once. */
  initial begin
     $dumpfile("sdram_test.vcd");
     $dumpvars(0,test);
     # 300000 $finish;
  end

  /* Make a regular pulsing clock. */
  reg clk_osc = 0;
  always #1 clk_osc = !clk_osc;
  reg [31:0] counter = 0;
  always @(posedge clk_osc) begin
        counter <= counter + 1;
  end

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
	  .clk(clk_osc),
	  .data_in(requests_fifo_data),
	  .data_out(dram_fifo_to_dram_data),
	  .write_enable(requests_fifo_write),
	  .read_enable(dram_fifo_to_dram_read_flag),
	  .full(requests_fifo_full),
	  .empty(dram_fifo_to_dram_empty_flag)
  );
  fifo_sync fifo_from_dram
  (
	  .clk(clk_osc),
	  .data_in(dram_fifo_from_dram_data),
	  .data_out(responses_fifo_data),
	  .write_enable(dram_fifo_from_dram_write_flag),
	  .read_enable(responses_fifo_read),
	  .full(dram_fifo_from_dram_full_flag),
	  .empty(responses_fifo_empty)
  );

  wire dram_clk;
  wire dram_cke;
  wire dram_cs;
  wire dram_we;
  wire dram_cas;
  wire dram_ras;
  wire dram_ldqm;
  wire dram_udqm;
  wire [1:0] dram_bs;
  wire [12:0] dram_a;
  wire [15:0] dram_dq;
  wire [3:0] state_out;
  sdram sdram_inst
  (
	 .clk_48(clk_osc),
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
  reg [15:0] test_dram_data = 16'hffff;
  reg [4:0] pause_counter = 0;
  always @(negedge clk_osc) begin
        if (state_out == 6) begin
          pause_counter = pause_counter + 1;
      end else begin
          pause_counter = 0;
      end
  end
  assign dram_dq = (state_out == 6 && pause_counter == 3) ? test_dram_data : {16{1'bz}};

  reg [15:0] data_reg;
  reg requests_fifo_write_reg = 0;
  reg responses_fifo_read_reg = 0;
  reg [40:0] requests_fifo_data_reg = 0;
  assign responses_fifo_read = responses_fifo_read_reg;
  assign requests_fifo_write = requests_fifo_write_reg;
  assign requests_fifo_data = requests_fifo_data_reg;

  // 0: writing to the dram
  // 1: reading the dram's response from the fifo
  // 2: reading from the dram
  // 3: reading the dram's data response from the fifo
  reg [1:0] state = 0;
  reg [23:0] address_to_rw = 0;

  always @(posedge clk_osc) begin
	if (state == 0) begin
		responses_fifo_read_reg <= 0;
		if (!requests_fifo_full) begin
			requests_fifo_data_reg <= {1'b1, // read or write
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
			if (address_to_rw == 24'h3) begin
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
			requests_fifo_data_reg <= {1'b0, // read or write
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
			if (address_to_rw == 24'h3) begin
				address_to_rw <= 0;
				state <= 0;
			end else begin
				address_to_rw <= address_to_rw + 1;
				state <= 2;
			end
		end else begin
			responses_fifo_read_reg <= 0;
		end
	end

  end

endmodule // test

