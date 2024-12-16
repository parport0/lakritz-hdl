module sdram (
	input clk_166,
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
	inout [15:0] dram_dq,
	output [7:0] out_number
);
	// The following info is based on the datasheet for Winbond W9825G6KH
	// It is a good datasheet, describes almost all you need to know
	// when working with SDRAMs, I recommend starting with the command list table

	// Pins:
	// CLK  -- clock input (clock driven by the FPGA)
	// CKE  -- clock enable, set to 1 to work with the DRAM and set to 0
	//	   for power down or suspend modes
	//	   I always set it to 1 here.
	// CS   -- chip select, it is inverted; usually set to 0, but set to 1
	//	   when inputs need to be ignored; same as giving a NOP command
	//	   I always set it to 0 here.
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

	// My SDRAM model is W9825G6KH-6. It supports 133 MHz and 166 MHz
	// "speed grades". I could only generate a clock of 166 MHz, not 133.
	// This means I can set the SDRAM mode to "CL3" (CAS Latency = 3)
	// and that one clock cycle would be around 6 nS (166 MHz = 6.024 nS)
	// CAS latency refers to the time in clock cycles between asking for
	// data to be read and the data appearing on the DQ lines

	// The characteristics table in the datasheet does specify, though,
	// that the cycle time can be as long as 1000 nS (that is just 1 MHz).
	// So I _could_ run it slower if I wanted to?

	// Initialization procedure:

	// An initial pause of 200 uS is needed
	// DQM and CKE must be held high during the initial pause period
	// 200 uS = 200_000 nS = 33_334 clock cycles

	// Then --- precharge all banks using the precharge command

	// Once precharged, Mode Register Set Command must be issued
	// CKE must be held high for at least one cycle before the Mode
	// Register Set Command can be issued
	// A new command may be issued once at least t_RSC (2 clock cycles) have passed
	// (this cycle + one more cycle?)

	// Eight Auto Refresh Cycles are required before OR after setting the Mode Register

	// Usage:

	// Bank Activate must be issued before every R or W operation
	// The delay between Bank Activate and the first R or W operation
	// must be at least t_RCD (15 nS, so at least 3 clock cycles)

	// For reading or writing, the row part of the address is passed in the
	// Bank Activate command; the column part of the address is passed in
	// the read or write command, and data appears "CAS Latency" clocks later

	// Once a bank has been activated it must be precharged before another
	// Bank Activate command can be issued to the same bank.
	// This is easy to do implement by following the sequence:
	// BankActivate -> Read/Write -> BankPrecharge (Precharge acts as "closing")
	// I ignore Auto-precharge for now

	// The minimum time between successive Bank Activate commands:
	// to the _same_ bank it is t_RC (60 nS = 10 clock cycles)
	// between different banks it is t_RRD (2 clock cycles)

	// The minimum time between precharging a bank and activating it again
	// is t_RP (15 nS = 3 clock cycles)

	// The minimum and maximum time a bank can be active for is specified by t_RAS
	// (min: 42 nS = 7 clock cycles; max: 100_000 nS = 16_667 clock cycles)

	// Reading or writing to a different row in the same bank requires
	// the bank to be precharged and activated again
	// It is possible to have more than one bank open at the same time

	// Holding CKE low makes the SDRAM enter a low-power mode
	// Looking at the command list, it seems OK to always hold CKE high
	// for a simple implementation
	// I also ignore burst reads and writes here

	// NOP is: CS = 0, RAS = 1, CAS = 1, WE = 1

	// Between reads and writes Auto-refresh is also needed.
	// The characteristics table states "Refresh Time (8K Refresh Cycles)"
	// is 64 mS. The document does not say that, but it apparently means
	// that 8192 refresh cycles are needed every 64 mS (10_666_667 clock cycles)
	// They specify 8192 because that's 2^13 = number of rows in every bank!
	// (remember, the row is specified with A0-A12?)
	// This does not really mean that an auto-refresh is needed every 1302
	// cycles, but that is one way to implement it.
	// What matters is that every cell can hold its charge for 64 mS,
	// and that there are 8192 rows that all need recharging.

	// You only need to run "an auto-refresh cycle" without specifying
	// which row to refresh; the SDRAM remembers which row needs to be
	// refreshed on a given cycle.

	// All banks must be closed before Auto-refresh.
	// Before giving a precharge command and an autorefresh command, you
	// must wait t_RP (15 nS = 3 clock cycles).
	// Before giving an autorefresh command and any other command, you
	// must wait t_RC ((60 nS = 10 clock cycles).
	// (that's from the 11.11 timing diagram at least)


endmodule
