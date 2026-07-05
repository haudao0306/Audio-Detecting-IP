`timescale 1ns / 1ps

module mac_unit_tb;

    // =========================================================
    // 1. C?U HÌNH THAM S?
    // =========================================================
    parameter NUM_FILTERS = 40;
    parameter NUM_BINS    = 512;
    parameter PK_WIDTH    = 33;
    parameter WMK_WIDTH   = 16;
    parameter PROD_WIDTH  = 49;
    parameter ACC_WIDTH   = 58;

    // =========================================================
    // 2. KHAI BÁO TÍN HI?U
    // =========================================================
    // Inputs
    reg clk;
    reg reset_n;
    reg enable;
    reg acc_clear;
    reg valid_in;
    reg [PK_WIDTH-1:0] mel_in;
    reg [$clog2(NUM_BINS)-1:0] bin_idx;

    // Outputs (?ã b? các chân FIFO)
    wire valid_out;
    wire [ACC_WIDTH-1:0] mel_out;
    wire [$clog2(NUM_FILTERS)-1:0] mel_idx;

    // =========================================================
    // 3. KH?I T?O DUT (Device Under Test)
    // =========================================================
    mac_unit #(
        .NUM_FILTERS(NUM_FILTERS),
        .NUM_BINS(NUM_BINS),
        .PK_WIDTH(PK_WIDTH),
        .WMK_WIDTH(WMK_WIDTH),
        .PROD_WIDTH(PROD_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) uut (
        .clk        (clk),
        .reset_n    (reset_n),
        .enable     (enable),
        .acc_clear  (acc_clear),
        .valid_in   (valid_in),
        .mel_in     (mel_in),
        .bin_idx    (bin_idx),
        
        .valid_out  (valid_out),
        .mel_out    (mel_out),
        .mel_idx    (mel_idx)
    );

    // =========================================================
    // 4. B? SINH XUNG CLOCK
    // =========================================================
    initial clk = 0;
    always #5 clk = ~clk; // 100MHz -> Chu k? 10ns

    // =========================================================
    // 5. MONITOR HI?N TH? K?T QU? ??U RA
    // =========================================================
    integer count_out = 0;
    always @(posedge clk) begin
        if (valid_out) begin
            $display("[TIME %0t] Output %0d: Filter Index = %0d, Value = %h", 
                     $time, count_out, mel_idx, mel_out);
            count_out = count_out + 1;
        end
    end

    // =========================================================
    // 6. K?CH B?N KI?M TH? (Test Sequence)
    // =========================================================
    integer i;
    initial begin
        // --- Kh?i t?o tín hi?u ---
        reset_n   = 0;
        enable    = 0;
        acc_clear = 0;
        valid_in  = 0;
        mel_in    = 0;
        bin_idx   = 0;

        // Reset h? th?ng
        #20 reset_n = 1;
        #10;

        // --- B?T ??U FRAME 1 ---
        $display("\n--- Starting Frame 1 ---");
        acc_clear = 1; // Xóa d? li?u c? (Xóa b? tích l?y)
        #10 acc_clear = 0;
        enable = 1;

        // ??y 512 bins vào
        for (i = 0; i < NUM_BINS; i = i + 1) begin
            @(posedge clk);
            valid_in <= 1;
            bin_idx  <= i;
            // Gi? l?p d? li?u: cho mel_in = 1 ?? d? ki?m tra xem m?ch 
            // có c?ng d?n ?úng b?ng t?ng các tr?ng s? không
            mel_in   <= 33'h000000001; 
        end

        // Sau khi ??y xong 512 bin, t?t c? valid_in
        @(posedge clk);
        valid_in <= 0;
        bin_idx  <= 0;

        // Ch? cho ??n khi kh?i MAC x? ?? 40 k?t qu?
        wait(count_out == NUM_FILTERS);
        
        $display("--- Frame 1 Completed. Total outputs: %0d ---", count_out);

        // --- B?T ??U FRAME 2 (Ki?m tra tính liên t?c) ---
        #100;
        count_out = 0;
        $display("\n--- Starting Frame 2 ---");
        
        // Reset l?i b? tích l?y cho Frame m?i
        acc_clear = 1;
        #10 acc_clear = 0;

        // ??y 512 bins d? li?u m?i
        for (i = 0; i < NUM_BINS; i = i + 1) begin
            @(posedge clk);
            valid_in <= 1;
            bin_idx  <= i;
            mel_in   <= $random; // ??y d? li?u ng?u nhiên
        end

        @(posedge clk);
        valid_in <= 0;

        // Ch? x? lý xong
        wait(count_out == NUM_FILTERS);
        #100;
        
        $display("\n[SUCCESS] Testbench Finished Successfully.");
        $finish;
    end
    
    
    // =========================================================
    // 8. K?T XU?T WAVEFORM DUMP
    // =========================================================
    initial begin
        $dumpfile("mac_unit_waveform.vcd");
        $dumpvars(0, mac_unit_tb);
    end

endmodule