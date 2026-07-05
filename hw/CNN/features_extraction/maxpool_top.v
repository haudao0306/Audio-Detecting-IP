module maxpool_top #(
    parameter DATA_WIDTH = 16,
    parameter CHANNELS   = 16,
    parameter IMG_H      = 40
)(
    input  wire                               clk,
    input  wire                               rst_n,

    // INPUT:  FILTER SONG SONG T? CONV_TOP
    input  wire                               in_valid,
    input  wire [(CHANNELS*DATA_WIDTH)-1:0]   in_pixels_flat,

    // OUTPUT:  FILTER SONG SONG
    output wire [(CHANNELS*DATA_WIDTH)-1:0]   out_pixels_flat,
    output wire                               out_valid
);

    // =====================================================
    // VALID SIGNALS
    // =====================================================

    wire [CHANNELS-1:0] filter_out_valids;

    // t?t c? channel ch?y ??ng b?
    assign out_valid = &filter_out_valids;

    // =====================================================
    // GENERATE CHANNELS
    // =====================================================

    genvar i;

    generate

        for (i = 0; i < CHANNELS; i = i + 1) begin : channel_array

            // =================================================
            // INPUT SLICE
            // =================================================

            wire [DATA_WIDTH-1:0] current_in_pixel;

            assign current_in_pixel =
                in_pixels_flat[
                    (i+1)*DATA_WIDTH-1 :
                    i*DATA_WIDTH
                ];

            // =================================================
            // BUFFER WIRES
            // =================================================

            wire [DATA_WIDTH-1:0] p0, p1, p2, p3;
            wire buffer_out_valid;

            // =================================================
            // MAXPOOL BUFFER
            // =================================================

            maxpool_buffer #(
                .DATA_WIDTH(DATA_WIDTH),
                .IMG_H(IMG_H)
            ) u_buffer (

                .clk(clk),
                .rst_n(rst_n),

                .buffer_in_valid(in_valid),
                .in_pixel(current_in_pixel),

                .p0(p0),
                .p1(p1),
                .p2(p2),
                .p3(p3),

                .buffer_out_valid(buffer_out_valid)
            );

            // =================================================
            // MAXPOOL DATAPATH
            // =================================================

            wire [DATA_WIDTH-1:0] current_out_pixel;

            maxpool_datapath #(
                .DATA_WIDTH(DATA_WIDTH)
            ) u_datapath (

                .clk(clk),
                .rst_n(rst_n),

                .valid_in(buffer_out_valid),

                .p0(p0),
                .p1(p1),
                .p2(p2),
                .p3(p3),

                .max_out(current_out_pixel),
                .valid_out(filter_out_valids[i])
            );

            // =================================================
            // OUTPUT PACKING
            // =================================================

            assign out_pixels_flat[
                (i+1)*DATA_WIDTH-1 :
                i*DATA_WIDTH
            ] = current_out_pixel;

        end

    endgenerate

endmodule