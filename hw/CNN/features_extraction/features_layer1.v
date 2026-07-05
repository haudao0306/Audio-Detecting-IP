module features_layer1 #(
    parameter DATA_WIDTH   = 16,
    parameter ACCUM_WIDTH  = 32,
    parameter IMG_H        = 40,
    parameter IMG_W        = 64,
    parameter IN_CHANNELS  = 1,
    parameter OUT_CHANNELS = 16,

    parameter PIXEL_FRAC  = 10,
    parameter WEIGHT_FRAC = 8,
    parameter OUT_FRAC    = 8,

    parameter WEIGHT_FILE = "features.0_fused_weight.hex",
    parameter BIAS_FILE   = "features.0_fused_bias.hex"
)(
    input  wire clk,
    input  wire rst_n,

    // Input tu khoi Log-Mel / khoi truoc
    input  wire                         in_valid,
    output wire                         in_ready,
    input  wire signed [DATA_WIDTH-1:0] in_pixel,

    // Output sau Conv + MaxPool
    output wire [(DATA_WIDTH*OUT_CHANNELS)-1:0] out_pixels_flat,
    output wire                                out_valid
);

    // =====================================================
    // Internal connection: Conv -> MaxPool
    // =====================================================
    wire [(DATA_WIDTH*OUT_CHANNELS)-1:0] conv_out_data;
    wire                                conv_out_valid;

    // MaxPool hien tai khong co backpressure, nen luon ready
    wire conv_out_ready;
    assign conv_out_ready = 1'b1;

    // =====================================================
    // CONV TOP
    // =====================================================
    conv_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH),
        .IMG_H(IMG_H),
        .IMG_W(IMG_W),
        .IN_CHANNELS(IN_CHANNELS),
        .OUT_CHANNELS(OUT_CHANNELS),

        .PIXEL_FRAC(PIXEL_FRAC),
        .WEIGHT_FRAC(WEIGHT_FRAC),
        .OUT_FRAC(OUT_FRAC),

        .WEIGHT_FILE(WEIGHT_FILE),
        .BIAS_FILE(BIAS_FILE)
    ) u_conv_top (
        .clk(clk),
        .rst_n(rst_n),

        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_pixel(in_pixel),

        .out_ready(conv_out_ready),
        .out_data(conv_out_data),
        .out_valid(conv_out_valid)
    );

    // =====================================================
    // MAXPOOL TOP
    // =====================================================
    maxpool_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .CHANNELS(OUT_CHANNELS),
        .IMG_H(IMG_H)
    ) u_maxpool_top (
        .clk(clk),
        .rst_n(rst_n),

        .in_valid(conv_out_valid),
        .in_pixels_flat(conv_out_data),

        .out_pixels_flat(out_pixels_flat),
        .out_valid(out_valid)
    );

endmodule