module maxpool2_top #(
    parameter DATA_WIDTH = 16,
    parameter CHANNELS   = 32,
    parameter IMG_H      = 20
)(
    input  wire                                clk,
    input  wire                                rst_n,

    input  wire                                in_valid,
    input  wire [(CHANNELS * DATA_WIDTH)-1:0]  in_pixels_512b,

    output wire [(CHANNELS * DATA_WIDTH)-1:0]  out_pixels_512b,
    output wire                                out_valid
);

    wire [CHANNELS-1:0] filter_out_valids;

    assign out_valid = &filter_out_valids;

    genvar i;
    generate
        for (i = 0; i < CHANNELS; i = i + 1) begin : channel_array

            wire [DATA_WIDTH-1:0] current_in_pixel;
            assign current_in_pixel =
                in_pixels_512b[(i+1)*DATA_WIDTH - 1 : i*DATA_WIDTH];

            wire [DATA_WIDTH-1:0] p0, p1, p2, p3;
            wire buffer_out_valid;

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

            assign out_pixels_512b[(i+1)*DATA_WIDTH - 1 : i*DATA_WIDTH] =
                current_out_pixel;

        end
    endgenerate

endmodule
