module features_layer3 #(
    parameter DATA_WIDTH   = 16,
    parameter ACCUM_WIDTH  = 32,

    parameter IMG_H        = 10,
    parameter IMG_W        = 16,

    parameter IN_CHANNELS  = 32,
    parameter OUT_CHANNELS = 64,

    parameter PIXEL_FRAC   = 8,
    parameter WEIGHT_FRAC  = 8,
    parameter OUT_FRAC     = 8,

    parameter IN_BUS_WIDTH  = IN_CHANNELS  * DATA_WIDTH,
    parameter OUT_BUS_WIDTH = OUT_CHANNELS * DATA_WIDTH,

    parameter WEIGHT_FILE  = "features.8_fused_weight.hex",
    parameter BIAS_FILE    = "features.8_fused_bias.hex"
)(
    input  wire clk,
    input  wire rst_n,

    // Input tu Layer 2: 32 channels x 16-bit
    input  wire                     in_valid,
    output wire                     in_ready,
    input  wire [IN_BUS_WIDTH-1:0]  in_pixels_flat,

    // Output sau Conv3 + MaxPool3: 64 channels x 16-bit
    output wire [OUT_BUS_WIDTH-1:0] out_pixels_flat,
    output wire                     out_valid
);

    // =====================================================
    // Internal connection: Conv3 -> MaxPool3
    // =====================================================
    wire [OUT_BUS_WIDTH-1:0] conv_out_data;
    wire                     conv_out_valid;

    // MaxPool3 hien tai khong co backpressure, nen luon ready
    wire conv_out_ready;
    assign conv_out_ready = 1'b1;

    // =====================================================
    // CONV3 TOP
    // =====================================================
    conv3_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH),

        .IMG_H(IMG_H),
        .IMG_W(IMG_W),

        .IN_CHANNELS(IN_CHANNELS),
        .OUT_CHANNELS(OUT_CHANNELS),

        .PIXEL_FRAC(PIXEL_FRAC),
        .WEIGHT_FRAC(WEIGHT_FRAC),
        .OUT_FRAC(OUT_FRAC),

        .IN_BUS_WIDTH(IN_BUS_WIDTH),
        .OUT_BUS_WIDTH(OUT_BUS_WIDTH),

        .WEIGHT_FILE(WEIGHT_FILE),
        .BIAS_FILE(BIAS_FILE)
    ) u_conv3_top (
        .clk(clk),
        .rst_n(rst_n),

        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_pixels_flat(in_pixels_flat),

        .out_ready(conv_out_ready),
        .out_data(conv_out_data),
        .out_valid(conv_out_valid)
    );

    // =====================================================
    // MAXPOOL3 TOP
    // =====================================================
    maxpool3_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .CHANNELS(OUT_CHANNELS),
        .IMG_H(IMG_H)
    ) u_maxpool3_top (
        .clk(clk),
        .rst_n(rst_n),

        .in_valid(conv_out_valid),
        .in_pixels_1024b(conv_out_data),

        .out_pixels_1024b(out_pixels_flat),
        .out_valid(out_valid)
    );

endmodule