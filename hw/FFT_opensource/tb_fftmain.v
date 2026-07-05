`timescale 1ns/1ps
`default_nettype none

module tb_fftmain;
	localparam integer NFFT   = 1024;
	localparam integer IWIDTH = 16;
	localparam integer OWIDTH = 22;
	localparam integer TOL    = 8;

	reg			i_clk;
	reg			i_reset;
	reg			i_ce;
	reg	[2*IWIDTH-1:0]	i_sample;
	wire	[2*OWIDTH-1:0]	o_result;
	wire			o_sync;

	reg	[2*IWIDTH-1:0]	input_mem	[0:NFFT-1];
	reg	[2*OWIDTH-1:0]	expected_mem	[0:NFFT-1];

	integer feed_idx;
	integer out_idx;
	integer errors;
	integer cycles;

	integer exp_r, exp_i;
	integer got_r, got_i;
	integer diff_r, diff_i;

	fftmain dut (
		.i_clk(i_clk),
		.i_reset(i_reset),
		.i_ce(i_ce),
		.i_sample(i_sample),
		.o_result(o_result),
		.o_sync(o_sync)
	);

	initial i_clk = 1'b0;
	always #5 i_clk = !i_clk;

	function integer s22;
		input [OWIDTH-1:0] value;
		begin
			if (value[OWIDTH-1])
				s22 = value - (1 << OWIDTH);
			else
				s22 = value;
		end
	endfunction

	function integer abs_int;
		input integer value;
		begin
			abs_int = (value < 0) ? -value : value;
		end
	endfunction

	task compare_one;
		begin
			exp_r = s22(expected_mem[out_idx][2*OWIDTH-1:OWIDTH]);
			exp_i = s22(expected_mem[out_idx][OWIDTH-1:0]);
			got_r = s22(o_result[2*OWIDTH-1:OWIDTH]);
			got_i = s22(o_result[OWIDTH-1:0]);
			diff_r = got_r - exp_r;
			diff_i = got_i - exp_i;

			$display("bin %0d: python=(%0d,%0d) verilog=(%0d,%0d) diff=(%0d,%0d) %s",
				out_idx, exp_r, exp_i, got_r, got_i, diff_r, diff_i,
				((abs_int(diff_r) <= TOL) && (abs_int(diff_i) <= TOL)) ? "PASS" : "FAIL");

			if ((abs_int(diff_r) > TOL) || (abs_int(diff_i) > TOL))
				errors = errors + 1;
		end
	endtask

	initial begin
		$readmemh("input.mem", input_mem);
		$readmemh("expected.mem", expected_mem);

		i_reset = 1'b1;
		i_ce = 1'b0;
		i_sample = 0;
		feed_idx = 0;
		out_idx = 0;
		errors = 0;
		cycles = 0;

		repeat (5) @(posedge i_clk);
		i_reset = 1'b0;

		while (out_idx < NFFT && cycles < 20000) begin
			@(negedge i_clk);
			i_ce = 1'b1;
			i_sample = input_mem[feed_idx];
			feed_idx = (feed_idx == NFFT-1) ? 0 : feed_idx + 1;

			@(posedge i_clk);
			#1;
			cycles = cycles + 1;

			if (o_sync)
				out_idx = 0;

			if (o_sync || out_idx != 0) begin
				compare_one();
				out_idx = out_idx + 1;
			end
		end

		@(negedge i_clk);
		i_ce = 1'b0;

		if (out_idx != NFFT) begin
			$display("TIMEOUT: captured %0d/%0d outputs", out_idx, NFFT);
			$finish;
		end

		if (errors == 0)
			$display("FFT TEST PASS: %0d bins compared, tolerance=%0d", NFFT, TOL);
		else
			$display("FFT TEST FAIL: %0d bins compared, errors=%0d, tolerance=%0d", NFFT, errors, TOL);

		$finish;
	end
endmodule

`default_nettype wire
