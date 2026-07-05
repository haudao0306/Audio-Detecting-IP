module features #(
    parameter DATA_WIDTH  = 16,
    parameter ACCUM_WIDTH = 32,

    parameter FIFO12_DEPTH      = 1024,
    parameter FIFO12_ADDR_WIDTH = 10,

    parameter FIFO23_DEPTH      = 256,
    parameter FIFO23_ADDR_WIDTH = 8
)(
    input  wire clk,
    input  wire rst_n,

    // Input tu Log-Mel
    input  wire                         in_valid,
    output wire                         in_ready,
    input  wire signed [DATA_WIDTH-1:0] in_pixel,

    // Output sau features_layer3
    output wire [(64*DATA_WIDTH)-1:0] out_pixels_flat,
    output wire                       out_valid
);

    // =====================================================
    // Layer 1
    // =====================================================
    wire [(16*DATA_WIDTH)-1:0] layer1_out_data;
    wire                       layer1_out_valid;

    features_layer1 #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) u_features_layer1 (
        .clk(clk),
        .rst_n(rst_n),

        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_pixel(in_pixel),

        .out_pixels_flat(layer1_out_data),
        .out_valid(layer1_out_valid)
    );

    // =====================================================
    // FIFO Layer1 -> Layer2
    // =====================================================
    wire [(16*DATA_WIDTH)-1:0] fifo12_out_data;
    wire                       fifo12_out_valid;
    wire                       fifo12_out_ready;
    wire                       fifo12_in_ready;

    stream_fifo #(
        .DATA_WIDTH(16*DATA_WIDTH),
        .DEPTH(FIFO12_DEPTH),
        .ADDR_WIDTH(FIFO12_ADDR_WIDTH)
    ) u_fifo12 (
        .clk(clk),
        .rst_n(rst_n),

        .in_valid(layer1_out_valid),
        .in_ready(fifo12_in_ready),
        .in_data(layer1_out_data),

        .out_valid(fifo12_out_valid),
        .out_ready(fifo12_out_ready),
        .out_data(fifo12_out_data)
    );

    // =====================================================
    // Layer 2
    // =====================================================
    wire [(32*DATA_WIDTH)-1:0] layer2_out_data;
    wire                       layer2_out_valid;
    wire                       layer2_in_ready;

    assign fifo12_out_ready = layer2_in_ready;

    features_layer2 #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) u_features_layer2 (
        .clk(clk),
        .rst_n(rst_n),

        .in_valid(fifo12_out_valid),
        .in_ready(layer2_in_ready),
        .in_pixels_flat(fifo12_out_data),

        .out_pixels_flat(layer2_out_data),
        .out_valid(layer2_out_valid)
    );

    // =====================================================
    // FIFO Layer2 -> Layer3
    // =====================================================
    wire [(32*DATA_WIDTH)-1:0] fifo23_out_data;
    wire                       fifo23_out_valid;
    wire                       fifo23_out_ready;
    wire                       fifo23_in_ready;

    stream_fifo #(
        .DATA_WIDTH(32*DATA_WIDTH),
        .DEPTH(FIFO23_DEPTH),
        .ADDR_WIDTH(FIFO23_ADDR_WIDTH)
    ) u_fifo23 (
        .clk(clk),
        .rst_n(rst_n),

        .in_valid(layer2_out_valid),
        .in_ready(fifo23_in_ready),
        .in_data(layer2_out_data),

        .out_valid(fifo23_out_valid),
        .out_ready(fifo23_out_ready),
        .out_data(fifo23_out_data)
    );

    // =====================================================
    // Layer 3
    // =====================================================
    wire layer3_in_ready;

    assign fifo23_out_ready = layer3_in_ready;

    features_layer3 #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) u_features_layer3 (
        .clk(clk),
        .rst_n(rst_n),

        .in_valid(fifo23_out_valid),
        .in_ready(layer3_in_ready),
        .in_pixels_flat(fifo23_out_data),

        .out_pixels_flat(out_pixels_flat),
        .out_valid(out_valid)
    );

endmodule