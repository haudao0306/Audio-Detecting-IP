`timescale 1ns/1ps

module tb_conv_buffer();

    // ==========================================
    // 1. PARAMETERS & SIGNALS
    // ==========================================
    parameter DATA_WIDTH = 16;
    parameter IMG_H = 4;
    parameter IMG_W = 4;

    reg clk;
    reg rst_n;

    reg buffer_in_valid;
    wire buffer_in_ready;
    reg next_window_en;
    reg [DATA_WIDTH-1:0] in_pixel;

    wire [DATA_WIDTH-1:0] p0, p1, p2;
    wire [DATA_WIDTH-1:0] p3, p4, p5;
    wire [DATA_WIDTH-1:0] p6, p7, p8;
    wire buffer_out_valid;

    // ==========================================
    // 2. DUT INSTANTIATION
    // ==========================================
    conv_buffer #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_H(IMG_H),
        .IMG_W(IMG_W)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .buffer_in_valid(buffer_in_valid),
        .buffer_in_ready(buffer_in_ready),
        .next_window_en(next_window_en),
        .in_pixel(in_pixel),
        .p0(p0), .p1(p1), .p2(p2),
        .p3(p3), .p4(p4), .p5(p5),
        .p6(p6), .p7(p7), .p8(p8),
        .buffer_out_valid(buffer_out_valid)
    );

    // ==========================================
    // 3. CLOCK GENERATION
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // Chu k? clock 10ns
    end

    // ==========================================
    // 4. INPUT STIMULUS (PRODUCER)
    // ==========================================
    integer r, c;
    initial begin
        // Kh?i t?o
        rst_n = 0;
        buffer_in_valid = 0;
        in_pixel = 0;
        next_window_en = 0;

        #20 rst_n = 1;

        // ??y ?nh 4x4 vào Buffer
        for (c = 1; c <= IMG_W; c = c + 1) begin
            for (r = 1; r <= IMG_H; r = r + 1) begin
                // Ch? buffer s?n sàng nh?n
                wait(buffer_in_ready);
                @(negedge clk);
                
                buffer_in_valid = 1;
                // T?o giá tr? pixel d? nh?n bi?t (VD: Hàng 1 C?t 2 -> 12)
                in_pixel = (r * 10) + c; 
                
                @(negedge clk);
                buffer_in_valid = 0;
                
                // Thêm m?t chút delay ng?u nhiên ?? mô ph?ng s? ng?t quãng c?a Log-Mel
                repeat(1) @(negedge clk);
            end
        end
    end

    // ==========================================
    // 5. OUTPUT MONITORING & FSM CONTROL (CONSUMER)
    // ==========================================
    integer window_count = 0;
    
    initial begin
        forever begin
            @(posedge clk);
            
            if (buffer_out_valid && !next_window_en) begin
                // In ra th?i ?i?m b?t ??u hold
                $display("-----------------------------------------");
                $display(">> [B?t ??u Hold] Time: %0t | Window Count: %0d", $time, window_count);
                
                // B??C 1: Ép m?ch ch? ?ÚNG 16 CHU K? CLOCK (Mô ph?ng 16 filter)
                repeat(16) @(posedge clk);

                // B??C 2: In th?i ?i?m k?t thúc ch? và giá tr? c?a s?
                $display(">> [K?t thúc Hold] Time: %0t | ?ã ch? 16 clocks", $time);
                $display("[%2d] [%2d] [%2d]", p0, p1, p2);
                $display("[%2d] [%2d] [%2d]", p3, p4, p5);
                $display("[%2d] [%2d] [%2d]", p6, p7, p8);
                
                // B??C 3: Kích xung yêu c?u tr??t c?a s?
                next_window_en = 1;
                @(posedge clk);
                next_window_en = 0; 
                
                window_count = window_count + 1;
                
                if (window_count == 6) begin
                    $display("=========================================");
                    $display("Testbench Hoàn Thành: ?ã in t??ng tr?ng %0d c?a s?.", window_count);
                    $stop;
                end
            end
        end
    end

endmodule