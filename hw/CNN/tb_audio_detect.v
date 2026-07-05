`timescale 1ns / 1ps

module tb_audio_detect;

    // =========================================================
    // PARAMETERS (C?u h?nh h? th?ng)
    // =========================================================
    parameter CLK_PERIOD  = 10;
    parameter MAX_SAMPLES = 65536; // Kh?p v?i 65536 d?ng c?a hw_input.mem
    parameter NUM_CLASSES = 3;     // Kh?p v?i 3 class ??u ra c?a CNN

    // =========================================================
    // T?N HI?U K?T N?I (DUT PORTS)
    // =========================================================
    reg         clk;
    reg         rst_n;
    reg         enable;
    reg  [31:0] audio_in_data;

    wire        cnn_out_valid;
    wire signed [15:0] cnn_class_0;
    wire signed [15:0] cnn_class_1;
    wire signed [15:0] cnn_class_2;

    // T?n hi?u n?i b? ?? probing/monitor n?u c?n (D?ng ???ng d?n ph?n c?p)
    wire        log_mel_valid_mon = dut.log_mel_valid_internal;
    wire [15:0] log_mel_data_mon  = dut.log_mel_data_internal;

    // =========================================================
    // B? NH? CH?A D? LI?U TEST (RAM m? ph?ng)
    // =========================================================
    reg [31:0] in_mem  [0:MAX_SAMPLES-1];
    reg [15:0] out_mem [0:NUM_CLASSES-1]; // Ch?a 3 logits k? v?ng t? Python

    integer i;
    integer out_cnt = 0;
    integer error_cnt = 0;

    // =========================================================
    // KH?I T?O DUT (Device Under Test)
    // =========================================================
    audio_detect #(
        .LOG_MEL_OUT   (16),
        .MEL_BINS      (40),
        .MEL_IDX_WIDTH (6),
        .FFT_SHIFT     (6),
        .CNN_FIFO_DEPTH(4096),
        .CNN_FIFO_ADDR_WIDTH(12)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .enable        (enable),
        .audio_in_data (audio_in_data),

        // ?? lo?i b? c?c c?ng log_mel_* kh?ng t?n t?i ? module top
        .cnn_out_valid (cnn_out_valid),
        .cnn_class_0   (cnn_class_0),
        .cnn_class_1   (cnn_class_1),
        .cnn_class_2   (cnn_class_2)
    );

    // =========================================================
    // T?O XUNG NH?P (CLOCK GENERATOR)
    // =========================================================
    initial begin
        clk = 0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // =========================================================
    // LU?NG K?CH TH?CH CH?NH (STIMULUS)
    // =========================================================
    initial begin
        // 1. ??c d? li?u t? file b? nh? xu?t t? Python
        $readmemh("hw_input.mem", in_mem);  
        $readmemh("hw_output.mem", out_mem);

        // Kh?i t?o tr?ng th?i ban ??u
        rst_n = 0;
        enable = 0;
        audio_in_data = 32'd0;

        // Reset h? th?ng ?n ??nh
        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 10);

        // 2. B?t ??u ??y d? li?u v?o m?ng pipeline
        enable = 1;
        $display("=================================================");
        $display("[INFO] Bat dau nap %0d mau audio vao he thong...", MAX_SAMPLES);
        $display("=================================================");

        // N?p m?u ??ng b? theo c?nh xu?ng ?? tr?nh l?i timing m? ph?ng
        for (i = 0; i < MAX_SAMPLES; i = i + 1) begin
            @(negedge clk);
            audio_in_data = in_mem[i];
        end

        // 3. Ch? to?n b? pipeline x? l? xong (FFT -> Log-Mel -> FIFO -> CNN)
        @(negedge clk);
        $display("[INFO] Da nap xong %0d mau. Giu enable de CNN x? ly...", MAX_SAMPLES);
        audio_in_data = 32'd0;
        
        // Ch? cho ??n khi cnn_out_valid b?t l?n ho?c b? Timeout k?ch ho?t
        @(posedge cnn_out_valid);
        #(CLK_PERIOD * 10); // Ch? th?m v?i chu k? ?? b? gi?m s?t in b?o c?o

        // 4. T?ng k?t ??nh gi? k?t qu?
        $display("=================================================");
        $display("M? PH?NG K?T TH?C TH?NH C?NG");
        $display("Tong so phan phoi da kiem tra: %0d", out_cnt);
        if (out_cnt == 0) begin
            $display("[RESULT] FAILED! Khong nhan duoc tin hieu cnn_out_valid.");
        end else if (error_cnt == 0) begin
            $display("[RESULT] PASSED! Tat ca ket qua phan loai deu khop voi Python.");
        end else begin
            $display("[RESULT] FAILED! Phat hien %0d loi sai lech lon.", error_cnt);
        end
        $display("=================================================");
        
        $finish;
    end

    // =========================================================
    // B?T OUTPUT V? SO S?NH (MONITOR UNIT)
    // =========================================================
    reg signed [15:0] exp_class_0;
    reg signed [15:0] exp_class_1;
    reg signed [15:0] exp_class_2;
    
    reg [15:0] diff_0, diff_1, diff_2;
    parameter ALLOWED_MARGIN = 15; // Ng??ng sai s? Fixed-point cho ph?p

    always @(posedge clk) begin
        if (cnn_out_valid) begin
            // ??c d? li?u v?ng t? Python trong out_mem
            exp_class_0 = out_mem[0];
            exp_class_1 = out_mem[1];
            exp_class_2 = out_mem[2];

            // T?nh ?? l?ch tuy?t ??i (Absolute Error)
            diff_0 = (cnn_class_0 > exp_class_0) ? (cnn_class_0 - exp_class_0) : (exp_class_0 - cnn_class_0);
            diff_1 = (cnn_class_1 > exp_class_1) ? (cnn_class_1 - exp_class_1) : (exp_class_1 - cnn_class_1);
            diff_2 = (cnn_class_2 > exp_class_2) ? (cnn_class_2 - exp_class_2) : (exp_class_2 - cnn_class_2);

            $display("-------------------------------------------------");
            $display("[MATCH] Bat duoc ket qua phan loi tai: %0t ns", $time);
            
            // In b?ng so s?nh tr?c quan
            $display("  [Nguon]  |  CUU (Class 0)  |  CUOP (Class 1)  |  UNK (Class 2)");
            $display("  Python   |      %6d     |      %6d      |      %6d", exp_class_0, exp_class_1, exp_class_2);
            $display("  Verilog  |      %6d     |      %6d      |      %6d", cnn_class_0, cnn_class_1, cnn_class_2);
            $display("  Do lech  |      %6d     |      %6d      |      %6d", diff_0, diff_1, diff_2);

            // Ki?m tra dung sai
            if (diff_0 <= ALLOWED_MARGIN && diff_1 <= ALLOWED_MARGIN && diff_2 <= ALLOWED_MARGIN) begin
                $display("  => [OK] Ket qua KHOP (Sai so Fixed-point <= %0d).", ALLOWED_MARGIN);
            end else begin
                $display("  => [LOI] Du lieu lech vuot muc cho phep!");
                error_cnt = error_cnt + 1;
            end

            out_cnt = out_cnt + 1;
        end
    end

    // M?ch b?o v? ch?ng treo (Timeout)
    initial begin
        #(CLK_PERIOD * 5000000); // Gi?i h?n 5 tri?u chu k?
        $display("=================================================");
        $display("[WARNING] Timeout mo phong! Core CNN co the da bi ket hoac mat tin hieu Valid.");
        $display("=================================================");
        $finish;
    end

endmodule
