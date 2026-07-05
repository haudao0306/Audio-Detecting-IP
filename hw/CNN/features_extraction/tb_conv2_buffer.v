`timescale 1ns/1ps

module tb_conv2_buffer;
    // C?u hình kích th??c nh? ?? d? soi log
    parameter DATA_WIDTH = 16;
    parameter CHANNELS   = 16;
    parameter IMG_H      = 4;  // Thu nh? còn 4x4
    parameter IMG_W      = 4;
    parameter BUS_WIDTH  = CHANNELS * DATA_WIDTH; // 256-bit

    reg clk, rst_n, in_valid;
    wire in_ready; // [FIX 1] Thêm tín hi?u in_ready (nh?n t? DUT)
    reg next_en;   // [FIX 1] Thêm tín hi?u next_window_en (??a vào DUT)
    
    reg  [BUS_WIDTH-1:0] in_pixels_256b;
    wire [BUS_WIDTH-1:0] p0, p1, p2, p3, p4, p5, p6, p7, p8;
    wire out_valid;

    // Kh?i t?o DUT
    conv2_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .CHANNELS(CHANNELS),
        .IMG_H(IMG_H),
        .IMG_W(IMG_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .buffer_in_valid(in_valid),
        .buffer_in_ready(in_ready), // [FIX 2] K?t n?i in_ready
        .next_window_en(next_en),   // [FIX 2] K?t n?i next_window_en
        .in_pixels_256b(in_pixels_256b),
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
        // 1. Kh?i t?o
        clk = 0; rst_n = 0; in_valid = 0; in_pixels_256b = 0;
        next_en = 1; // [FIX 3] Gi? l?p kh?i sau luôn s?n sàng nh?n d? li?u
        #25 rst_n = 1;
        
        $display("=== TEST LAYER 2 BUFFER (SIZE 4x4) ===");

        // 2. G?i d? li?u ?nh 4x4 (M?i pixel là 1 vector 256-bit)
        // Công th?c gán tr?: Pixel = C?t * 10 + Hàng (?? d? nhìn to? ??)
        for (c = 0; c < IMG_W; c = c + 1) begin
            for (r = 0; r < IMG_H; r = r + 1) begin
                // N?p 16 channels gi?ng h?t nhau ?? d? ki?m tra
                for (ch = 0; ch < CHANNELS; ch = ch + 1) begin
                    in_pixels_256b[ch*DATA_WIDTH +: DATA_WIDTH] = (c * 10) + r;
                end
                
                in_valid = 1;
                
                // [FIX 4] Handshake Wait: Ch? ??n khi buffer s?n sàng nh?n
                @(posedge clk);
                while (!in_ready) begin
                    @(posedge clk);
                end
            end
        end

        // 3. K?t thúc n?p (Auto-flush)
        in_valid = 0;
        in_pixels_256b = {CHANNELS{16'hFFFF}}; // ?ánh d?u d? li?u rác

        // 4. Ch? m?ch x? lý n?t các pixel cu?i cùng
        wait (dut.active == 0);
        
        #50;
        $display("=== KET THUC MO PHONG ===");
        $finish;
    end

    // --- KH?I IN LOG D?NG B?NG ---
    integer out_cnt = 0;
    always @(posedge clk) begin
        // [FIX 5] Ch? in ra khi c?a s? ??u ra h?p l? VÀ ?ã ???c ??c
        if (out_valid && next_en) begin 
            out_cnt = out_cnt + 1;
            $display("\n[KQ %0d] Tai Tam: Col=%0d Row=%0d", out_cnt, dut.out_c, dut.out_r);
            $display("    --- Cua so 3x3 (Hien thi Channel 0) ---");
            $display("    %2d | %2d | %2d", p0[15:0], p1[15:0], p2[15:0]);
            $display("    %2d | %2d | %2d", p3[15:0], p4[15:0], p5[15:0]);
            $display("    %2d | %2d | %2d", p6[15:0], p7[15:0], p8[15:0]);
            
            // In thêm channel cu?i ?? ch?c ch?n bus 256-bit không b? ??t
            if (p4[255:240] != p4[15:0]) 
                $display("    >> CANH BAO: Channel 15 (%d) khac Channel 0!", p4[255:240]);
            
            $display("    ---------------------------------------");
        end
    end

endmodule