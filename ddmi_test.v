module test;

  /* Make a reset that pulses once. */
  initial begin
     $dumpfile("ddmi_test.vcd");
     $dumpvars(0,test);
     # 100000 $finish;
  end

  /* Make a regular pulsing clock. */
  reg clk = 0;
  reg clk_10 = 0;
  always #2 clk = !clk;
  always #20 clk_10 = !clk_10;

  wire value0;
  wire value1;
  wire value2;
  wire valueclk;

  ddmi ddmi_inst
  (
          .clk_tmds(clk),
          .clk_pixel(clk_10),
          .ddmi_clk_p(valueclk),
          .ddmi_d0_p(value0),
          .ddmi_d1_p(value1),
          .ddmi_d2_p(value2)
  );
endmodule // test

