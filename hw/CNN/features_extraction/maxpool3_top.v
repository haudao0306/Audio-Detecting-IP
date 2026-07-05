module maxpool3_top #(
    parameter DATA_WIDTH = 16,
    parameter CHANNELS   = 64,      // [C?P NH?T]: Layer 3 m? r?ng lên 64 channels
    parameter IMG_H      = 10       // [C?P NH?T]: Chi?u cao ?nh vào Layer 3 MaxPool là 10
)(
    input  wire                               clk,
    input  wire                               rst_n,
    
    // Giao ti?p v?i ??u ra c?a Conv3_top (1024-bit ch?a 64 pixels song song)
    input  wire                               in_valid,
    input  wire [(CHANNELS * DATA_WIDTH)-1:0] in_pixels_1024b, // Bus ??i thành 1024-bit
    
    // Giao ti?p v?i l?p ti?p theo (Flatten -> Classifier)
    output wire [(CHANNELS * DATA_WIDTH)-1:0] out_pixels_1024b, // Bus ??i thành 1024-bit
    output wire                               out_valid
);

    // M?ng ch?a tín hi?u valid ??u ra c?a toàn b? 64 channel
    wire [CHANNELS-1:0] filter_out_valids;
    
    // Vì 64 channel ch?y song song ??ng b? hoàn toàn v?i nhau, ch? c?n l?y c? valid c?a channel 0
    assign out_valid = &filter_out_valids;

    // =========================================================
    // GENERATE BLOCK: T? ??NG SINH 64 KH?I BUFFER & DATAPATH SONG SONG
    // =========================================================
    genvar i;
    generate
        for (i = 0; i < CHANNELS; i = i + 1) begin : channel_array
            
            // 1. Phân tách (Slicing) input: Trích xu?t pixel 16-bit c?a channel th? 'i' t? bus 1024-bit
            wire [DATA_WIDTH-1:0] current_in_pixel;
            assign current_in_pixel = in_pixels_1024b[(i+1)*DATA_WIDTH - 1 : i*DATA_WIDTH];
            
            // 2. Các dây n?i n?i b? k?t n?i gi?a Buffer và Datapath c?a t?ng channel
            wire [DATA_WIDTH-1:0] p0, p1, p2, p3;
            wire buffer_out_valid;
            
            // 3. Kh?i t?o tái s? d?ng MaxPool Buffer cho channel th? 'i'
            maxpool_buffer #(
                .DATA_WIDTH(DATA_WIDTH), // 16-bit
                .IMG_H(IMG_H)            // Truy?n tham s? chi?u cao b?ng 10 vào RAM xoay vòng
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
            
            // 4. Kh?i t?o tái s? d?ng MaxPool Datapath cho channel th? 'i'
            wire [DATA_WIDTH-1:0] current_out_pixel;
            
            maxpool_datapath #(
                .DATA_WIDTH(DATA_WIDTH)  // 16-bit
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
            
            // 5. ?óng gói (Packing) output: Ghép pixel 16-bit ?ã tính toán ng??c l?i vào bus ph?ng 1024-bit
            assign out_pixels_1024b[(i+1)*DATA_WIDTH - 1 : i*DATA_WIDTH] = current_out_pixel;
            
        end
    endgenerate

endmodule
