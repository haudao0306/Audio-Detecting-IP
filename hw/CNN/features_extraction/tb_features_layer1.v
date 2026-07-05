`timescale 1ns/1ps

module tb_features_layer1;

    localparam DATA_WIDTH   = 16;
    localparam ACCUM_WIDTH  = 32;
    localparam IMG_H        = 40;
    localparam IMG_W        = 64;
    localparam OUT_CHANNELS = 16;

    localparam OUT_H       = IMG_H / 2;
    localparam OUT_W       = IMG_W / 2;
    localparam IN_PIXELS   = IMG_H * IMG_W;
    localparam NUM_OUTPUTS = OUT_H * OUT_W;

    reg clk;
    reg rst_n;

    reg  in_valid;
    wire in_ready;
    reg  signed [DATA_WIDTH-1:0] in_pixel;

    wire [(DATA_WIDTH*OUT_CHANNELS)-1:0] layer_out_pixels;
    wire                                 layer_out_valid;

    reg [DATA_WIDTH-1:0] in_mem  [0:IN_PIXELS-1];
    reg [(DATA_WIDTH*OUT_CHANNELS)-1:0] ref_mem [0:NUM_OUTPUTS-1];

    integer i;
    integer out_cnt;
    integer error_cnt;
    integer sent_cnt;

    integer conv_to_pool_cnt;
    integer pool_buffer_valid_cnt;
    integer layer_valid_cnt;

    // =====================================================
    // DUT
    // =====================================================
    features_layer1 #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH),
        .IMG_H(IMG_H),
        .IMG_W(IMG_W),
        .OUT_CHANNELS(OUT_CHANNELS)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_pixel(in_pixel),

        .out_pixels_flat(layer_out_pixels),
        .out_valid(layer_out_valid)
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
        $display(" LOADING TEST VECTORS");
        $display("====================================================");

        $readmemh("input_layer1.hex", in_mem);
        $readmemh("output_layer1_ref.hex", ref_mem);

        $display(" INPUT  VECTOR : input_layer1.hex");
        $display(" GOLDEN VECTOR : output_layer1_ref.hex");
        $display("====================================================");
        $display("");
    end

    // =====================================================
    // RESET
    // =====================================================
    initial begin
        rst_n    = 1'b0;
        in_valid = 1'b0;
        in_pixel = {DATA_WIDTH{1'b0}};

        out_cnt   = 0;
        error_cnt = 0;
        sent_cnt  = 0;

        conv_to_pool_cnt      = 0;
        pool_buffer_valid_cnt = 0;
        layer_valid_cnt       = 0;

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
        $display(" START SENDING INPUT STREAM");
        $display("====================================================");
        $display("");

        i = 0;

        while (i < IN_PIXELS) begin
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
        in_pixel = {DATA_WIDTH{1'b0}};

        $display("");
        $display("====================================================");
        $display(" INPUT STREAM FINISHED");
        $display(" SENT PIXELS : %0d / %0d", sent_cnt, IN_PIXELS);
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
                conv_to_pool_cnt = conv_to_pool_cnt + 1;

            if (dut.u_maxpool_top.channel_array[0].buffer_out_valid)
                pool_buffer_valid_cnt = pool_buffer_valid_cnt + 1;

            if (layer_out_valid)
                layer_valid_cnt = layer_valid_cnt + 1;
        end
    end

    // =====================================================
    // OUTPUT CHECKER
    // =====================================================
    always @(posedge clk) begin
        if (rst_n && layer_out_valid) begin

            if (out_cnt >= NUM_OUTPUTS) begin
                $display("----------------------------------------------------");
                $display(" EXTRA OUTPUT FROM VERILOG");
                $display(" OUTPUT INDEX : %0d", out_cnt);
                $display(" VERILOG      : %h", layer_out_pixels);
                $display(" EXPECTED MAX : %0d outputs", NUM_OUTPUTS);
                $display("----------------------------------------------------");
                error_cnt = error_cnt + 1;
                finish_report();
            end

            $display("----------------------------------------------------");
            $display(" OUTPUT INDEX : %0d", out_cnt);
            $display(" VERILOG      : %h", layer_out_pixels);
            $display(" PYTHON       : %h", ref_mem[out_cnt]);

            if (layer_out_pixels !== ref_mem[out_cnt]) begin
                $display(" RESULT       : MISMATCH");
                error_cnt = error_cnt + 1;
            end
            else begin
                $display(" RESULT       : MATCH");
            end

            $display("----------------------------------------------------");
            $display("");

            out_cnt = out_cnt + 1;

            if (out_cnt == NUM_OUTPUTS) begin
                repeat (5) @(posedge clk);
                finish_report();
            end
        end
    end

    // =====================================================
    // FINISH REPORT TASK
    // =====================================================
    task finish_report;
    begin
        $display("");
        $display("====================================================");
        $display(" SIMULATION FINISHED");
        $display("====================================================");
        $display(" INPUT SENT              : %0d / %0d", sent_cnt, IN_PIXELS);
        $display(" CONV -> POOL VALID COUNT: %0d / %0d", conv_to_pool_cnt, IN_PIXELS);
        $display(" POOL BUFFER VALID COUNT : %0d / %0d", pool_buffer_valid_cnt, NUM_OUTPUTS);
        $display(" LAYER OUTPUT COUNT      : %0d / %0d", out_cnt, NUM_OUTPUTS);
        $display(" LAYER VALID RAW COUNT   : %0d", layer_valid_cnt);
        $display(" TOTAL ERRORS            : %0d", error_cnt);

        if ((error_cnt == 0) && (out_cnt == NUM_OUTPUTS)) begin
            $display("");
            $display(" PASS: FEATURES_LAYER1 IS CORRECT");
        end
        else begin
            $display("");
            $display(" FAIL: FEATURES_LAYER1 HAS ERRORS OR MISSING OUTPUTS");
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
        $display(" INPUT SENT              : %0d / %0d", sent_cnt, IN_PIXELS);
        $display(" CONV -> POOL VALID COUNT: %0d / %0d", conv_to_pool_cnt, IN_PIXELS);
        $display(" POOL BUFFER VALID COUNT : %0d / %0d", pool_buffer_valid_cnt, NUM_OUTPUTS);
        $display(" LAYER OUTPUT COUNT      : %0d / %0d", out_cnt, NUM_OUTPUTS);
        $display(" LAYER VALID RAW COUNT   : %0d", layer_valid_cnt);
        $display(" TOTAL ERRORS            : %0d", error_cnt);
        $display("====================================================");
        $display("");

        $finish;
    end

endmodule

