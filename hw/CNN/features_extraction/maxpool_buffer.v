module maxpool_buffer #(
    parameter DATA_WIDTH = 16,
    parameter IMG_H = 40
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  buffer_in_valid,
    input  wire [DATA_WIDTH-1:0] in_pixel,
    
    output reg  [DATA_WIDTH-1:0] p0, p1, p2, p3,
    output reg                   buffer_out_valid
);

    // RAM l?u ?úng 1 c?t (??a ch? t? 0 ??n 39)
    reg [DATA_WIDTH-1:0] col_ram [0:IMG_H-1];
    
    // T?i ?u: Ch? c?n ??m hàng ?? làm ??a ch? RAM
    reg [5:0] in_r; 
    
    // T?i ?u: Thay vì ??m c?t, ch? c?n 1 bit ?? bi?t C?t Ch?n (0) hay L? (1)
    reg       col_phase; 

    reg [DATA_WIDTH-1:0] top_left;
    reg [DATA_WIDTH-1:0] top_right;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_r <= 0;
            col_phase <= 0; // 0: C?t ch?n, 1: C?t l?
            buffer_out_valid <= 0;
            top_left <= 0; top_right <= 0;
            p0 <= 0; p1 <= 0; p2 <= 0; p3 <= 0;
        end 
        else begin
            buffer_out_valid <= 1'b0; 

            if (buffer_in_valid) begin
                if (col_phase == 1'b0) begin 
                    // C?T CH?N: Ch? ghi RAM, không xu?t data
                    col_ram[in_r] <= in_pixel;
                end 
                else begin 
                    // C?T L?: B?t ??u ghép c?a s?
                    if (in_r[0] == 1'b0) begin
                        // HÀNG CH?N (0, 2, 4...): C?t t?m d? li?u lên thanh ghi (ch?a ?? 4 pixel)
                        top_left  <= col_ram[in_r]; // Pixel c?t tr??c
                        top_right <= in_pixel;      // Pixel c?t này
                    end 
                    else begin
                        // HÀNG L? (1, 3, 5...): ?ã gom ?? 4 pixel, b?n data ra ngoài!
                        p0 <= top_left;
                        p1 <= top_right;
                        p2 <= col_ram[in_r]; 
                        p3 <= in_pixel;     
                        
                        buffer_out_valid <= 1'b1; 
                    end
                end

                // Logic cu?n hàng (Roll-over)
                if (in_r == IMG_H - 1) begin
                    in_r <= 0;
                    col_phase <= ~col_phase; // H?t hàng 39 thì ??o pha ch?n/l? c?a c?t
                end else begin
                    in_r <= in_r + 1;
                end
            end
        end
    end

endmodule
