`timescale 1ns/1ps

module tb_conv3_buffer;
    // C?u hình kích th??c nh? ?? d? soi log mô ph?ng
    parameter DATA_WIDTH = 16;
    parameter CHANNELS   = 32; // T?ng lên 32 kênh cho Layer 3
    parameter IMG_H      = 4;  // Thu nh? còn 4x4 ?? d? ki?m tra logic
    parameter IMG_W      = 4;
    parameter BUS_WIDTH  = CHANNELS * DATA_WIDTH; // 512-bit

    reg clk, rst_n, in_valid;
    reg  [BUS_WIDTH-1:0] in_pixels_512b; // Bus 512-bit cho Layer 3
    wire [BUS_WIDTH-1:0] p0, p1, p2, p3, p4, p5, p6, p7, p8;
    wire out_valid;

    // Kh?i t?o DUT (Layer 3 Buffer)
    conv3_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .CHANNELS(CHANNELS),
        .IMG_H(IMG_H),
        .IMG_W(IMG_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .buffer_in_valid(in_valid),
        .in_pixels_512b(in_pixels_512b),
        .p0(p0), .p1(p1), .p2(p2), 
        .p3(p3), .p4(p4), .p5(p5), 
        .p6(p6), .p7(p7), .p8(p8),
        .buffer_out_valid(out_valid)
    );

    // T?o xung Clock
    always #5 clk = ~clk;

    // Bi?n h? tr? loop
    integer r, c, ch;

    initial begin
        // 1. Kh?i t?o ban ??u
        clk = 0; rst_n = 0; in_valid = 0; in_pixels_512b = 0;
        #25 rst_n = 1;
        
        $display("=== TEST LAYER 3 BUFFER (SIZE 4x4, 32 CHANNELS) ===");

        // 2. G?i d? li?u ?nh gi? l?p 4x4 (M?i pixel là m?t vector 512-bit g?m 32 kênh)
        // Công th?c gán tr?: Pixel = C?t * 10 + Hàng (?? nhìn log ra là bi?t ngay t?a ?? nào)
        for (c = 0; c < IMG_W; c = c + 1) begin
            for (r = 0; r < IMG_H; r = r + 1) begin
                @(posedge clk);
                in_valid = 1;
                
                // N?p 32 channels gi?ng h?t nhau ?? d? ki?m tra chéo
                // N?u Channel 0 ?úng thì các channel khác t? ??ng ?úng
                for (ch = 0; ch < CHANNELS; ch = ch + 1) begin
                    in_pixels_512b[ch*DATA_WIDTH +: DATA_WIDTH] = (c * 10) + r;
                end
            end
        end

        // 3. K?t thúc n?p d? li?u (Auto-flush kích ho?t)
        @(posedge clk);
        in_valid = 0;
        in_pixels_512b = {32{16'hFFFF}}; // Gán d? li?u rác FFFF ?? ki?m tra xem m?ch có b? ?n l?m d? li?u rác không

        // 4. Ch? m?ch x? lý ??y n?t các c?a s? cu?i cùng ? rìa ph?i ra ngoài
        wait (dut.active == 0);
        
        #50;
        $display("=== KET THUC MO PHONG ===");
        $finish;
    end

    // --- KH?I IN LOG D?NG B?NG (Giám sát ??u ra t?ng chu k?) ---
    integer out_cnt = 0;
    always @(posedge clk) begin
        if (out_valid) begin
            out_cnt = out_cnt + 1;
            $display("\n[KQ %0d] Tai Tam: Col=%0d Row=%0d", out_cnt, dut.out_c, dut.out_r);
            $display("    --- Cua so 3x3 (Hien thi Channel 0) ---");
            $display("    %2d | %2d | %2d", p0[15:0], p1[15:0], p2[15:0]);
            $display("    %2d | %2d | %2d", p3[15:0], p4[15:0], p5[15:0]);
            $display("    %2d | %2d | %2d", p6[15:0], p7[15:0], p8[15:0]);
            
            // In thêm channel cu?i (Kênh 31: bit t? 496 ??n 511) ?? ch?c ch?n toàn b? bus 512-bit truy?n song song không l?i
            if (p4[511:496] != p4[15:0]) 
                $display("    ?? CANH BAO: Channel 31 (%d) khac Channel 0!", p4[511:496]);
            
            $display("    ---------------------------------------");
        end
    end

endmodule