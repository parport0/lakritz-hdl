module sdram (
	input clk_48,
	output dram_clk,
	output dram_cke,
	output reg dram_cs,
	output reg dram_we,
	output reg dram_cas,
	output reg dram_ras,
	output reg dram_ldqm,
	output reg dram_udqm,
	output reg [1:0] dram_bs,
	output reg [12:0] dram_a,
	inout [15:0] dram_dq,

	input [40:0] fifo_to_dram_data,
	output fifo_to_dram_read_flag,
	input fifo_to_dram_empty_flag,
	output [40:0] fifo_from_dram_data,
	output fifo_from_dram_write_flag,
	input fifo_from_dram_full_flag,

	// debug
	output [3:0] state_out
);
	// I use two FIFOs for communicating with the DRAM:
	// one for requests, and one for responses.
	//
	// fifo_to_dram_data:
	// 40 -- 1 to write, 0 to read
	// 39:38 -- address: bank
	// 37:25 -- address: row
	// 24:16 -- address: column
	// 15:0 -- data to write (only relevant when writing)
	wire in_write_request = fifo_to_dram_data[40];
	wire [1:0] in_bank = fifo_to_dram_data[39:38];
	wire [12:0] in_row = fifo_to_dram_data[37:25];
	wire [8:0] in_column = fifo_to_dram_data[24:16];
	wire [15:0] in_data = fifo_to_dram_data[15:0];
	reg in_write_request_reg = 0;
	reg [1:0] in_bank_reg;
	reg [12:0] in_row_reg;
	reg [8:0] in_column_reg;
	reg [15:0] in_data_reg;

	// Let the FIFOs know that an item appears or disappears
	//assign fifo_to_dram_read_flag = (state == 6 && pause_counter[2:0] == 5) ? 1 : 0;
	//assign fifo_from_dram_write_flag = (state == 6 && pause_counter[2:0] == 4) ? 1 : 0;
	reg fifo_to_dram_read_flag_reg = 0;
	reg fifo_from_dram_write_flag_reg = 0;
	assign fifo_to_dram_read_flag = fifo_to_dram_read_flag_reg;
	assign fifo_from_dram_write_flag = fifo_from_dram_write_flag_reg;

	// dram_dq is an inout pin. Inout pins are difficult to handle;
	// when we might want to read from it, we need to assign z to it.
	// A separate register and flag "reading or writing" are needed.
	// Inout pins shouldn't be reg, only wire
	reg dram_dq_assign = 0;
	reg [15:0] dram_dq_reg = 0;
	assign dram_dq = (dram_dq_assign) ? dram_dq_reg : {16{1'bz}};

	assign fifo_from_dram_data = {in_write_request_reg, 24'b0, dram_dq_reg};
	// The following info is based on the datasheet for Winbond W9825G6KH
	// It is a good datasheet, describes almost all you need to know
	// when working with SDRAMs, I recommend starting with the command list table.

	// What I did not know when I started is that all modern SDRAM chips
	// function the same; if something in the datasheet isn't clear it is
	// still possible to look up "how generic SDRAM works".

	// My SDRAM model is W9825G6KH-6. It supports 133 MHz and 166 MHz
	// "speed grades". I failed timing at 166 MHz, so I am running it
	// at the FPGA clock rate (48 MHz). It should be fine to run it slower.
	// The characteristics table in the datasheet does specify that
	// the cycle time can be as long as 1000 nS (that is just 1 MHz).

	// One clock cycle would be around ~21 nS (48 MHz = 20.83(3) nS).

	// I set the SDRAM mode to "CL2" (CAS Latency = 2).
	// CAS latency refers to the time in clock cycles between asking for
	// data to be read and the data appearing on the DQ lines.
	// The speed grades refer to the allowed CAS Latency on different
	// frequencies. 133 MHz allows for CL2, but 166 MHz allows only for CL3.

	// State machine states:
	// 0 -- Initial 200uS pause
	// 1 -- Initial precharge
	// 2 -- Mode Register Set command
	// 3 -- Initial eight Auto Refresh Cycles
	// 4 -- Idle
	// 5 -- Bank Activat1e
	// 6 -- Read/Write
	// 7 -- Auto Refresh
	reg [3:0] state = 0;
	assign state_out = state;

	// Pins:
	// CLK  -- clock input (clock driven by the FPGA)
	assign dram_clk = clk_48;

	// CKE  -- clock enable, set to 1 to work with the DRAM and set to 0
	//	   for power down or suspend modes
	//	   Looking at the command list, it seems OK to always
	//	   hold CKE high for a simple implementation
	//	   I always set it to 1 here.
	assign dram_cke = 1;

	// CS   -- chip select, it is inverted; usually set to 0, but set to 1
	//	   when inputs need to be ignored; same as giving a NOP command.
	// WE   -- write enable, is inverted; for read/write commands it is
	//	   1 to read, 0 to write. But also has meaning in other commands;
	//	   distinguishes "bank activate" vs "bank/all precharge" commands,
	//	   distinguishes "mode register set" vs "auto-refresh" commands.
	// CAS  -- column address strobe
	// RAS  -- row address strobe
	//	   These two are just documented as "command input".
	//	   Their names surely have some meaning as well, just like WE,
	//	   but I do not know it and do not want to know.
	// LDQM -- lower data (DQ) mask
	// UDQM -- upper data (DQ) mask
	//	   Usually 0; set to 1 to not write certain bits when
	//	   performing write operations, or to return Z for certain bits
	//	   when performing read operations
	//	   Wikipedia snippet: "There is one DQM line per 8 bits".
	//	   This chip's word is 16 bits long, that's probably why
	//	   there are two DQMs in this chip
	//	   I always set these to 0 here.
	// BS   -- bank select, for read/write, bank activation/precharge.
	//	   Also set to "v" and not "x" (valid instead of don't care)
	//	   in the command table for Mode Register Set, but the "Mode
	//	   Register Set Cycle" graphic shows BS0 and BS1 set to 0
	//	   with a remark "Reserved"
	// A    -- address, used for Mode Register Set to set the Mode Register
	//	   contents (not DQ, interestingly), and also for read and write
	//	   operations (in which case A0-A8 specify the _column_),
	//	   and for bank activation (then A0-A12 specify the _row_).
	//	   A10 is special.
	//	   A10 is used to specify if a read or write is performed with
	//	   auto-precharge (= 1) or not (= 0)
	//	   (and again, in the read/write operations only A0-A8
	//	   are used for the actual address)
	//	   A10 is also used to distinguish between single bank precharge
	//	   (= 0) or all banks precharge (= 1)
	//	   (A0-A9 and A11-A12 are not used in the precharge command)
	// DQ   -- data, input and output, the only pins that we ever read
	//	   from the chip. They are just that, data, 16 bits of it.
	//	   The "DQ buffer" inside the SDRAM is the one and only one that
	//	   takes in the LDQM and UDQM signals.

	// Pause counter -- many times we need to wait for some clock cycles
	// until we can transition into the next state.
	// Auto refresh counter -- to keep track of the cell refresh requirements.
	reg [15:0] pause_counter = 0;
	reg [10:0] auto_refresh_counter = 0;

	// Initialization procedure:

	// An initial pause of 200 uS is needed
	// DQM and CKE must be held high during the initial pause period
	// 200 uS = 200_000 nS = 9_601 clock cycle
	always @(negedge clk_48) begin
		if (state == 0) begin
			auto_refresh_counter <= auto_refresh_counter + 1;
			// "DQM and CKE must be held high during the initial pause period"
			dram_ldqm <= 1;
			dram_udqm <= 1;

			// The NOP command
			dram_cs <= 1;

			if (pause_counter == 9610) begin // 200uS
				state <= state + 1;
				pause_counter <= 0;
			end else begin
				pause_counter <= pause_counter + 1;
			end
		end

	// Then --- precharge all banks using the precharge command
	// It is not clear, but from the diagram 11.11 "Auto Refresh Cycle",
	// t_RP must pass after this (15 nS = 1 clock cycle)
		if (state == 1) begin
			auto_refresh_counter <= auto_refresh_counter + 1;
			if (pause_counter == 0) begin
				// All Banks Precharge command
				dram_a[10] <= 1;
				dram_ras <= 0;
				dram_cas <= 1;
				dram_we <= 0;
				dram_cs <= 0;

				// Allow r/w
				dram_ldqm <= 0;
				dram_udqm <= 0;
//			end else begin
//				// The NOP command
//				dram_cs <= 1;
//				dram_ras <= 1;
//				dram_cas <= 1;
//				dram_we <= 1;
//			end
//			if (pause_counter == 0) begin // t_RP
				state <= state + 1;
				pause_counter <= 0;
//			end else begin
//				pause_counter <= pause_counter + 1;
			end
		end

	// Once precharged, Mode Register Set Command must be issued
	// CKE must be held high for at least one cycle
	// before the Mode Register Set Command can be issued
	// A new command may be issued once at least t_RSC (2 clock cycles) have passed
	// (this cycle + one more cycle)
	// Diagram 10.4 "Mode Register Set Cycle"
		if (state == 2) begin
			auto_refresh_counter <= auto_refresh_counter + 1;
			if (pause_counter == 0) begin
				// Mode Register Set
				dram_ras <= 0;
				dram_cas <= 0;
				dram_we <= 0;
				dram_cs <= 0;
				dram_a[2:0] <= 3'b000; // burst length = 1
				dram_a[3] <= 0; // sequential, not interleaved
				dram_a[6:4] <= 3'b010; // CAS latency = 2
				dram_a[8:7] <= 2'b00; // reserved
				dram_a[9] <= 1; // single write mode
				dram_a[12:10] <= 3'b000; // reserved
				dram_bs <= 2'b00; // reserved
			end else begin
				// The NOP command
				dram_cs <= 1;
			end

			if (pause_counter == 1) begin // t_RSC
				state <= state + 1;
				pause_counter <= 0;
			end else begin
				pause_counter <= pause_counter + 1;
			end
		end

	// Eight Auto Refresh Cycles are required before OR after setting the Mode Register
	// Diagram 11.11 "Auto Refresh Cycle"
	// Eight commands that are t_RC (60 nS = 3 clock cycles) clocks apart
		if (state == 3) begin
			auto_refresh_counter <= auto_refresh_counter + 1;
			if (pause_counter[3:0] == 0) begin
				// Auto Refresh command
				dram_ras <= 0;
				dram_cas <= 0;
				dram_we <= 1;
				dram_cs <= 0;
			end else begin
				// The NOP command
				dram_cs <= 1;
			end
			if (pause_counter[7:0] == 8'b0110_0010) begin // 8 times 3
				state <= state + 1;
				pause_counter <= 0;
			end else if (pause_counter[3:0] == 2) begin
				pause_counter[3:0] <= 0;
				pause_counter[7:4] <= pause_counter[7:4] + 1;
			end else begin
				pause_counter[3:0] <= pause_counter[3:0] + 1;
			end
		end

	// Initialization done

	// Between reads and writes Auto-refresh is needed.
	// The characteristics table states "Refresh Time (8K Refresh Cycles)"
	// is 64 mS. The document does not say that, but it apparently means
	// that 8192 refresh cycles are needed every 64 mS (3_047_619 clock cycles)
	// They specify 8192 because that's 2^13 = number of rows in every bank!
	// (remember, the row is specified with A0-A12?)

	// This does not really mean that an auto-refresh is needed every 372
	// cycles, but that is one way to implement it.
	// What matters is that every cell can hold its charge for 64 mS,
	// and that there are 8192 rows that all need recharging.

	// All banks must be closed before Auto-refresh.
	// Before giving an autorefresh command after the precharge command, you
	// must wait t_RP (15 nS = 1 clock cycles).
	// Before giving a command after auto-refresh, you
	// must wait t_RC ((60 nS = 3 clock cycles).
	// (that's from the 11.11 timing diagram) TODO verify.

	// You only need to run "an auto-refresh cycle" without specifying
	// which row to refresh; the SDRAM remembers which row needs to be
	// refreshed on a given cycle.
		if (state == 7) begin
			if (pause_counter == 0) begin
				// The Auto-refresh command
				dram_ras <= 0;
				dram_cas <= 0;
				dram_we <= 1;
				auto_refresh_counter <= 0;
				dram_cs <= 0;
			end else begin
				auto_refresh_counter <= auto_refresh_counter + 1;
				// The NOP command
				dram_cs <= 1;
			end

			if (pause_counter == 1) begin // t_RC
				state <= 4;
				pause_counter <= 0;
			end else begin
				pause_counter <= pause_counter + 1;
			end
		end

	// Idle state
		if (state == 4) begin
			auto_refresh_counter <= auto_refresh_counter + 1;
			// The NOP command
			dram_cs <= 1;

			in_write_request_reg <= in_write_request;
			in_bank_reg <= in_bank;
			in_row_reg <= in_row;
			in_column_reg <= in_column;
			in_data_reg <= in_data;

			if (auto_refresh_counter > 372) begin
				state <= 7;
				pause_counter <= 0;
			end else if (!fifo_to_dram_empty_flag && !fifo_from_dram_full_flag) begin
				state <= state + 1;
				pause_counter <= 0;
			end

			// From state 6
			fifo_from_dram_write_flag_reg = 0;
			fifo_to_dram_read_flag_reg = 0;
		end

	// Usage:

	// Bank Activate must be issued before every R or W operation
	// The delay between Bank Activate and the first R or W operation
	// must be at least t_RCD (15 nS, so at least 1 clock cycle)

	// The minimum time between successive Bank Activate commands:
	// to the _same_ bank it is t_RC (60 nS = 3 clock cycles)
	// between different banks it is t_RRD (2 clock cycles)

	// The minimum time between precharging a bank and activating it again
	// is t_RP (15 nS = 1 clock cycle)

	// The minimum and maximum time a bank can be active for is specified by t_RAS
	// (min: 42 nS = 3 clock cycles; max: 100_000 nS)

	// Reading or writing to a different row in the same bank requires
	// the bank to be precharged and activated again
	// It is possible to have more than one bank open at the same time

	// For reading or writing, the row part of the address is passed in the
	// Bank Activate command; the column part of the address is passed in
	// the read or write command
		if (state == 5) begin
			auto_refresh_counter <= auto_refresh_counter + 1;
			if (pause_counter == 0) begin
				// Bank Activate
				dram_ras <= 0;
				dram_cas <= 1;
				dram_we <= 1;
				dram_bs[1:0] <= in_bank_reg;
				dram_a[12:0] <= in_row_reg;
				dram_cs <= 0;

//			end else begin
//				// The NOP command
//				dram_ras <= 1;
//				dram_cs <= 1;
//				dram_cas <= 1;
//				dram_we <= 1;
//			end
//
//			if (pause_counter == 1) begin // t_RCD
				state <= state + 1;
				pause_counter <= 0;
//			end else begin
//				pause_counter <= pause_counter + 1;
			end
		end

	// Once a bank has been activated it must be precharged before another
	// Bank Activate command can be issued to the same bank.
	// This is easy to do implement by following the sequence:
	// BankActivate -> Read/Write -> BankPrecharge (Precharge acts as "closing")
	// Alternatively Auto-Precharge can be used.

	// Auto-Precharge does Bank Precharge by itself
	// near the finish of the read/write operation.
	// For reading:
	// "the active bank will begin to precharge automatically before all
	// burst read cycles have been completed" -- CAS Latency clocks prior
	// For writing:
	// "The SDRAM automatically enters the precharge operation two clock
	// delays from the last burst write cycle."

	// I use Auto-Precharge
	// By diagrams 11.9 "Auto-precharge Read" and 11.10 "Auto-precharge Write"
	// having max(t_RC, t_RAS + t_RP)
	// between successive _bank activation_ operations should be fine.
	// In my case max(t_RC, t_RAS + t_RP) = max(60nS, 57nS) = 60nS
	// = 3 clock cycles
	// 1 clock cycle (t_RCD) have already been waited for
	// in the activation block above (confusing but 11.9/11.10 show it well)

	// For reading, data appears "CAS Latency" clocks after the Read command
	// (see 10.2 "Read Timing")
	// My CAS Latency is, again, 2

		if (state == 6) begin
			auto_refresh_counter <= auto_refresh_counter + 1;
			if (pause_counter == 0) begin
				// Read / Write commands
				dram_a[10] <= 1; // With auto-precharge
				dram_ras <= 1;
				dram_cas <= 0;
				dram_we <= ~in_write_request_reg;
				dram_bs[1:0] <= in_bank_reg;
				dram_a[8:0] <= in_column_reg;

				dram_dq_reg <= in_data_reg;
				dram_dq_assign <= in_write_request_reg;

				dram_cs <= 0;
			end else begin
				// The NOP command
				dram_cs <= 1;

				// Let dq float again
				dram_dq_assign <= 0;
			end

			if (pause_counter == 3) begin // t_RC - t_RCD
				state <= 4;
				pause_counter <= 0;

				// but also CAS latency
			//end else if (pause_counter == 2) begin // Read the data
				dram_dq_reg <= dram_dq;
				fifo_from_dram_write_flag_reg = 1;
				fifo_to_dram_read_flag_reg = 1;
			end else begin
				pause_counter <= pause_counter + 1;
			end
		end
	end
endmodule
