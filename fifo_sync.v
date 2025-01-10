// "FIFO" of depth 1 :)
// Same-clock only (no clock domain crossing)
module fifo_sync (
	input clk,
	input [40:0] data_in,
	output [40:0] data_out,
	input write_enable,
	input read_enable,
	output full,
	output empty
);
	reg [40:0] buffer;
	reg count = 0;

	assign full = (count == 1) ? 1 : 0;
	assign empty = (count == 0) ? 1 : 0;
	assign data_out = buffer;

	always @(posedge clk) begin
		if (write_enable && !read_enable) begin
			count <= count + 1;
		end
		if (read_enable && !write_enable) begin
			count <= count - 1;
		end

		if (write_enable) begin
			buffer <= data_in;
		end
	end
endmodule
