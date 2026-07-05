module conv3_buffer #(
    parameter DATA_WIDTH = 16,
    parameter CHANNELS   = 32,
    parameter IMG_H      = 10,
    parameter IMG_W      = 16,
    parameter BUS_WIDTH  = CHANNELS * DATA_WIDTH
)(
    input  wire                 clk,
    input  wire                 rst_n,

    input  wire                 buffer_in_valid,
    output wire                 buffer_in_ready,
    input  wire                 next_window_en,
    input  wire [BUS_WIDTH-1:0] in_pixels_512b,

    output reg  [BUS_WIDTH-1:0] p0, p1, p2,
    output reg  [BUS_WIDTH-1:0] p3, p4, p5,
    output reg  [BUS_WIDTH-1:0] p6, p7, p8,

    output reg                  buffer_out_valid
);

    localparam TOTAL_PIXELS = IMG_H * IMG_W;

    reg [BUS_WIDTH-1:0] mem [0:2][0:IMG_H-1];

    reg [3:0] in_r;
    reg [1:0] wr_ptr;
    reg [7:0] pixel_count;

    wire all_pixels_in = (pixel_count == TOTAL_PIXELS);

    reg [3:0] out_r;
    reg [3:0] out_c;
    reg [1:0] mid_ptr;
    reg       active;
    reg [4:0] wr_col;

    reg last_window_loaded;

    wire [4:0] max_ahead = (out_c == 0) ? 5'd3 : 5'd2;
    wire [4:0] col_distance = wr_col - out_c;
    wire safe_to_write = (col_distance < max_ahead);

    assign buffer_in_ready = !all_pixels_in && safe_to_write;

    wire write_en = buffer_in_valid && buffer_in_ready;

    wire [1:0] l_ptr = (mid_ptr == 2'd0) ? 2'd2 : mid_ptr - 1'b1;
    wire [1:0] r_ptr = (mid_ptr == 2'd2) ? 2'd0 : mid_ptr + 1'b1;

    wire [3:0] safe_r_up = (out_r == 0) ? 4'd0 : out_r - 1'b1;
    wire [3:0] safe_r_dn = (out_r == IMG_H - 1) ? out_r : out_r + 1'b1;

    wire current_addr_is_last =
        (out_c == IMG_W - 1) &&
        (out_r == IMG_H - 1);

    wire consume_last_window =
        buffer_out_valid &&
        last_window_loaded &&
        next_window_en;

    wire have_cols_for_window =
    (out_c == IMG_W - 1) ? (wr_col >= IMG_W) :
                           (wr_col >= (out_c + 2));

    wire safe_to_read =
        active &&
        !consume_last_window &&
        have_cols_for_window;

    wire load_window =
        safe_to_read &&
        (!buffer_out_valid || next_window_en);

    // =====================================================
    // WRITE SIDE
    // =====================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_r        <= 4'd0;
            wr_ptr      <= 2'd0;
            pixel_count <= 8'd0;
            active      <= 1'b0;
            wr_col      <= 5'd0;
        end
        else begin
            if (write_en) begin
                mem[wr_ptr][in_r] <= in_pixels_512b;
                pixel_count       <= pixel_count + 1'b1;

                if (wr_ptr == 2'd1 && in_r == IMG_H - 1)
                    active <= 1'b1;

                if (in_r == IMG_H - 1) begin
                    in_r   <= 4'd0;
                    wr_ptr <= (wr_ptr == 2'd2) ? 2'd0 : wr_ptr + 1'b1;
                    wr_col <= wr_col + 1'b1;
                end
                else begin
                    in_r <= in_r + 1'b1;
                end
            end

            if (consume_last_window)
                active <= 1'b0;
        end
    end

    // =====================================================
    // READ SIDE
    // =====================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_r              <= 4'd0;
            out_c              <= 4'd0;
            mid_ptr            <= 2'd0;
            buffer_out_valid   <= 1'b0;
            last_window_loaded <= 1'b0;

            p0 <= {BUS_WIDTH{1'b0}};
            p1 <= {BUS_WIDTH{1'b0}};
            p2 <= {BUS_WIDTH{1'b0}};
            p3 <= {BUS_WIDTH{1'b0}};
            p4 <= {BUS_WIDTH{1'b0}};
            p5 <= {BUS_WIDTH{1'b0}};
            p6 <= {BUS_WIDTH{1'b0}};
            p7 <= {BUS_WIDTH{1'b0}};
            p8 <= {BUS_WIDTH{1'b0}};
        end
        else begin
            if (consume_last_window) begin
                buffer_out_valid   <= 1'b0;
                last_window_loaded <= 1'b0;
            end
            else if (load_window) begin
                buffer_out_valid   <= 1'b1;
                last_window_loaded <= current_addr_is_last;

                p0 <= (out_r == 0 || out_c == 0)             ? {BUS_WIDTH{1'b0}} : mem[l_ptr][safe_r_up];
                p1 <= (out_r == 0)                           ? {BUS_WIDTH{1'b0}} : mem[mid_ptr][safe_r_up];
                p2 <= (out_r == 0 || out_c == IMG_W - 1)     ? {BUS_WIDTH{1'b0}} : mem[r_ptr][safe_r_up];

                p3 <= (out_c == 0)                           ? {BUS_WIDTH{1'b0}} : mem[l_ptr][out_r];
                p4 <=                                                               mem[mid_ptr][out_r];
                p5 <= (out_c == IMG_W - 1)                   ? {BUS_WIDTH{1'b0}} : mem[r_ptr][out_r];

                p6 <= (out_r == IMG_H - 1 || out_c == 0)     ? {BUS_WIDTH{1'b0}} : mem[l_ptr][safe_r_dn];
                p7 <= (out_r == IMG_H - 1)                   ? {BUS_WIDTH{1'b0}} : mem[mid_ptr][safe_r_dn];
                p8 <= (out_r == IMG_H - 1 || out_c == IMG_W - 1)
                                                                  ? {BUS_WIDTH{1'b0}} : mem[r_ptr][safe_r_dn];

                if (out_r == IMG_H - 1) begin
                    out_r <= 4'd0;
                    mid_ptr <= (mid_ptr == 2'd2) ? 2'd0 : mid_ptr + 1'b1;

                    if (out_c != IMG_W - 1)
                        out_c <= out_c + 1'b1;
                end
                else begin
                    out_r <= out_r + 1'b1;
                end
            end
            else if (next_window_en) begin
                buffer_out_valid   <= 1'b0;
                last_window_loaded <= 1'b0;
            end
        end
    end

endmodule
