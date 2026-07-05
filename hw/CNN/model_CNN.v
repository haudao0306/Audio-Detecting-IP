module model_CNN #(
    parameter DATA_WIDTH   = 16,
    parameter ACCUM_WIDTH  = 32,

    parameter OUT_CLASSES  = 3,

    parameter FEAT_BUS_WIDTH = 64 * DATA_WIDTH,

    parameter FC_FIFO_DEPTH      = 32,
    parameter FC_FIFO_ADDR_WIDTH = 5
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // Input stream
    input  wire                         in_valid,
    output wire                         in_ready,
    input  wire signed [DATA_WIDTH-1:0] in_pixel,

    // Final logits
    output wire                         out_valid,
    output wire signed [15:0]           out_class_0,
    output wire signed [15:0]           out_class_1,
    output wire signed [15:0]           out_class_2
);

    // =====================================================
    // Features output
    // =====================================================
    wire                         feat_out_valid;
    wire [FEAT_BUS_WIDTH-1:0]    feat_out_data;

    features #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACCUM_WIDTH(ACCUM_WIDTH)
    ) u_features (
        .clk(clk),
        .rst_n(rst_n),

        .in_valid(in_valid),
        .in_ready(in_ready),
        .in_pixel(in_pixel),

        .out_pixels_flat(feat_out_data),
        .out_valid(feat_out_valid)
    );

    // =====================================================
    // FIFO: Features -> Classifier
    // =====================================================
    wire                      fifo_out_valid;
    wire                      fifo_out_ready;
    wire [FEAT_BUS_WIDTH-1:0] fifo_out_data;

    wire fifo_in_ready;

    stream_fifo #(
        .DATA_WIDTH(FEAT_BUS_WIDTH),
        .DEPTH(FC_FIFO_DEPTH),
        .ADDR_WIDTH(FC_FIFO_ADDR_WIDTH)
    ) u_features_to_classifier_fifo (
        .clk(clk),
        .rst_n(rst_n),

        .in_valid(feat_out_valid),
        .in_ready(fifo_in_ready),
        .in_data(feat_out_data),

        .out_valid(fifo_out_valid),
        .out_ready(fifo_out_ready),
        .out_data(fifo_out_data)
    );

    // =====================================================
    // Classifier
    // =====================================================
    wire classifier_in_ready;

    assign fifo_out_ready = classifier_in_ready;

    classifier #(
        .DATA_WIDTH(DATA_WIDTH),
        .IN_CHANNELS(64),
        .NUM_CYCLES(40),
        .MID_NODES(128),
        .OUT_CLASSES(OUT_CLASSES),
        .L1_ACCUM_WIDTH(48),
        .L2_ACCUM_WIDTH(40),
        .Q_FRAC(8)
    ) u_classifier (
        .clk(clk),
        .rst_n(rst_n),

        .in_valid(fifo_out_valid),
        .in_ready(classifier_in_ready),
        .in_data_flat(fifo_out_data),

        .out_valid(out_valid),
        .out_class_0(out_class_0),
        .out_class_1(out_class_1),
        .out_class_2(out_class_2)
    );

endmodule