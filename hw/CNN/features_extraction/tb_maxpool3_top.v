`timescale 1ns/1ps

module tb_maxpool3_top();

    // Parameters - ?ã c?p nh?t chính xác cho Layer 3
    localparam DATA_WIDTH = 16;
    localparam CHANNELS   = 64;                          // L?p 3 m? r?ng thành 64 channels
    localparam IMG_H      = 10;                          // Kích th??c ?nh ??u vào MaxPool3 là 10
    localparam IMG_W      = 16;                          // Kích th??c ?nh ??u vào MaxPool3 là 16
    localparam IN_TOTAL_PIXELS = IMG_H * IMG_W;         // 10 * 16 = 160 pixels vào
    localparam OUT_TOTAL_PIXELS = (IMG_H/2) * (IMG_W/2); // 5 * 8 = 40 pixels ra
    localparam BUS_WIDTH  = CHANNELS * DATA_WIDTH;      // 64 * 16 = 1024 bit

    // Signals
    reg clk;
    reg rst_n;
    reg in_valid;
    reg  [BUS_WIDTH-1:0] in_pixels_1024b; // ??i bus n?p thành 1024-bit
    wire [BUS_WIDTH-1:0] out_pixels_1024b;// ??i bus xu?t thành 1024-bit
    wire out_valid;

    // Memories to load Hex files (M? r?ng ?? r?ng ô nh? lên 1024-bit)
    reg [BUS_WIDTH-1:0] in_mem  [0:IN_TOTAL_PIXELS-1];  // B? nh? ch?a 160 dòng 
    reg [BUS_WIDTH-1:0] exp_mem [0:OUT_TOTAL_PIXELS-1]; // B? nh? ch?a 40 dòng

    // Counters
    integer in_count  = 0;
    integer out_count = 0;
    integer error_count = 0;

    // Kh?i t?o Module MaxPool3 Top c?n ki?m tra (DUT)
    maxpool3_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .CHANNELS(CHANNELS),
        .IMG_H(IMG_H)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_pixels_1024b(in_pixels_1024b),
        .out_pixels_1024b(out_pixels_1024b),
        .out_valid(out_valid)
    );

    // Clock generation (Chu k? 10ns -> 100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test Sequence
    initial begin
        // 1. ??c d? li?u t? file Hex do script Python Layer 3 t?o ra
        $readmemh("maxpool3_input.hex", in_mem);
        $readmemh("maxpool3_expected.hex", exp_mem);
        
        // 2. Reset h? th?ng ban ??u
        rst_n = 0;
        in_valid = 0;
        in_pixels_1024b = 0;
        #20;
        rst_n = 1;
        #10;
        
        $display("=== BAT DAU MO PHONG MAXPOOL 3 ===");
        
        // 3. ??y tu?n t? 160 pixel (d?ng dòng 1024-bit) vào m?ch
        for (in_count = 0; in_count < IN_TOTAL_PIXELS; in_count = in_count + 1) begin
            @(posedge clk);
            in_valid <= 1'b1;
            in_pixels_1024b <= in_mem[in_count];
        end
        
        // Ng?ng ??y d? li?u sau khi h?t ?nh
        @(posedge clk);
        in_valid <= 1'b0;
        in_pixels_1024b <= 0;
        
        // Ch? thêm m?t kho?ng th?i gian ng?n ?? pipeline x? n?t các k?t qu? cu?i
        #500;
        
        // 4. Báo cáo t?ng k?t ch?t l??ng ph?n c?ng Layer 3
        $display("==================================================================");
        if (out_count == OUT_TOTAL_PIXELS && error_count == 0) begin
            $display(">> SUCCESS: Tat ca %0d pixels cua Layer 3 deu KHOP HOAN TOAN!", out_count);
        end else begin
            $display(">> FAILED: Co %0d loi tren tong so %0d pixels thu duoc o Layer 3.", error_count, out_count);
        end
        $display("==================================================================");
        
        $stop;
    end

    integer fw; // Bi?n gi? file ID n?u c?n dùng, gi? nguyên theo form c? c?a b?n
    
    // T? ??ng b?t l?i và hi?n th? song song ngay khi out_valid kéo lên 1
    always @(posedge clk) begin
        if (out_valid) begin
            // 1. Ghi k?t qu? ph?n c?ng ra file (N?u b?n truy?n file descriptor 'fw' t? ngoài)
            // C?p nh?t lên %0256x ?? bao ph? ?? ?? r?ng 256 ký t? Hex cho bus 1024-bit
            $fdisplay(fw, "%0256x", out_pixels_1024b);
            
            // 2. Hi?n th? tr?c ti?p lên màn hình Console (c? ph?n c?ng và Python) ?? theo dõi t?ng pixel
            $display("=== Layer 3 Pixel %0d ===", out_count + 1);
            $display("  HW Output : %0256x", out_pixels_1024b);
            $display("  PY Expect : %0256x", exp_mem[out_count]);
            
            // 3. So sánh tr?c ti?p t?ng bit m?t (X? lý ch?t ch? v?i toán t? !==)
            if (out_pixels_1024b !== exp_mem[out_count]) begin
                $display("  -> [LOI] KET QUA KHONG KHOP!");
                error_count = error_count + 1;
            end else begin
                $display("  -> [OK] KHOP HOAN TOAN!");
            end
            $display("------------------------------------------------------------------");
            
            out_count = out_count + 1;
        end
    end

endmodule
