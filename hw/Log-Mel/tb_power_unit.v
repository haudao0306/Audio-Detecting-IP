`timescale 1ns/1ps

module tb_power_unit;

    // =========================================================
    // 1. C?U HÌNH THAM S?
    // =========================================================
    parameter DATA_WIDTH = 16;
    parameter BIN_WIDTH  = 9;   // ?? r?ng Index t? FFT (512 bins) gi?ng module Top

    // Tín hi?u k?t n?i
    reg clk;
    reg reset_n;
    reg enable;
    reg signed [DATA_WIDTH-1:0] re_in;
    reg signed [DATA_WIDTH-1:0] im_in;
    reg                         valid_in;
    reg        [BIN_WIDTH-1:0]  in_bin_idx;  // Thêm bi?n ??m ngõ vào

    wire [2*DATA_WIDTH:0]       p_out;
    wire                        valid_out;
    wire [BIN_WIDTH-1:0]        out_bin_idx; // Thêm bi?n ??m ngõ ra

    // =========================================================
    // 2. KH?I T?O DUT (Device Under Test)
    // Chú ý: B?n hãy s?a tên c?ng .in_bin_idx và .out_bin_idx 
    // bên d??i cho kh?p hoàn toàn v?i tên b?n ??t trong power_unit.v
    // =========================================================
    power_unit #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk         (clk),
        .reset_n     (reset_n),
        .enable      (enable),
        .re_in       (re_in),
        .im_in       (im_in),
        .valid_in    (valid_in),
        .bin_idx_in (in_bin_idx),  // <-- CHÂN BI?N ??M VÀO
        
        .p_out       (p_out),
        .valid_out   (valid_out),
        .bin_idx_out (out_bin_idx) // <-- CHÂN BI?N ??M RA
    );

    // =========================================================
    // 3. B? SINH XUNG CLOCK (100MHz -> Chu k? 10ns)
    // =========================================================
    always #5 clk = ~clk;  

    // =========================================================
    // 4. TASK: PHÁT D? LI?U ??U VÀO (C?p nh?t thêm Index)
    // =========================================================
    task send_input;
        input signed [DATA_WIDTH-1:0] re;
        input signed [DATA_WIDTH-1:0] im;
        input        [BIN_WIDTH-1:0]  idx; // Nh?n thêm ch? s? Bin
        begin
            @(posedge clk);
            re_in      <= re;
            im_in      <= im;
            in_bin_idx <= idx;
            valid_in   <= 1'b1;

            @(posedge clk);
            valid_in   <= 1'b0;
        end
    endtask

    // =========================================================
    // 5. FUNCTION: ?ÁP ÁN M?U (Golden Model)
    // =========================================================
    function [2*DATA_WIDTH:0] calc_power;
        input signed [DATA_WIDTH-1:0] re;
        input signed [DATA_WIDTH-1:0] im;
        reg    [2*DATA_WIDTH-1:0] re_sq;
        reg    [2*DATA_WIDTH-1:0] im_sq;
        begin
            re_sq = re * re;
            im_sq = im * im;
            calc_power = re_sq + im_sq;
        end
    endfunction

    // =========================================================
    // 6. MÔ PH?NG PIPELINE 2 GIAI ?O?N ?? T? ??NG CHECK K?T QU?
    // =========================================================
    reg [2*DATA_WIDTH:0] exp_p_pipe   [0:1];
    reg [BIN_WIDTH-1:0]  exp_idx_pipe [0:1];

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            exp_p_pipe[0]   <= 0; exp_p_pipe[1]   <= 0;
            exp_idx_pipe[0] <= 0; exp_idx_pipe[1] <= 0;
        end else if (enable) begin
            // Stage 1 c?a hàng ??i Testbench
            exp_p_pipe[0]   <= calc_power(re_in, im_in);
            exp_idx_pipe[0] <= in_bin_idx;
            
            // Stage 2 c?a hàng ??i Testbench (S? kh?p v?i ngõ ra sau 2 chu k?)
            exp_p_pipe[1]   <= exp_p_pipe[0];
            exp_idx_pipe[1] <= exp_idx_pipe[0];
        end
    end

    // =========================================================
    // 7. MONITOR: IN VÀ SO SÁNH K?T QU? ??U RA
    // =========================================================
    always @(posedge clk) begin
        if (valid_out) begin
            if ((p_out === exp_p_pipe[1]) && (out_bin_idx === exp_idx_pipe[1])) begin
                $display("[PASS] TIME=%0t | Bin=%0d | HW_Power=%0d | Chinh xac!", 
                         $time, out_bin_idx, p_out);
            end else begin
                $display("[FAIL] TIME=%0t | L?I T?I BIN=%0d (D? ki?n Bin=%0d) | HW_Power=%0d (D? ki?n=%0d)", 
                         $time, out_bin_idx, exp_idx_pipe[1], p_out, exp_p_pipe[1]);
            end
        end
    end

    // =========================================================
    // 8. K?CH B?N KI?M TH? CHÍNH (Main Test)
    // =========================================================
    initial begin
        // Kh?i t?o tr?ng thái ban ??u
        clk        = 0;
        reset_n    = 0;
        enable     = 0;
        re_in      = 0;
        im_in      = 0;
        in_bin_idx = 0;
        valid_in   = 0;

        // C?p phát H? th?ng Reset
        #20;
        reset_n = 1;
        enable  = 1;
        #10;

        $display("\n=======================================================");
        $display("==         B?T ??U KI?M TH? KH?I POWER UNIT          ==");
        $display("=======================================================\n");

        // ??y các Test Cases kèm ch? s? Bin t?nh ti?n t? 0, 1, 2, 3...
        send_input(3, 4, 9'd0);      // 3^2 + 4^2 = 25
        send_input(-5, 12, 9'd1);    // 25 + 144 = 169
        send_input(7, -8, 9'd2);     // 49 + 64 = 113
        send_input(-10, -10, 9'd3);  // 100 + 100 = 200

        // Ch? d? li?u x? h?t kh?i ???ng ?ng Pipeline (2 Stages)
        repeat(5) @(posedge clk);

        $display("\n=======================================================");
        $display("==             HOÀN THÀNH KI?M TH?                   ==");
        $display("=======================================================\n");
        $finish;
    end

endmodule
