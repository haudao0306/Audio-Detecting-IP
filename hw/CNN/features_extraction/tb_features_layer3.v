`timescale 1ns / 1ps

module tb_features_layer3;

    parameter DATA_WIDTH   = 16;
    parameter ACCUM_WIDTH  = 32;

    parameter IMG_H        = 10;
    parameter IMG_W        = 16;

    parameter IN_CHANNELS  = 32;
    parameter OUT_CHANNELS = 64;

    parameter PIXEL_FRAC   = 8;
    parameter WEIGHT_FRAC  = 8;
    parameter OUT_FRAC     = 8;

    localparam TOTAL_INPUTS  = IMG_H * IMG_W;
    localparam TOTAL_OUTPUTS = (IMG_H / 2) * (IMG_W / 2);

    localparam IN_BUS_WIDTH  = IN_CHANNELS  * DATA_WIDTH;
    localparam OUT_BUS_WIDTH = OUT_CHANNELS * DATA_WIDTH;

    reg clk;
    reg rst_n;

    reg                       in_valid;
    wire                      in_ready;
    reg  [IN_BUS_WIDTH-1:0]   in_pixels_flat;

    wire [OUT_BUS_WIDTH-1:0]  out_pixels_flat;
    wire                      out_valid;

    reg [IN_BUS_WIDTH-1:0]    input_memory    [0:TOTAL_INPUTS-1];
    reg [OUT_BUS_WIDTH-1:0]   expected_memory [0:TOTAL_OUTPUTS-1];

    integer i;
    integer sent_count;
    integer out_count;
    integer error_count;

    integer conv3_out_count;
    integer pool3_buffer_count;
    integer layer3_valid_count;

    // =====================================================
    // DUT
    // =====================================================
    features_layer3 #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH),

        .IMG_H(IMG_H),
        .IMG_W(IMG_W),

        .IN_CHANNELS(IN_CHANNELS),
        .OUT_CHANNELS(OUT_CHANNELS),

        .PIXEL_FRAC(PIXEL_FRAC),
        .WEIGHT_FRAC(WEIGHT_FRAC),
        .OUT_FRAC(OUT_FRAC),

        .WEIGHT_FILE("features.8_fused_weight.hex"),
        .BIAS_FILE("features.8_fused_bias.hex")
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_pixels_flat(in_pixels_flat),

        .out_pixels_flat(out_pixels_flat),
        .out_valid(out_valid)
    );

    // =====================================================
    // CLOCK
    // =====================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =====================================================
    // INIT / LOAD FILES
    // =====================================================
    initial begin
        $display("");
        $display("====================================================");
        $display(" LOADING TEST VECTORS FOR FEATURES_LAYER3");
        $display("====================================================");

        $readmemh("input_layer3.hex", input_memory);
        $readmemh("output_layer3.hex", expected_memory);

        $display(" INPUT  VECTOR : input_layer3.hex");
        $display(" GOLDEN VECTOR : output_layer3.hex");
        $display(" TOTAL INPUTS  : %0d", TOTAL_INPUTS);
        $display(" TOTAL OUTPUTS : %0d", TOTAL_OUTPUTS);
        $display("====================================================");
        $display("");
    end

    // =====================================================
    // RESET
    // =====================================================
    initial begin
        rst_n          = 1'b0;
        in_valid      = 1'b0;
        in_pixels_flat = {IN_BUS_WIDTH{1'b0}};

        sent_count = 0;
        out_count = 0;
        error_count = 0;

        conv3_out_count = 0;
        pool3_buffer_count = 0;
        layer3_valid_count = 0;

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
    end

    // =====================================================
    // INPUT DRIVER WITH HANDSHAKE
    // =====================================================
    initial begin
        @(posedge rst_n);
        @(negedge clk);

        $display("");
        $display("====================================================");
        $display(" START SENDING INPUT STREAM TO FEATURES_LAYER3");
        $display("====================================================");
        $display("");

        i = 0;

        while (i < TOTAL_INPUTS) begin
            @(negedge clk);

            in_valid       = 1'b1;
            in_pixels_flat = input_memory[i];

            @(posedge clk);

            if (in_ready) begin
                i = i + 1;
                sent_count = sent_count + 1;
            end
        end

        @(negedge clk);
        in_valid       = 1'b0;
        in_pixels_flat = {IN_BUS_WIDTH{1'b0}};

        $display("");
        $display("====================================================");
        $display(" INPUT STREAM FINISHED");
        $display(" SENT INPUTS : %0d / %0d", sent_count, TOTAL_INPUTS);
        $display(" WAITING FOR OUTPUTS");
        $display("====================================================");
        $display("");
    end

    // =====================================================
    // DEBUG COUNTERS
    // =====================================================
    always @(posedge clk) begin
        if (rst_n) begin
            if (dut.conv_out_valid)
                conv3_out_count = conv3_out_count + 1;

            if (dut.u_maxpool3_top.channel_array[0].buffer_out_valid)
                pool3_buffer_count = pool3_buffer_count + 1;

            if (out_valid)
                layer3_valid_count = layer3_valid_count + 1;
        end
    end

    // =====================================================
    // OUTPUT CHECKER
    // =====================================================
    always @(posedge clk) begin
        if (rst_n && out_valid) begin

            if (out_count >= TOTAL_OUTPUTS) begin
                $display("----------------------------------------------------");
                $display(" EXTRA OUTPUT FROM VERILOG");
                $display(" OUTPUT INDEX : %0d", out_count);
                $display(" VERILOG      : %h", out_pixels_flat);
                $display(" EXPECTED MAX : %0d outputs", TOTAL_OUTPUTS);
                $display("----------------------------------------------------");
                error_count = error_count + 1;
                finish_report();
            end

            $display("----------------------------------------------------");
            $display(" OUTPUT INDEX : %0d", out_count);
            $display(" VERILOG      : %h", out_pixels_flat);
            $display(" PYTHON       : %h", expected_memory[out_count]);

            if (out_pixels_flat !== expected_memory[out_count]) begin
                $display(" RESULT       : MISMATCH");
                error_count = error_count + 1;
            end
            else begin
                $display(" RESULT       : MATCH");
            end

            $display("----------------------------------------------------");
            $display("");

            out_count = out_count + 1;

            if (out_count == TOTAL_OUTPUTS) begin
                repeat (5) @(posedge clk);
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
        $display(" INPUT SENT              : %0d / %0d", sent_count, TOTAL_INPUTS);
        $display(" CONV3 -> POOL3 COUNT    : %0d / %0d", conv3_out_count, TOTAL_INPUTS);
        $display(" POOL3 BUFFER VALID COUNT: %0d / %0d", pool3_buffer_count, TOTAL_OUTPUTS);
        $display(" LAYER3 OUTPUT COUNT     : %0d / %0d", out_count, TOTAL_OUTPUTS);
        $display(" LAYER3 VALID RAW COUNT  : %0d", layer3_valid_count);
        $display(" TOTAL ERRORS            : %0d", error_count);

        if ((error_count == 0) && (out_count == TOTAL_OUTPUTS)) begin
            $display("");
            $display(" PASS: FEATURES_LAYER3 IS CORRECT");
        end
        else begin
            $display("");
            $display(" FAIL: FEATURES_LAYER3 HAS ERRORS OR MISSING OUTPUTS");
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
        #5000000;

        $display("");
        $display("====================================================");
        $display(" TIMEOUT ERROR");
        $display("====================================================");
        $display(" INPUT SENT              : %0d / %0d", sent_count, TOTAL_INPUTS);
        $display(" CONV3 -> POOL3 COUNT    : %0d / %0d", conv3_out_count, TOTAL_INPUTS);
        $display(" POOL3 BUFFER VALID COUNT: %0d / %0d", pool3_buffer_count, TOTAL_OUTPUTS);
        $display(" LAYER3 OUTPUT COUNT     : %0d / %0d", out_count, TOTAL_OUTPUTS);
        $display(" LAYER3 VALID RAW COUNT  : %0d", layer3_valid_count);
        $display(" TOTAL ERRORS            : %0d", error_count);
        $display("====================================================");
        $display("");

        $finish;
    end

endmodule
