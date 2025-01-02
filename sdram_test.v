module test;

  /* Make a reset that pulses once. */
  initial begin
     $dumpfile("sdram_test.vcd");
     $dumpvars(0,test);
     # 300000 $finish;
  end

  /* Make a regular pulsing clock. */
  reg clk_83 = 0;
  always #1 clk_83 = !clk_83;
  reg [31:0] counter = 0;
  always @(posedge clk_83) begin
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
	  .clk(clk_83),
	  .data_in(requests_fifo_data),
	  .data_out(dram_fifo_to_dram_data),
	  .write_enable(requests_fifo_write),
	  .read_enable(dram_fifo_to_dram_read_flag),
	  .full(requests_fifo_full),
	  .empty(dram_fifo_to_dram_empty_flag)
  );
  fifo_sync fifo_from_dram
  (
	  .clk(clk_83),
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
  sdram sdram_inst
  (
	 .clk_83(clk_83),
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
	 .fifo_from_dram_full_flag(dram_fifo_from_dram_full_flag)
  );
  reg [15:0] test_dram_data = 16'hffff;
  assign dram_dq = test_dram_data;

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

  always @(posedge clk_83) begin
	if (state == 0) begin
		responses_fifo_read_reg <= 0;
		if (!requests_fifo_full) begin
			requests_fifo_data_reg <= {1'b1, // read or write
				2'b11, // bank -- 2 bits
				{11{2'b01}}, // address -- 13  + 9 = 22 bits
				{4{2'b00, counter[25], counter[30]}}}; // data to write -- 16 bits
			requests_fifo_write_reg <= 1;
			state <= state + 1;
		end else begin
			requests_fifo_write_reg <= 0;
		end
	end

	if (state == 1) begin
		requests_fifo_write_reg <= 0;
		if (responses_fifo_empty == 1'b0) begin
			responses_fifo_read_reg <= 1;
			state <= state + 1;
		end else begin
			responses_fifo_read_reg <= 0;
		end
	end

	if (state == 2) begin
		responses_fifo_read_reg <= 0;
		if (!requests_fifo_full) begin
			requests_fifo_data_reg <= {1'b0, // read or write
				2'b11, // bank -- 2 bits
				{11{2'b01}}, // address -- 13  + 9 = 22 bits
				{4{2'b00, counter[25], counter[30]}}}; // data to write -- 16 bits
			requests_fifo_write_reg <= 1;
			state <= state + 1;
		end else begin
			requests_fifo_write_reg <= 0;
		end
	end

	if (state == 3) begin
		requests_fifo_write_reg <= 0;
		if (responses_fifo_empty == 1'b0) begin
			data_reg <= responses_fifo_data[15:0];
			responses_fifo_read_reg <= 1;
			state <= state + 1;
		end else begin
			responses_fifo_read_reg <= 0;
		end
	end

  end

endmodule // test

