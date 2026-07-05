module classifier #(
    parameter DATA_WIDTH     = 16,
    parameter IN_CHANNELS    = 64,
    parameter NUM_CYCLES     = 40,
    parameter MID_NODES      = 128,
    parameter OUT_CLASSES    = 3,

    parameter L1_ACCUM_WIDTH = 48,
    parameter L2_ACCUM_WIDTH = 40,

    parameter Q_FRAC         = 8,

    parameter FIFO_DEPTH      = 32,
    parameter FIFO_ADDR_WIDTH = 5,

    parameter IN_BUS_WIDTH   = IN_CHANNELS * DATA_WIDTH,
    parameter MID_BUS_WIDTH  = MID_NODES * DATA_WIDTH
)(
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire                         in_valid,
    output wire                         in_ready,
    input  wire [IN_BUS_WIDTH-1:0]      in_data_flat,

    output wire                         out_valid,
    output wire signed [15:0]           out_class_0,
    output wire signed [15:0]           out_class_1,
    output wire signed [15:0]           out_class_2
);

    // =========================================================
    // LAYER 1
    // =========================================================
    wire                     layer1_out_valid;
    wire                     layer1_out_ready;
    wire [MID_BUS_WIDTH-1:0] layer1_out_data;

    classifier_layer1 #(
        .DATA_WIDTH  (DATA_WIDTH),
        .IN_CHANNELS (IN_CHANNELS),
        .NUM_CYCLES  (NUM_CYCLES),
        .ACCUM_WIDTH (L1_ACCUM_WIDTH),
        .OUT_NODES   (MID_NODES),
        .WEIGHT_FILE ("classifier.0_weight.hex"),
        .BIAS_FILE   ("classifier.0_bias.hex")
    ) layer1_inst (
        .clk            (clk),
        .rst_n          (rst_n),

        .in_valid       (in_valid),
        .in_ready       (in_ready),
        .in_data_flat   (in_data_flat),

        .out_ready      (layer1_out_ready),
        .out_valid      (layer1_out_valid),
        .out_layer_data (layer1_out_data)
    );

    // =========================================================
    // STREAM FIFO
    // =========================================================
    wire                     fifo_out_valid;
    wire                     fifo_out_ready;
    wire [MID_BUS_WIDTH-1:0] fifo_out_data;

    stream_fifo #(
        .DATA_WIDTH (MID_BUS_WIDTH),
        .DEPTH      (FIFO_DEPTH),
        .ADDR_WIDTH (FIFO_ADDR_WIDTH)
    ) u_classifier_fifo (
        .clk       (clk),
        .rst_n     (rst_n),

        .in_valid  (layer1_out_valid),
        .in_ready  (layer1_out_ready),
        .in_data   (layer1_out_data),

        .out_valid (fifo_out_valid),
        .out_ready (fifo_out_ready),
        .out_data  (fifo_out_data)
    );

    // =========================================================
    // LAYER 2
    // =========================================================
    wire layer2_in_ready;

    // FIFO s? t? ??ng pop data khi Layer 2 báo ready
    assign fifo_out_ready = layer2_in_ready;

    classifier_layer2 #(
        .DATA_WIDTH  (DATA_WIDTH),
        .IN_NODES    (MID_NODES),
        .OUT_CLASSES (OUT_CLASSES),
        .ACCUM_WIDTH (L2_ACCUM_WIDTH),
        .Q_FRAC      (Q_FRAC)
    ) layer2_inst (
        .clk            (clk),
        .rst_n          (rst_n),

        // N?i tr?c ti?p tín hi?u valid/ready v?i FIFO
        .in_valid       (fifo_out_valid),
        .in_ready       (layer2_in_ready),
        .in_layer1_data (fifo_out_data),

        .out_valid      (out_valid),
        .out_class_0    (out_class_0),
        .out_class_1    (out_class_1),
        .out_class_2    (out_class_2)
    );

endmodule