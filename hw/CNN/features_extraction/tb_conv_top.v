`timescale 1ns/1ps

module tb_conv_top;

    // =====================================================
    // PARAMETERS
    // =====================================================
    localparam DATA_WIDTH    = 16;
    localparam ACCUM_WIDTH   = 32;
    localparam IMG_H         = 40;
    localparam IMG_W         = 64;
    localparam OUT_CHANNELS  = 16;
    localparam OUT_BUS_WIDTH = OUT_CHANNELS * DATA_WIDTH;
    localparam TOTAL_PIXELS  = IMG_H * IMG_W;

    // =====================================================
    // SIGNALS
    // =====================================================
    reg clk;
    reg rst_n;

    reg  in_valid;
    wire in_ready;
    reg  signed [DATA_WIDTH-1:0] in_pixel;

    reg  out_ready;
    wire [OUT_BUS_WIDTH-1:0] out_data;
    wire                     out_valid;

    wire [DATA_WIDTH*9-1:0] dbg_weight_word_q;
    wire [ACCUM_WIDTH-1:0]  dbg_dp_partial_sum;
    wire [ACCUM_WIDTH-1:0]  dbg_bias_q;
    wire [39:0]             dbg_final_preact;
    wire [DATA_WIDTH-1:0]   dbg_final_pixel_calc;

    // =====================================================
    // TEST MEMORY
    // =====================================================
    reg [DATA_WIDTH-1:0] in_mem [0:TOTAL_PIXELS-1];
    reg [OUT_BUS_WIDTH-1:0] ref_mem [0:TOTAL_PIXELS-1];

    integer i;
    integer sent_cnt;
    integer out_cnt;
    integer error_cnt;
    integer debug_count;

    // =====================================================
    // DUT
    // =====================================================
    conv_top dut (
        .clk(clk),
        .rst_n(rst_n),

        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_pixel(in_pixel),

        .out_ready(out_ready),
        .out_data(out_data),
        .out_valid(out_valid),

        .dbg_weight_word_q(dbg_weight_word_q),
        .dbg_dp_partial_sum(dbg_dp_partial_sum),
        .dbg_bias_q(dbg_bias_q),
        .dbg_final_preact(dbg_final_preact),
        .dbg_final_pixel_calc(dbg_final_pixel_calc)
    );

    // =====================================================
    // CLOCK
    // =====================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =====================================================
    // LOAD TEST VECTORS
    // =====================================================
    initial begin
        $display("");
        $display("====================================================");
        $display(" LOADING TEST VECTORS FOR CONV_TOP");
        $display("====================================================");

        $readmemh("input.mem", in_mem);
        $readmemh("golden_output.mem", ref_mem);

        $display(" INPUT  VECTOR : input.mem");
        $display(" GOLDEN VECTOR : golden_output.mem");
        $display(" TOTAL PIXELS  : %0d", TOTAL_PIXELS);
        $display("====================================================");
        $display("");
    end

    // =====================================================
    // RESET / INIT
    // =====================================================
    initial begin
        rst_n       = 1'b0;
        in_valid    = 1'b0;
        in_pixel    = 16'd0;
        out_ready   = 1'b1;
        sent_cnt    = 0;
        out_cnt     = 0;
        error_cnt   = 0;
        debug_count = 0;

        repeat(10) @(posedge clk);
        rst_n = 1'b1;
    end

    // =====================================================
    // INPUT DRIVER
    // =====================================================
    initial begin
        @(posedge rst_n);
        @(negedge clk);

        $display("");
        $display("====================================================");
        $display(" START SENDING INPUT STREAM");
        $display("====================================================");
        $display("");

        i = 0;

        while (i < TOTAL_PIXELS) begin
            @(negedge clk);

            in_valid = 1'b1;
            in_pixel = in_mem[i];

            @(posedge clk);

            if (in_ready) begin
                i = i + 1;
                sent_cnt = sent_cnt + 1;
            end
        end

        @(negedge clk);

        in_valid = 1'b0;
        in_pixel = 16'd0;

        $display("");
        $display("====================================================");
        $display(" INPUT STREAM FINISHED");
        $display(" SENT PIXELS : %0d / %0d", sent_cnt, TOTAL_PIXELS);
        $display(" WAITING FOR OUTPUTS");
        $display("====================================================");
        $display("");
    end

    // =====================================================
    // SIMPLE DEBUG PRINT TO TCL CONSOLE ONLY
    // =====================================================
    always @(posedge clk) begin
        if (rst_n && out_valid && out_ready && debug_count < 5) begin
            $display("");
            $display("========== SIMPLE CONV_TOP DEBUG ==========");
            $display("TIME=%0t OUTPUT_INDEX=%0d", $time, out_cnt);
            $display("out_data             = %h", out_data);
            $display("golden               = %h", ref_mem[out_cnt]);
            $display("dbg_weight_word_q    = %h", dbg_weight_word_q);
            $display("dbg_dp_partial_sum   = %h", dbg_dp_partial_sum);
            $display("dbg_bias_q           = %h", dbg_bias_q);
            $display("dbg_final_preact     = %h", dbg_final_preact);
            $display("dbg_final_pixel_calc = %h", dbg_final_pixel_calc);
            $display("===========================================");
            $display("");

            debug_count = debug_count + 1;
        end
    end

    // =====================================================
    // OUTPUT CHECKER
    // =====================================================
    always @(posedge clk) begin
        if (rst_n && out_valid && out_ready) begin
            if (out_cnt >= TOTAL_PIXELS) begin
                $display("----------------------------------------------------");
                $display(" EXTRA OUTPUT DETECTED");
                $display(" OUTPUT INDEX : %0d", out_cnt);
                $display(" VERILOG      : %h", out_data);
                $display("----------------------------------------------------");

                error_cnt = error_cnt + 1;
                finish_report();
            end

            $display("----------------------------------------------------");
            $display(" OUTPUT INDEX : %0d", out_cnt);
            $display(" VERILOG      : %h", out_data);
            $display(" PYTHON       : %h", ref_mem[out_cnt]);

            if (out_data !== ref_mem[out_cnt]) begin
                $display(" RESULT       : MISMATCH");
                error_cnt = error_cnt + 1;
            end
            else begin
                $display(" RESULT       : MATCH");
            end

            $display("----------------------------------------------------");
            $display("");

            out_cnt = out_cnt + 1;

            if (out_cnt == TOTAL_PIXELS) begin
                repeat(5) @(posedge clk);
                finish_report();
            end
        end
    end

    // =====================================================
    // FINISH REPORT
    // =====================================================
    task finish_report;
    begin
        $display("");
        $display("====================================================");
        $display(" SIMULATION FINISHED");
        $display("====================================================");

        $display(" INPUT SENT   : %0d / %0d", sent_cnt, TOTAL_PIXELS);
        $display(" OUTPUT COUNT : %0d / %0d", out_cnt, TOTAL_PIXELS);
        $display(" TOTAL ERRORS : %0d", error_cnt);

        if ((error_cnt == 0) && (out_cnt == TOTAL_PIXELS)) begin
            $display("");
            $display(" PASS: CONV_TOP IS CORRECT");
        end
        else begin
            $display("");
            $display(" FAIL: CONV_TOP HAS ERRORS OR MISSING OUTPUTS");
        end

        $display("====================================================");
        $display("");

        $finish;
    end
    endtask

    // =====================================================
    // TIMEOUT
    // =====================================================
    initial begin
        #3000000;

        $display("");
        $display("====================================================");
        $display(" TIMEOUT ERROR");
        $display("====================================================");

        $display(" INPUT SENT   : %0d / %0d", sent_cnt, TOTAL_PIXELS);
        $display(" OUTPUT COUNT : %0d / %0d", out_cnt, TOTAL_PIXELS);
        $display(" TOTAL ERRORS : %0d", error_cnt);

        $display("====================================================");
        $display("");

        $finish;
    end

endmodule

