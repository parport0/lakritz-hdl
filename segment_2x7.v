module segment_2x7 (
	input clk,
	input [7:0] number,
	output [6:0] pmod_a,
	output pmod_a10
	);
	//reg [6:0] content;
	//assign pmod_a = content;
	//always @(posedge clk)
	//begin
	//	content <= number[6:0];
	//end

	reg [6:0] digit_counter;
	reg [6:0] content;
	assign pmod_a10 = ~digit_counter[6];
	assign pmod_a = content;
	always @(posedge clk)
	begin
		digit_counter <= digit_counter + 1;
		case (number[digit_counter[6]*4 +: 4])
			4'b0000: content <= 7'b1000000; // 0
			4'b0001: content <= 7'b1111001; // 1
			4'b0010: content <= 7'b0100100; // 2
			4'b0011: content <= 7'b0110000; // 3
			4'b0100: content <= 7'b0011001; // 4
			4'b0101: content <= 7'b0010010; // 5
			4'b0110: content <= 7'b0000010; // 6
			4'b0111: content <= 7'b1111000; // 7
			4'b1000: content <= 7'b0000000; // 8
			4'b1001: content <= 7'b0011000; // 9
			4'b1010: content <= 7'b0001000; // A
			4'b1011: content <= 7'b0000011; // B
			4'b1100: content <= 7'b1000110; // C
			4'b1101: content <= 7'b0100001; // D
			4'b1110: content <= 7'b0000110; // E
			4'b1111: content <= 7'b0001110; // F
			default: content <= 7'b1111111; // ??
		endcase
	end
endmodule
