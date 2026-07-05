`timescale 1ns / 1ps

module tb_log_mel_spectrogram();

    // ============================================================
    // 1. THAM S? C?U HÌNH (Kh?p v?i Top Module)
    // ============================================================
    parameter DATA_WIDTH    = 16;
    parameter BIN_WIDTH     = 9;
    parameter MEL_BINS      = 40;
    parameter ACC_WIDTH     = 57;
    parameter Q_SHIFT       = 15;
    parameter LUT_BITS      = 12;
    parameter OUT_WIDTH     = 16;
    parameter MEL_IDX_WIDTH = 6;
    
    // ============================================================
    // 2. KHAI BÁO TÍN HI?U
    // ============================================================
    reg  clk;
    reg  reset_n;
    reg  enable;
    reg  frame_start; // Tín hi?u này gi? ch? ch?y trong Testbench, không n?i vào DUT
    
    // Ngõ vào (T??ng t? tín hi?u t? kh?i FFT)
    reg  datain_valid;
    reg  signed [DATA_WIDTH-1:0] in_real;
    reg  signed [DATA_WIDTH-1:0] in_imag;
    reg  [BIN_WIDTH-1:0]         in_bin_idx;
    
    // Ngõ ra
    wire dataout_valid;
    wire [OUT_WIDTH-1:0]     dataout;
    wire [MEL_IDX_WIDTH-1:0] out_bin_idx;

    // ============================================================
    // 3. KH?I T?O B? NH? VÀ ??C FILE K?CH B?N (STIMULUS & EXPECTED)
    // ============================================================
    // - File Input: 512 m?u x 64-bit Hex (16b FrameStart + 16b Idx + 16b Re + 16b Im)
    // - File Output: 40 m?u x 24-bit Hex (6b MelIdx + 16b LogOut)
    reg [63:0] stim_mem [0:511];
    reg [23:0] exp_mem  [0:39];
    
    initial begin
        $readmemh("spectrogram_in_stimulus.mem", stim_mem);
        $readmemh("spectrogram_out_expected.mem", exp_mem);
    end

    // ============================================================
    // 4. INSTANTIATE DUT (Thi?t b? c?n test)
    // ============================================================
    log_mel_spectrogram #(
        .DATA_WIDTH(DATA_WIDTH),
        .BIN_WIDTH(BIN_WIDTH),
        .MEL_BINS(MEL_BINS),
        .ACC_WIDTH(ACC_WIDTH),
        .Q_SHIFT(Q_SHIFT),
        .LUT_BITS(LUT_BITS),
        .OUT_WIDTH(OUT_WIDTH),
        .MEL_IDX_WIDTH(MEL_IDX_WIDTH)
    ) uut (
        .clk            (clk),
        .reset_n        (reset_n),
        .enable         (enable),
        
        // ?ã xóa .frame_start(frame_start) ? ?ây
        
        .datain_valid   (datain_valid),
        .in_real        (in_real),
        .in_imag        (in_imag),
        .in_bin_idx     (in_bin_idx),
        
        .dataout_valid  (dataout_valid),
        .dataout        (dataout),
        .out_bin_idx    (out_bin_idx)
    );

    // ============================================================
    // 5. T?O CLOCK (Chu k? 10ns -> 100MHz)
    // ============================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ============================================================
    // 6. LU?NG ?I?U KHI?N & B?M D? LI?U VÀO (INJECT STIMULUS)
    // ============================================================
    integer i, f;
    
    initial begin
        // --- 6.1 Kh?i t?o tr?ng thái ban ??u ---
        reset_n      = 0;
        enable       = 0;
        frame_start  = 0;
        datain_valid = 0;
        in_real      = 0;
        in_imag      = 0;
        in_bin_idx   = 0;
        
        #30;
        reset_n = 1;
        enable  = 1;
        #10;
        
        $display("==================================================");
        $display("BAT DAU TEST TOP-MODULE: LOG MEL SPECTROGRAM");
        $display("==================================================");

        // --- 6.2 B?m 2 Frame liên ti?p ---
        for (f = 0; f < 2; f = f + 1) begin
            
            // Cho m?ch ngh? 10 chu k? gi?a 2 frame ?? x? h?t Pipeline
            if (f > 0) begin
                @(posedge clk);
                datain_valid = 0;
                frame_start  = 0;
                repeat(10) @(posedge clk);
            end

            for (i = 0; i < 512; i = i + 1) begin
                @(posedge clk);
                
                // Ép c?ng frame_start ch? này lên 1 ? ?úng bin ??u tiên
                if (i == 0) frame_start = 1;
                else        frame_start = 0;
                
                // Trích xu?t d? li?u
                in_bin_idx   = stim_mem[i][40:32]; 
                in_real      = stim_mem[i][31:16]; 
                in_imag      = stim_mem[i][15:0];  
                datain_valid = 1;
                
                // DEBUG: In th? 3 m?u d? li?u ??u tiên c?a Frame 0 ?? ki?m tra file MEM
                if (f == 0 && i < 3) begin
                    $display("[DEBUG INPUT] Bin: %0d | Real: %0h | Imag: %0h", in_bin_idx, in_real, in_imag);
                end
            end
        end
        
        // K?t thúc n?p d? li?u
        @(posedge clk);
        datain_valid = 0;
        frame_start  = 0;
        
        #5000;
        $display("TIMEOUT: Ket thuc mo phong.");
        $finish;
    end

    // ============================================================
    // 7. KI?M TRA D? LI?U NGÕ RA (OUTPUT CHECKER)
    // ============================================================
    integer out_ptr = 0;
    integer valid_frame_cnt = 0; // Bi?n ??m s? l??ng frame ?ã xu?t ra
    
    wire [23:0] hw_full_out = {2'b00, out_bin_idx, dataout};
    wire [5:0]  exp_idx = exp_mem[out_ptr][21:16];
    wire [15:0] exp_log = exp_mem[out_ptr][15:0];

    always @(posedge clk) begin
        if (dataout_valid) begin
            // ----------------------------------------------------
            // Giai ?o?n 1: B? qua 40 k?t qu? ??u tiên (Frame rác/toàn 0)
            // ----------------------------------------------------
            if (valid_frame_cnt == 0) begin
                out_ptr = out_ptr + 1;
                if (out_ptr == MEL_BINS) begin
                    out_ptr = 0;
                    valid_frame_cnt = 1; // Xong frame rác, chu?n b? ?ón d? li?u th?t
                    $display(">>> DA BO QUA FRAME 0 (GIA TRI RONG). BAT DAU CHECK FRAME 1 <<<");
                end
            end 
            // ----------------------------------------------------
            // Giai ?o?n 2: B?t ??u ??i chi?u d? li?u th?t c?a Frame 1
            // ----------------------------------------------------
            else begin
                $display("[OUTPUT @Time %0t ps] Kiem tra ngo ra thu: %0d", $time, out_ptr);
                $display("   -> VERILOG Hardware: Chuoi ghep (Hex) = %06x | Idx_out = %0d, Log_out = %04x", 
                         hw_full_out, out_bin_idx, dataout & 16'hFFFF);
                $display("   -> PYTHON Golden:    Chuoi ghep (Hex) = %06x | Idx_exp = %0d, Log_exp = %04x", 
                         exp_mem[out_ptr], exp_idx, exp_log);
                         
                if (hw_full_out === exp_mem[out_ptr]) begin
                    $display("   [=> CHUAN XAC]");
                end else begin
                    $display("   [=> SAI LECH] !!!");
                end
                $display("------------------------------------------------------------------------");
                
                out_ptr = out_ptr + 1;
                
                if (out_ptr == MEL_BINS) begin
                    $display("==================================================");
                    $display("PASS: Da kiem tra thanh cong %0d Mel Channels!", MEL_BINS);
                    $display("==================================================");
                    $finish;
                end
            end
        end
    end

endmodule