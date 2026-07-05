`timescale 1ns/1ps

module tb_conv3_top;

    localparam DATA_WIDTH   = 16;
    localparam ACCUM_WIDTH  = 32;

    localparam IMG_H        = 10;
    localparam IMG_W        = 16;

    localparam IN_CHANNELS  = 32;
    localparam OUT_CHANNELS = 64;

    localparam IN_BUS_WIDTH  = IN_CHANNELS  * DATA_WIDTH; // 512
    localparam OUT_BUS_WIDTH = OUT_CHANNELS * DATA_WIDTH; // 1024

    localparam TOTAL_PIXELS = IMG_H * IMG_W;

    reg clk;
    reg rst_n;

    reg  in_valid;
    wire in_ready;
    reg  [IN_BUS_WIDTH-1:0] in_pixels_flat;

    reg  out_ready;
    wire [OUT_BUS_WIDTH-1:0] out_data;
    wire                     out_valid;

    reg [IN_BUS_WIDTH-1:0]  in_mem  [0:TOTAL_PIXELS-1];
    reg [OUT_BUS_WIDTH-1:0] ref_mem [0:TOTAL_PIXELS-1];

    integer i;
    integer sent_cnt;
    integer out_cnt;
    integer error_cnt;

    // =====================================================
    // DUT
    // =====================================================
    conv3_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH),
        .IMG_H(IMG_H),
        .IMG_W(IMG_W),
        .IN_CHANNELS(IN_CHANNELS),
        .OUT_CHANNELS(OUT_CHANNELS),
        .PIXEL_FRAC(8),
        .WEIGHT_FRAC(8),
        .OUT_FRAC(8),
        .WEIGHT_FILE("features.8_fused_weight.hex"),
        .BIAS_FILE("features.8_fused_bias.hex")
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_pixels_flat(in_pixels_flat),

        .out_ready(out_ready),
        .out_data(out_data),
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
    // LOAD TEST VECTORS
    // =====================================================
    initial begin
        $display("");
        $display("====================================================");
        $display(" LOADING TEST VECTORS FOR CONV3_TOP");
        $display("====================================================");

        $readmemh("conv3_top_input.hex", in_mem);
        $readmemh("conv3_top_output.hex", ref_mem);

        $display(" INPUT  VECTOR : conv3_top_input.hex");
        $display(" GOLDEN VECTOR : conv3_top_output.hex");
        $display(" TOTAL PIXELS  : %0d", TOTAL_PIXELS);
        $display("====================================================");
        $display("");
    end

    // =====================================================
    // RESET / INIT
    // =====================================================
    initial begin
        rst_n          = 1'b0;
        in_valid       = 1'b0;
        in_pixels_flat = {IN_BUS_WIDTH{1'b0}};
        out_ready      = 1'b1;

        sent_cnt  = 0;
        out_cnt   = 0;
        error_cnt = 0;

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
        $display(" START SENDING CONV3 INPUT STREAM");
        $display("====================================================");
        $display("");

        i = 0;

        while (i < TOTAL_PIXELS) begin
            @(negedge clk);

            in_valid       = 1'b1;
            in_pixels_flat = in_mem[i];

            @(posedge clk);

            if (in_ready) begin
                i = i + 1;
                sent_cnt = sent_cnt + 1;
            end
        end

        @(negedge clk);
        in_valid       = 1'b0;
        in_pixels_flat = {IN_BUS_WIDTH{1'b0}};

        $display("");
        $display("====================================================");
        $display(" INPUT STREAM FINISHED");
        $display(" SENT PIXELS : %0d / %0d", sent_cnt, TOTAL_PIXELS);
        $display(" WAITING FOR OUTPUTS");
        $display("====================================================");
        $display("");
    end

    // =====================================================
    // OUTPUT CHECKER
    // =====================================================
    always @(posedge clk) begin
        if (rst_n && out_valid && out_ready) begin

            if (out_cnt >= TOTAL_PIXELS) begin
                $display("----------------------------------------------------");
                $display(" EXTRA OUTPUT FROM VERILOG");
                $display(" OUTPUT INDEX : %0d", out_cnt);
                $display(" VERILOG      : %h", out_data);
                $display(" EXPECTED MAX : %0d outputs", TOTAL_PIXELS);
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
        $display(" INPUT SENT        : %0d / %0d", sent_cnt, TOTAL_PIXELS);
        $display(" OUTPUT COUNT      : %0d / %0d", out_cnt, TOTAL_PIXELS);
        $display(" TOTAL ERRORS      : %0d", error_cnt);

        if ((error_cnt == 0) && (out_cnt == TOTAL_PIXELS)) begin
            $display("");
            $display(" PASS: CONV3_TOP IS CORRECT");
        end
        else begin
            $display("");
            $display(" FAIL: CONV3_TOP HAS ERRORS OR MISSING OUTPUTS");
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
        #10000000;

        $display("");
        $display("====================================================");
        $display(" TIMEOUT ERROR");
        $display("====================================================");
        $display(" INPUT SENT        : %0d / %0d", sent_cnt, TOTAL_PIXELS);
        $display(" OUTPUT COUNT      : %0d / %0d", out_cnt, TOTAL_PIXELS);
        $display(" TOTAL ERRORS      : %0d", error_cnt);
        $display("====================================================");
        $display("");

        $finish;
    end

endmodule