`timescale 1ns/1ps

module tb_maxpool2_top();

    // Parameters
    localparam DATA_WIDTH = 16;
    localparam CHANNELS   = 32;
    localparam IMG_H      = 20;
    localparam IMG_W      = 32;
    localparam IN_TOTAL_PIXELS = IMG_H * IMG_W;         // 640
    localparam OUT_TOTAL_PIXELS = (IMG_H/2) * (IMG_W/2); // 160
    localparam BUS_WIDTH  = CHANNELS * DATA_WIDTH;      // 512

    // Signals
    reg clk;
    reg rst_n;
    reg in_valid;
    reg  [BUS_WIDTH-1:0] in_pixels_512b;
    wire [BUS_WIDTH-1:0] out_pixels_512b;
    wire out_valid;

    // Memories to load Hex files
    reg [BUS_WIDTH-1:0] in_mem  [0:IN_TOTAL_PIXELS-1];
    reg [BUS_WIDTH-1:0] exp_mem [0:OUT_TOTAL_PIXELS-1];

    // Counters
    integer in_count  = 0;
    integer out_count = 0;
    integer error_count = 0;

    // Kh?i t?o Module MaxPool2
    maxpool2_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .CHANNELS(CHANNELS),
        .IMG_H(IMG_H)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_pixels_512b(in_pixels_512b),
        .out_pixels_512b(out_pixels_512b),
        .out_valid(out_valid)
    );

    // Clock generation (Chu k? 10ns)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test Sequence
    initial begin
        // 1. ??c d? li?u t? file Hex
        $readmemh("maxpool2_input.hex", in_mem);
        $readmemh("maxpool2_expected.hex", exp_mem);
        
        // 2. Reset h? th?ng
        rst_n = 0;
        in_valid = 0;
        in_pixels_512b = 0;
        #20;
        rst_n = 1;
        #10;
        
        $display("=== BAT DAU MO PHONG MAXPOOL 2 ===");
        
        // 3. ??y 640 pixel vào tu?n t?
        for (in_count = 0; in_count < IN_TOTAL_PIXELS; in_count = in_count + 1) begin
            @(posedge clk);
            in_valid <= 1'b1;
            in_pixels_512b <= in_mem[in_count];
        end
        
        // Ng?ng ??y d? li?u
        @(posedge clk);
        in_valid <= 1'b0;
        in_pixels_512b <= 0;
        
        // Ch? thêm m?t chút ?? pipeline x? lý n?t
        #100;
        
        // 4. Báo cáo k?t qu?
        if (out_count == OUT_TOTAL_PIXELS && error_count == 0) begin
            $display(">> SUCCESS: Tat ca %0d pixels deu khop hoan toan!", out_count);
        end else begin
            $display(">> FAILED: Co %0d loi tren tong so %0d pixels thu duoc.", error_count, out_count);
        end
        
        $stop;
    end

    integer fw;
    // T? ??ng ki?m tra Output m?i khi out_valid kéo lên 1
    always @(posedge clk) begin
        if (out_valid) begin
            // 1. Ghi k?t qu? ph?n c?ng ra file ?? d? dàng ??i chi?u
            $fdisplay(fw, "%0128x", out_pixels_512b);
            
            // 2. Hi?n th? lên màn hình Console (c? ph?n c?ng và Python)
            $display("=== Pixel %0d ===", out_count + 1);
            $display("  HW Output : %0128x", out_pixels_512b);
            $display("  PY Expect : %0128x", exp_mem[out_count]);
            
            // 3. So sánh
            if (out_pixels_512b !== exp_mem[out_count]) begin
                $display("  -> [L?I] K?T QU? KHÔNG KH?P!");
                error_count = error_count + 1;
            end else begin
                $display("  -> [OK] KH?P HOÀN TOÀN!");
            end
            $display("------------------------------------------------------------------");
            
            out_count = out_count + 1;
        end
    end

endmodule
